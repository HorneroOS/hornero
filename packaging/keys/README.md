# Release signing key

`hornero-release.pub.asc` is the armoured **public** key that verifies
every signed HorneroOS release asset, including the `horneroctl`
binaries published through the AUR `horneroctl-bin` package and the
signed Preview ISOs.

- Fingerprint: `FCFBEE43925AB5429362278AE59EAB44AA2498DC`
- Identity: `HorneroOS releases <releases@horneroos.com>`

Distribution channels and the full trust model are documented in
[`docs/RELEASE_SIGNING.md`](../../docs/RELEASE_SIGNING.md). The same
key also ships with the AUR package under
`packaging/horneroctl-bin/keys/pgp/` and is published to public
keyservers; the fingerprint above is the pinned trust anchor in every
channel.

Never commit private key material here or anywhere in this repo.
The private key lives only in the maintainer's custody and, for CI
signing, in the `HORNERO_RELEASE_GPG_PRIVATE_KEY` repository secret.
