"""Reversible Studio audio and performance mode contract tests."""
from __future__ import annotations

import copy
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location(
    "resolve_edition", ROOT / "scripts" / "resolve-edition.py"
)
assert SPEC and SPEC.loader
resolver = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(resolver)


def catalogue():
    return resolver.load_catalogue()


def test_balanced_is_the_only_default_and_others_opt_in():
    modes = catalogue()["studioAudioModes"]
    assert modes["balanced"]["default"] is True
    assert modes["balanced"]["explicitOptIn"] is False
    for name in ("low-latency", "advanced"):
        assert modes[name]["default"] is False
        assert modes[name]["explicitOptIn"] is True


def test_modes_restore_previous_state_and_never_equate_quantum_with_latency():
    for mode in catalogue()["studioAudioModes"].values():
        assert {"disable", "error"} <= set(mode["restoresPreviousStateOn"])
        assert mode["presentsQuantumAsPhysicalLatency"] is False


def test_performance_mode_is_temporary_and_forbids_global_tuning():
    performance = catalogue()["studioPerformanceMode"]
    assert performance["temporary"] is True
    assert performance["usesPowerProfilesDaemon"] is True
    assert {"timeout", "cancel", "error"} <= set(performance["restoresPreviousStateOn"])
    assert set(performance["forbiddenOperations"]) == resolver.FORBIDDEN_MODE_OPERATIONS


def test_studio_resolution_exposes_mode_contract_only_for_studio():
    studio = resolver.resolve_edition(catalogue(), "studio")
    assert set(studio["audioModes"]) == {"balanced", "low-latency", "advanced"}
    assert studio["performanceMode"]["temporary"] is True
    desktop = resolver.resolve_edition(catalogue(), "desktop")
    assert desktop["audioModes"] is None
    assert desktop["performanceMode"] is None


def test_mode_contract_rejects_unsafe_mutations():
    changed = copy.deepcopy(catalogue())
    changed["studioAudioModes"]["low-latency"]["explicitOptIn"] = False
    assert any("explicit opt-in" in error for error in resolver.validate_catalogue(changed))

    changed = copy.deepcopy(catalogue())
    changed["studioAudioModes"]["balanced"]["presentsQuantumAsPhysicalLatency"] = True
    assert any("physical latency" in error for error in resolver.validate_catalogue(changed))

    changed = copy.deepcopy(catalogue())
    changed["studioPerformanceMode"]["forbiddenOperations"] = ["rt-kernel"]
    assert any("forbid" in error for error in resolver.validate_catalogue(changed))

    changed = copy.deepcopy(catalogue())
    changed["studioPerformanceMode"]["usesPowerProfilesDaemon"] = False
    assert any("power-profiles-daemon" in error for error in resolver.validate_catalogue(changed))
