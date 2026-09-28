# Release ledger

Derived record of every HorneroOS release. This file is generated
from the release definitions in this directory — edit the release
files, not this ledger; regenerate when a release is cut.

## Convention

- Versions follow the manifest process in `docs/RELEASE_PROCESS.md`.
- Codenames are Argentine birds and places, assigned when the release
  is tagged and recorded here. Past releases predate the convention
  and keep an empty codename rather than a retroactive one.
- A new release adds one row: version, date, codename, manifest, the
  pinned component SHAs, and its checklist.

## Releases

| Version | Date | Codename | Manifest | shell | config | Checklist |
|---|---|---|---|---|---|---|
| v0.1.0-draft | 2026-09-10 | — | `manifests/v0.1.0-draft.yaml` | `b0a864c` | `c4ac003` | `releases/v0.1.0-draft-checklist.md` |
| v0.2.0-preview2 | 2026-09-15 | — | `manifests/v0.2.0-preview2.yaml` | `643185e` | `4c761ae` | `releases/v0.2.0-preview2-checklist.md` |
| v0.2.0-preview3 | 2026-09-28 | — | `manifests/v0.2.0-preview3.yaml` | `ba7032e` | `f344f30` | `releases/v0.2.0-preview3-checklist.md` |
