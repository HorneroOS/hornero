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
    if set(editions) != {"desktop", "server", "agents", "studio"}:
        errors.append("user-facing editions must be desktop, server, agents, and studio")
    agents = editions.get("agents")
    if isinstance(agents, dict) and agents.get("extends") != "server":
        errors.append("Agents must derive from Server")
    studio = editions.get("studio")
    if isinstance(studio, dict) and studio.get("extends") != "desktop":
        errors.append("Studio must derive from Desktop")
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
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Resolve a HorneroOS edition package composition")
    parser.add_argument("edition", choices=("desktop", "server", "agents", "studio"))
    parser.add_argument("--compositor", choices=("hyprland", "niri"))
    parser.add_argument("--json", action="store_true", help="Print machine-readable composition")
    args = parser.parse_args()
    try:
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
