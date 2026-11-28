#!/usr/bin/env python3
"""Validate HorneroOS Canonical Verified Application Catalog (catalog/apps.v1.json)."""
from __future__ import annotations

import datetime as dt
import json
import re
import sys
from pathlib import Path

import jsonschema

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CATALOG = ROOT / "catalog" / "apps.v1.json"
DEFAULT_SCHEMA = ROOT / "catalog" / "apps.schema.json"

SHELL_META_RE = re.compile(r"[;|&$`<>(){}\\\\'\"\n\r\t\x00 ]")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

ALLOWED_CATEGORIES = {
    "ai-assistants", "ai-coding", "browsers", "productivity",
    "communication", "development", "creative-studio", "gaming",
    "multimedia", "utilities", "security", "education",
}
ALLOWED_STATUSES = {
    "installable_validated", "installable_with_limitations", "official_web_app",
    "community_maintained", "guided_setup_required", "deprecated",
    "pending_verification", "unsupported",
}
ALLOWED_PROVENANCE = {
    "arch_official", "flathub_verified", "flathub_community",
    "vendor_official", "hornero_official", "official_web_app",
    "community_package",
}
ALLOWED_BACKENDS = {"arch_native", "flatpak", "aur", "webapp", "vendor_repo", "appimage", "guided"}
ALLOWED_STABILITY = {"stable", "beta", "alpha", "preview", "deprecated"}


def _walk_urls(obj: object, path: str, errors: list[str]) -> None:
    if isinstance(obj, dict):
        for k, v in obj.items():
            _walk_urls(v, f"{path}.{k}", errors)
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            _walk_urls(v, f"{path}[{i}]", errors)
    elif isinstance(obj, str) and "http://" in obj:
        errors.append(f"insecure http:// URL found at {path}: {obj}")


def validate_catalog(catalog_path: Path = DEFAULT_CATALOG, schema_path: Path = DEFAULT_SCHEMA, max_age_days: int = 365) -> list[str]:
    errors: list[str] = []
    if not catalog_path.is_file():
        return [f"missing catalog file: {catalog_path}"]
    if not schema_path.is_file():
        return [f"missing schema file: {schema_path}"]

    doc = json.loads(catalog_path.read_text(encoding="utf-8"))
    schema = json.loads(schema_path.read_text(encoding="utf-8"))

    validator = jsonschema.Draft202012Validator(schema)
    for err in sorted(validator.iter_errors(doc), key=lambda e: list(e.path)):
        loc = ".".join(str(p) for p in err.path) or "<root>"
        errors.append(f"schema error at {loc}: {err.message}")

    _walk_urls(doc, "$", errors)

    cat_ids = [c["id"] for c in doc.get("categories", [])]
    if len(cat_ids) != len(set(cat_ids)):
        errors.append("duplicate category ids")
    if set(cat_ids) != ALLOWED_CATEGORIES:
        errors.append(f"category set mismatch: {sorted(set(cat_ids) ^ ALLOWED_CATEGORIES)}")

    apps = doc.get("apps", [])
    seen_ids: set[str] = set()
    app_map: dict[str, dict] = {}
    for app in apps:
        aid = app.get("id", "")
        if aid in seen_ids:
            errors.append(f"duplicate app id: {aid}")
        seen_ids.add(aid)
        app_map[aid] = app

        if app.get("category") not in ALLOWED_CATEGORIES:
            errors.append(f"{aid}: invalid category {app.get('category')}")
        if app.get("status") not in ALLOWED_STATUSES:
            errors.append(f"{aid}: invalid status {app.get('status')}")
        if app.get("stability") not in ALLOWED_STABILITY:
            errors.append(f"{aid}: invalid stability {app.get('stability')}")

        last_ver = app.get("last_verified", "")
        if not DATE_RE.match(last_ver):
            errors.append(f"{aid}: invalid last_verified date {last_ver!r}")
        else:
            d = dt.date.fromisoformat(last_ver)
            ref = dt.date.fromisoformat(doc.get("verifiedAt", last_ver))
            if (ref - d).days > max_age_days:
                errors.append(f"{aid}: stale last_verified {last_ver} (> {max_age_days} days old)")

        sources = app.get("sources", [])
        rec = app.get("recommended_source", "")
        backends = [s.get("backend") for s in sources]
        if app.get("status") in ("pending_verification", "unsupported"):
            if any(s.get("verified") for s in sources):
                errors.append(f"{aid}: {app.get('status')} app must not claim a verified install source")
        else:
            if not sources:
                errors.append(f"{aid}: active app has empty sources[]")
            elif rec not in backends:
                errors.append(f"{aid}: recommended_source {rec!r} not found in sources backends {backends}")

        for idx, s in enumerate(sources):
            b = s.get("backend")
            p = s.get("provenance")
            pid = s.get("package_id", "")
            if b not in ALLOWED_BACKENDS:
                errors.append(f"{aid}.sources[{idx}]: invalid backend {b!r}")
            if p not in ALLOWED_PROVENANCE:
                errors.append(f"{aid}.sources[{idx}]: invalid provenance {p!r}")
            if SHELL_META_RE.search(pid):
                errors.append(f"{aid}.sources[{idx}]: shell metacharacter or whitespace in package_id {pid!r}")
            if b == "aur" and p != "community_package":
                errors.append(f"{aid}.sources[{idx}]: AUR source must have provenance community_package, got {p!r}")
            if p == "flathub_verified" and not s.get("verified"):
                errors.append(f"{aid}.sources[{idx}]: flathub_verified must have verified=true")
            if p == "flathub_community" and s.get("verified"):
                errors.append(f"{aid}.sources[{idx}]: flathub_community must have verified=false")

        if aid == "claude-desktop":
            if rec != "webapp":
                errors.append("claude-desktop: recommended_source must be 'webapp' (official web app), never AUR")
            for s in sources:
                if s.get("backend") == "aur" and s.get("provenance") != "community_package":
                    errors.append("claude-desktop: AUR source must stay community_package")

    for col in doc.get("collections", []):
        for aid in col.get("apps", []):
            if aid not in app_map:
                errors.append(f"collection {col['id']}: unknown app id {aid}")

    for prof in doc.get("profiles", []):
        for aid in prof.get("apps", []):
            if aid not in app_map:
                errors.append(f"profile {prof['id']}: unknown app id {aid}")
            elif not app_map[aid].get("is_open_source"):
                errors.append(f"profile {prof['id']}: non-open-source app {aid} must be in proprietaryOptIn, not apps")
        for aid in prof.get("proprietaryOptIn", []):
            if aid not in app_map:
                errors.append(f"profile {prof['id']}: unknown proprietaryOptIn app id {aid}")

    featured_count = sum(1 for a in apps if a.get("featured"))
    if not (40 <= featured_count <= 48):
        errors.append(f"featured app count must be 40..48, got {featured_count}")

    return errors


def main() -> int:
    errors = validate_catalog()
    if errors:
        print("CATALOG-FAIL:", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1
    doc = json.loads(DEFAULT_CATALOG.read_text(encoding="utf-8"))
    featured = sum(1 for a in doc["apps"] if a["featured"])
    print(
        f"CATALOG-PASS: {len(doc['apps'])} apps, {len(doc['categories'])} categories, "
        f"{len(doc['collections'])} collections, {len(doc['profiles'])} profiles, {featured} featured"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
