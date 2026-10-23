#!/usr/bin/env bash
# Signing smoke test: generate an EPHEMERAL key in a throwaway
# keyring, then run the actual release verifier with that public key
# in a temporary repository. No maintainer key material is needed.
set -euo pipefail

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
export GNUPGHOME="${work}/gnupg"
mkdir -p "${GNUPGHOME}"
chmod 700 "${GNUPGHOME}"

echo "horneroctl dummy release asset" > "${work}/asset"

gpg --batch --quiet --pinentry-mode loopback --passphrase 'smoke-passphrase' \
  --quick-generate-key "HorneroOS signing smoke <smoke@invalid>" ed25519 sign 1d
fpr="$(gpg --batch --with-colons --list-keys | awk -F: '/^fpr:/{print $10; exit}')"

HORNERO_RELEASE_KEY_ID="${fpr}" \
  HORNERO_RELEASE_PASSPHRASE='smoke-passphrase' \
  "$(dirname "${BASH_SOURCE[0]}")/sign-release.sh" "${work}/asset" >/dev/null

repo="${work}/repo"
assets="${work}/assets"
mkdir -p "${repo}/scripts" "${repo}/packaging/keys" \
  "${repo}/packaging/horneroctl-bin" "${assets}"
cp "$(dirname "${BASH_SOURCE[0]}")/verify-release.sh" "${repo}/scripts/verify-release.sh"
cp "$(dirname "${BASH_SOURCE[0]}")/stamp-aur-package.sh" "${repo}/scripts/stamp-aur-package.sh"
cp "$(dirname "${BASH_SOURCE[0]}")/../packaging/horneroctl-bin/PKGBUILD" \
  "${repo}/packaging/horneroctl-bin/PKGBUILD"
chmod +x "${repo}/scripts/stamp-aur-package.sh"
gpg --batch --armor --export "${fpr}" > "${repo}/packaging/keys/hornero-release.pub.asc"

# The actual release verifier must accept a clean asset.
bash "${repo}/scripts/verify-release.sh" "${work}/asset"

# Exercise the exact AUR stamping path with both signed architecture assets.
for asset in horneroctl-linux-x86_64 horneroctl-linux-arm64; do
  cp "${work}/asset" "${assets}/${asset}"
  cp "${work}/asset.asc" "${assets}/${asset}.asc"
done
"${repo}/scripts/stamp-aur-package.sh" horneroctl-v1.2.3 "${assets}"
pkgbuild="${repo}/packaging/horneroctl-bin/PKGBUILD"
bash -n "${pkgbuild}"
grep -Fxq '_reltag=horneroctl-v1.2.3' "${pkgbuild}"
grep -Fxq "validpgpkeys=('${fpr}')" "${pkgbuild}"
echo "PASS: AUR package pinned signed binaries and release fingerprint"

# Tampered asset must fail.
echo "tampered" >> "${work}/asset"
if bash "${repo}/scripts/verify-release.sh" "${work}/asset" >/dev/null 2>&1; then
  echo "FAIL: tampered asset verified" >&2
  exit 1
fi
echo "PASS: tampered asset rejected"

# The verifier must fail closed when either trust input is missing.
if bash "${repo}/scripts/verify-release.sh" "${work}/asset" "${work}/missing.asc" >/dev/null 2>&1; then
  echo "FAIL: missing signature was accepted" >&2
  exit 1
fi
mv "${repo}/packaging/keys/hornero-release.pub.asc" "${work}/public-key.asc"
if bash "${repo}/scripts/verify-release.sh" "${work}/asset" >/dev/null 2>&1; then
  echo "FAIL: missing public key was accepted" >&2
  exit 1
fi
echo "PASS: missing signature and public key rejected"
echo "signing smoke: PASS"
