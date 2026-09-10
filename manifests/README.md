# Composition manifests

A manifest pins every component of Hornero OS to an exact version.
This directory holds the pinning schema and the dated manifests.

## Files

- `schema.json` — JSON Schema (draft 2020-12) for `CompositionManifest`
  documents. It enforces the component table shape, the `pinned` /
  `local` / `future` statuses, and the 40-char commit SHA format.
- `v0.1.0-draft.yaml` — first manifest, backing the `0.1.0-draft`
  pre-release. Pins `shell` and `config` to their current `main` SHAs.

## Component statuses

- `pinned` — an exact `sha` on `ref` is recorded. Used for `shell`
  and `config`.
- `local` — built from this repository at release time (currently
  `horneroctl` from `cli/`). Never carries a `sha`.
- `future` — a named slot with no resolved version yet (currently
  `installer` and `iso`). Never carries a `sha` or `ref`.

## No git submodules

Pins are plain YAML data, not submodules. Rationale: a manifest must
stay reviewable as a diff, checkable without network access, and
releasable from a source archive. Nothing here requires
`git submodule update`.

## Bump process

To pin newer component revisions:

1. Resolve the new SHAs from the component `main` branches:

   ```bash
   git ls-remote https://github.com/HorneroOS/shell refs/heads/main
   git ls-remote https://github.com/HorneroOS/config refs/heads/main
   ```

2. Copy the current manifest to a new dated file (or edit it in
   place for a draft), update `date`, `sha`, and `subject` fields.
3. Validate everything:

   ```bash
   python3 scripts/check-manifests.py
   python3 -m pytest tests/ -q
   ```

4. Rescan for personal data and secrets (see `docs/RELEASE_PROCESS.md`)
   before committing and pushing.

## Validation

```bash
python3 scripts/check-manifests.py
```

The checker validates every manifest against `schema.json`
(`jsonschema` when installed, strict built-in checks otherwise),
then verifies status rules (`pinned` implies `sha`, `future` and
`local` forbid it) and cross-references from `profiles/` and
`releases/`.
