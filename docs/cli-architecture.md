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
- `horneroctl system info` reads `/usr/lib/hornero/system-profile.json`, an
  immutable install record generated from the edition catalogue and resolver.
  It distinguishes the selected compositor from the active session and reports
  installations without a record as unrecorded instead of inferring a product
  edition from package coincidence.

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
home directory.

## Validation

Unit tests cover domain behavior and CLI dispatch. Integration scripts use
isolated HOME and XDG directories. Package-only checks verify installed data
resolution without personal configuration. The build and CI workflow run the
same formatter, V tests, and repository validation used during development.
