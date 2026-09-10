# Edition profiles

Profiles compose the pinned components from a manifest into named
editions. Every profile references one manifest by name and lists
the manifest components it ships, with the role each plays.

## Files

- `base.yaml` — minimal system for VM smoke tests.
- `desktop.yaml` — full desktop edition. Extends `base`.
- `developer.yaml` — desktop plus a development tooling layer.
  Extends `desktop`.

## Rules

- `manifest` must name an existing manifest in `manifests/`.
- `extends`, when present, must name another existing profile.
  Extension chains must be acyclic.
- Every entry under `components` must name a component from the
  referenced manifest whose status is `pinned` or `local`.
  `future` slots (`installer`, `iso`) cannot be shipped by a profile.
- `target` is `vm` or `hardware` and documents what the edition is
  validated on.

New editions add a file here; existing editions change only through
the release process in `docs/RELEASE_PROCESS.md`.
