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
- `.github/workflows/release.yml` — creates a draft release, requires
  the private-key secret and a matching committed public key, signs
  and verifies each architecture's asset, and publishes only after
  both builds succeed. Missing or mismatched key material fails the
  workflow; an unsigned public release is not produced.
- The AUR package includes each detached `.asc` beside its binary,
  pins the release fingerprint in `validpgpkeys`, and stamps hashes
  for both files. Users building the AUR package must import the public
  key into their GPG keyring before `makepkg`:

  ```sh
  curl -fsSLO https://raw.githubusercontent.com/HorneroOS/hornero/main/packaging/keys/hornero-release.pub.asc
  gpg --import hornero-release.pub.asc
  ```

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
4. The release workflow reads the committed public key fingerprints
   and stamps `validpgpkeys` plus binary/signature hashes into the AUR
   PKGBUILD. Do not publish a tag until the public key and matching
   GitHub secret are configured; the workflow fails closed otherwise.
5. Verify a downloaded release directly with
   `scripts/verify-release.sh <asset> [signature]`. The script imports
   only the in-repository public key into a temporary keyring.

## Rotation

1. Generate the replacement key and export its public key alongside
   the old key in `hornero-release.pub.asc`.
2. Update the GitHub private-key secret to contain the replacement
   key. The release workflow selects a secret key whose fingerprint
   appears in the committed public key bundle; only such signatures
   pass release verification.
3. Keep both fingerprints in the public bundle and AUR `validpgpkeys`
   for one full release cycle. Then revoke the old key, publish its
   revocation, and remove it from the bundle in a reviewed change.
4. Announce the rotation in the release notes of the first release
   signed with the replacement key.
