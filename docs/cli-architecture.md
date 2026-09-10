# Hornero system CLI architecture (locked design)

Status: **locked**. This document defines the long-term system CLI
surface for Hornero OS. It resolves
[hornero#1](https://github.com/HorneroOS/hornero/issues/1).
No global implementation is authorized by this document; implementation
happens per phase in section 7.

Scope: one user-facing system CLI that subsumes the legacy `dots-*`
bash/EasyOptions fleet (owned today by `ulises-jeremias/dotfiles`,
read-only reference) and gives the shell, config, package, and
installer concerns a single stable entry point.

Grounding sources (all read during design):

- `ulises-jeremias/dotfiles`: full `dots-*` inventory under
  `home/dot_local/bin/` (49 commands plus the `dots` dispatcher) and
  the registry `home/dot_local/lib/dots/dots-scripts.sh`.
- `HorneroOS/shell` `docs/IPC.md`: the Quickshell IPC contract that
  must stay stable.
- `HorneroOS/shell` `docs/COMPAT.md` and `docs/MIGRATION.md`: the
  per-CLI adapter table and dispositions A-G.
- `HorneroOS/config` `docs/DECISIONS.md`: the GTK-theme family
  (`dots-gtk-theme`, `dots-appearance`, `dots-hyprlock-theme`,
  `dots-theme-selector`) already extracted there.
- `HorneroOS/installer`: early scaffolding (no CLI surface yet).

## 1. Name decision: `horneroctl`

The system CLI is named **`horneroctl`**.

### Rationale

- Reads as "Hornero control", matching the `kubectl`-style
  `<product>ctl` convention operators already know.
- `dots` and `dots-*` stay reserved for the legacy fleet during
  migration, so old scripts and shell call sites keep working as
  shims without name collisions.
- A bare `hornero` binary name stays free for a future
  session/login entry point; spending it now on admin commands
  would close that door.

### Alternatives considered

| Candidate | Verdict | Reason |
|---|---|---|
| `horneroctl` | chosen | Unambiguous, tab-completes well, no collision |
| `hornero` | rejected | Reserved for a future session entry point |
| `hctl` | rejected | Too terse, collides with unrelated tools |
| `dots` | rejected | Legacy dispatcher name; keeps its meaning during migration |
| `hornero-cli` | rejected | Hyphenated names compose poorly as a command root |

Binary: `horneroctl`. Shell completion ships for bash, zsh, and fish
via `horneroctl completion <shell>`.

## 2. Subcommand tree

Top-level groups. Every leaf supports `--help`, `--json` (stable
machine output, see section 3), and standard exit codes.

```text
horneroctl
├── appearance          # themes, schemes, colors, GTK, wallpaper styling
│   ├── theme list | show <id> | apply <id> [--wallpaper <path>]
│   ├── scheme list | set <name> | variant <v> | mode <dark|light>
│   ├── gtk list | current | apply <theme> [icon] [policy] | set-icons <i>
│   ├── gtk color-scheme <policy> | sync-color-scheme
│   ├── colors generate | analyze | current
│   ├── accent set <hex> | clear
│   ├── wallpaper (alias of top-level wallpaper)
│   ├── night-mode on | off | toggle | status
│   ├── lock-theme generate | apply
│   └── status [--json] | sync | doctor
├── wallpaper           # wallpaper pointer operations
│   ├── set <path> | current | list
├── scheme              # alias of `appearance scheme` (compat shortcut)
├── shell               # desktop shell lifecycle and chrome
│   ├── start | stop | restart | status
│   ├── ipc <target> <fn> [args...]   # passthrough to `qs ipc`
│   ├── preset list | apply <name> | current
│   ├── config get <key> | set <key> <value>
│   ├── toggle <bar|launcher|dashboard|sidebar|session|utilities>
│   ├── workspace next
│   └── launcher | switcher            # launch helpers
├── config              # reusable desktop and system defaults
│   ├── snapshot create | list | restore <id>
│   ├── default-apps list | set <mime> <app>
│   ├── materialize --dest <dir>
│   └── gui                               # open settings hub
├── package             # system package workflows (no new package manager)
│   ├── check | updates | upgrade | deps
├── device              # hardware and compositor device state
│   ├── brightness get | set <v> [--device <q>]
│   ├── monitors list | apply <profile>
│   ├── keyboard layout | help | settings
│   └── hypr animations <p> | layout <p> | plugins
├── system              # session, media, and host operations
│   ├── power <menu|off|reboot|suspend|lock>
│   ├── lock [--now]
│   ├── session menu
│   ├── audio mic mute | unmute | toggle | status
│   ├── battery status
│   ├── network check
│   ├── clipboard history | clear
│   ├── record start | stop | pause
│   ├── screenshot [--mode <area|screen|window>]
│   ├── weather [--json]
│   ├── performance status | profile <name> | benchmark
│   ├── security audit [--fix]
│   ├── files                           # open default file manager
│   └── notify <title> <body>           # desktop notification helper
├── backup              # dotfiles and config backups
│   ├── create | list | restore <id> | schedule
├── setup               # RESERVED for HorneroOS/installer flows
├── doctor              # cross-area consistency checks
├── version
└── completion <bash|zsh|fish>
```

### Concern coverage

| Concern | Owner repo | CLI surface |
|---|---|---|
| Shell lifecycle, presets, toggles, IPC | HorneroOS/shell | `shell` |
| Appearance orchestration (themes, GTK, M3) | HorneroOS/config | `appearance`, `wallpaper`, `scheme` |
| Desktop defaults and snapshots | HorneroOS/config | `config` |
| Package updates and dependencies | HorneroOS/hornero | `package` |
| Install and first-boot flows | HorneroOS/installer | `setup` (reserved namespace) |
| Session, media, host utilities | HorneroOS/hornero | `system`, `device`, `backup` |

The `setup` group is namespace-reserved only. Its subcommands are
defined by `HorneroOS/installer` in a follow-up; nothing here may
claim names under it.

## 3. Stability and versioning policy

- Versioning: Semantic Versioning on `horneroctl --version`.
  Pre-1.0 (`0.y`) means "implementing the locked surface"; the
  surface itself only changes through an amendment to this document.
- Surface levels:
  - **Stable**: top-level group names, leaf names used by the shell
    adapters (`appearance`, `wallpaper`, `shell`), `--json` field
    names, exit codes. Changes require a major version and a
    migration note.
  - **Draft**: flags and extra leaves. May change in a minor
    version with a changelog entry.
- Machine output: `--json` output adds fields but never renames or
  removes them within a major version. `--plain` (one value per
  line) is stable for the `current`/`list` leaves the shell parses.
- Deprecation: a legacy `dots-*` name or a draft flag is announced
  deprecated for at least two minor releases before removal, with a
  warning printed on stderr on every use.
- Exit codes: `0` success, `1` runtime failure, `2` usage error,
  `3` privilege denied, `4` degraded (fallback used, details on
  stderr as JSON in `--json` mode).
- Contract tests: every stable leaf has a golden invocation test in
  the owning repo. Shell-side, `tests/test_ipc_mapping.py` keeps
  covering the IPC surface; CLI-side, adapter shims keep the
  `COMPAT.md` table green until section 7 phase 3 retires them.

## 4. Auth and privilege model (polkit)

- Default posture: `horneroctl` runs **unprivileged** as the
  invoking user. Read and per-user state operations
  (`appearance`, `wallpaper`, `config`, `shell`, `doctor`) never
  escalate.
- Privileged operations (`package upgrade`, `system performance
  profile`, `system power off/reboot`, `security audit --fix`)
  escalate through **polkit actions** under
  `org.hornero.system.*`, one action per leaf (for example
  `org.hornero.system.package-upgrade`). No setuid helpers, no
  password read on stdin by the CLI itself.
- Denied authorization exits `3` with a one-line machine-readable
  error; partial application is forbidden (validate authorization
  before mutating).
- System vs user scope: flags `--user` (default) and `--system`
  select per-user state under XDG paths versus host state. The
  shell and config adapters always use `--user`.
- Secrets: the CLI never prints tokens, keys, or personal identity
  (names, emails, hosts, SSIDs). `doctor` redacts values matching
  credential patterns before display.

## 5. Migration mapping (every legacy `dots-*` command)

Source inventory: `home/dot_local/bin/` in
`ulises-jeremias/dotfiles` (49 `dots-*` commands plus the `dots`
dispatcher) and the `dots-scripts.sh` registry. The shell call
sites below come from `HorneroOS/shell` `docs/COMPAT.md`.

Phase tags: **P1** thin shim (forward to new surface, shell-safe),
**P2** canonical reimplementation in the owning repo, **P3**
late-tail migration. Shell-called CLIs are P1 so the shell never
breaks; nothing else may jump ahead of them.

| Legacy command | New surface | Phase | Notes |
|---|---|---|---|
| `dots` (dispatcher) | `horneroctl` (root) | P1 | `-l/--list` becomes `horneroctl --help` groups |
| `dots-appearance` | `appearance ...` | P1 | `status`, `theme list/show/apply`, `set-*`, `sync`, `doctor` map 1:1 |
| `dots-gtk-theme` | `appearance gtk ...` | P1 | Shell canonical path; `apply`, `color-scheme`, `detect`, `auto` kept |
| `dots-m3-colors` | `appearance colors generate` | P1 | Shell canonical path; interpreter selection stays internal |
| `dots-color-scheme` | `appearance scheme ...` | P1 | `mode`, `variant`, `sync-state` (`sync`) kept |
| `dots-smart-colors` | `appearance colors analyze` | P2 | Palette analysis entry point |
| `dots-accent-override` | `appearance accent set/clear` | P2 | Shell accent section calls this |
| `dots-theme-selector` | `appearance theme apply` (picker flag) | P2 | Terminal picker becomes a flag, not a binary |
| `dots-hyprlock-theme` | `appearance lock-theme ...` | P2 | Theme side effect, failure-tolerant semantics kept |
| `dots-wal-reload` | `appearance sync` | P1 | Deprecated alias; warns on stderr |
| `dots-wallpaper-set` | `wallpaper set` | P1 | Shell launcher action target |
| `dots-wallpaper-current` | `wallpaper current` | P1 | Shell `FileView` fallback stays until P3 |
| `dots-night-mode` | `appearance night-mode ...` | P2 | Shell quick-toggle target |
| `dots-quickshell` | `shell ...` | P1 | `start/stop/restart/status/ipc/preset/config/rebuild`; `presets/*.json` fallback stays in shell |
| `dots-toggle` | `shell toggle ...` | P2 | `--bar/--launcher/...` become positional toggle names |
| `dots-snappy-switcher` | `shell switcher` | P3 | Theme side effect only |
| `dots-next-workspace` | `shell workspace next` | P2 | Overlaps `hypr` IPC target; CLI wraps it |
| `dots-launcher` | `shell launcher` | P2 | Quickshell-first, minimal fallback |
| `dots-power-menu` | `system power` (+ `system session menu`) | P2 | `--mode` becomes backend selection internal |
| `dots-lockscreen` | `system lock` | P2 | Shell `--lock` action target |
| `dots-screenshooter` | `system screenshot` | P2 | Shell-launched, not embedded |
| `dots-recorder` | `system record ...` | P2 | Shell `Recorder.qml` backend contract |
| `dots-microphone` | `system audio mic ...` | P3 | Toggle plus monitor icon |
| `dots-brightness` | `device brightness ...` | P2 | Overlaps `brightness` IPC target; CLI wraps it |
| `dots-hypr-monitors` | `device monitors ...` | P2 | Persistence and restore kept |
| `dots-hypr-layout` | `device hypr layout` | P2 | Profile persistence kept |
| `dots-hypr-animations` | `device hypr animations` | P2 | Fixed profile set |
| `dots-hyprland-plugins` | `device hypr plugins` | P3 | Idempotent bootstrap |
| `dots-keyboard-layout` | `device keyboard layout` | P2 | Wayland/X11 toggle |
| `dots-keyboard-help` | `device keyboard help` | P3 | Overlay launcher |
| `dots-keyboard-settings` | `device keyboard settings` | P3 | Opens GUI, not embedded |
| `dots-checkupdates` | `package check` | P2 | Read-only, unprivileged |
| `dots-updates` | `package updates` | P2 | Notify-oriented readout |
| `dots-sysupdate` | `package upgrade` | P2 | Privileged via polkit (section 4) |
| `dots-dependencies` | `package deps` | P3 | Check plus install |
| `dots-config-manager` | `config snapshot ...` | P2 | Snapshots and backups |
| `dots-default-apps` | `config default-apps ...` | P3 | `handlr` backend stays internal |
| `dots-settings-gui` | `config gui` | P3 | Shell-launched hub |
| `dots-backup` | `backup ...` | P3 | Cron scheduling kept |
| `dots-security-audit` | `system security audit` | P3 | `--fix` privileged via polkit |
| `dots-performance` | `system performance status` | P3 | Benchmarks stay subcommands |
| `dots-performance-mode` | `system performance profile` | P3 | Privileged via polkit |
| `dots-battery-monitor` | `system battery ...` | P3 | Daemon plus thresholds |
| `dots-check-network` | `system network check` | P3 | Read-only |
| `dots-clipboard` | `system clipboard ...` | P3 | copyq-first ordering kept |
| `dots-file-manager` | `system files` | P3 | Default-app launcher |
| `dots-yazi` | `system files --with yazi` | P3 | Smart-defaults profile of `system files` |
| `dots-git-notify` | dropped | P3 | Personal-workstation helper, no product surface |
| `dots-weather-info` | `system weather` | P3 | Read-only |
| `eww`, `start-gnome-keyring.sh` | out of scope | — | Not `dots-*`; no mapping |

Behavioral notes for the table:

- `dots-appearance theme` packs stay apply-once recipes with no
  sticky "current theme"; `theme list/show` read the same
  `theme.json` packs the config repo ships.
- The follow-policy rule stays: shell `mode` only pushes into GTK
  when the persisted `gtkColorScheme` policy is `follow`
  (missing key means `follow` for legacy boots).
- `doctor` merges `dots-appearance doctor` checks (scheme/state
  parity, wallpaper pointer, `wal` target, hyprlock conf,
  materialyoucolor interpreter) with per-area checks owned by
  each group.

## 6. Non-goals

- No global implementation in this change. This document locks the
  surface; code lands per phase in section 7.
- No change to the shell IPC contract. Targets and functions in
  `HorneroOS/shell` `docs/IPC.md` (`wallpaper`, `appearance`,
  `colours`, `drawers`, and the rest) are untouched by this design.
- No new package manager, init system, or daemon. `package`
  orchestrates the distro tooling; privileged steps go through
  polkit (section 4).
- No replacement of `qs ipc`. `shell ipc` is a thin passthrough
  for scripts; QML `IpcHandler` declarations stay authoritative.
- No migration of personal-workstation helpers (`dots-git-notify`,
  private credential flows) into the product surface.
- No breaking of bare-name `dots-*` invocations before phase 3
  retires them with the deprecation policy from section 3.

## 7. Phased adoption plan (shell IPC stays stable)

Invariant across all phases: the shell keeps spawning bare-name
`dots-*` CLIs per `docs/COMPAT.md`, and every Quickshell IPC
target in `docs/IPC.md` keeps its name and arity. Shell QML does
not change until phase 3, and then only to prefer `horneroctl`
spellings behind the same adapters.

- **Phase 0 — locked design (this document).** No code. Name,
  tree, stability, auth, mapping, and non-goals are fixed here.
  Done when this file merges.
- **Phase 1 — thin shims, shell-safe.** Ship `horneroctl` as a
  dispatcher whose P1 leaves forward to the existing `dots-*`
  implementations. Install `dots-*` compat shims that forward to
  `horneroctl` so both spellings work. Shell behavior unchanged;
  `COMPAT.md` table and appearance-consistency tests stay green.
- **Phase 2 — canonical implementations.** Owning repos
  reimplement their groups behind the locked surface: config owns
  `appearance`/`wallpaper`/`config`, shell owns `shell`,
  hornero owns `package`/`system`/`device`/`backup`, installer
  defines `setup`. Shims remain. Each cutover keeps `--json`
  output byte-compatible with the shim it replaces.
- **Phase 3 — deprecation.** `dots-*` spellings print the
  section 3 deprecation warning and delegate. Shell adapters
  prefer `horneroctl` spellings with `dots-*` fallback. Two
  minor releases minimum before any removal.
- **Phase 4 — removal.** Legacy shims leave the images. Docs and
  the `COMPAT.md` table record the final state; this document
  stays as the archaeology record.

Entry criteria per phase: previous phase contract tests green,
no open IPC-mapping failures, and a secrets rescan with no
findings. No phase may edit the shell IPC surface to "make room";
pressure on IPC names is a design smell to resolve here first.
