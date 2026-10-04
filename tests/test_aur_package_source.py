from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_cli_package_source_filename_changes_with_package_version():
    pkgbuild = (ROOT / "packaging/horneroctl-bin/PKGBUILD").read_text()

    assert 'source_x86_64=("horneroctl-${pkgver}::' in pkgbuild
    assert 'source_aarch64=("horneroctl-${pkgver}::' in pkgbuild
    assert '"${srcdir}/horneroctl-${pkgver}"' in pkgbuild
