#!/usr/bin/env bash
# Signing smoke test: generate an EPHEMERAL key in a throwaway
# keyring, sign a dummy asset, verify a clean copy passes and a
# tampered copy fails. Uses a temporary copy of the verify logic
# pointed at the ephemeral public key, so it exercises the same
# gpg invocation shape as scripts/verify-release.sh without needing
# the real maintainer key (which is a human custody step).
set -euo pipefail

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
export GNUPGHOME="${work}/gnupg"
mkdir -p "${GNUPGHOME}"
chmod 700 "${GNUPGHOME}"

echo "horneroctl dummy release asset" > "${work}/asset"

gpg --batch --quiet --pinentry-mode loopback --passphrase '' \
  --quick-generate-key "HorneroOS signing smoke <smoke@invalid>" ed25519 sign 1d
fpr="$(gpg --batch --with-colons --list-keys | awk -F: '/^fpr:/{print $10; exit}')"

HORNERO_RELEASE_KEY_ID="${fpr}" "$(dirname "${BASH_SOURCE[0]}")/sign-release.sh" "${work}/asset" >/dev/null

# Clean asset must verify.
gpg --batch --quiet --verify "${work}/asset.asc" "${work}/asset"
echo "PASS: clean asset verifies"

# Tampered asset must fail.
echo "tampered" >> "${work}/asset"
if gpg --batch --quiet --verify "${work}/asset.asc" "${work}/asset" 2>/dev/null; then
  echo "FAIL: tampered asset verified" >&2
  exit 1
fi
echo "PASS: tampered asset rejected"
echo "signing smoke: PASS"
