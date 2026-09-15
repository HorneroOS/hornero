# Composition manifests

A manifest pins every component of Hornero OS to an exact version.
This directory holds the pinning schema and the dated manifests.

## Files

- `schema.json` — JSON Schema (draft 2020-12) for `CompositionManifest`
  documents. It enforces the component table shape, the `pinned` /
  `local` / `future` statuses, and the 40-char commit SHA format.
- `candidate` — pointer naming the ONE release-candidate manifest
  whose pins must be fresh. Reviewed like code; CI follows it.
- `v0.1.0-draft.yaml` — IMMUTABLE record of the `0.1.0-draft`
  (Preview 0) composition. Never rewritten; history lives here, not
  in refreshed pins.
- `v0.2.0-preview2.yaml` — release-candidate composition for
  Development Preview 2. Frozen on tag day, then immutable too.

## Immutability rule

A manifest describes exactly one composition. A new release gets a
new manifest file; a tagged manifest is never edited again, not even
to "refresh" pins. `git tag` preserves the release state; the file
preserves its content. A PR that mutates a manifest older than the
candidate is a release-architecture bug, and tests fail it
(`tests/test_composition.py`).

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

## Release-candidate refresh (before freeze only)

To refresh the release-candidate pins:

1. Resolve the new SHAs from the component `main` branches:

   ```bash
   git ls-remote https://github.com/HorneroOS/shell refs/heads/main
   git ls-remote https://github.com/HorneroOS/config refs/heads/main
   ```

2. Update `sha` and `subject` in the candidate manifest named by
   `candidate`. Never touch any other manifest file.
3. Validate everything:

   ```bash
   python3 scripts/check-manifests.py
   python3 scripts/check-pins.py
   python3 -m pytest tests/ -q
   ```

4. Rescan for personal data and secrets (see `docs/RELEASE_PROCESS.md`)
   before committing and pushing.

## Cutting a new release

1. Copy the candidate manifest to a new file (e.g.
   `v0.3.0.yaml`), update `name`, `date`, `sha`, `subject`.
2. Repoint `candidate` at the new file.
3. Point `profiles/` at the new manifest name; add the release
   definition plus checklist under `releases/`.
4. Run the four gates (`docs/RELEASE_PROCESS.md`); tag only when
   the checklist is complete. The previous manifest stays untouched.

## Validation

```bash
python3 scripts/check-manifests.py
```

The checker validates every manifest against `schema.json`
(`jsonschema` when installed, strict built-in checks otherwise),
then verifies status rules (`pinned` implies `sha`, `future` and
`local` forbid it) and cross-references from `profiles/` and
`releases/`.
