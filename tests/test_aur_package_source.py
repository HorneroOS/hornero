from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]


def test_cli_package_sources_include_signed_architecture_assets():
    pkgbuild = (ROOT / "packaging/horneroctl-bin/PKGBUILD").read_text()

    assert '"horneroctl-${pkgver}::' in pkgbuild
    assert '"horneroctl-${pkgver}.asc::' in pkgbuild
    assert "horneroctl-linux-x86_64.asc" in pkgbuild
    assert "horneroctl-linux-arm64.asc" in pkgbuild
    assert "validpgpkeys=(" in pkgbuild
    assert '"${srcdir}/horneroctl-${pkgver}"' in pkgbuild


def test_release_stays_draft_until_signed_assets_verify():
    workflow = yaml.safe_load(
        (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
    )
    jobs = workflow["jobs"]

    create_release = next(
        step for step in jobs["create-release"]["steps"]
        if step.get("name") == "Create or resume draft release"
    )
    assert "gh release create" in create_release["run"]
    assert "--draft --generate-notes" in create_release["run"]
    assert "Reusing existing draft release" in create_release["run"]
    assert set(jobs["publish-release"]["needs"]) == {"create-release", "build"}
    assert "publish-release" in jobs["aur-publish"]["needs"]

    upload = next(
        step for step in jobs["build"]["steps"] if step.get("name") == "Upload release asset"
    )
    publish = jobs["publish-release"]["steps"][0]
    for step in (upload, publish):
        assert step["env"]["RELEASE_TAG"] == "${{ needs.create-release.outputs.tag }}"
        assert "${{ needs.create-release.outputs.tag }}" not in step["run"]
        assert '"${RELEASE_TAG}"' in step["run"]

    signing = next(
        step for step in jobs["build"]["steps"] if step.get("name") == "Sign release asset"
    )
    assert "HORNERO_RELEASE_GPG_PRIVATE_KEY" in signing["env"]["SIGNING_KEY"]
    assert "refusing an unsigned release" in signing["run"]
    assert "scripts/verify-release.sh" in signing["run"]


def test_release_pin_export_uses_runner_yaml_without_installing_a_package():
    workflow = yaml.safe_load(
        (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
    )
    steps = workflow["jobs"]["build"]["steps"]
    export_pins = next(step for step in steps if step.get("name") == "Export composition pins")

    assert "pip install" not in export_pins["run"]
    assert "ruby -ryaml" in export_pins["run"]
    assert "YAML.safe_load_file" in export_pins["run"]
    assert "aliases: false" in export_pins["run"]


def test_plugin_management_tools_are_documented_optional_dependencies():
    pkgbuild = (ROOT / "packaging/horneroctl-bin/PKGBUILD").read_text()

    assert "'git: install community Shell plugin packages from HTTPS repositories'" in pkgbuild
    assert "'hornero-shell: validate community plugin packages with the Shell-owned contract checker'" in pkgbuild
