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

if [ -n "${HORNERO_RELEASE_PASSPHRASE:-}" ]; then
  printf '%s' "${HORNERO_RELEASE_PASSPHRASE}" \
    | gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 \
      --local-user "${key_id}" \
      --detach-sign --armor --output "${file}.asc" "${file}"
else
  gpg --batch --yes --local-user "${key_id}" \
    --detach-sign --armor --output "${file}.asc" "${file}"
fi

echo "signed: ${file}.asc (key ${key_id})"
