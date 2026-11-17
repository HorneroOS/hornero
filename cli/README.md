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

- `appearance` and `wallpaper` for Hornero Signal themes, GTK, the live
  colour scheme, derived colour files, and wallpaper state (see
  [Appearance](#appearance-hornero-signal));
- `shell` for Quickshell lifecycle, IPC, layout presets, and component toggles;
- `config` for path inspection, validation, snapshots, default applications,
  package materialization, and opening Control Center panes;
- `package`, `backup`, and `power` for updates, user-owned configuration
  archives, and session actions;
- `system info` for the installed edition/compositor record and current
  compositor session;
- `lock`, `capture`, `hypr`, `hardware`, `apps`, and `welcome` for their
  corresponding platform and desktop capabilities.
- `mode list|get|set|reset|status` for the shell's experience modes (focus,
  everyday, signal, gaming, studio); see [Experience modes](#experience-modes).
- `agent list|status|doctor|default|launch` for the declarative Agent
  Registry (javi-hermes, codex, claude-code, muse, opencode) as data:
  executable/discovery/install-source/arch, config, instruction and
  skills paths, MCP format, ACP, session, approval, sandbox, usage and
  uninstall semantics. The read-only commands probe PATH and file
  presence only (credential contents are never read); `agent default
  set <id>` records the user default under XDG config only with
  `--yes` (or `--dry-run` to preview), and `agent launch <id>` returns
  a dry-run proposal only — it never executes an agent and never adds
  an auto-approval flag.
- `plugin new|install|remove|list|validate` for community Shell packages.
  `new` writes a static scaffold to a new path with an explicitly selected MIT
  license template; install/list/remove operate on receipt-owned data, and
  validate delegates to the Shell-owned contract checker. This CLI does not
  load or sandbox third-party QML.
- `plugin catalog list|install|update|rollback` for the reviewed official
  HorneroOS extension catalogue. Catalogue installs verify payload hashes and
  keep extensions inert until separately enabled. `--revision <commit>` fetches
  and checks out that exact catalogue commit, so links pinned by the website
  remain reproducible after `main` advances.

`horneroctl system info` reads the immutable profile record installed by a
HorneroOS installer composition. It reports the installed edition, role,
package-set layers, maturity and configured compositor separately from the
compositor active in the current session. An installation without that record
is reported as unrecorded; the command never guesses an edition from packages
that happen to be present.

`horneroctl package check` and `package updates` report repository updates
through `checkupdates` and AUR updates through `yay -Qua` or `paru -Qua` when an
AUR helper is available. When `pacman-conf` is available, they also report the
configured `IgnorePkg` and `IgnoreGroup` patterns that suppress matching
upgrades during pacman's system-upgrade operation, plus `HoldPkg` entries.
`HoldPkg` asks for confirmation before removal; it does not hold a package back
from upgrades. The command uses
pacman-conf's resolved configuration, including included config files; it does
not parse pacman.conf itself. These are system-wide package results, not a
Hornero-only update status. The AUR lane is read-only and bounded to 30 seconds;
without a helper the CLI reports that AUR updates were not checked instead of
presenting repository results as a complete system status. `package upgrade`
runs a separate, explicit full-system transaction through `pacman -Syu`,
including kernel packages selected by the configured repositories. It does not
create a system snapshot or provide OS rollback. `config snapshot` and
`backup` cover Hornero configuration only; see
[`../docs/UPDATE_RECOVERY.md`](../docs/UPDATE_RECOVERY.md) for exact boundaries.

`horneroctl package deps` checks common CLI and shell prerequisites, the
selected compositor runtime, and its portal backends. It selects the compositor from the
installed Hornero profile, then the active Wayland session; an unprofiled
system without an active session retains Hyprland as the compatibility default.
Use `--compositor hyprland` or `--compositor niri` to choose explicitly. Niri's
dependency check is marked experimental. Portal service binaries are checked
in Arch's `/usr/lib` service path as well as checking normal commands on `PATH`.

`horneroctl config gui --pane <id>` asks the running Hornero Shell to open a
registered Control Center destination over Shell IPC. The Shell registry is
the source of truth for pane IDs; when the Shell is not running, the command
returns a clear error instead of launching a differently owned GUI.

`horneroctl config default-apps set terminal <kitty|alacritty|ghostty> --yes`
keeps the Exo terminal helper and the generic `xdg-terminals.list` preference
in sync, removing a fallback exclusion for the selected terminal. The latter
is consumed by the optional `xdg-terminal-exec` package;
desktop-specific XDG terminal lists can still override the generic preference.
`config default-apps list` reports the Exo terminal and generic XDG preference
separately.

`horneroctl doctor` also checks which supported terminals are installed and
whether the Hornero Shell's selected terminal can be launched. A missing or
unsupported selection is reported as a health failure with the available
choices; the check is read-only.

`horneroctl doctor` and `horneroctl appearance doctor` also check that the
live Hornero Signal scheme is valid and that the IBM Plex Sans, Mono and Sans
Condensed fonts (`ttf-ibm-plex`) are installed.

`horneroctl lock now --yes` skips a duplicate launch when a `hyprlock`
process owned by the current user is already running. `horneroctl lock status`
reports that process observation separately from the selected lock backend.
The process state can be `running`, `not running`, or `unknown` when `pgrep` is
unavailable or fails; it is a best-effort observation, not proof that the
current session is securely locked. The command never terminates an existing
locker.

## Experience modes

`horneroctl mode` is the system interface to the experience modes of RFC 0001
section 5a. The shell owns the Experience service and persists the active mode;
every verb is a validated passthrough to `qs ipc call experience <verb>`
(contract: shell `docs/IPC.md`, `docs/EXPERIENCE.md`).

```sh
horneroctl mode list             # five modes, active one marked
horneroctl mode get              # active mode id
horneroctl mode set signal       # switch (validated; no --yes, reversible)
horneroctl mode reset --yes      # factory Everyday + Cockpit + Signal Night
horneroctl mode status --json    # mode, previous, source, auto-switch, deck
```

All verbs accept `--json`; `set` and `reset` accept `--dry-run`, which prints
the planned IPC call without needing the shell. Unknown mode names exit 2/1
before the shell is contacted. `reset` needs `--yes` because it reapplies the
factory layout and theme; it keeps per-mode customisations and never deletes
`shell.json` or the user's customisation files.

When the shell is not running, every verb except `--dry-run` explains that,
exits 1 and reports nothing: horneroctl does not guess the mode and does not
write the shell's state file.

## Appearance (Hornero Signal)

Colours come only from the selected theme pack: a schema-v2 `theme.json`
(`palette` with the RFC 0001 §3.1 role set plus a 16-colour `terminal`
array; HorneroOS/.github#28). There is no wallpaper-driven palette
synthesis; setting a wallpaper never changes a colour.

- `appearance theme apply <id> --yes` validates the pack, then atomically
  writes the live scheme the shell watches,
  `${XDG_STATE_HOME:-~/.local/state}/hornero/signal/scheme.json`
  (`{"schemaVersion":2,"id","mode","palette","terminal"}`), followed by
  the derived files, matching HorneroOS/config's `apply-appearance.sh`:
  `colors-hyprland.lua` (active border = `signal`, inactive = `rule`,
  locked groups = `cue`) and `colors-hyprlock.conf` (hyprlang `$hs_*`
  variables only) under `$XDG_CACHE_HOME/hornero/smart-colors/`, the
  Alacritty, Ghostty, btop and Cava "Hornero Dynamic" colours, the kitty
  `include <id>.conf` swap, the selection in the appearance state and
  `shell.json`, and the pack's GTK theme and libadwaita recolour.
- `appearance theme set <hornero-signal-night|hornero-signal-day|hornero-signal-contrast>`
  switches between the built-in themes and verifies scheme and GTK agree.
  `hornero-signal-night` is the factory default.
- `appearance sync --yes` migrates persisted selections of removed
  themes once (`hornero-dark` and `hornero-199x` to night,
  `hornero-light` to day, `neon-city`, `vapor-dreams`, `soft-morning`
  and `warm-sunset` to night) and rewrites the live scheme and derived files from the selected theme.
  Typed retired ids are rejected with their replacement, not rewritten.
- `appearance scheme status|current`, `appearance status`, `appearance
  colors status|concept|export` and `appearance doctor` are read-only.
- `shell preset apply` falls back to the `cockpit` preset, and its safe
  reset layout is the minimal Cockpit composition.

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
