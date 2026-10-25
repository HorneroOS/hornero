"""Composable Studio specialization and application selection tests."""
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


def catalogue():
    return resolver.load_catalogue()


def test_all_ten_specializations_have_stable_ids():
    specializations = catalogue()["studioSpecializations"]
    assert set(specializations) == resolver.REQUIRED_SPECIALIZATIONS
    for spec_id, specialization in specializations.items():
        assert specialization["title"], spec_id


def test_audio_plus_streaming_excludes_unrelated_workloads():
    plan = resolver.resolve_studio_selection(
        catalogue(), ["audio-music-production", "streaming-content-creation"]
    )
    packages = set(plan["packages"])
    assert {"ardour", "guitarix", "obs-studio", "ffmpeg"} <= packages
    assert not {"kdenlive", "blender", "krita", "gimp", "inkscape", "darktable", "freecad", "godot"} & packages


def test_custom_selection_supports_application_only_choice():
    plan = resolver.resolve_studio_selection(catalogue(), ["custom-selection"], ["krita"])
    assert plan["applications"] == ["krita"]
    assert "krita" in plan["packages"]
    assert "ardour" not in plan["packages"]
    # The shared pro-audio platform is always present for Studio selections.
    assert "pipewire-jack" in plan["packages"]


def test_complete_is_union_and_shared_packages_deduplicated():
    catalogue_doc = catalogue()
    plan = resolver.resolve_studio_selection(catalogue_doc, ["complete-creative-workstation"])
    assert plan["packages"].count("blender") == 1
    assert plan["packages"].count("ffmpeg") == 1
    assert {"godot", "freecad", "darktable", "scribus"} <= set(plan["packages"])


def test_proprietary_apps_need_explicit_opt_in():
    catalogue_doc = catalogue()
    by_group = resolver.resolve_studio_selection(catalogue_doc, ["audio-music-production"])
    assert "reaper" not in by_group["packages"]
    assert by_group["proprietaryOptInRequired"] == ["reaper"]
    explicit = resolver.resolve_studio_selection(catalogue_doc, [], ["reaper"])
    assert "reaper" in explicit["packages"]
    assert explicit["packageProvenance"]["reaper"]["licenseClass"] == "proprietary"


def test_unknown_and_reference_only_selections_fail_actionably():
    catalogue_doc = catalogue()
    with pytest.raises(ValueError, match="unknown studio specialization"):
        resolver.resolve_studio_selection(catalogue_doc, ["nope"])
    with pytest.raises(ValueError, match="unknown studio application"):
        resolver.resolve_studio_selection(catalogue_doc, [], ["nope"])
    with pytest.raises(ValueError, match="reference-only"):
        resolver.resolve_studio_selection(catalogue_doc, [], ["penpot"])


def test_experimental_apps_are_flagged_not_silent():
    plan = resolver.resolve_studio_selection(catalogue(), [], ["graphite"])
    assert plan["experimental"] == ["graphite"]
    assert "graphite" in plan["packages"]


def test_selection_plan_is_deterministic_and_provenance_complete():
    catalogue_doc = catalogue()
    first = resolver.resolve_studio_selection(
        catalogue_doc, ["photography-raw-processing", "audio-music-production"], ["krita"]
    )
    second = resolver.resolve_studio_selection(
        catalogue_doc, ["photography-raw-processing", "audio-music-production"], ["krita"]
    )
    assert first == second
    assert set(first["packageProvenance"]) == set(first["packages"])
    assert first["schemaVersion"] == 1


def test_non_studio_resolution_is_unchanged_without_selection():
    result = resolver.resolve_edition(catalogue(), "desktop")
    assert "hornero-shell" in result["packages"]
    assert result["edition"] == "desktop"


def test_selection_model_rejects_broken_group_contracts():
    import copy

    catalogue_doc = catalogue()
    changed = copy.deepcopy(catalogue_doc)
    changed["studioSpecializations"]["maker-cad"]["applications"].append("penpot")
    errors = resolver.validate_catalogue(changed)
    assert any("complete-creative-workstation must be the union" in error for error in errors)

    changed = copy.deepcopy(catalogue_doc)
    changed["studioApplications"]["krita"]["packages"] = ["not-a-real-package"]
    errors = resolver.validate_catalogue(changed)
    assert any("missing provenance" in error for error in errors)
