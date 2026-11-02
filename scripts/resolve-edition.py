#!/usr/bin/env python3
"""Resolve a HorneroOS edition into its ordered Arch package set."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parent.parent
CATALOGUE = ROOT / "editions" / "catalogue.yaml"
MATURITIES = {"planned", "experimental", "preview", "supported"}
PROVENANCE_SOURCES = {"arch-core", "arch-extra", "arch-multilib", "aur", "vendor"}
LICENSE_CLASSES = {"open-source", "proprietary"}
INSTALL_METHODS = {"pacman-repository", "pacman-repository-opt-in", "manual"}
# Legacy session manager superseded by WirePlumber; it must never return to
# the Studio composition (HorneroOS/hornero#284).
FORBIDDEN_STUDIO_PACKAGES = {"pipewire-media-session"}


def load_catalogue(path: Path = CATALOGUE) -> dict:
    doc = yaml.safe_load(path.read_text(encoding="utf-8"))
    errors = validate_catalogue(doc)
    if errors:
        raise ValueError("invalid edition catalogue:\n- " + "\n- ".join(errors))
    return doc


def validate_catalogue(doc: object) -> list[str]:
    if not isinstance(doc, dict):
        return ["catalogue must be a mapping"]
    errors: list[str] = []
    if doc.get("apiVersion") != "hornero.os/v1" or doc.get("kind") != "EditionCatalogue":
        errors.append("catalogue must use hornero.os/v1 EditionCatalogue")
    sets = doc.get("packageSets")
    editions = doc.get("editions")
    compositors = doc.get("compositors")
    if not isinstance(sets, dict) or not isinstance(editions, dict) or not isinstance(compositors, dict):
        return errors + ["packageSets, editions, and compositors must be mappings"]
    base_packages = doc.get("base", {}).get("packages") if isinstance(doc.get("base"), dict) else None
    if not isinstance(base_packages, list) or not base_packages:
        errors.append("base.packages must be a non-empty list")
    all_sets = dict(sets)
    all_sets["base"] = {"packages": base_packages or []}
    for name, package_set in all_sets.items():
        packages = package_set.get("packages") if isinstance(package_set, dict) else None
        optional_packages = package_set.get("optionalPackages", []) if isinstance(package_set, dict) else None
        if not isinstance(packages, list) or not packages or any(not isinstance(p, str) or not p for p in packages):
            errors.append(f"package set '{name}' must contain package names")
        elif len(packages) != len(set(packages)):
            errors.append(f"package set '{name}' has duplicate package names")
        if not isinstance(optional_packages, list) or any(not isinstance(p, str) or not p for p in optional_packages):
            errors.append(f"package set '{name}' optionalPackages must be a list of package names")
        elif len(optional_packages) != len(set(optional_packages)):
            errors.append(f"package set '{name}' has duplicate optional package names")
        elif isinstance(packages, list) and set(packages) & set(optional_packages):
            errors.append(f"package set '{name}' lists a package as both required and optional")
    for name, compositor in compositors.items():
        if not isinstance(compositor, dict) or compositor.get("maturity") not in MATURITIES:
            errors.append(f"compositor '{name}' has invalid maturity")
            continue
        package_set = compositor.get("packageSet")
        if package_set is not None and package_set not in sets:
            errors.append(f"compositor '{name}' references unknown package set '{package_set}'")
        if compositor.get("maturity") == "planned" and package_set is not None:
            errors.append(f"planned compositor '{name}' must not imply an installable package set")
    for name, edition in editions.items():
        if not isinstance(edition, dict):
            errors.append(f"edition '{name}' must be a mapping")
            continue
        if edition.get("maturity") not in MATURITIES:
            errors.append(f"edition '{name}' has invalid maturity")
        if not isinstance(edition.get("title"), str) or not edition["title"]:
            errors.append(f"edition '{name}' needs a title")
        if not isinstance(edition.get("role"), str) or not edition["role"]:
            errors.append(f"edition '{name}' needs a non-empty role")
        if not isinstance(edition.get("packageSets"), list):
            errors.append(f"edition '{name}' packageSets must be a list")
            continue
        for package_set in edition["packageSets"]:
            if package_set not in sets:
                errors.append(f"edition '{name}' references unknown package set '{package_set}'")
        parent = edition.get("extends")
        if parent is not None and parent not in editions:
            errors.append(f"edition '{name}' extends unknown edition '{parent}'")
        seen = {name}
        cursor = parent
        while cursor in editions:
            cursor_edition = editions[cursor]
            if not isinstance(cursor_edition, dict):
                break
            if cursor in seen:
                errors.append(f"edition '{name}' has a cyclic inheritance chain")
                break
            seen.add(cursor)
            cursor = cursor_edition.get("extends")
        compositor_choice = edition.get("compositor")
        if compositor_choice is not None:
            if not isinstance(compositor_choice, dict):
                errors.append(f"edition '{name}' compositor must be a mapping")
                continue
            if "inherit" in compositor_choice:
                inherited = compositor_choice["inherit"]
                if inherited != parent or inherited not in editions or not editions[inherited].get("compositor"):
                    errors.append(f"edition '{name}' must inherit compositor choice from its parent")
                continue
            default = compositor_choice.get("default")
            supported = compositor_choice.get("supported")
            if default not in compositors or not isinstance(supported, list) or default not in supported:
                errors.append(f"edition '{name}' has an invalid default compositor")
            for backend in supported if isinstance(supported, list) else []:
                if backend not in compositors:
                    errors.append(f"edition '{name}' references unknown compositor '{backend}'")
                elif compositors[backend].get("maturity") == "planned":
                    errors.append(f"edition '{name}' advertises planned compositor '{backend}'")
    if set(editions) != {"desktop", "server", "agents", "studio", "gaming"}:
        errors.append("user-facing editions must be desktop, server, agents, studio, and gaming")
    agents = editions.get("agents")
    if isinstance(agents, dict) and agents.get("extends") != "server":
        errors.append("Agents must derive from Server")
    studio = editions.get("studio")
    if isinstance(studio, dict) and studio.get("extends") != "desktop":
        errors.append("Studio must derive from Desktop")
    errors.extend(_validate_studio_provenance(doc, sets, studio))
    errors.extend(_validate_studio_modes(doc))
    gaming = editions.get("gaming")
    if isinstance(gaming, dict) and gaming.get("extends") != "desktop":
        errors.append("Gaming must derive from Desktop")
    errors.extend(_validate_gaming_provenance(doc, sets))
    errors.extend(_validate_installation_model(doc, editions))
    desktop_names = {"hornero-shell", "hornero-config", "horneroctl-bin", "quickshell", "hyprland", "niri"}
    server_sets = ["server"]
    for set_name in server_sets:
        server_set = sets.get(set_name, {})
        if not isinstance(server_set, dict):
            continue
        names = set(server_set.get("packages", []))
        leaked = names & desktop_names
        if leaked:
            errors.append(f"server package set leaks desktop packages: {', '.join(sorted(leaked))}")
    return errors


def _validate_studio_provenance(doc: dict, sets: object, studio: object) -> list[str]:
    """Every Studio package and optional integration needs auditable source,
    license and install metadata. Provenance never implies support, and a
    proprietary or AUR entry can never become a silent default."""
    provenance = doc.get("studioProvenance")
    if not isinstance(provenance, dict) or not provenance:
        return ["studioProvenance must be a non-empty mapping"]
    studio_packages: list[str] = []
    if isinstance(sets, dict):
        studio_set = sets.get("studio")
        if isinstance(studio_set, dict) and isinstance(studio_set.get("packages"), list):
            studio_packages = [p for p in studio_set["packages"] if isinstance(p, str)]
    errors: list[str] = []
    for forbidden in sorted(set(studio_packages) & FORBIDDEN_STUDIO_PACKAGES):
        errors.append(f"studio package set must not contain legacy package '{forbidden}'")
    integration_ids: list[str] = []
    if isinstance(studio, dict):
        integrations = studio.get("optionalIntegrations", [])
        if not isinstance(integrations, list):
            errors.append("studio optionalIntegrations must be a list")
            integrations = []
        for integration in integrations:
            if not isinstance(integration, dict) or not isinstance(integration.get("id"), str):
                errors.append("studio optionalIntegrations entries need an id")
                continue
            integration_ids.append(integration["id"])
            if integration.get("source") not in PROVENANCE_SOURCES:
                errors.append(f"integration '{integration['id']}' has invalid source '{integration.get('source')}'")
            entry = provenance.get(integration["id"])
            if isinstance(entry, dict) and entry.get("source") != integration.get("source"):
                errors.append(f"integration '{integration['id']}' source disagrees with studioProvenance")
    application_packages: set[str] = set()
    applications = doc.get("studioApplications")
    if isinstance(applications, dict):
        for application in applications.values():
            if isinstance(application, dict) and isinstance(application.get("packages"), list):
                application_packages.update(p for p in application["packages"] if isinstance(p, str))
    allowed = set(studio_packages) | set(integration_ids) | {"yabridgectl"} | application_packages
    for package in studio_packages:
        if package not in provenance:
            errors.append(f"studio package '{package}' is missing provenance metadata")
    for name, entry in provenance.items():
        if name not in allowed:
            errors.append(f"studioProvenance entry '{name}' does not match a Studio package or integration")
            continue
        if not isinstance(entry, dict):
            errors.append(f"studioProvenance entry '{name}' must be a mapping")
            continue
        if entry.get("source") not in PROVENANCE_SOURCES:
            errors.append(f"studioProvenance entry '{name}' has invalid source '{entry.get('source')}'")
        source_url = entry.get("sourceUrl")
        if not isinstance(source_url, str) or not source_url.startswith("https://"):
            errors.append(f"studioProvenance entry '{name}' needs an https sourceUrl")
        licenses = entry.get("licenses")
        if not isinstance(licenses, list) or not licenses or any(not isinstance(item, str) or not item for item in licenses):
            errors.append(f"studioProvenance entry '{name}' needs a non-empty licenses list")
        if entry.get("licenseClass") not in LICENSE_CLASSES:
            errors.append(f"studioProvenance entry '{name}' has invalid licenseClass '{entry.get('licenseClass')}'")
        if entry.get("installMethod") not in INSTALL_METHODS:
            errors.append(f"studioProvenance entry '{name}' has invalid installMethod '{entry.get('installMethod')}'")
        if not isinstance(entry.get("optional"), bool):
            errors.append(f"studioProvenance entry '{name}' optional must be a boolean")
        if entry.get("support") not in MATURITIES:
            errors.append(f"studioProvenance entry '{name}' has invalid support maturity '{entry.get('support')}'")
        if entry.get("licenseClass") == "proprietary" and entry.get("optional") is not True:
            errors.append(f"proprietary studioProvenance entry '{name}' must be optional and opt-in")
        if entry.get("source") == "aur" and (entry.get("installMethod") != "manual" or entry.get("optional") is not True):
            errors.append(f"AUR studioProvenance entry '{name}' must be optional with manual install; AUR recipes are never executed")
        if name in integration_ids and entry.get("optional") is not True:
            errors.append(f"integration '{name}' must be optional in studioProvenance")
        if name in application_packages and name not in studio_packages and entry.get("optional") is not True:
            errors.append(f"selectable application package '{name}' must be optional in studioProvenance")
    errors.extend(_validate_studio_selection_model(doc, provenance, studio_packages))
    return errors


REQUIRED_SPECIALIZATIONS = {
    "audio-music-production",
    "video-editing-post-production",
    "streaming-content-creation",
    "graphic-design-illustration",
    "photography-raw-processing",
    "3d-animation-vfx",
    "game-development",
    "maker-cad",
    "complete-creative-workstation",
    "custom-selection",
}


def _validate_studio_selection_model(doc: dict, provenance: dict, studio_packages: list[str]) -> list[str]:
    errors: list[str] = []
    applications = doc.get("studioApplications")
    specializations = doc.get("studioSpecializations")
    platform = doc.get("studioPlatformPackages")
    if not isinstance(applications, dict) or not applications:
        return ["studioApplications must be a non-empty mapping"]
    if not isinstance(specializations, dict) or not specializations:
        return errors + ["studioSpecializations must be a non-empty mapping"]
    if set(specializations) != REQUIRED_SPECIALIZATIONS:
        errors.append("studioSpecializations must define exactly the ten required specializations")
    if not isinstance(platform, list) or not platform:
        errors.append("studioPlatformPackages must be a non-empty list")
    else:
        for package in platform:
            if package not in provenance:
                errors.append(f"studio platform package '{package}' is missing provenance metadata")
            if package not in studio_packages:
                errors.append(f"studio platform package '{package}' must belong to the studio package set")
    for app_id, application in applications.items():
        if not isinstance(application, dict) or not isinstance(application.get("title"), str) or not application["title"]:
            errors.append(f"studio application '{app_id}' needs a title")
            continue
        packages = application.get("packages")
        if not isinstance(packages, list) or any(not isinstance(p, str) or not p for p in packages):
            errors.append(f"studio application '{app_id}' packages must be a list of package names")
            continue
        if not packages and application.get("availability") != "reference-only":
            errors.append(f"studio application '{app_id}' has no packages and is not reference-only")
        for package in packages:
            if package not in provenance:
                errors.append(f"studio application '{app_id}' package '{package}' is missing provenance metadata")
    curated_union: set[str] = set()
    for spec_id, specialization in specializations.items():
        if not isinstance(specialization, dict) or not isinstance(specialization.get("title"), str) or not specialization["title"]:
            errors.append(f"studio specialization '{spec_id}' needs a title")
            continue
        apps = specialization.get("applications")
        if not isinstance(apps, list) or any(not isinstance(a, str) for a in apps):
            errors.append(f"studio specialization '{spec_id}' applications must be a list of application ids")
            continue
        if len(apps) != len(set(apps)):
            errors.append(f"studio specialization '{spec_id}' has duplicate applications")
        for app_id in apps:
            if app_id not in applications:
                errors.append(f"studio specialization '{spec_id}' references unknown application '{app_id}'")
        if spec_id not in ("complete-creative-workstation", "custom-selection"):
            curated_union.update(a for a in apps if isinstance(a, str))
    complete = specializations.get("complete-creative-workstation")
    if isinstance(complete, dict) and isinstance(complete.get("applications"), list):
        if set(complete["applications"]) != curated_union:
            errors.append("complete-creative-workstation must be the union of the other curated specializations")
    custom = specializations.get("custom-selection")
    if isinstance(custom, dict) and custom.get("applications") not in ([], None):
        errors.append("custom-selection must not require any specialization applications")
    return errors


def _application_is_proprietary(doc: dict, app_id: str) -> bool:
    provenance = doc.get("studioProvenance") or {}
    application = (doc.get("studioApplications") or {}).get(app_id) or {}
    return any(
        (provenance.get(package) or {}).get("licenseClass") == "proprietary"
        for package in application.get("packages", [])
    )


def _validate_gaming_provenance(doc: dict, sets: object) -> list[str]:
    """Every Gaming platform/selectable package needs auditable source,
    license and install metadata. Provenance never implies support, game
    compatibility, or hardware qualification, and a proprietary or AUR
    entry can never become a silent default."""
    provenance = doc.get("gamingProvenance")
    if not isinstance(provenance, dict) or not provenance:
        return ["gamingProvenance must be a non-empty mapping"]
    gaming_packages: list[str] = []
    if isinstance(sets, dict):
        gaming_set = sets.get("gaming")
        if isinstance(gaming_set, dict) and isinstance(gaming_set.get("packages"), list):
            gaming_packages = [p for p in gaming_set["packages"] if isinstance(p, str)]
    applications = doc.get("gamingApplications")
    application_packages: set[str] = set()
    if isinstance(applications, dict):
        for application in applications.values():
            if isinstance(application, dict) and isinstance(application.get("packages"), list):
                application_packages.update(p for p in application["packages"] if isinstance(p, str))
    allowed = set(gaming_packages) | application_packages
    errors: list[str] = []
    for package in gaming_packages:
        if package not in provenance:
            errors.append(f"gaming package '{package}' is missing provenance metadata")
    for name, entry in provenance.items():
        if name not in allowed:
            errors.append(f"gamingProvenance entry '{name}' does not match a Gaming package")
            continue
        if not isinstance(entry, dict):
            errors.append(f"gamingProvenance entry '{name}' must be a mapping")
            continue
        if entry.get("source") not in PROVENANCE_SOURCES:
            errors.append(f"gamingProvenance entry '{name}' has invalid source '{entry.get('source')}'")
        source_url = entry.get("sourceUrl")
        if not isinstance(source_url, str) or not source_url.startswith("https://"):
            errors.append(f"gamingProvenance entry '{name}' needs an https sourceUrl")
        licenses = entry.get("licenses")
        if not isinstance(licenses, list) or not licenses or any(not isinstance(item, str) or not item for item in licenses):
            errors.append(f"gamingProvenance entry '{name}' needs a non-empty licenses list")
        if entry.get("licenseClass") not in LICENSE_CLASSES:
            errors.append(f"gamingProvenance entry '{name}' has invalid licenseClass '{entry.get('licenseClass')}'")
        if entry.get("installMethod") not in INSTALL_METHODS:
            errors.append(f"gamingProvenance entry '{name}' has invalid installMethod '{entry.get('installMethod')}'")
        if not isinstance(entry.get("optional"), bool):
            errors.append(f"gamingProvenance entry '{name}' optional must be a boolean")
        if entry.get("support") not in MATURITIES:
            errors.append(f"gamingProvenance entry '{name}' has invalid support maturity '{entry.get('support')}'")
        if entry.get("licenseClass") == "proprietary" and entry.get("optional") is not True:
            errors.append(f"proprietary gamingProvenance entry '{name}' must be optional and opt-in")
        if entry.get("source") == "aur" and (entry.get("installMethod") != "manual" or entry.get("optional") is not True):
            errors.append(f"AUR gamingProvenance entry '{name}' must be optional with manual install; AUR recipes are never executed")
        if name in application_packages and name not in gaming_packages and entry.get("optional") is not True:
            errors.append(f"selectable gaming application package '{name}' must be optional in gamingProvenance")
    errors.extend(_validate_gaming_selection_model(doc, provenance, gaming_packages))
    return errors


REQUIRED_GAMING_SPECIALIZATIONS = {
    "desktop-gaming",
    "handheld",
    "streaming",
    "multi-launcher",
    "vr",
    "advanced-compat",
}


def _validate_gaming_selection_model(doc: dict, provenance: dict, gaming_packages: list[str]) -> list[str]:
    errors: list[str] = []
    applications = doc.get("gamingApplications")
    specializations = doc.get("gamingSpecializations")
    platform = doc.get("gamingPlatformPackages")
    if not isinstance(applications, dict) or not applications:
        return ["gamingApplications must be a non-empty mapping"]
    if not isinstance(specializations, dict) or not specializations:
        return errors + ["gamingSpecializations must be a non-empty mapping"]
    if set(specializations) != REQUIRED_GAMING_SPECIALIZATIONS:
        errors.append("gamingSpecializations must define exactly the six required specializations")
    defaults = [spec_id for spec_id, spec in specializations.items() if isinstance(spec, dict) and spec.get("default") is True]
    if defaults != ["desktop-gaming"]:
        errors.append("desktop-gaming must be the only default gaming specialization")
    if not isinstance(platform, list) or not platform:
        errors.append("gamingPlatformPackages must be a non-empty list")
    else:
        for package in platform:
            if package not in provenance:
                errors.append(f"gaming platform package '{package}' is missing provenance metadata")
            if package not in gaming_packages:
                errors.append(f"gaming platform package '{package}' must belong to the gaming package set")
    for app_id, application in applications.items():
        if not isinstance(application, dict) or not isinstance(application.get("title"), str) or not application["title"]:
            errors.append(f"gaming application '{app_id}' needs a title")
            continue
        packages = application.get("packages")
        if not isinstance(packages, list) or any(not isinstance(p, str) or not p for p in packages):
            errors.append(f"gaming application '{app_id}' packages must be a list of package names")
            continue
        if not packages and application.get("availability") != "reference-only":
            errors.append(f"gaming application '{app_id}' has no packages and is not reference-only")
        for package in packages:
            if package not in provenance:
                errors.append(f"gaming application '{app_id}' package '{package}' is missing provenance metadata")
    for spec_id, specialization in specializations.items():
        if not isinstance(specialization, dict) or not isinstance(specialization.get("title"), str) or not specialization["title"]:
            errors.append(f"gaming specialization '{spec_id}' needs a title")
            continue
        apps = specialization.get("applications")
        if not isinstance(apps, list) or any(not isinstance(a, str) for a in apps):
            errors.append(f"gaming specialization '{spec_id}' applications must be a list of application ids")
            continue
        if len(apps) != len(set(apps)):
            errors.append(f"gaming specialization '{spec_id}' has duplicate applications")
        for app_id in apps:
            if app_id not in applications:
                errors.append(f"gaming specialization '{spec_id}' references unknown application '{app_id}'")
    return errors


def _gaming_application_is_proprietary(doc: dict, app_id: str) -> bool:
    provenance = doc.get("gamingProvenance") or {}
    application = (doc.get("gamingApplications") or {}).get(app_id) or {}
    return any(
        (provenance.get(package) or {}).get("licenseClass") == "proprietary"
        for package in application.get("packages", [])
    )


REQUIRED_KERNELS = {"linux", "linux-lts", "linux-zen", "linux-hardened"}
REQUIRED_BOOTLOADERS = {"grub", "systemd-boot"}
REQUIRED_CAPABILITIES = {"bluetooth", "printing", "openssh", "developer"}
FIRMWARES = {"uefi", "bios"}


def _validate_installation_model(doc: dict, editions: object) -> list[str]:
    errors: list[str] = []
    kernels = doc.get("kernels")
    bootloaders = doc.get("bootloaders")
    capabilities = doc.get("capabilities")
    provenance = doc.get("installationProvenance")
    if not isinstance(kernels, dict) or set(kernels) != REQUIRED_KERNELS:
        errors.append("kernels must define exactly linux, linux-lts, linux-zen, and linux-hardened")
        kernels = kernels if isinstance(kernels, dict) else {}
    if not isinstance(bootloaders, dict) or set(bootloaders) != REQUIRED_BOOTLOADERS:
        errors.append("bootloaders must define exactly grub and systemd-boot")
        bootloaders = bootloaders if isinstance(bootloaders, dict) else {}
    if not isinstance(capabilities, dict) or set(capabilities) != REQUIRED_CAPABILITIES:
        errors.append("capabilities must define exactly bluetooth, printing, openssh, and developer")
        capabilities = capabilities if isinstance(capabilities, dict) else {}
    if not isinstance(provenance, dict) or not provenance:
        errors.append("installationProvenance must be a non-empty mapping")
        provenance = {}
    needed: set[str] = set()
    for name, kernel in kernels.items():
        if not isinstance(kernel, dict):
            errors.append(f"kernel '{name}' must be a mapping")
            continue
        packages = kernel.get("packages")
        if packages != [name]:
            errors.append(f"kernel '{name}' packages must be ['{name}']")
        if kernel.get("headers") != f"{name}-headers":
            errors.append(f"kernel '{name}' headers must be '{name}-headers'")
        if kernel.get("maturity") not in MATURITIES:
            errors.append(f"kernel '{name}' has invalid maturity")
        if isinstance(packages, list):
            needed.update(p for p in packages if isinstance(p, str))
        if isinstance(kernel.get("headers"), str):
            needed.add(kernel["headers"])
    if [n for n, k in kernels.items() if isinstance(k, dict) and k.get("default") is True] != ["linux"]:
        errors.append("linux must be the only default kernel")
    for name, loader in bootloaders.items():
        if not isinstance(loader, dict):
            errors.append(f"bootloader '{name}' must be a mapping")
            continue
        packages = loader.get("packages")
        if not isinstance(packages, list) or any(not isinstance(p, str) or not p for p in packages):
            errors.append(f"bootloader '{name}' packages must be a list of package names")
        else:
            needed.update(packages)
        firmwares = loader.get("firmwares")
        if not isinstance(firmwares, list) or not firmwares or not set(firmwares) <= FIRMWARES:
            errors.append(f"bootloader '{name}' firmwares must be a non-empty subset of uefi/bios")
        if loader.get("requiresUefi") is True and firmwares != ["uefi"]:
            errors.append(f"bootloader '{name}' requires UEFI and must list firmwares [uefi] only")
        for key in ("espBaseMiB", "perKernelMiB"):
            if not isinstance(loader.get(key), int) or loader[key] <= 0:
                errors.append(f"bootloader '{name}' {key} must be a positive integer")
    if [n for n, b in bootloaders.items() if isinstance(b, dict) and b.get("default") is True] != ["grub"]:
        errors.append("grub must be the only default bootloader")
    for name, capability in capabilities.items():
        if not isinstance(capability, dict):
            errors.append(f"capability '{name}' must be a mapping")
            continue
        packages = capability.get("packages")
        if not isinstance(packages, list) or not packages or any(not isinstance(p, str) or not p for p in packages):
            errors.append(f"capability '{name}' must contain package names")
        else:
            needed.update(packages)
        services = capability.get("services")
        if not isinstance(services, list) or any(not isinstance(s, str) or not (s.endswith(".service") or s.endswith(".socket")) for s in services):
            errors.append(f"capability '{name}' services must be systemd unit names")
        applies = capability.get("appliesTo")
        if not isinstance(applies, list) or not applies or (isinstance(editions, dict) and not set(applies) <= set(editions)):
            errors.append(f"capability '{name}' appliesTo must list known editions")
        defaults = capability.get("defaultByEdition")
        if not isinstance(defaults, dict) or (isinstance(editions, dict) and set(defaults) != set(editions)) or any(not isinstance(v, bool) for v in (defaults or {}).values()):
            errors.append(f"capability '{name}' defaultByEdition must give a boolean for every edition")
        for key in ("conflicts", "requires"):
            refs = capability.get(key)
            if not isinstance(refs, list) or any(not isinstance(r, str) for r in refs):
                errors.append(f"capability '{name}' {key} must be a list of capability ids")
                continue
            for ref in refs:
                if ref not in capabilities:
                    errors.append(f"capability '{name}' {key} references unknown capability '{ref}'")
                if ref == name:
                    errors.append(f"capability '{name}' must not reference itself in {key}")
    for package in sorted(needed):
        entry = provenance.get(package)
        if not isinstance(entry, dict):
            errors.append(f"installation package '{package}' is missing installationProvenance metadata")
            continue
        if entry.get("source") not in PROVENANCE_SOURCES:
            errors.append(f"installationProvenance entry '{package}' has invalid source '{entry.get('source')}'")
        if not isinstance(entry.get("sourceUrl"), str) or not entry["sourceUrl"].startswith("https://"):
            errors.append(f"installationProvenance entry '{package}' needs an https sourceUrl")
        if not isinstance(entry.get("licenses"), list) or not entry["licenses"]:
            errors.append(f"installationProvenance entry '{package}' needs a non-empty licenses list")
        if entry.get("licenseClass") not in LICENSE_CLASSES:
            errors.append(f"installationProvenance entry '{package}' has invalid licenseClass")
        if entry.get("installMethod") not in INSTALL_METHODS:
            errors.append(f"installationProvenance entry '{package}' has invalid installMethod")
        if not isinstance(entry.get("optional"), bool):
            errors.append(f"installationProvenance entry '{package}' optional must be a boolean")
        if entry.get("support") not in MATURITIES:
            errors.append(f"installationProvenance entry '{package}' has invalid support maturity")
        if entry.get("licenseClass") == "proprietary" and entry.get("optional") is not True:
            errors.append(f"proprietary installationProvenance entry '{package}' must be optional and opt-in")
    for package in provenance:
        if package not in needed:
            errors.append(f"installationProvenance entry '{package}' does not match a kernel, bootloader, or capability package")
    return errors


def resolve_installation(
    doc: dict,
    edition_name: str,
    compositor_name: str | None = None,
    kernels: list[str] | tuple[str, ...] | None = None,
    primary_kernel: str | None = None,
    fallback_kernel: str | None = None,
    bootloader: str | None = None,
    firmware: str = "uefi",
    encryption: str = "none",
    capabilities: list[str] | tuple[str, ...] | None = None,
    disabled_capabilities: list[str] | tuple[str, ...] = (),
    proprietary_nvidia: bool = False,
) -> dict:
    """Resolve an edition plus kernel/bootloader/capability selection.

    Deterministic: identical selections produce identical plans. Legacy
    resolve_edition() output is untouched; this layers the installation
    choices on top of it, substituting kernels and bootloader packages
    exactly once instead of appending duplicates.
    """
    kernel_map = doc.get("kernels") or {}
    bootloader_map = doc.get("bootloaders") or {}
    capability_map = doc.get("capabilities") or {}
    if kernels is None:
        kernels = [name for name, k in kernel_map.items() if isinstance(k, dict) and k.get("default") is True]
    kernels = list(kernels)
    if not kernels:
        raise ValueError(f"select at least one kernel (valid: {', '.join(sorted(kernel_map))})")
    if len(kernels) != len(set(kernels)):
        raise ValueError("kernels must not contain duplicates")
    for name in kernels:
        if name not in kernel_map:
            raise ValueError(f"unknown kernel '{name}' (valid: {', '.join(sorted(kernel_map))})")
    primary_kernel = primary_kernel or kernels[0]
    if primary_kernel not in kernels:
        raise ValueError("the primary kernel must be one of the installed kernels")
    if fallback_kernel is not None:
        if fallback_kernel not in kernels:
            raise ValueError("the fallback kernel must be one of the installed kernels")
        if fallback_kernel == primary_kernel:
            raise ValueError("the fallback kernel must differ from the primary kernel")
    if bootloader is None:
        bootloader = next((n for n, b in bootloader_map.items() if isinstance(b, dict) and b.get("default") is True), "grub")
    if bootloader not in bootloader_map:
        raise ValueError(f"unknown bootloader '{bootloader}' (valid: {', '.join(sorted(bootloader_map))})")
    if firmware not in FIRMWARES:
        raise ValueError(f"unknown firmware '{firmware}' (valid: {', '.join(sorted(FIRMWARES))})")
    loader = bootloader_map[bootloader]
    if firmware not in loader.get("firmwares", []):
        if bootloader == "systemd-boot" and firmware == "bios":
            raise ValueError("systemd-boot needs UEFI - this machine booted in legacy BIOS mode. Choose GRUB or reboot the installer in UEFI mode.")
        raise ValueError(f"bootloader '{bootloader}' does not support firmware '{firmware}' (valid: {', '.join(loader.get('firmwares', []))})")
    if encryption not in ("none", "luks"):
        raise ValueError("encryption must be 'none' or 'luks'")
    if capabilities is None:
        selected_caps = [name for name, cap in capability_map.items() if isinstance(cap, dict) and (cap.get("defaultByEdition") or {}).get(edition_name) is True]
    else:
        selected_caps = list(dict.fromkeys(capabilities))
    for name in selected_caps:
        if name not in capability_map:
            raise ValueError(f"unknown capability '{name}' (valid: {', '.join(sorted(capability_map))})")
    for name in disabled_capabilities:
        if name not in capability_map:
            raise ValueError(f"unknown capability '{name}' (valid: {', '.join(sorted(capability_map))})")
        if name in selected_caps:
            selected_caps.remove(name)
    # Transitive requires, in catalogue order for determinism.
    changed = True
    while changed:
        changed = False
        for name in list(selected_caps):
            for req in capability_map[name].get("requires", []):
                if req not in selected_caps:
                    selected_caps.append(req)
                    changed = True
    selected_caps = [name for name in capability_map if name in selected_caps]
    for name in selected_caps:
        capability = capability_map[name]
        if edition_name not in capability.get("appliesTo", []):
            raise ValueError(f"capability '{name}' is not available for edition '{edition_name}'; deselect it or choose another edition")
        for other in capability.get("conflicts", []):
            if other in selected_caps:
                raise ValueError(f"capability '{name}' conflicts with capability '{other}'; select only one")
    base = resolve_edition(doc, edition_name, compositor_name)
    kernel_packages: set[str] = set()
    for kernel in kernel_map.values():
        if isinstance(kernel, dict):
            kernel_packages.update(kernel.get("packages") or [])
            if isinstance(kernel.get("headers"), str):
                kernel_packages.add(kernel["headers"])
    bootloader_packages: set[str] = set()
    for item in bootloader_map.values():
        if isinstance(item, dict):
            bootloader_packages.update(item.get("packages") or [])
    ordered_kernels = [primary_kernel] + [k for k in kernels if k != primary_kernel]
    new_kernel_packages: list[str] = []
    for name in ordered_kernels:
        for package in kernel_map[name].get("packages") or []:
            if package not in new_kernel_packages:
                new_kernel_packages.append(package)
        headers = kernel_map[name].get("headers")
        if headers and headers not in new_kernel_packages:
            new_kernel_packages.append(headers)
    packages: list[str] = []
    kernel_done = bootloader_done = False
    for package in base["packages"]:
        if package in kernel_packages:
            if not kernel_done:
                packages.extend(p for p in new_kernel_packages if p not in packages)
                kernel_done = True
            continue
        if package in bootloader_packages:
            if not bootloader_done:
                packages.extend(p for p in loader.get("packages") or [] if p not in packages)
                bootloader_done = True
            continue
        if package not in packages:
            packages.append(package)
    if not kernel_done:
        packages = new_kernel_packages + packages
    services: list[str] = []
    for name in selected_caps:
        for package in capability_map[name].get("packages") or []:
            if package not in packages:
                packages.append(package)
        for service in capability_map[name].get("services") or []:
            if service not in services:
                services.append(service)
    warnings: list[str] = []
    nvidia_module: str | None = None
    if proprietary_nvidia:
        if set(kernels) == {"linux"}:
            nvidia_module = "nvidia-open"
        elif set(kernels) == {"linux-lts"}:
            nvidia_module = "nvidia-open-lts"
        else:
            nvidia_module = "nvidia-open-dkms"
        if "linux-hardened" in kernels:
            warnings.append("linux-hardened with the proprietary NVIDIA driver is unsupported upstream and may fail to build or boot; prefer linux or linux-lts, or use the open kernel module at your own risk")
        if len(kernels) > 1:
            warnings.append(f"multiple kernels with NVIDIA use {nvidia_module} only; never combine per-kernel NVIDIA module packages")
    provenance = doc.get("installationProvenance") or {}
    merged_provenance = dict(base.get("packageProvenance") or {})
    for package in packages:
        if package in provenance:
            merged_provenance[package] = provenance[package]
    esp = int(loader["espBaseMiB"]) + int(loader["perKernelMiB"]) * (len(kernels) - 1)
    return {
        "schemaVersion": 2,
        "edition": edition_name,
        "title": base["title"],
        "maturity": base["maturity"],
        "role": base["role"],
        "compositor": base["compositor"],
        "selection": {
            "edition": edition_name,
            "compositor": base["compositor"],
            "kernels": ordered_kernels,
            "primaryKernel": primary_kernel,
            "fallbackKernel": fallback_kernel,
            "bootloader": bootloader,
            "firmware": firmware,
            "encryption": encryption,
            "capabilities": selected_caps,
        },
        "packages": packages,
        "packageSets": base["packageSets"],
        "optionalPackages": base["optionalPackages"],
        "packageProvenance": {p: merged_provenance[p] for p in packages if p in merged_provenance},
        "services": services,
        "espRecommendedMiB": esp,
        "kernelImages": [kernel_map[k].get("image") for k in ordered_kernels],
        "nvidiaModule": nvidia_module,
        "proprietaryOptInRequired": base.get("proprietaryOptInRequired", []),
        "planWarnings": warnings,
    }


def resolve_gaming_selection(
    doc: dict,
    specialization_ids: list[str] | tuple[str, ...] = (),
    application_ids: list[str] | tuple[str, ...] = (),
) -> dict:
    """Resolve a user Gaming selection into a deterministic package plan.

    Specialization membership never installs proprietary applications:
    those need an explicit application-level selection. Reference-only
    applications (managed outside the catalogue, e.g. SteamVR inside
    Steam) fail with an actionable error instead of silently falling
    back. GPU drivers are never resolved here: they are a hardware
    decision for the installer/first-boot diagnostics, not a package
    catalogue promise.
    """
    applications = doc.get("gamingApplications") or {}
    specializations = doc.get("gamingSpecializations") or {}
    provenance = doc.get("gamingProvenance") or {}
    unknown_specs = [item for item in specialization_ids if item not in specializations]
    if unknown_specs:
        raise ValueError(
            f"unknown gaming specialization '{unknown_specs[0]}' (valid: {', '.join(sorted(specializations))})"
        )
    unknown_apps = [item for item in application_ids if item not in applications]
    if unknown_apps:
        raise ValueError(
            f"unknown gaming application '{unknown_apps[0]}' (valid: {', '.join(sorted(applications))})"
        )
    selected: list[str] = []
    opt_in_required: list[str] = []
    for spec_id in specialization_ids:
        for app_id in specializations[spec_id].get("applications", []):
            if _gaming_application_is_proprietary(doc, app_id):
                if app_id not in opt_in_required:
                    opt_in_required.append(app_id)
                continue
            if app_id not in selected:
                selected.append(app_id)
    for app_id in application_ids:
        if app_id not in selected:
            selected.append(app_id)
    packages: list[str] = []
    for package in doc.get("gamingPlatformPackages") or []:
        if package not in packages:
            packages.append(package)
    experimental: list[str] = []
    for app_id in selected:
        application = applications[app_id]
        if application.get("availability") == "reference-only" or not application.get("packages"):
            raise ValueError(
                f"gaming application '{app_id}' is reference-only and cannot be installed from the catalogue; "
                "remove it from the selection"
            )
        if application.get("experimental") and app_id not in experimental:
            experimental.append(app_id)
        for package in application["packages"]:
            if package not in packages:
                packages.append(package)
    for spec_id in specialization_ids:
        if specializations[spec_id].get("experimental") and spec_id not in experimental:
            experimental.append(spec_id)
    return {
        "schemaVersion": 1,
        "specializations": list(specialization_ids),
        "applications": selected,
        "packages": packages,
        "packageProvenance": {package: provenance[package] for package in packages if package in provenance},
        "proprietaryOptInRequired": opt_in_required,
        "experimental": experimental,
    }


def resolve_studio_selection(
    doc: dict,
    specialization_ids: list[str] | tuple[str, ...] = (),
    application_ids: list[str] | tuple[str, ...] = (),
) -> dict:
    """Resolve a user Studio selection into a deterministic package plan.

    Specialization membership never installs proprietary applications:
    those need an explicit application-level selection. Reference-only
    applications (no Arch package) fail with an actionable error instead
    of silently falling back to a full workstation.
    """
    applications = doc.get("studioApplications") or {}
    specializations = doc.get("studioSpecializations") or {}
    provenance = doc.get("studioProvenance") or {}
    unknown_specs = [item for item in specialization_ids if item not in specializations]
    if unknown_specs:
        raise ValueError(
            f"unknown studio specialization '{unknown_specs[0]}' (valid: {', '.join(sorted(specializations))})"
        )
    unknown_apps = [item for item in application_ids if item not in applications]
    if unknown_apps:
        raise ValueError(
            f"unknown studio application '{unknown_apps[0]}' (valid: {', '.join(sorted(applications))})"
        )
    selected: list[str] = []
    opt_in_required: list[str] = []
    for spec_id in specialization_ids:
        for app_id in specializations[spec_id].get("applications", []):
            if _application_is_proprietary(doc, app_id):
                if app_id not in opt_in_required:
                    opt_in_required.append(app_id)
                continue
            if app_id not in selected:
                selected.append(app_id)
    for app_id in application_ids:
        if app_id not in selected:
            selected.append(app_id)
    packages: list[str] = []
    for package in doc.get("studioPlatformPackages") or []:
        if package not in packages:
            packages.append(package)
    experimental: list[str] = []
    for app_id in selected:
        application = applications[app_id]
        if application.get("availability") == "reference-only" or not application.get("packages"):
            raise ValueError(
                f"studio application '{app_id}' is reference-only and cannot be installed from the catalogue; "
                "remove it from the selection"
            )
        if application.get("experimental") and app_id not in experimental:
            experimental.append(app_id)
        for package in application["packages"]:
            if package not in packages:
                packages.append(package)
    return {
        "schemaVersion": 1,
        "specializations": list(specialization_ids),
        "applications": selected,
        "packages": packages,
        "packageProvenance": {package: provenance[package] for package in packages if package in provenance},
        "proprietaryOptInRequired": opt_in_required,
        "experimental": experimental,
    }


AUDIO_MODES = {"balanced", "low-latency", "advanced"}
FORBIDDEN_MODE_OPERATIONS = {"rt-kernel", "irq-tuning", "cpu-governor", "gpu-tuning", "io-scheduler", "privilege-policy"}
RESTORE_EVENTS = {"disable", "error", "logout", "reboot", "timeout", "cancel"}


def _validate_studio_modes(doc: dict) -> list[str]:
    errors: list[str] = []
    modes = doc.get("studioAudioModes")
    if not isinstance(modes, dict) or set(modes) != AUDIO_MODES:
        errors.append("studioAudioModes must define exactly balanced, low-latency, and advanced")
        modes = modes if isinstance(modes, dict) else {}
    defaults = [name for name, mode in modes.items() if isinstance(mode, dict) and mode.get("default") is True]
    if defaults != ["balanced"]:
        errors.append("balanced must be the only default Studio audio mode")
    for name, mode in modes.items():
        if not isinstance(mode, dict):
            errors.append(f"studio audio mode '{name}' must be a mapping")
            continue
        if name != "balanced" and mode.get("explicitOptIn") is not True:
            errors.append(f"studio audio mode '{name}' must require explicit opt-in")
        if mode.get("presentsQuantumAsPhysicalLatency") is not False:
            errors.append(f"studio audio mode '{name}' must not present quantum as physical latency")
        restores = mode.get("restoresPreviousStateOn")
        if not isinstance(restores, list) or not {"disable", "error"} <= set(restores) or not set(restores) <= RESTORE_EVENTS:
            errors.append(f"studio audio mode '{name}' must restore previous state on disable and error")
    performance = doc.get("studioPerformanceMode")
    if not isinstance(performance, dict):
        errors.append("studioPerformanceMode must be a mapping")
    else:
        if performance.get("explicitOptIn") is not True or performance.get("temporary") is not True:
            errors.append("studio performance mode must be explicit opt-in and temporary")
        if performance.get("usesPowerProfilesDaemon") is not True:
            errors.append("studio performance mode must reuse power-profiles-daemon instead of writing governor settings")
        restores = performance.get("restoresPreviousStateOn")
        if not isinstance(restores, list) or not {"timeout", "cancel", "error"} <= set(restores):
            errors.append("studio performance mode must restore previous state on timeout, cancel, and error")
        forbidden = performance.get("forbiddenOperations")
        if not isinstance(forbidden, list) or set(forbidden) != FORBIDDEN_MODE_OPERATIONS:
            errors.append("studio performance mode must forbid rt-kernel, irq-tuning, cpu-governor, gpu-tuning, io-scheduler, and privilege-policy changes")
    return errors


def resolve_edition(doc: dict, edition_name: str, compositor_name: str | None = None) -> dict:
    editions = doc["editions"]
    if edition_name not in editions:
        raise ValueError(f"unknown edition '{edition_name}'")
    edition = editions[edition_name]
    choice = edition.get("compositor")
    while isinstance(choice, dict) and "inherit" in choice:
        choice = editions[choice["inherit"]].get("compositor")
    if choice:
        compositor_name = compositor_name or choice["default"]
        if compositor_name not in choice["supported"]:
            raise ValueError(f"compositor '{compositor_name}' is not listed for '{edition_name}'")
        backend = doc["compositors"][compositor_name]
        if backend.get("packageSet") is None:
            raise ValueError(f"compositor '{compositor_name}' has no installable package set")
    elif compositor_name:
        raise ValueError(f"edition '{edition_name}' is headless and does not accept a compositor")
    else:
        backend = None

    chain: list[dict] = []
    current = edition
    visited: set[str] = set()
    while True:
        current_name = next((name for name, value in editions.items() if value is current), None)
        if current_name is None or current_name in visited:
            raise ValueError(f"invalid inheritance chain for '{edition_name}'")
        visited.add(current_name)
        chain.append(current)
        parent = current.get("extends")
        if parent is None:
            break
        current = editions[parent]
    package_sets = ["base"]
    for layer in reversed(chain):
        package_sets.extend(layer["packageSets"])
    if backend:
        package_sets.append(backend["packageSet"])
    sets = doc["packageSets"]
    packages: list[str] = []
    optional_packages: list[str] = []
    for set_name in package_sets:
        package_set = {"packages": doc["base"]["packages"]} if set_name == "base" else sets[set_name]
        for package in package_set["packages"]:
            if package not in packages:
                packages.append(package)
        for package in package_set.get("optionalPackages", []):
            if package not in packages and package not in optional_packages:
                optional_packages.append(package)
    # Provenance is edition-scoped: a shared package (for example
    # obs-studio) must report the provenance of the edition being
    # resolved, never the other edition's optional/opt-in flags.
    provenance_key = "gamingProvenance" if edition_name == "gaming" else "studioProvenance"
    provenance_index: dict = {}
    if isinstance(doc.get(provenance_key), dict):
        provenance_index.update(doc[provenance_key])
    package_provenance = {
        package: provenance_index[package] for package in packages if package in provenance_index
    }
    integrations = []
    if edition_name == "studio":
        for integration in edition.get("optionalIntegrations", []):
            entry = dict(integration)
            entry["provenance"] = provenance_index.get(integration.get("id"))
            integrations.append(entry)
    return {
        "edition": edition_name,
        "title": edition["title"],
        "maturity": edition["maturity"],
        "role": edition["role"],
        "compositor": compositor_name,
        "compositorMaturity": backend.get("maturity") if backend else None,
        "packageSets": package_sets,
        "packages": packages,
        "optionalPackages": optional_packages,
        "packageProvenance": package_provenance,
        "optionalIntegrations": integrations,
        "audioModes": doc.get("studioAudioModes") if edition_name == "studio" else None,
        "performanceMode": doc.get("studioPerformanceMode") if edition_name == "studio" else None,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Resolve a HorneroOS edition package composition")
    parser.add_argument("edition", choices=("desktop", "server", "agents", "studio", "gaming"))
    parser.add_argument("--compositor", choices=("hyprland", "niri"))
    parser.add_argument("--json", action="store_true", help="Print machine-readable composition")
    parser.add_argument("--specialization", action="append", default=[], help="Studio/Gaming specialization id (repeatable, studio and gaming only)")
    parser.add_argument("--application", action="append", default=[], help="Studio/Gaming application id (repeatable, studio and gaming only)")
    parser.add_argument("--installation", action="store_true", help="Resolve a full installation plan (kernel/bootloader/capabilities)")
    parser.add_argument("--kernel", action="append", default=[], dest="kernels", help="Kernel id (repeatable, installation only)")
    parser.add_argument("--primary-kernel", help="Primary kernel id (installation only)")
    parser.add_argument("--fallback-kernel", help="Fallback kernel id (installation only)")
    parser.add_argument("--bootloader", choices=("grub", "systemd-boot"), help="Bootloader id (installation only)")
    parser.add_argument("--firmware", choices=("uefi", "bios"), default="uefi", help="Firmware type (installation only)")
    parser.add_argument("--encryption", choices=("none", "luks"), default="none", help="Disk encryption (installation only)")
    parser.add_argument("--capability", action="append", default=[], dest="capabilities", help="Capability id to add (repeatable, installation only)")
    parser.add_argument("--no-capability", action="append", default=[], dest="no_capabilities", help="Capability id to remove (repeatable, installation only)")
    parser.add_argument("--proprietary-nvidia", action="store_true", help="Plan for the proprietary NVIDIA driver (installation only)")
    args = parser.parse_args()
    try:
        installation_requested = args.installation or bool(args.kernels or args.primary_kernel or args.fallback_kernel or args.bootloader or args.capabilities or args.no_capabilities or args.proprietary_nvidia)
        if installation_requested:
            if args.specialization or args.application:
                parser.error("--specialization/--application cannot be combined with installation options in one invocation")
            doc = load_catalogue()
            defaults = [name for name, cap in (doc.get("capabilities") or {}).items() if (cap.get("defaultByEdition") or {}).get(args.edition) is True]
            selected = list(dict.fromkeys(defaults + args.capabilities))
            print(json.dumps(resolve_installation(doc, args.edition, args.compositor, kernels=args.kernels or None, primary_kernel=args.primary_kernel, fallback_kernel=args.fallback_kernel, bootloader=args.bootloader, firmware=args.firmware, encryption=args.encryption, capabilities=selected, disabled_capabilities=args.no_capabilities, proprietary_nvidia=args.proprietary_nvidia), indent=2))
            return 0
        if args.specialization or args.application:
            if args.edition == "studio":
                print(json.dumps(resolve_studio_selection(load_catalogue(), args.specialization, args.application), indent=2))
                return 0
            if args.edition == "gaming":
                print(json.dumps(resolve_gaming_selection(load_catalogue(), args.specialization, args.application), indent=2))
                return 0
            parser.error("--specialization/--application are only valid for the studio and gaming editions")
        result = resolve_edition(load_catalogue(), args.edition, args.compositor)
    except (OSError, ValueError) as exc:
        parser.error(str(exc))
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print(f"{result['title']} ({result['maturity']})")
        if result["compositor"]:
            print(f"Compositor: {result['compositor']} ({result['compositorMaturity']})")
        else:
            print("Compositor: none (headless)")
        print("Package composition:")
        for package in result["packages"]:
            print(f"  {package}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
