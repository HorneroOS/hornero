# Plugin lifecycle JSON contract

Control Center > Extensions (HorneroOS/shell `services/ExtensionStore.qml`)
installs, updates, rolls back, removes, trusts, enables and disables
extensions by running these `horneroctl` verbs. This page is the contract the
GUI relies on. Changing a key or an error code below is a breaking change:
add the new one, keep the old one for a release, and say so in the release
notes.

## Envelope and exit codes

Every verb accepts `--json` (before or after the subcommand) and prints one
JSON object on stdout:

```json
{"command": "plugin catalog install", "ok": true, "message": "…", "data": {"id": "hornero-pomodoro", "…": "…"}}
```

- `ok` is a JSON boolean. `message` is the human explanation (English).
- `data` is a flat object of strings. List-valued fields (`plugins`) are a
  JSON array encoded as a string, so decode them a second time.
- A failed verb has `"ok": false` and `data.error`, a stable machine code
  (table below). The message may change wording; the code does not.

| Exit | Meaning |
| --- | --- |
| `0` | `ok: true` |
| `1` | The verb ran and refused or failed (`ok: false`, `data.error` set) |
| `2` | Usage error: unknown flag or subcommand. The envelope is `{"ok": false, "code": "plugin.usage", "message": …}` with no `data` |

Mutating verbs need `--yes` (or `--dry-run`, which previews and changes
nothing). Without either they fail with `confirmation-required`. The GUI
passes `--yes` only from its own second, confirming click.

## Verbs

| Verb | Success `data` keys |
| --- | --- |
| `plugin list` | `plugins`: array of `{id, name, version, installed, enabled, trust, signer, source, revision, catalog_sha256, capabilities, capabilities_verified, rollback_available}` |
| `plugin catalog` | `plugins`, `source`, `revision` (catalogue commit). Rows below |
| `plugin catalog install <id> [--revision <commit>]` | `id`, `path`, `revision`, `sha256` (dry run: `dry_run`, `id`, `sha256`, `revision`) |
| `plugin catalog update <id> [--revision <commit>]` | `id`, `from`, `version`, `revision`, `sha256`; already current: `id`, `version`, `revision` |
| `plugin catalog rollback <id>` | `id`, `version` |
| `plugin remove <id>` | `id`, `version`, `was_enabled`, `rollback_copy` (`"true"` when a kept rollback copy was also removed) |
| `plugin trust <id>` | `id`, `hash`, `trust` |
| `plugin enable <id>` / `plugin disable <id>` | `id`, `enabled` |

`--revision` pins the catalogue commit the person was reading. If the
catalogue moved on, install and update fail with `catalogue-changed` instead
of installing content nobody reviewed.

### Catalogue rows

Each row of `plugin catalog` carries the catalogue fields (`id`, `name`,
`version`, `description`, `author`, `license`, `homepage`, `placement`,
`category`, `trust`, `sha256`, `generatedFrom`, `capabilities`, `pluginKit`)
plus:

| Key | Meaning |
| --- | --- |
| `state` | `available` or `installed` (a receipt exists) |
| `installed_version`, `enabled`, `installed_source` | From the local receipt; empty/false when not installed |
| `update_available` | The receipt came from the official catalogue and the catalogue now ships a different version or payload hash |
| `rollback_available` | A kept previous payload exists and matches its recorded hash |
| `signer` | Who vouches for the catalogue payload: `HorneroOS/plugins (official catalogue)` |
| `permissions` | Plain-language lines `{kind, value, en, es}` from HorneroOS/plugins (`kind`: `program`, `network`, `data`, `action`, `settings`) |
| `marketplace` | The manifest's marketplace object (changelog, compatibility, deprecation, packaged screenshots) |
| `screenshots` | Catalogue screenshots as listed: `{path, sha256, bytes, alt}` |
| `screenshot_files` | The ones that passed checks, cached locally: `{file, alt, sha256}` |

Screenshots are cached under
`$XDG_CACHE_HOME/hornero/plugins/catalog-screenshots/<sha256>.<ext>` only when
the path is under `docs/screenshots/`, the extension is png/jpg/jpeg/webp, the
file is a regular file of at most 4 MiB, and its SHA-256 matches the catalogue.
Anything else is skipped silently and never shown. The shell shows only these
local files and never fetches an image.

### Signer in `plugin list`

| `signer` | When |
| --- | --- |
| `HorneroOS/plugins (official catalogue)` | Trust state `official` |
| `author key <KEYID>` | Trust state `signed`; `KEYID` is the minisign key id as `minisign -V` prints it |
| `you (local trust record)` | Trust state `trusted` (recorded with `plugin trust`) |
| empty | Nobody vouches for the current payload |

## Error codes (`data.error`)

| Code | Meaning |
| --- | --- |
| `invalid-id` | The id is not a valid plugin id |
| `confirmation-required` | Neither `--yes` nor `--dry-run` was given |
| `unsafe-path` | A symbolic link sits in an owned plugin path; nothing was touched |
| `not-installed` | No receipt owns this id |
| `already-installed` | A payload already exists; remove it first |
| `receipt-invalid` | The receipt is malformed or names another id |
| `payload-missing` | The receipt exists but its files (or the kept copy) are missing |
| `catalogue-unavailable` | The catalogue could not be fetched or pinned |
| `catalogue-invalid` | The catalogue has no `catalog.json` or a row's path is missing |
| `catalogue-changed` | The catalogue commit differs from `--revision` |
| `not-in-catalogue` | The id is not (or no longer) in the official catalogue |
| `hash-mismatch` | Fetched or kept files do not match the recorded SHA-256 |
| `manifest-invalid` | The package manifest is missing or not JSON |
| `validation-failed` | The shell's package validator rejected it (or is missing) |
| `not-catalogue-source` | Update refused: the plugin was installed from another source |
| `locally-modified` | Update refused: the installed files differ from the catalogue at the same version and are not trusted |
| `nothing-to-roll-back` | No kept previous payload |
| `trust-required` | Enable refused: a non-official payload without trust or a valid signature |
| `io-failed` | A file could not be read, written, copied or removed |

## Remove

`plugin remove <id>` deletes only receipt-owned data: the payload directory,
the kept rollback copy (`<id>.previous`) and a staged rollback leftover
(`<id>.rollback-current`), then the receipt. The extension's settings live in
the shell configuration and are kept, so a reinstall picks them up.
