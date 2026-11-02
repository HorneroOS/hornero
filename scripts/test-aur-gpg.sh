#!/usr/bin/env bash
# Regression test for the horneroctl-bin AUR GPG failure
# ("gpg: keyserver receive failed: No data" on fresh installs).
#
# Builds the STAMPED AUR package (the PKGBUILD as published to AUR, with
# real pkgver/checksums/validpgpkeys) in throwaway GNUPGHOMEs whose
# keyserver is deliberately unreachable, proving that:
#   1. fresh install works by importing the shipped keys/pgp/<fpr>.asc
#      after checking its fingerprint against the pinned validpgpkeys;
#   2. with no key available the build still fails closed (unknown key);
#   3. an unrelated key in the keyring does not satisfy validpgpkeys;
#   4. a tampered download is rejected.
# The user's real keyring is never touched. Network is used only to
# download the release assets named by the PKGBUILD sources.
# Scope note: case 1 proves the manual-import path that always works.
# Automatic helper retrieval (yay/paru fetching validpgpkeys from
# keyservers) is a separate channel, covered by publishing the key to
# public keyservers and verified with a fresh keyring at release time
# (see docs/RELEASE_SIGNING.md); it is not re-proven here.
#
# Usage: scripts/test-aur-gpg.sh [stamped-package-dir]
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pkg_src="${1:-${repo_root}/packaging/horneroctl-bin}"
[[ -f "${pkg_src}/PKGBUILD" ]] || { echo "FAIL: no PKGBUILD in ${pkg_src}" >&2; exit 1; }

if grep -q "validpgpkeys=('0000000000000000000000000000000000000000')" "${pkg_src}/PKGBUILD"; then
  echo "FAIL: ${pkg_src}/PKGBUILD is the unstamped template; test the published AUR snapshot instead" >&2
  exit 1
fi
if grep -q 'skippgpcheck' "${pkg_src}/PKGBUILD"; then
  echo "FAIL: PKGBUILD must never use --skippgpcheck" >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

pinned_fprs() {
  # shellcheck disable=SC1091
  ( source "${pkg_src}/PKGBUILD" >/dev/null 2>&1; printf '%s\n' "${validpgpkeys[@]}" )
}
mapfile -t PINNED_FPRS < <(pinned_fprs)
[[ ${#PINNED_FPRS[@]} -ge 1 ]] || { echo "FAIL: no validpgpkeys parsed" >&2; exit 1; }
for fpr in "${PINNED_FPRS[@]}"; do
  [[ "${fpr}" =~ ^[0-9A-F]{40}$ ]] || { echo "FAIL: pinned fingerprint not parsed: '${fpr}'" >&2; exit 1; }
done
FPR="${PINNED_FPRS[0]}"
# The key ships as a declared package source (included in every AUR
# snapshot tarball) and, for git clones, also under keys/pgp/.
key_file="${pkg_src}/hornero-release.pub"
[[ -s "${key_file}" ]] || key_file="${pkg_src}/keys/pgp/${FPR}.asc"
[[ -s "${key_file}" ]] || {
  echo "FAIL: shipped key missing: ${pkg_src}/hornero-release.pub" >&2; exit 1; }

new_home() {
  local home="${work}/gnupg-$1"
  mkdir -p "${home}"
  chmod 700 "${home}"
  # Deliberately unavailable keyserver: the fix must not depend on one.
  printf 'keyserver hkps://invalid.invalid\n' > "${home}/dirmngr.conf"
  printf '%s' "${home}"
}

copy_pkg() {
  local dest="${work}/pkg-$1"
  mkdir -p "${dest}"
  cp -r "${pkg_src}/." "${dest}/"
  printf '%s' "${dest}"
}

build() { # <gnupghome> <pkgdir>
  ( cd "$2" && GNUPGHOME="$1" makepkg --noconfirm --nodeps -f ) \
    >"$2/build.log" 2>&1
}

echo "== case 1: fresh install, broken keyserver, shipped key =="
home1="$(new_home fresh)"
export GNUPGHOME="${home1}"
# Import EVERY pinned key (key rotation keeps old + replacement in
# validpgpkeys for a full cycle; the signing key may be any of them).
# The shipped file may be a bundle; verify each pinned fingerprint is
# actually present after import instead of trusting the first key.
gpg --batch --quiet --import "${key_file}"
for fpr in "${PINNED_FPRS[@]}"; do
  per_key="${pkg_src}/keys/pgp/${fpr}.asc"
  if [[ -s "${per_key}" ]]; then
    gpg --batch --quiet --import "${per_key}"
  fi
  gpg --batch --list-keys "${fpr}" >/dev/null 2>&1 || {
    echo "FAIL: pinned fingerprint ${fpr} not importable from shipped key material" >&2
    exit 1; }
done
unset GNUPGHOME
pkg1="$(copy_pkg fresh)"
if ! build "${home1}" "${pkg1}"; then
  tail -20 "${pkg1}/build.log" >&2
  echo "FAIL: fresh build with shipped key did not succeed" >&2; exit 1
fi
grep -q "Verifying source file signatures" "${pkg1}/build.log"
echo "PASS: fresh install verifies signatures without any keyserver"

echo "== case 2: no key available still fails closed =="
home2="$(new_home missing)"
pkg2="$(copy_pkg missing)"
if build "${home2}" "${pkg2}"; then
  echo "FAIL: build without the release key unexpectedly succeeded" >&2; exit 1
fi
grep -Eq "unknown public key|One or more PGP signatures could not be verified" "${pkg2}/build.log"
echo "PASS: missing key is a hard failure, never a silent skip"

echo "== case 3: unrelated key does not satisfy validpgpkeys =="
home3="$(new_home wrong)"
GNUPGHOME="${home3}" gpg --batch --passphrase '' --quick-generate-key \
  "Unrelated Test <unrelated@example.invalid>" ed25519 sign never >/dev/null 2>&1
pkg3="$(copy_pkg wrong)"
if build "${home3}" "${pkg3}"; then
  echo "FAIL: build with an unrelated key unexpectedly succeeded" >&2; exit 1
fi
echo "PASS: invalid fingerprint rejected"

echo "== case 4: tampered download is rejected =="
pkg4="$(copy_pkg tampered)"
build_home="${home1}"
# Prime the source cache with a good download, then flip one byte.
( cd "${pkg4}" && GNUPGHOME="${build_home}" makepkg --noconfirm --nodeps -o ) \
  >"${pkg4}/prime.log" 2>&1
binary="$(find "${pkg4}" -maxdepth 1 -type f -name 'horneroctl-*' ! -name '*.asc' | head -1)"
[[ -n "${binary}" ]] || { echo "FAIL: downloaded binary not found in ${pkg4}" >&2; exit 1; }
printf 'X' | dd of="${binary}" bs=1 seek=64 count=1 conv=notrunc status=none
if build "${build_home}" "${pkg4}"; then
  echo "FAIL: tampered download unexpectedly built" >&2; exit 1
fi
echo "PASS: tampered download rejected"

echo "OK: all AUR GPG regression cases passed for ${FPR}"
