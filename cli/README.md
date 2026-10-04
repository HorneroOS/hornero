# horneroctl

`horneroctl` is HorneroOS's command-line interface for stable operating-system
and session operations. It is written in V; domain modules return structured
results, while `hornero_cli` handles argument dispatch, help, output, and exit
codes.

## Usage model

The CLI is non-interactive by default. Reads are repeatable, mutations preview
with `--dry-run`, and changes that need explicit consent require `--yes`.
Global `--json` and `--quiet` flags support scripts and automation. Exit codes
are `0` for success, `1` for runtime or environment errors, and `2` for invalid
usage.

## Command groups

Run `horneroctl --help` for the installed command list and
`horneroctl <group> --help` for examples. The CLI includes:

- `appearance` and `wallpaper` for themes, GTK, color schemes, palettes, and
  wallpaper state;
- `shell` for Quickshell lifecycle, IPC, layout presets, and component toggles;
- `config` for path inspection, validation, snapshots, default applications,
  package materialization, and opening Control Center panes;
- `package`, `backup`, and `power` for updates, user-owned configuration
  archives, and session actions;
- `lock`, `capture`, `hypr`, `hardware`, `apps`, and `welcome` for their
  corresponding platform and desktop capabilities.

`horneroctl config gui --pane <id>` asks the running Hornero Shell to open a
registered Control Center destination over Shell IPC. The Shell registry is
the source of truth for pane IDs; when the Shell is not running, the command
returns a clear error instead of launching a differently owned GUI.

## Ownership

The Shell owns live session state and visual interactions. `horneroctl` owns
stable system operations and shared file contracts. HorneroOS/config owns
factory defaults, packaged application settings, and read-only catalogues.
User state is stored under the standard XDG roots in the `hornero` namespace;
installed package data is never modified at runtime. See
[`../docs/PATH_CONTRACT.md`](../docs/PATH_CONTRACT.md) and
[`../docs/cli-architecture.md`](../docs/cli-architecture.md).

## Build and verify

```sh
./make.vsh build-cli
./make.vsh test
./make.vsh fmt-check
./make.vsh vet
```

Build metadata is injected at composition time. A standalone checkout remains
buildable without repository metadata; the version report then marks unknown
provenance explicitly.
