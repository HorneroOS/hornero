"""Tests for the Hornero OS composition (manifests, profiles, releases)."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent


def _load_module(name, script):
    import importlib.util

    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_checker = _load_module("check_manifests", "check-manifests.py")
check_manifest_doc = _checker.check_manifest_doc
check_profile_doc = _checker.check_profile_doc
check_release_doc = _checker.check_release_doc
check_tree = _checker.check_tree
candidate_manifest_name = _checker.candidate_manifest_name

_pins = _load_module("check_pins", "check-pins.py")
read_candidate_name = _pins.read_candidate_name
manifest_pin_entries = _pins.manifest_pin_entries
validate_historical_manifests = _pins.validate_historical_manifests
compare_pins = _pins.compare_pins

# Preview 0 composition, frozen at tag v0.1.0-draft. These MUST match the
# tag forever: manifests/v0.1.0-draft.yaml is an immutable historical
# record, never a live pin surface.
SHELL_SHA = "b0a864cd57cfea01d7314c1de9823b873fb9269a"
CONFIG_SHA = "c4ac00326cd5476c5efc05c11a403d1d6353a7d6"

# Release-candidate composition (Development Preview 2).
CANDIDATE_SHELL_SHA = "4317bddcff59b367a87bc2984363a33ef7bf8103"
CANDIDATE_CONFIG_SHA = "923bdbc932036145f37ccea981d9cbc62f0f4077"


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


def test_candidate_pointer_is_explicit_and_deterministic():
    import yaml

    assert read_candidate_name(ROOT) == "v0.2.0-preview2.yaml"
    doc = yaml.safe_load(read_text(ROOT / "manifests" / "v0.2.0-preview2.yaml"))
    assert candidate_manifest_name(ROOT) == doc["name"] == "hornero-0.2.0-preview2"


def test_candidate_manifest_pins_release_candidate():
    import yaml

    doc = yaml.safe_load(read_text(ROOT / "manifests" / "v0.2.0-preview2.yaml"))
    assert doc["components"]["shell"]["sha"] == CANDIDATE_SHELL_SHA
    assert doc["components"]["config"]["sha"] == CANDIDATE_CONFIG_SHA
    assert doc["components"]["shell"]["status"] == "pinned"
    assert doc["components"]["config"]["status"] == "pinned"


def test_profiles_track_candidate_manifest():
    import yaml

    candidate = "hornero-0.2.0-preview2"
    assert candidate_manifest_name(ROOT) == candidate
    for edition in ("base", "desktop", "developer"):
        profile = yaml.safe_load(read_text(ROOT / "profiles" / f"{edition}.yaml"))
        assert profile["manifest"] == candidate


def test_historical_manifest_is_exempt_from_freshness():
    # Preview 0 pins are stale by design (b0a864c/c4ac003 predate current
    # mains). The freshness gate must NOT select them: only the candidate
    # manifest yields pin entries, and the structural check passes.
    assert validate_historical_manifests(ROOT, "v0.2.0-preview2.yaml") == []
    entries = manifest_pin_entries(ROOT / "manifests" / "v0.2.0-preview2.yaml")
    assert {name for _, name, _, _, _ in entries} == {"shell", "config"}
    stale = manifest_pin_entries(ROOT / "manifests" / "v0.1.0-draft.yaml")
    assert stale, "historical manifest must still parse its pins"
    # ... but comparing historical pins against live mains WOULD fail,
    # proving the exemption lives in manifest selection, not comparison.
    live = {
        ("https://github.com/HorneroOS/shell", "main"): CANDIDATE_SHELL_SHA,
        ("https://github.com/HorneroOS/config", "main"): CANDIDATE_CONFIG_SHA,
    }
    assert compare_pins(stale, live) != []
    assert compare_pins(entries, live) == []


def test_historical_release_survives_moved_profiles():
    import yaml

    release = yaml.safe_load(read_text(ROOT / "releases" / "v0.1.0-draft.yaml"))
    profiles = {
        edition: yaml.safe_load(read_text(ROOT / "profiles" / f"{edition}.yaml"))
        for edition in ("base", "desktop", "developer")
    }
    manifests = {"hornero-0.1.0-draft": None}
    # Strict mode flags the moved profiles (they track the candidate)...
    assert (
        check_release_doc(release, "test", manifests, profiles, True) != []
    )
    # ...while the historical path keeps existence validation only.
    assert (
        check_release_doc(release, "test", manifests, profiles, False) == []
    )


def test_unknown_profile_still_rejected_for_historical_release():
    release = {
        "apiVersion": "hornero.os/v1",
        "kind": "Release",
        "name": "v0",
        "version": "0.1.0-draft",
        "status": "pre-release",
        "manifest": "hornero-0.1.0-draft",
        "profiles": ["does-not-exist"],
    }
    assert (
        check_release_doc(release, "test", {"hornero-0.1.0-draft": None}, {}, False)
        != []
    )


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q"]))
