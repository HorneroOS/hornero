# Release process

How to cut a Hornero OS release from the composition in this
repository. Follow the steps in order; each step gates the next.

## 0. Release model (read first)

Composition manifests are immutable release records:

- one manifest file describes exactly one composition;
- a new release gets a NEW manifest file (never reuse, never
  rename-and-refresh an old one);
- a tagged manifest is never edited again — not even to refresh
  pins. Tags preserve the release state; the file preserves its
  content;
- `manifests/candidate` names the ONE release-candidate manifest
  whose `shell`/`config` pins track current component mains;
- historical manifests keep schema/content validation but are
  exempt from freshness checks and are never rewritten;
- `profiles/` are live files tracking the candidate manifest;
  `releases/` definitions pin one manifest each, so historical
  releases stay valid without chasing moved profiles;
- `scripts/compose.sh` defaults to the candidate pointer;
  `scripts/check-pins.py` enforces freshness for the candidate
  only (`--manifest` overrides the pointer explicitly).

## 1. Refresh the candidate

1. Resolve the current component SHAs from their `main` branches:

   ```bash
   git ls-remote https://github.com/HorneroOS/shell refs/heads/main
   git ls-remote https://github.com/HorneroOS/config refs/heads/main
   ```

2. Update `sha` / `subject` ONLY in the candidate manifest named by
   `manifests/candidate`. Keep `installer` and `iso` as `future`
   slots until their owning work lands; never pin a SHA you have
   not resolved yourself; never touch a historical manifest.
3. Point new or updated profiles in `profiles/` at the candidate
   manifest name, and write the release definition plus checklist in
   `releases/` (copy `v0.2.0-preview2` as a template for the next
   release: new manifest file, repointed `candidate`, updated
   profiles and release files).

## 2. Validate

Run all five gates from the repository root:

```bash
python3 scripts/check-manifests.py
python3 scripts/check-pins.py
python3 -m pytest tests/ -q
markdownlint manifests/README.md profiles/README.md \
  releases/v0.2.0-preview2-checklist.md docs/RELEASE_PROCESS.md
./scripts/compose.sh --yes
```

All four must pass. Fix failures at the source: never weaken the
schema, skip a check, or hand-edit generated output to make a gate
pass. `compose.sh` is the executable gate: it fetches the pinned
shell/config SHAs, builds horneroctl, materializes the config pin into
a scratch root, and validates that root with `config paths`, `config
validate`, and `config show`. The same script runs as the `compose`
job in `composition-ci`.

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
