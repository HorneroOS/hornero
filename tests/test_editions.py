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


def test_catalogue_has_the_five_user_facing_editions():
    catalogue = resolver.load_catalogue()
    assert set(catalogue["editions"]) == {"desktop", "server", "agents", "studio", "gaming"}
    assert catalogue["editions"]["desktop"]["maturity"] == "preview"
    assert catalogue["editions"]["server"]["maturity"] == "planned"
    assert catalogue["editions"]["agents"]["maturity"] == "planned"
    assert catalogue["editions"]["studio"]["maturity"] == "preview"
    assert catalogue["editions"]["gaming"]["maturity"] == "preview"


def test_desktop_uses_one_selected_compositor_backend():
    catalogue = resolver.load_catalogue()
    default = resolver.resolve_edition(catalogue, "desktop")
    niri = resolver.resolve_edition(catalogue, "desktop", "niri")
    assert default["compositor"] == "hyprland"
    assert "hyprland" in default["packages"]
    assert "niri" not in default["packages"]
    assert not {"xdg-desktop-portal-gtk", "xdg-desktop-portal-gnome"} & set(default["packages"])
    assert niri["compositor"] == "niri"
    assert niri["compositorMaturity"] == "experimental"
    assert "niri" in niri["packages"]
    assert "hyprland" not in niri["packages"]
    assert {"xdg-desktop-portal-gtk", "xdg-desktop-portal-gnome"} <= set(niri["packages"])


def test_shared_base_contains_filesystems_encryption_and_bootloaders():
    packages = set(resolver.load_catalogue()["base"]["packages"])
    required = {"btrfs-progs", "cryptsetup", "dosfstools", "efibootmgr", "e2fsprogs", "grub", "lvm2"}
    assert required <= packages


def test_desktop_composition_contains_a_login_manager_and_hornero_greeter():
    packages = set(resolver.resolve_edition(resolver.load_catalogue(), "desktop")["packages"])
    required = {"sddm", "hornero-greeter", "hornero-greeter-media-base"}
    assert required <= packages


def test_desktop_composition_installs_factory_default_providers():
    packages = set(resolver.resolve_edition(resolver.load_catalogue(), "desktop")["packages"])
    required = {
        "exo",
        "papirus-icon-theme",
        "qt6ct",
        "ttf-cascadia-code-nerd",
        "ttf-material-symbols-variable",
        "ttf-rubik-vf",
    }
    assert required <= packages


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


def test_studio_provenance_covers_every_studio_package_and_integration():
    catalogue = resolver.load_catalogue()
    provenance = catalogue["studioProvenance"]
    studio_packages = set(catalogue["packageSets"]["studio"]["packages"])
    assert studio_packages <= set(provenance)
    assert {"reaper", "yabridge", "yabridgectl"} <= set(provenance)
    for entry in provenance.values():
        assert entry["source"] == "arch-extra"
        assert entry["sourceUrl"].startswith("https://archlinux.org/packages/extra/x86_64/")
        assert entry["licenses"]
        assert entry["support"] == "planned"


def test_studio_optional_integrations_use_arch_extra_not_aur():
    catalogue = resolver.load_catalogue()
    integrations = {item["id"]: item for item in catalogue["editions"]["studio"]["optionalIntegrations"]}
    assert integrations["reaper"]["source"] == "arch-extra"
    assert integrations["yabridge"]["source"] == "arch-extra"
    reaper = catalogue["studioProvenance"]["reaper"]
    assert reaper["licenseClass"] == "proprietary"
    assert reaper["optional"] is True
    assert "reaper" not in resolver.resolve_edition(catalogue, "studio")["packages"]
    yabridge = catalogue["studioProvenance"]["yabridge"]
    assert yabridge["optional"] is True
    assert "Wine" in yabridge["notes"]


def test_studio_resolution_exposes_provenance_without_changing_packages():
    catalogue = resolver.load_catalogue()
    result = resolver.resolve_edition(catalogue, "studio", "niri")
    assert set(result["packageProvenance"]) == set(catalogue["packageSets"]["studio"]["packages"])
    assert result["packageProvenance"]["ardour"]["licenses"]
    assert {item["id"] for item in result["optionalIntegrations"]} == {"reaper", "yabridge"}
    desktop = resolver.resolve_edition(catalogue, "desktop")
    assert desktop["packageProvenance"] == {}
    assert desktop["optionalIntegrations"] == []


def test_studio_provenance_rejects_missing_and_invalid_metadata():
    import copy

    catalogue = resolver.load_catalogue()
    missing = copy.deepcopy(catalogue)
    del missing["studioProvenance"]["ardour"]
    assert any("missing provenance" in error for error in resolver.validate_catalogue(missing))

    invalid = copy.deepcopy(catalogue)
    invalid["studioProvenance"]["ardour"]["source"] = "somewhere"
    invalid["studioProvenance"]["ardour"]["licenses"] = []
    errors = resolver.validate_catalogue(invalid)
    assert any("invalid source" in error for error in errors)
    assert any("licenses" in error for error in errors)


def test_studio_provenance_rejects_proprietary_defaults_and_aur_execution():
    import copy

    catalogue = resolver.load_catalogue()
    proprietary = copy.deepcopy(catalogue)
    proprietary["studioProvenance"]["reaper"]["optional"] = False
    assert any("proprietary" in error for error in resolver.validate_catalogue(proprietary))

    aur = copy.deepcopy(catalogue)
    aur["studioProvenance"]["ardour"]["source"] = "aur"
    aur["studioProvenance"]["ardour"]["installMethod"] = "pacman-repository"
    assert any("AUR" in error for error in resolver.validate_catalogue(aur))


def test_studio_composition_excludes_legacy_pipewire_media_session():
    import copy

    catalogue = resolver.load_catalogue()
    assert "pipewire-media-session" not in catalogue["packageSets"]["studio"]["packages"]
    assert catalogue["studioProvenance"]["wireplumber"]["source"] == "arch-extra"
    changed = copy.deepcopy(catalogue)
    changed["packageSets"]["studio"]["packages"].append("pipewire-media-session")
    changed["studioProvenance"]["pipewire-media-session"] = copy.deepcopy(
        changed["studioProvenance"]["wireplumber"]
    )
    assert any("legacy package 'pipewire-media-session'" in error for error in resolver.validate_catalogue(changed))


def test_gaming_inherits_desktop_and_selected_compositor():
    catalogue = resolver.load_catalogue()
    desktop = resolver.resolve_edition(catalogue, "desktop")
    gaming = resolver.resolve_edition(catalogue, "gaming")
    gaming_niri = resolver.resolve_edition(catalogue, "gaming", "niri")
    assert gaming["extends"] if "extends" in gaming else True
    assert set(desktop["packages"]) <= set(gaming["packages"])
    assert "gamescope" in gaming["packages"]
    assert "steam" not in gaming["packages"]
    assert gaming_niri["compositor"] == "niri"
    assert "gamescope" in gaming_niri["packages"]


def test_gaming_provenance_rejects_proprietary_defaults_and_aur_execution():
    import copy

    catalogue = resolver.load_catalogue()

    broken = copy.deepcopy(catalogue)
    broken["gamingProvenance"]["steam"]["optional"] = False
    assert any("must be optional" in e for e in resolver._validate_gaming_provenance(broken, broken["packageSets"]))

    broken = copy.deepcopy(catalogue)
    broken["gamingProvenance"]["bottles"]["installMethod"] = "pacman-repository"
    assert any("AUR" in e for e in resolver._validate_gaming_provenance(broken, broken["packageSets"]))

    broken = copy.deepcopy(catalogue)
    del broken["gamingProvenance"]["gamescope"]
    errors = resolver._validate_gaming_provenance(broken, broken["packageSets"])
    assert any("gamescope" in e for e in errors)
