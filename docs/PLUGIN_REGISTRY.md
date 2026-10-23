# Community extension registry client

`horneroctl plugin community list` fetches the public
[`HorneroOS/plugins`](https://github.com/HorneroOS/plugins) repository and
prints community entries only after verifying `community/index.json.minisig`
against the system trust key at `/etc/hornero/registry.pub`. The command
requires `minisign`; the `horneroctl-bin` package declares it as an optional
dependency because first-party catalogue operations do not use it.

The client captures bounded index, signature, and key bytes, verifies private
temporary snapshots, then parses the exact index bytes that were verified. It
rejects duplicate JSON keys, unknown schema fields, unsupported versions,
mutable or malformed revisions, non-approved repository hosts, invalid hashes,
duplicate/unsorted IDs, and entries with an invalid author-key fingerprint.
It records the highest accepted `indexVersion` under XDG state and refuses a
lower version on subsequent reads. The state write is locked and atomic.

The trusted key is deliberately not included yet. A maintainer must provision
the production public key and review its bootstrap and rotation policy before
the command can expose a production registry. Until then, the command fails
closed with a missing-key error. Tests may create ephemeral keys; no test or
build step generates a production key.

Registry publication proves only that the registry published a pinned entry.
It does not mean HorneroOS reviewed the plugin. Community QML runs with the
user's privileges and is not sandboxed. This discovery slice does not install,
update, enable, or roll back community entries; those operations must preserve
the verified revision, payload hash, and author fingerprint through their
receipts before community installation is enabled in the UI.

## Validation

```sh
cd cli
./make.vsh test
./make.vsh fmt-check
./make.vsh build-cli
```

The CLI integration tests use ephemeral Minisign keys in CI. They cover signed
index acceptance, signature failure, the exact-bytes verification boundary,
strict schema validation, and persistent rollback rejection.
