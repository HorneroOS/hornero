import copy
import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent

spec = importlib.util.spec_from_file_location(
    "resolve_edition_installation", ROOT / "scripts" / "resolve-edition.py"
)
resolver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resolver)


def catalogue():
    return resolver.load_catalogue()


def test_catalogue_schema_valid_and_required_maps():
    doc = catalogue()
    assert resolver.validate_catalogue(doc) == []
    assert set(doc["kernels"]) == {"linux", "linux-lts", "linux-zen", "linux-hardened"}
    assert set(doc["bootloaders"]) == {"grub", "systemd-boot"}
    assert set(doc["capabilities"]) == {"bluetooth", "printing", "openssh", "developer"}


def test_default_installation_matches_legacy_plus_bluetooth_contract():
    doc = catalogue()
    legacy = resolver.resolve_edition(doc, "desktop")
    plan = resolver.resolve_installation(doc, "desktop")
    # Bluetooth workstream contract: bluez/bluez-utils + bluetooth.service.
    assert set(plan["packages"]) == set(legacy["packages"]) | {"bluez", "bluez-utils", "linux-headers"}
    assert len(plan["packages"]) == len(set(plan["packages"]))
    assert plan["selection"]["kernels"] == ["linux"]
    assert plan["selection"]["bootloader"] == "grub"
    assert plan["services"] == ["bluetooth.service"]
    assert plan["espRecommendedMiB"] == 512
    assert plan["schemaVersion"] == 2


def test_presets_unchanged_via_legacy_resolver():
    doc = catalogue()
    for edition in ("desktop", "studio", "gaming"):
        plan = resolver.resolve_installation(doc, edition)
        legacy = resolver.resolve_edition(doc, edition)
        assert set(legacy["packages"]) <= set(plan["packages"])
        assert "linux" in plan["packages"] and "grub" in plan["packages"]


def test_kernel_substitution_adds_matching_headers_once():
    plan = resolver.resolve_installation(catalogue(), "desktop", kernels=["linux-lts"], primary_kernel="linux-lts", capabilities=[])
    assert "linux-lts" in plan["packages"] and "linux-lts-headers" in plan["packages"]
    assert "linux" not in plan["packages"] and "linux-headers" not in plan["packages"]
    assert plan["kernelImages"] == ["vmlinuz-linux-lts"]


def test_dual_kernel_primary_and_fallback():
    plan = resolver.resolve_installation(
        catalogue(), "desktop", kernels=["linux", "linux-lts"],
        primary_kernel="linux", fallback_kernel="linux-lts", capabilities=[],
    )
    assert plan["selection"]["kernels"] == ["linux", "linux-lts"]
    assert {"linux", "linux-headers", "linux-lts", "linux-lts-headers"} <= set(plan["packages"])
    assert plan["espRecommendedMiB"] == 768


def test_each_supported_kernel_resolves():
    for kernel in ("linux", "linux-lts", "linux-zen", "linux-hardened"):
        plan = resolver.resolve_installation(catalogue(), "desktop", kernels=[kernel], primary_kernel=kernel, capabilities=[])
        assert kernel in plan["packages"] and f"{kernel}-headers" in plan["packages"]


def test_systemd_boot_requires_uefi():
    doc = catalogue()
    plan = resolver.resolve_installation(doc, "desktop", bootloader="systemd-boot", firmware="uefi", capabilities=[])
    assert plan["espRecommendedMiB"] == 1024
    assert "grub" not in plan["packages"]
    with pytest.raises(ValueError, match="systemd-boot needs UEFI"):
        resolver.resolve_installation(doc, "desktop", bootloader="systemd-boot", firmware="bios")


def test_grub_allows_bios_and_luks_preserved_in_selection():
    plan = resolver.resolve_installation(catalogue(), "desktop", bootloader="grub", firmware="bios", encryption="luks", capabilities=[])
    assert plan["selection"]["encryption"] == "luks"


def test_capabilities_compose_and_disable():
    doc = catalogue()
    plan = resolver.resolve_installation(doc, "desktop", capabilities=["printing", "developer"])
    assert {"cups", "sane", "simple-scan", "base-devel", "gdb"} <= set(plan["packages"])
    assert plan["services"] == ["cups.service"]
    off = resolver.resolve_installation(doc, "desktop", disabled_capabilities=["bluetooth"])
    assert "bluez" not in off["packages"] and off["services"] == []


def test_openssh_default_on_server_not_desktop():
    doc = catalogue()
    assert "openssh" in resolver.resolve_installation(doc, "server")["selection"]["capabilities"]
    assert resolver.resolve_installation(doc, "server")["services"] == ["sshd.service"]
    assert "openssh" not in resolver.resolve_installation(doc, "desktop")["selection"]["capabilities"]


def test_capability_on_wrong_edition_raises():
    with pytest.raises(ValueError, match="not available for edition 'server'"):
        resolver.resolve_installation(catalogue(), "server", capabilities=["printing"])


def test_incompatibility_errors():
    doc = catalogue()
    with pytest.raises(ValueError, match="at least one kernel"):
        resolver.resolve_installation(doc, "desktop", kernels=[])
    with pytest.raises(ValueError, match="primary kernel must be one of"):
        resolver.resolve_installation(doc, "desktop", kernels=["linux"], primary_kernel="linux-lts")
    with pytest.raises(ValueError, match="fallback kernel must differ"):
        resolver.resolve_installation(doc, "desktop", kernels=["linux", "linux-lts"], primary_kernel="linux", fallback_kernel="linux")
    with pytest.raises(ValueError, match="unknown kernel"):
        resolver.resolve_installation(doc, "desktop", kernels=["linux-rt"])
    with pytest.raises(ValueError, match="unknown capability"):
        resolver.resolve_installation(doc, "desktop", capabilities=["nope"])


def test_hardened_proprietary_nvidia_warns_and_uses_dkms():
    plan = resolver.resolve_installation(
        catalogue(), "gaming", kernels=["linux-hardened"], primary_kernel="linux-hardened",
        proprietary_nvidia=True,
    )
    assert plan["nvidiaModule"] == "nvidia-open-dkms"
    assert any("linux-hardened" in w and "NVIDIA" in w for w in plan["planWarnings"])
    single = resolver.resolve_installation(catalogue(), "gaming", proprietary_nvidia=True)
    assert single["nvidiaModule"] == "nvidia-open"


def test_deterministic_byte_identical_json():
    doc = catalogue()
    kwargs = dict(kernels=["linux", "linux-zen"], primary_kernel="linux-zen", fallback_kernel="linux", capabilities=["developer", "printing"])
    first = json.dumps(resolver.resolve_installation(doc, "desktop", **kwargs), indent=2, sort_keys=True)
    second = json.dumps(resolver.resolve_installation(doc, "desktop", **kwargs), indent=2, sort_keys=True)
    assert first == second


def test_schema_validation_rejects_broken_installation_model():
    doc = catalogue()
    broken = copy.deepcopy(doc)
    broken["bootloaders"]["systemd-boot"]["firmwares"] = ["uefi", "bios"]
    assert any("systemd-boot" in e for e in resolver.validate_catalogue(broken))
    broken2 = copy.deepcopy(doc)
    del broken2["installationProvenance"]["linux-zen-headers"]
    assert any("linux-zen-headers" in e for e in resolver.validate_catalogue(broken2))
    broken3 = copy.deepcopy(doc)
    broken3["capabilities"]["bluetooth"]["defaultByEdition"] = {"desktop": True}
    assert any("bluetooth" in e for e in resolver.validate_catalogue(broken3))


def test_cli_installation_plan():
    out = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "resolve-edition.py"), "desktop", "--installation",
         "--kernel", "linux", "--kernel", "linux-lts", "--primary-kernel", "linux",
         "--fallback-kernel", "linux-lts", "--bootloader", "systemd-boot", "--capability", "printing"],
        capture_output=True, text=True, check=True,
    )
    plan = json.loads(out.stdout)
    assert plan["selection"]["bootloader"] == "systemd-boot"
    assert plan["espRecommendedMiB"] == 1280
    assert "cups" in plan["packages"]
