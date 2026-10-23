#!/usr/bin/env bash
# Stamp the AUR PKGBUILD with hashes and trusted fingerprints for one release.
# Usage: scripts/stamp-aur-package.sh <horneroctl-tag> <download-dir> [PKGBUILD]
set -euo pipefail

tag="${1:?usage: stamp-aur-package.sh <horneroctl-tag> <download-dir> [PKGBUILD]}"
assets="${2:?usage: stamp-aur-package.sh <horneroctl-tag> <download-dir> [PKGBUILD]}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pkgbuild="${3:-${repo_root}/packaging/horneroctl-bin/PKGBUILD}"
pubkey="${repo_root}/packaging/keys/hornero-release.pub.asc"

[[ "${tag}" =~ ^horneroctl-v[0-9]+(\.[0-9]+)*(-[A-Za-z0-9.]+)?$ ]] || {
  echo "FAIL: invalid horneroctl release tag: ${tag}" >&2
  exit 1
}
[[ -s "${pubkey}" ]] || {
  echo "FAIL: committed release public key is missing: ${pubkey}" >&2
  exit 1
}
[[ -f "${pkgbuild}" ]] || { echo "FAIL: missing PKGBUILD: ${pkgbuild}" >&2; exit 1; }

version="${tag#horneroctl-v}"
aur_version="${version//-/_}"
fingerprints="$(gpg --batch --with-colons --show-keys "${pubkey}" \
  | awk -F: '$1 == "pub" { want=1; next } want && $1 == "fpr" { print $10; want=0 }')"
[[ -n "${fingerprints}" ]] || {
  echo "FAIL: no public-key fingerprints found in ${pubkey}" >&2
  exit 1
}

declare -A hashes
for arch in x86_64 aarch64; do
  if [[ "${arch}" == x86_64 ]]; then
    asset="horneroctl-linux-x86_64"
  else
    asset="horneroctl-linux-arm64"
  fi
  binary="${assets}/${asset}"
  signature="${binary}.asc"
  [[ -s "${binary}" && -s "${signature}" ]] || {
    echo "FAIL: missing release binary or signature for ${arch}" >&2
    exit 1
  }
  "${repo_root}/scripts/verify-release.sh" "${binary}" "${signature}"
  hashes["${arch}"]="$(sha256sum "${binary}" "${signature}" | awk '{ print $1 }' | paste -sd' ' -)"
done

python3 - "${pkgbuild}" "${tag}" "${aur_version}" "${fingerprints}" \
  "${hashes[x86_64]}" "${hashes[aarch64]}" <<'PY'
from pathlib import Path
import re
import sys

pkgbuild, tag, version, fingerprint_text, x86_hashes, arm_hashes = sys.argv[1:]
path = Path(pkgbuild)
lines = path.read_text(encoding="utf-8").splitlines()

def replace_assignment(name: str, value: str) -> None:
    matches = [i for i, line in enumerate(lines) if line.startswith(f"{name}=")]
    if len(matches) != 1:
        raise SystemExit(f"FAIL: expected exactly one {name}= assignment in {path}")
    lines[matches[0]] = f"{name}={value}"

fingerprints = fingerprint_text.split()
if not fingerprints or any(re.fullmatch(r"[0-9A-Fa-f]{40,64}", fpr) is None for fpr in fingerprints):
    raise SystemExit("FAIL: invalid release public-key fingerprint")
for hashes in (x86_hashes.split(), arm_hashes.split()):
    if len(hashes) != 2 or any(len(value) != 64 for value in hashes):
        raise SystemExit("FAIL: expected SHA-256 values for binary and signature")

replace_assignment("_reltag", tag)
replace_assignment("pkgver", version)
replace_assignment("validpgpkeys", "(" + " ".join(f"'{fpr}'" for fpr in fingerprints) + ")")
replace_assignment("sha256sums_x86_64", "(" + " ".join(f"'{value}'" for value in x86_hashes.split()) + ")")
replace_assignment("sha256sums_aarch64", "(" + " ".join(f"'{value}'" for value in arm_hashes.split()) + ")")
path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

echo "AUR metadata stamped and both architecture signatures verified for ${tag}"
