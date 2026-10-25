# horneroctl architecture

`horneroctl` keeps policy and stable system behavior in HorneroOS/hornero.
The Shell owns presentation and live session interactions; packaged
configuration owns defaults and read-only catalogue data.

## Layers

- `cli/modules/hornero_core` implements domain operations, validation,
  catalogue resolution, and atomic file writes.
- `cli/modules/hornero_cli` parses commands, builds help, and renders text,
  JSON, or quiet output.
- `cli/cmd` provides the thin executable entry point.
- Quickshell IPC is the boundary for GUI destinations and live shell actions.
  GUI pane IDs are validated by the Shell's canonical pane registry.
- OS operations use specific installed tools only where the platform itself
  owns the capability, such as `gsettings`, `xdg-mime`, `hyprctl`, `pacman`,
  or `systemctl`. Paths are passed as individual arguments and mutations
  require explicit consent.
- Hyprland commands detect the standard `$XDG_CONFIG_HOME/hypr/hyprland.lua`
  provider. Layout, animation, monitor, and keyboard operations use the current
  Lua runtime APIs (`hyprctl eval`, `hl.config`, `hl.curve`, `hl.animation`,
  and `hl.monitor`) when that file is present; otherwise they retain the
  hyprlang `keyword` path. This detection intentionally does not guess when a
  session was started with a nonstandard `--config` path.
- `horneroctl system info` reads `/usr/lib/hornero/system-profile.json`, an
  immutable install record generated from the edition catalogue and resolver.
  It distinguishes the selected compositor from the active session and reports
  installations without a record as unrecorded instead of inferring a product
  edition from package coincidence.
- `horneroctl studio` records versioned Studio selection intent
  (`~/.config/hornero/studio-selection.json`, schemaVersion 1) and reports
  read-only diagnostics (`studio doctor`). It validates the canonical
  specialization/application IDs from `editions/catalogue.yaml` and never
  duplicates package lists. Recording a selection installs nothing; the
  package-apply lifecycle is a separate later slice.
- `horneroctl studio jobs` is the launchable, allow-listed render-job API
  (HorneroOS/hornero#289): adapters `blender-render` and `ffmpeg-export`
  build fixed argv (no shell, no custom flags), outputs are never
  overwritten, and `run` needs `--yes`. Jobs persist under Hornero state as
  `<id>.json`/`<id>.log`; a persisted `running` state reconciles to
  `interrupted` after a crash. Logs are only shown through `studio jobs
  log` with secret redaction. Storage review uses a fixed `df` evidence
  probe; this slice does not infer arbitrary process completions.
- `horneroctl plugin` manages community extension packages as user-owned data
  under XDG roots, with receipts under Hornero state. Validation delegates to
  the Shell package's contract checker. The command never activates packages:
  Quickshell QML runs with user privileges and is not sandboxed.
  Signed community-registry discovery verifies the index before exposing
  entries and persists a per-user anti-rollback version; installation from
  those entries remains a separate provenance-preserving slice (see
  [`PLUGIN_REGISTRY.md`](PLUGIN_REGISTRY.md)).

## State and package data

All writable state uses XDG roots under `hornero`. Theme packs, wallpapers,
layout presets, and other packaged catalogue data are read from user data first
and system data second. User overrides win by ID; writes never target a system
catalogue. The exact paths and precedence rules are defined in
[`PATH_CONTRACT.md`](PATH_CONTRACT.md).

## Safety and output

Every command exposes usage through layered help and includes runnable
examples. `--dry-run` validates and describes mutations without writing.
Mutations require `--yes`; privileged system actions use polkit where
available. External commands are invoked with argv boundaries, and operation
results use `CommandResult` so human and machine output share the same status.

Snapshot archives contain only the Hornero configuration roots and are stored
in the Hornero data catalogue. Backups archive only the explicit Hornero
configuration directory. Neither operation traverses or packages the whole
home directory. They are configuration recovery tools, not OS snapshots.
`package upgrade` is a full `pacman -Syu` transaction and does not hold the
kernel or provide rollback. See [update and recovery boundaries](UPDATE_RECOVERY.md)
before describing either operation as a system update or rollback feature.

## Validation

Unit tests cover domain behavior and CLI dispatch. Integration scripts use
isolated HOME and XDG directories. Package-only checks verify installed data
resolution without personal configuration. The build and CI workflow run the
same formatter, V tests, and repository validation used during development.
