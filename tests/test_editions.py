"""Product-level edition package composition tests."""
from __future__ import annotations

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location(
    "resolve_edition", ROOT / "scripts" / "resolve-edition.py"
)
assert SPEC and SPEC.loader
resolver = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(resolver)


def test_catalogue_has_the_four_user_facing_editions():
    catalogue = resolver.load_catalogue()
    assert set(catalogue["editions"]) == {"desktop", "server", "agents", "studio"}
    assert catalogue["editions"]["desktop"]["maturity"] == "preview"
    assert catalogue["editions"]["server"]["maturity"] == "planned"
    assert catalogue["editions"]["agents"]["maturity"] == "planned"
    assert catalogue["editions"]["studio"]["maturity"] == "planned"


def test_desktop_uses_one_selected_compositor_backend():
    catalogue = resolver.load_catalogue()
    default = resolver.resolve_edition(catalogue, "desktop")
    niri = resolver.resolve_edition(catalogue, "desktop", "niri")
    assert default["compositor"] == "hyprland"
    assert "hyprland" in default["packages"]
    assert "niri" not in default["packages"]
    assert niri["compositor"] == "niri"
    assert niri["compositorMaturity"] == "experimental"
    assert "niri" in niri["packages"]
    assert "hyprland" not in niri["packages"]
    assert "xdg-desktop-portal-gnome" in niri["packages"]


def test_server_is_headless_and_remote_admin_focused():
    result = resolver.resolve_edition(resolver.load_catalogue(), "server")
    assert result["compositor"] is None
    assert {"openssh", "nftables", "tmux", "smartmontools"} <= set(result["packages"])
    assert not {"quickshell", "hornero-shell", "hyprland", "niri", "gtk3"} & set(result["packages"])


def test_agents_extend_server_without_host_docker_or_desktop_stack():
    catalogue = resolver.load_catalogue()
    result = resolver.resolve_edition(catalogue, "agents")
    assert {"openssh", "nftables", "podman", "crun"} <= set(result["packages"])
    assert not {"docker", "docker-compose", "quickshell", "hyprland", "niri"} & set(result["packages"])
    assert not {"fuse-overlayfs", "slirp4netns"} & set(result["packages"])
    assert {"fuse-overlayfs", "slirp4netns"} == set(catalogue["packageSets"]["agents"]["optionalPackages"])
    assert set(result["optionalPackages"]) == {"fuse-overlayfs", "slirp4netns"}
    model = catalogue["editions"]["agents"]["workloadModel"]
    assert model["hostDockerSocket"] == "forbidden"
    assert model["secretsInImage"] == "forbidden"


def test_studio_inherits_desktop_and_selected_compositor():
    result = resolver.resolve_edition(resolver.load_catalogue(), "studio", "niri")
    assert result["compositor"] == "niri"
    assert {"hornero-shell", "pipewire-jack", "ardour", "obs-studio", "kdenlive"} <= set(result["packages"])
    assert "reaper" not in result["packages"]


def test_headless_edition_rejects_a_compositor():
    import pytest

    with pytest.raises(ValueError, match="headless"):
        resolver.resolve_edition(resolver.load_catalogue(), "server", "niri")


def test_planned_compositor_cannot_be_offered_as_installable():
    import copy

    catalogue = resolver.load_catalogue()
    changed = copy.deepcopy(catalogue)
    changed["editions"]["desktop"]["compositor"]["supported"].append("labwc")
    assert any("planned compositor 'labwc'" in error for error in resolver.validate_catalogue(changed))


def test_optional_package_entries_are_validated_and_resolved():
    import copy

    catalogue = resolver.load_catalogue()
    changed = copy.deepcopy(catalogue)
    changed["packageSets"]["agents"]["optionalPackages"] = ["podman"]
    assert any("both required and optional" in error for error in resolver.validate_catalogue(changed))


def test_malformed_editions_return_validation_errors_instead_of_raising():
    import copy

    catalogue = resolver.load_catalogue()
    changed = copy.deepcopy(catalogue)
    changed["editions"]["agents"] = "invalid"
    changed["editions"]["studio"]["role"] = ""
    changed["packageSets"]["server"] = []
    errors = resolver.validate_catalogue(changed)
    assert any("edition 'agents' must be a mapping" in error for error in errors)
    assert any("edition 'studio' needs a non-empty role" in error for error in errors)
    assert any("package set 'server'" in error for error in errors)


def test_inheritance_cycle_with_non_mapping_entry_does_not_raise():
    import copy

    catalogue = resolver.load_catalogue()
    changed = copy.deepcopy(catalogue)
    changed["editions"]["agents"] = []
    errors = resolver.validate_catalogue(changed)
    assert any("edition 'agents' must be a mapping" in error for error in errors)
