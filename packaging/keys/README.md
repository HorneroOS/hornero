# Release signing key

`hornero-release.pub.asc` belongs here: the armoured **public** key
that verifies every signed `horneroctl` release asset.

**Status: not committed yet.** Generating the private key is a human
maintainer action (see `docs/RELEASE_SIGNING.md`). Until the public
key and matching GitHub private-key secret are configured:

- release publication fails closed before publishing unsigned assets, and
- `scripts/verify-release.sh` fails closed, by design.

Never commit private key material here or anywhere in this repo.
The private key lives only in the maintainer's custody and, for CI
signing, in the `HORNERO_RELEASE_GPG_PRIVATE_KEY` repository secret.
