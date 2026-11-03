"""Gaming specialization/application selection contract tests."""
from __future__ import annotations

import importlib.util
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location(
    "resolve_edition", ROOT / "scripts" / "resolve-edition.py"
)
assert SPEC and SPEC.loader
resolver = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(resolver)


def test_all_six_specializations_have_stable_ids():
    catalogue = resolver.load_catalogue()
    assert set(catalogue["gamingSpecializations"]) == {
        "desktop-gaming",
        "handheld",
        "streaming",
        "multi-launcher",
        "vr",
        "advanced-compat",
    }
    assert catalogue["gamingSpecializations"]["desktop-gaming"]["default"] is True


def test_specialization_never_installs_proprietary_steam():
    catalogue = resolver.load_catalogue()
    plan = resolver.resolve_gaming_selection(catalogue, ["desktop-gaming"])
    assert plan["applications"] == []
    assert plan["proprietaryOptInRequired"] == ["steam"]
    assert "steam" not in plan["packages"]
    assert "gamescope" in plan["packages"]


def test_explicit_steam_opt_in_is_recorded():
    catalogue = resolver.load_catalogue()
    plan = resolver.resolve_gaming_selection(catalogue, ["desktop-gaming"], ["steam"])
    assert plan["applications"] == ["steam"]
    assert "steam" in plan["packages"]
    assert plan["packageProvenance"]["steam"]["licenseClass"] == "proprietary"


def test_unknown_and_reference_only_selections_fail_actionably():
    catalogue = resolver.load_catalogue()
    with pytest.raises(ValueError, match="unknown gaming specialization"):
        resolver.resolve_gaming_selection(catalogue, ["esports"])
    with pytest.raises(ValueError, match="unknown gaming application"):
        resolver.resolve_gaming_selection(catalogue, [], ["origin"])
    with pytest.raises(ValueError, match="reference-only"):
        resolver.resolve_gaming_selection(catalogue, [], ["heroic-games-launcher"])
    with pytest.raises(ValueError, match="reference-only"):
        resolver.resolve_gaming_selection(catalogue, [], ["steamvr"])


def test_every_specialization_resolves_without_reference_only_apps():
    catalogue = resolver.load_catalogue()
    for spec_id in catalogue["gamingSpecializations"]:
        plan = resolver.resolve_gaming_selection(catalogue, [spec_id])
        assert plan["specializations"] == [spec_id]


def test_vr_specialization_is_flagged_experimental():
    catalogue = resolver.load_catalogue()
    plan = resolver.resolve_gaming_selection(catalogue, ["vr"], ["steam"])
    assert "vr" in plan["experimental"]


def test_selection_plan_is_deterministic_and_provenance_complete():
    catalogue = resolver.load_catalogue()
    first = resolver.resolve_gaming_selection(catalogue, ["streaming", "advanced-compat"])
    second = resolver.resolve_gaming_selection(catalogue, ["streaming", "advanced-compat"])
    assert first == second
    for package in first["packages"]:
        assert package in first["packageProvenance"]


def test_provenance_is_edition_scoped_for_shared_packages():
    catalogue = resolver.load_catalogue()
    gaming = resolver.resolve_gaming_selection(catalogue, ["streaming"])
    studio = resolver.resolve_studio_selection(
        catalogue, ["streaming-content-creation"]
    )
    assert gaming["packageProvenance"]["obs-studio"]["optional"] is True
    assert studio["packageProvenance"]["obs-studio"]["optional"] is False


# Vendor GPU driver packages must never enter a Gaming plan: the
# catalogue is hardware-neutral for AMD, Intel, NVIDIA, hybrid and
# unknown topologies alike, so every topology receives the same safe
# Vulkan loader set and doctor reports capability only.
VENDOR_DRIVER_PACKAGES = {
    "nvidia", "nvidia-dkms", "nvidia-open", "nvidia-open-dkms",
    "lib32-nvidia-utils", "nvidia-utils", "xf86-video-amdgpu",
    "xf86-video-intel", "xf86-video-nouveau", "vulkan-radeon",
    "lib32-vulkan-radeon", "vulkan-intel", "lib32-vulkan-intel",
    "vulkan-nouveau", "lib32-vulkan-nouveau",
}


def test_gaming_plans_are_hardware_neutral_for_every_specialization():
    catalogue = resolver.load_catalogue()
    for specialization in catalogue["gamingSpecializations"]:
        plan = resolver.resolve_gaming_selection(catalogue, [specialization])
        packages = set(plan["packages"])
        assert packages.isdisjoint(VENDOR_DRIVER_PACKAGES), specialization
        assert "vulkan-icd-loader" in packages, specialization
        assert "lib32-vulkan-icd-loader" in packages, specialization
