# Release composition profiles

These files record which pinned repository components a release profile
contains. They do not define edition package composition. The user-facing
edition and package-set source of truth is [`../editions/catalogue.yaml`](../editions/catalogue.yaml).

## Files

- `base.yaml`, `desktop.yaml`, `developer.yaml` — release-era composition
  profiles referenced by the frozen Preview 14 release record.

## Rules

- `manifest` must name an existing manifest in `manifests/`.
- `extends`, when present, must name another existing profile.
  Extension chains must be acyclic.
- Every entry under `components` must name a component from the
  referenced manifest whose status is `pinned` or `local`.
  `future` slots (`installer`, `iso`) cannot be shipped by a profile.
- `target` is `vm` or `hardware` and documents what the edition is
  validated on.

Create or change user-facing edition package composition in
`editions/catalogue.yaml`; validate it with `scripts/resolve-edition.py` and
`tests/test_editions.py`. Release profiles change only through the process in
`docs/RELEASE_PROCESS.md`.
