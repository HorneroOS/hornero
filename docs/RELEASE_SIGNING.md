# Release signing

How `horneroctl` release binaries are signed and verified, and the
one human step that turns it on.

## Decision: GPG, not minisign

`horneroctl-bin` is distributed through AUR/makepkg. makepkg verifies
GPG detached signatures natively: add the `.asc` to the package
sources and the key fingerprint to `validpgpkeys`, and a tampered or
wrongly-signed download is a hard build failure with no extra tooling
on the user's machine. minisign is a fine tool, but makepkg has no
native minisign verification, so every user would need a custom
`verify()` step and the minisign binary installed. GPG is the
ecosystem fit; minisign was rejected for the AUR flow specifically.

This is a different key from the AUR SSH publishing key
(HorneroOS/.github#9) and from any future ISO signing key (installer
repo). Do not conflate them.

## State today

- `scripts/sign-release.sh` — detached armoured signing, key already
  in the keyring; never imports or prints key material.
- `scripts/verify-release.sh` — verifies an asset against only the
  in-repo public key, in a throwaway keyring; fails closed when the
  signature or the public key is missing.
- `scripts/test-signing.sh` — CI smoke: ephemeral key, clean asset
  verifies, tampered asset is rejected. Runs in `horneroctl-ci`.
- `.github/workflows/release.yml` — when the
  `HORNERO_RELEASE_GPG_PRIVATE_KEY` secret exists, each built asset
  is signed and its `.asc` uploaded next to it. Without the secret
  the release is published unsigned with a loud workflow warning;
  nothing pretends otherwise.

## The human step (maintainer only)

1. On a trusted machine, generate the release key:
   `gpg --full-generate-key` (ed25519, sign-only is fine), identity
   `HorneroOS releases <releases@horneroos.com>` or the maintainer's
   chosen release identity.
2. Export the public key into this repo:
   `gpg --armor --export <fingerprint> > packaging/keys/hornero-release.pub.asc`
   and commit it.
3. Add the armoured **private** key export as the GitHub secret
   `HORNERO_RELEASE_GPG_PRIVATE_KEY` (and its passphrase, if any, as
   `HORNERO_RELEASE_GPG_PASSPHRASE`). Never commit it.
4. Record the fingerprint in `packaging/horneroctl-bin/PKGBUILD`:
   add `.asc` companions to `source_x86_64`/`source_aarch64` and set
   `validpgpkeys=('<fingerprint>')`. Do this only once signed assets
   actually exist, or AUR builds will fail looking for signatures.

## Rotation

1. Generate the new key; export its public key alongside the old one
   (both keys in `hornero-release.pub.asc` during the overlap).
2. Sign new releases with the new key; update `validpgpkeys` to the
   new fingerprint.
3. After one full release cycle on the new key, revoke the old key,
   publish the revocation, and drop it from the in-repo file.
4. Announce the rotation in the release notes of the first release
   signed with the new key.
