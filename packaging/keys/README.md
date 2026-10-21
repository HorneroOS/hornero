# Release signing key

`hornero-release.pub.asc` belongs here: the armoured **public** key
that verifies every signed `horneroctl` release asset.

**Status: not committed yet.** Generating the private key is a human
maintainer action (see `docs/RELEASE_SIGNING.md`). Until the public
key lands in this directory:

- release assets are published unsigned (SHA-256 only), and
- `scripts/verify-release.sh` fails closed, by design.

Never commit private key material here or anywhere in this repo.
The private key lives only in the maintainer's custody and, for CI
signing, in the `HORNERO_RELEASE_GPG_PRIVATE_KEY` repository secret.
