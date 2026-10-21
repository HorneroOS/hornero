#!/usr/bin/env bash
# Verify one horneroctl release asset against its detached signature
# using ONLY the in-repo public key (packaging/keys/hornero-release.pub.asc),
# imported into a throwaway keyring. A mismatch, a missing signature,
# or a missing public key is a hard failure.
#
# Usage: scripts/verify-release.sh <file> [signature]
set -euo pipefail

file="${1:?usage: verify-release.sh <file> [signature]}"
sig="${2:-${file}.asc}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pubkey="${repo_root}/packaging/keys/hornero-release.pub.asc"

[ -f "${file}" ] || { echo "FAIL: no such file: ${file}" >&2; exit 1; }
[ -f "${sig}" ] || { echo "FAIL: missing signature: ${sig}" >&2; exit 1; }
[ -f "${pubkey}" ] || {
  echo "FAIL: in-repo public key not committed yet: ${pubkey}" >&2
  echo "The maintainer key-generation step (docs/RELEASE_SIGNING.md) has not landed." >&2
  exit 1
}

tmp_home="$(mktemp -d)"
trap 'rm -rf "${tmp_home}"' EXIT
export GNUPGHOME="${tmp_home}"
chmod 700 "${GNUPGHOME}"

gpg --batch --quiet --import "${pubkey}"
if gpg --batch --status-fd 1 --verify "${sig}" "${file}" 2>/dev/null \
  | grep -q '^\[GNUPG:\] VALIDSIG '; then
  echo "OK: ${file} verifies against the in-repo HorneroOS release key"
else
  echo "FAIL: signature verification failed for ${file}" >&2
  exit 1
fi
