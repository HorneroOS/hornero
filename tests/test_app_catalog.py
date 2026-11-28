"""Tests for the Canonical Verified Application Catalog and validator."""
from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location(
    "validate_app_catalog", ROOT / "scripts" / "validate-app-catalog.py"
)
assert SPEC and SPEC.loader
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)


def test_canonical_catalog_passes_validation():
    errors = validator.validate_catalog()
    assert errors == [], errors


def test_canonical_catalog_invariants():
    doc = json.loads((ROOT / "catalog" / "apps.v1.json").read_text(encoding="utf-8"))
    assert doc["apiVersion"] == "hornero.os/v1"
    assert doc["kind"] == "ApplicationCatalog"
    assert doc["schemaVersion"] == 1
    assert len(doc["apps"]) >= 200
    assert len(doc["categories"]) == 12
    assert len(doc["collections"]) == 10
    assert len(doc["profiles"]) == 9

    apps = {a["id"]: a for a in doc["apps"]}
    claude = apps["claude-desktop"]
    assert claude["recommended_source"] == "webapp"
    aur_sources = [s for s in claude["sources"] if s["backend"] == "aur"]
    assert aur_sources and aur_sources[0]["provenance"] == "community_package"

    chatgpt = apps["chatgpt-desktop"]
    assert chatgpt["recommended_source"] == "vendor_repo"
    assert chatgpt["sources"][0]["provenance"] == "vendor_official"


def test_validator_rejects_bad_claude_or_http_or_shell_meta(tmp_path):
    doc = json.loads((ROOT / "catalog" / "apps.v1.json").read_text(encoding="utf-8"))
    bad = copy.deepcopy(doc)
    for a in bad["apps"]:
        if a["id"] == "claude-desktop":
            a["recommended_source"] = "aur"
        if a["id"] == "firefox":
            a["homepage"] = "http://firefox.com"
            a["sources"][0]["package_id"] = "firefox;rm -rf /"
    p = tmp_path / "bad.json"
    p.write_text(json.dumps(bad), encoding="utf-8")
    errors = validator.validate_catalog(catalog_path=p)
    assert any("claude-desktop" in e for e in errors)
    assert any("http://" in e for e in errors)
    assert any("shell metacharacter" in e for e in errors)
