#!/usr/bin/env python3
"""Validate the Hornero OS composition: manifests, profiles, releases.

Usage:
    python3 scripts/check-manifests.py [--root DIR]

Exit 0 when every check passes, 1 otherwise. Manifests are validated
against manifests/schema.json with the `jsonschema` package when it
is installed; a strict built-in structural check always runs too, so
results are identical with or without the optional dependency.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.exit("ERROR: PyYAML is required (pip install pyyaml)")

try:
    import jsonschema

    HAVE_JSONSCHEMA = True
except ImportError:
    HAVE_JSONSCHEMA = False

API_VERSION = "hornero.os/v1"
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
DATE_RE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
VERSION_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.]+)?$")
STATUSES = ("pinned", "local", "future")
TARGETS = ("vm", "hardware")
RELEASE_STATUSES = ("draft", "pre-release", "final")


def load_yaml(path: Path):
    with path.open(encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def doc_files(directory: Path, suffix: str) -> list[Path]:
    return sorted(
        p
        for p in directory.glob(f"*.{suffix}")
        if not p.name.startswith(".") and p.name != ".gitkeep"
    )


def check_manifest_doc(doc, source: str) -> list[str]:
    errors: list[str] = []
    if not isinstance(doc, dict):
        return [f"{source}: document must be a mapping"]
    for key in ("apiVersion", "kind", "name", "date", "components"):
        if key not in doc:
            errors.append(f"{source}: missing required key '{key}'")
    if errors:
        return errors
    if doc["apiVersion"] != API_VERSION:
        errors.append(f"{source}: apiVersion must be '{API_VERSION}'")
    if doc["kind"] != "CompositionManifest":
        errors.append(f"{source}: kind must be 'CompositionManifest'")
    if not isinstance(doc.get("name"), str) or not NAME_RE.match(doc["name"]):
        errors.append(f"{source}: invalid manifest name")
    date = doc.get("date")
    date_str = str(date) if not isinstance(date, str) else date
    if not DATE_RE.match(date_str):
        errors.append(f"{source}: date must be YYYY-MM-DD")
    components = doc.get("components")
    if not isinstance(components, dict):
        return errors + [f"{source}: components must be a mapping"]
    for required in ("shell", "config"):
        comp = components.get(required)
        if not isinstance(comp, dict):
            errors.append(f"{source}: missing component '{required}'")
            continue
        if comp.get("status") != "pinned":
            errors.append(f"{source}: component '{required}' must be pinned")
    for name, comp in components.items():
        if not isinstance(comp, dict):
            errors.append(f"{source}: component '{name}' must be a mapping")
            continue
        status = comp.get("status")
        if status not in STATUSES:
            errors.append(f"{source}: component '{name}' has bad status")
            continue
        if not comp.get("repo"):
            errors.append(f"{source}: component '{name}' needs a repo URL")
        if status == "pinned":
            if not comp.get("ref"):
                errors.append(f"{source}: pinned '{name}' needs a ref")
            sha = comp.get("sha", "")
            if not isinstance(sha, str) or not SHA_RE.match(sha):
                errors.append(f"{source}: pinned '{name}' needs a 40-char sha")
        else:
            if "sha" in comp:
                errors.append(f"{source}: {status} '{name}' must not carry a sha")
            if status == "future" and "ref" in comp:
                errors.append(f"{source}: future '{name}' must not carry a ref")
    return errors


def check_profile_doc(doc, source: str, manifests: dict) -> list[str]:
    errors: list[str] = []
    if not isinstance(doc, dict):
        return [f"{source}: document must be a mapping"]
    for key in ("apiVersion", "kind", "name", "manifest", "components"):
        if key not in doc:
            errors.append(f"{source}: missing required key '{key}'")
    if errors:
        return errors
    if doc["apiVersion"] != API_VERSION:
        errors.append(f"{source}: apiVersion must be '{API_VERSION}'")
    if doc["kind"] != "EditionProfile":
        errors.append(f"{source}: kind must be 'EditionProfile'")
    manifest = manifests.get(doc.get("manifest"))
    if manifest is None:
        errors.append(f"{source}: unknown manifest '{doc.get('manifest')}'")
        return errors
    components = doc.get("components")
    if not isinstance(components, list) or not components:
        errors.append(f"{source}: components must be a non-empty list")
        return errors
    seen: set[str] = set()
    pinned = manifest.get("components", {})
    for entry in components:
        if not isinstance(entry, dict) or "name" not in entry:
            errors.append(f"{source}: each component needs a name")
            continue
        name = entry["name"]
        if name in seen:
            errors.append(f"{source}: duplicate component '{name}'")
        seen.add(name)
        target = pinned.get(name)
        if not isinstance(target, dict):
            errors.append(f"{source}: unknown component '{name}'")
        elif target.get("status") not in ("pinned", "local"):
            errors.append(f"{source}: component '{name}' is not shippable")
    if doc.get("target") not in TARGETS:
        errors.append(f"{source}: target must be one of {list(TARGETS)}")
    return errors


def check_profile_chain(profiles: dict) -> list[str]:
    errors: list[str] = []
    for name, doc in profiles.items():
        parent = doc.get("extends")
        if parent is None:
            continue
        if parent not in profiles:
            errors.append(f"profiles/{name}: unknown parent '{parent}'")
            continue
        seen = {name}
        while parent is not None:
            if parent in seen:
                errors.append(f"profiles/{name}: cyclic extends chain")
                break
            seen.add(parent)
            parent = profiles[parent].get("extends")
    return errors


def check_release_doc(doc, source: str, manifests: dict, profiles: dict) -> list[str]:
    errors: list[str] = []
    if not isinstance(doc, dict):
        return [f"{source}: document must be a mapping"]
    for key in ("apiVersion", "kind", "name", "version", "status", "manifest", "profiles"):
        if key not in doc:
            errors.append(f"{source}: missing required key '{key}'")
    if errors:
        return errors
    if doc["apiVersion"] != API_VERSION:
        errors.append(f"{source}: apiVersion must be '{API_VERSION}'")
    if doc["kind"] != "Release":
        errors.append(f"{source}: kind must be 'Release'")
    if not VERSION_RE.match(str(doc.get("version", ""))):
        errors.append(f"{source}: version must be semver-like")
    if doc.get("status") not in RELEASE_STATUSES:
        errors.append(f"{source}: status must be one of {list(RELEASE_STATUSES)}")
    manifest_name = doc.get("manifest")
    if manifest_name not in manifests:
        errors.append(f"{source}: unknown manifest '{manifest_name}'")
        return errors
    for profile_name in doc.get("profiles", []):
        profile = profiles.get(profile_name)
        if profile is None:
            errors.append(f"{source}: unknown profile '{profile_name}'")
        elif profile.get("manifest") != manifest_name:
            errors.append(f"{source}: profile '{profile_name}' uses another manifest")
    return errors


def check_tree(root: Path) -> list[str]:
    errors: list[str] = []
    manifests_dir = root / "manifests"
    schema_path = manifests_dir / "schema.json"
    try:
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        return [f"manifests/schema.json: unreadable ({exc})"]
    if not isinstance(schema, dict) or "$defs" not in schema:
        errors.append("manifests/schema.json: not the expected schema document")

    manifests: dict[str, dict] = {}
    for path in doc_files(manifests_dir, "yaml"):
        doc = load_yaml(path)
        source = f"manifests/{path.name}"
        if HAVE_JSONSCHEMA:
            try:
                jsonschema.validate(doc, schema)
            except jsonschema.ValidationError as exc:
                errors.append(f"{source}: schema violation: {exc.message}")
        errors.extend(check_manifest_doc(doc, source))
        if isinstance(doc, dict) and isinstance(doc.get("name"), str):
            if doc["name"] in manifests:
                errors.append(f"{source}: duplicate manifest '{doc['name']}'")
            manifests[doc["name"]] = doc

    profiles: dict[str, dict] = {}
    for path in doc_files(root / "profiles", "yaml"):
        doc = load_yaml(path)
        source = f"profiles/{path.name}"
        errors.extend(check_profile_doc(doc, source, manifests))
        if isinstance(doc, dict) and isinstance(doc.get("name"), str):
            profiles[doc["name"]] = doc
    errors.extend(check_profile_chain(profiles))

    for path in doc_files(root / "releases", "yaml"):
        doc = load_yaml(path)
        source = f"releases/{path.name}"
        errors.extend(check_release_doc(doc, source, manifests, profiles))
        checklist = doc.get("checklist") if isinstance(doc, dict) else None
        if isinstance(checklist, str) and not (root / checklist).is_file():
            errors.append(f"{source}: missing checklist '{checklist}'")

    if (root / ".gitmodules").exists():
        errors.append(".gitmodules exists: pins must be data, not submodules")
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate Hornero OS composition files.")
    parser.add_argument("--root", default=None, help="Repository root (default: parent of scripts/)")
    args = parser.parse_args(argv)
    root = Path(args.root) if args.root else Path(__file__).resolve().parent.parent
    errors = check_tree(root)
    backend = "jsonschema" if HAVE_JSONSCHEMA else "built-in"
    if errors:
        for error in errors:
            print(f"CHECK-FAIL: {error}")
        print(f"check-manifests: {len(errors)} failure(s) [schema backend: {backend}]")
        return 1
    print(f"CHECK-PASS: manifests, profiles, and releases agree [schema backend: {backend}]")
    return 0


if __name__ == "__main__":
    sys.exit(main())
