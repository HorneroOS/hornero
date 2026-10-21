#!/usr/bin/env bash
# Sign one horneroctl release asset with a detached armoured GPG
# signature (<file>.asc). The private key must already be in the
# keyring selected by GNUPGHOME; this script never imports, generates,
# or prints key material.
#
# Usage: HORNERO_RELEASE_KEY_ID=<fingerprint> scripts/sign-release.sh <file>
set -euo pipefail

file="${1:?usage: sign-release.sh <file>}"
key_id="${HORNERO_RELEASE_KEY_ID:?set HORNERO_RELEASE_KEY_ID to the release key fingerprint}"

[ -f "${file}" ] || { echo "no such file: ${file}" >&2; exit 1; }

passphrase_args=()
if [ -n "${HORNERO_RELEASE_PASSPHRASE:-}" ]; then
  passphrase_args=(--pinentry-mode loopback --passphrase "${HORNERO_RELEASE_PASSPHRASE}")
fi

gpg --batch --yes "${passphrase_args[@]}" \
  --local-user "${key_id}" \
  --detach-sign --armor --output "${file}.asc" "${file}"

echo "signed: ${file}.asc (key ${key_id})"
