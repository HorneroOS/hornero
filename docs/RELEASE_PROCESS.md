# Release process

How to cut a Hornero OS release from the composition in this
repository. Follow the steps in order; each step gates the next.

## 1. Bump

1. Resolve the current component SHAs from their `main` branches:

   ```bash
   git ls-remote https://github.com/HorneroOS/shell refs/heads/main
   git ls-remote https://github.com/HorneroOS/config refs/heads/main
   ```

2. Create the new manifest in `manifests/` (copy the previous one),
   update `name`, `date`, and the `sha` / `subject` fields.
   Keep `installer` and `iso` as `future` slots until their owning
   work lands; never pin a SHA you have not resolved yourself.
3. Point new or updated profiles in `profiles/` at the new manifest
   name, and write the release definition plus checklist in
   `releases/` (copy `v0.1.0-draft` as a template).

## 2. Validate

Run all three gates from the repository root:

```bash
python3 scripts/check-manifests.py
python3 -m pytest tests/ -q
markdownlint manifests/README.md profiles/README.md \
  releases/v0.1.0-draft-checklist.md docs/RELEASE_PROCESS.md
```

All three must pass. Fix failures at the source: never weaken the
schema, skip a check, or hand-edit generated output to make a gate
pass.

## 3. Tag

1. Work through the release checklist in `releases/`; every box must
   be checked.
2. Rescan for personal data and secrets (names, emails, hosts,
   SSIDs, tokens, keys) across the branch diff.
3. Push the release branch (never `main`) and wait for
   `composition-ci` to go green.
4. Tag the release from `main` after merge, or from the release
   commit for a draft:

   ```bash
   git tag -a vX.Y.Z -m "Hornero OS vX.Y.Z"
   git push origin vX.Y.Z
   ```

## 4. Build order

Build in dependency order so each layer resolves against the
already-built one below it:

1. `horneroctl` from `cli/` in this repository.
2. `config` (`HorneroOS/config`) at its pinned SHA.
3. `shell` (`HorneroOS/shell`) at its pinned SHA.
4. `installer` — slot reserved, currently skipped.
5. `iso` — slot reserved, currently skipped.

Record skipped slots in the release notes rather than silently
dropping them, so the next release knows what is still future.
