"""Tests for the Hornero OS composition (manifests, profiles, releases)."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent


def _load_checker():
    import importlib.util

    spec = importlib.util.spec_from_file_location(
        "check_manifests", ROOT / "scripts" / "check-manifests.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_checker = _load_checker()
check_manifest_doc = _checker.check_manifest_doc
check_profile_doc = _checker.check_profile_doc
check_release_doc = _checker.check_release_doc
check_tree = _checker.check_tree

SHELL_SHA = "329b6858c9bade373efba908fe452e23369d364f"
CONFIG_SHA = "69d5ca3c0a082de88f841882100994bc6c837310"


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_checker_green_on_repo_tree():
    assert check_tree(ROOT) == []


def test_checker_script_exits_zero():
    proc = subprocess.run(
        [sys.executable, "scripts/check-manifests.py"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert "CHECK-PASS" in proc.stdout


def test_first_manifest_pins_shell_and_config():
    import yaml

    doc = yaml.safe_load(read_text(ROOT / "manifests" / "v0.1.0-draft.yaml"))
    assert doc["components"]["shell"]["sha"] == SHELL_SHA
    assert doc["components"]["config"]["sha"] == CONFIG_SHA
    assert doc["components"]["shell"]["status"] == "pinned"
    assert doc["components"]["config"]["status"] == "pinned"
    assert doc["components"]["installer"]["status"] == "future"
    assert doc["components"]["iso"]["status"] == "future"
    assert "sha" not in doc["components"]["installer"]
    assert "sha" not in doc["components"]["iso"]


def test_no_submodules():
    assert not (ROOT / ".gitmodules").exists()


def test_bad_sha_is_rejected():
    import copy

    import yaml

    doc = yaml.safe_load(read_text(ROOT / "manifests" / "v0.1.0-draft.yaml"))
    bad = copy.deepcopy(doc)
    bad["components"]["shell"]["sha"] = "not-a-sha"
    assert check_manifest_doc(bad, "test") != []


def test_future_slot_must_not_carry_sha():
    import copy

    import yaml

    doc = yaml.safe_load(read_text(ROOT / "manifests" / "v0.1.0-draft.yaml"))
    bad = copy.deepcopy(doc)
    bad["components"]["installer"]["sha"] = "0" * 40
    bad["components"]["installer"]["ref"] = "main"
    assert check_manifest_doc(bad, "test") != []


def test_profile_cannot_ship_future_slot():
    import yaml

    manifest = yaml.safe_load(read_text(ROOT / "manifests" / "v0.1.0-draft.yaml"))
    profile = {
        "apiVersion": "hornero.os/v1",
        "kind": "EditionProfile",
        "name": "bad",
        "manifest": manifest["name"],
        "target": "vm",
        "components": [{"name": "installer"}],
    }
    assert check_profile_doc(profile, "test", {manifest["name"]: manifest}) != []


def test_release_must_reference_known_manifest():
    release = {
        "apiVersion": "hornero.os/v1",
        "kind": "Release",
        "name": "v9",
        "version": "9.0.0",
        "status": "draft",
        "manifest": "does-not-exist",
        "profiles": [],
    }
    assert check_release_doc(release, "test", {}, {}) != []


def test_all_three_editions_cover_pinned_components():
    import yaml

    manifest = yaml.safe_load(read_text(ROOT / "manifests" / "v0.1.0-draft.yaml"))
    pinned = {
        name
        for name, comp in manifest["components"].items()
        if comp["status"] in ("pinned", "local")
    }
    assert pinned == {"shell", "config", "horneroctl"}
    for edition in ("base", "desktop", "developer"):
        profile = yaml.safe_load(read_text(ROOT / "profiles" / f"{edition}.yaml"))
        assert {c["name"] for c in profile["components"]} == pinned


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q"]))
