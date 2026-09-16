module hornero_cli

import hornero_core

pub fn root_help() string {
	ver := hornero_core.cli_version()
	return 'horneroctl — Hornero OS system CLI (${ver})

Usage: horneroctl [--json|--quiet] <command> [options]

Commands:
  version       Print version
  doctor        Read-only environment health checks
  shell         Desktop shell integration (status, ipc, preset)
  appearance    Appearance backend (status, sync, call, theme, scheme)
  scheme        Alias of appearance scheme (compat shortcut)
  config        Configuration paths, values, validation, snapshots
  package       Pending system updates (check, updates)
  backup        Config backups (list, schedule)
  power         Session power actions (lock, suspend, reboot, shutdown, logout, status)
  lock          Screen lock (now, status)
  hypr          Hyprland controls (animations, layout, monitors, workspace, plugins)
  hardware      Hardware controls (brightness, battery, mic, keyboard, network)
  welcome       First-login onboarding state (status, set-show-on-login, mark-seen, open, reset)
  wallpaper     Wallpaper image (set, current, reload)
  capture       Screenshot, recording, clipboard (screenshot, record, clipboard)
  apps          Everyday apps (files, terminal-file, weather, git-status, audit, launch, toggle, switcher, performance)
  completion    Print shell completions
  help          Show help for a command

Global flags:
  --json        Structured JSON output
  --quiet       Exit code only, no output
  -h, --help    Show help
  -V, --version Print version

Examples:
  horneroctl doctor
  horneroctl shell status --json
  horneroctl appearance sync --dry-run
  horneroctl config validate
  horneroctl package check --dry-run
  horneroctl backup list
'
}

pub fn command_help(name string) string {
	match name {
		'version' {
			return 'Usage: horneroctl version [--json]

Print the horneroctl version, build commit, and release provenance
(shell/config pins, manifest, release name; each baked in at build time
via make.vsh from HX_SHELL_SHA/HX_CONFIG_SHA/HX_MANIFEST/HX_RELEASE,
defaulting to unknown).

Examples:
  horneroctl version
  horneroctl version --json
'
		}
		'doctor' {
			return 'Usage: horneroctl doctor [--json]

Read-only health checks: Wayland/Hyprland session, required binaries,
shell configuration presence, plus a legacy-paths section listing the
detected dots/* state per contract row (with a migration hint when any
legacy state exists). Never changes anything.

Exit codes:
  0  all checks passed
  1  one or more checks failed (details in output)

Examples:
  horneroctl doctor
  horneroctl doctor --json
'
		}
		'shell' {
			return 'Usage: horneroctl shell <status|ipc|preset> [options]

  status              Summarize shell session reachability
  ipc [--dry-run] -- <qs-args...>
                      Pass arguments through to `qs ipc`
  preset list         List installed shell presets (read-only)
  preset current      Show the active preset (read-only)

Options:
  --dry-run           Preview the qs invocation without running it

Later phases: preset apply (needs a pinned merge backend).

Examples:
  horneroctl shell status
  horneroctl shell ipc -- show
  horneroctl shell ipc --dry-run -- call bar toggleLauncher
  horneroctl shell preset list
  horneroctl shell preset current --json
'
		}
		'shell preset' {
			return 'Usage: horneroctl shell preset <list|current>

  list                List installed shell presets (read-only)
  current             Show the active preset (read-only)

Preset sources: HORNERO_PRESETS_DIR, else the XDG data catalogue
(hornero/shell-presets, legacy dots/shell-presets as read-only fallback);
the active pointer lives under XDG state.

Later phases: preset apply (needs a pinned merge backend).

Examples:
  horneroctl shell preset list
  horneroctl shell preset current
  horneroctl shell preset list --json
'
		}
		'appearance' {
			return 'Usage: horneroctl appearance <status|sync|call|theme|scheme|colors|accent|night-mode> [options]

  status              Show current appearance state (read-only)
  sync [--dry-run]    Apply the pending color scheme (needs --yes)
  call [--dry-run] -- <backend-args...>
                      Pass arguments to the appearance backend directly
  theme ...           Installed theme packs (list, show, get, apply, set)
  scheme ...          Color scheme state and setters (status, set-mode, set-variant)
  colors ...          Smart-color palette (status, generate, m3)
  accent ...          Accent override seed (show, set, clear)
  night-mode ...      Display temperature backend (status)

Options:
  --dry-run           Preview without changing anything
  --yes               Confirm a mutating action

Examples:
  horneroctl appearance status
  horneroctl appearance sync --dry-run
  horneroctl appearance sync --yes
  horneroctl appearance call -- theme list
  horneroctl appearance theme list
  horneroctl appearance scheme status
  horneroctl appearance colors status --dry-run
  horneroctl appearance accent show
  horneroctl appearance night-mode status
'
		}
		'appearance theme' {
			return 'Usage: horneroctl appearance theme <list|show|get|apply|set> [options]

  list                List installed theme packs (read-only)
  show <id>           Show one theme pack (read-only)
  get [--dry-run]     Show the active official theme (read-only)
  apply <id> [--wallpaper <path>] [--dry-run]
                      Apply a theme pack (needs --yes)
  set <hornero-dark|hornero-light|pampa> [--dry-run]
                      Switch the official theme atomically (needs --yes)

Pack source: HORNERO_THEMES_DIR, else the XDG data catalogue
(hornero/themes, legacy dots/themes as read-only fallback).
Reads parse the installed theme.json manifests;
apply delegates to dots-appearance (HORNERO_DOTS_APPEARANCE_BIN).
get matches the live backend state against the official
hornero-dark/hornero-light/pampa trio; set validates, applies via
dots-appearance, then verifies GTK/scheme agree (best-effort
rollback to the previous official theme on failure).

Examples:
  horneroctl appearance theme list
  horneroctl appearance theme show vapor-dreams
  horneroctl appearance theme get
  horneroctl appearance theme apply vapor-dreams --dry-run
  horneroctl appearance theme apply vapor-dreams --yes
  horneroctl appearance theme set hornero-dark --dry-run
  horneroctl appearance theme set hornero-light --yes
'
		}
		'appearance scheme' {
			return 'Usage: horneroctl appearance scheme <status|set-mode|set-variant> [options]

  status              Show mode/flavour/variant (read-only)
  set-mode <dark|light> [--dry-run]
                      Set the color-scheme mode (needs --yes)
  set-variant <name> [--dry-run]
                      Set the color-scheme variant (needs --yes)

State source: the materialized scheme files under XDG state/cache;
setters delegate to dots-appearance (HORNERO_DOTS_APPEARANCE_BIN).

Later phases: device brightness and other hardware controls (no
verified IPC path yet).

Examples:
  horneroctl appearance scheme status
  horneroctl appearance scheme set-mode dark --dry-run
  horneroctl appearance scheme set-mode dark --yes
  horneroctl appearance scheme set-variant tonalspot --yes
'
		}
		'appearance colors' {
			return 'Usage: horneroctl appearance colors <status|generate|m3> [options]

  status [--dry-run]  Preview the generated palette (read-only)
  generate [--m3] [--dry-run]
                      Rewrite the smart-color files (needs --yes;
                      --m3 also refreshes scheme.json)
  m3 [--dry-run] -- <backend-args...>
                      Pass arguments to dots-m3-colors directly (needs --yes)

Backend: dots-smart-colors (HORNERO_SMART_COLORS_BIN); m3 passes
through to dots-m3-colors (HORNERO_M3_COLORS_BIN). The palette
generation engine itself stays in the backend; V only delegates.
Every backend call runs under HORNEROCTL_DELEGATED=1 so the
delegating dots-* shims run their legacy body.

Examples:
  horneroctl appearance colors status
  horneroctl appearance colors status --dry-run
  horneroctl appearance colors generate --dry-run
  horneroctl appearance colors generate --m3 --yes
  horneroctl appearance colors m3 --dry-run -- --help
'
		}
		'appearance accent' {
			return 'Usage: horneroctl appearance accent <show|set|clear> [options]

  show [--dry-run]    Print the accent override seed (read-only)
  set <hex> [--dry-run]
                      Set the accent seed (needs --yes)
  clear [--dry-run]   Clear the override, regenerate from wallpaper (needs --yes)

Backend: dots-accent-override (HORNERO_ACCENT_OVERRIDE_BIN).
Set/clear trigger a scheme regenerate downstream. Every backend
call runs under HORNEROCTL_DELEGATED=1 so the delegating dots-*
shims run their legacy body.

Examples:
  horneroctl appearance accent show
  horneroctl appearance accent set "#8839ef" --dry-run
  horneroctl appearance accent set "#8839ef" --yes
  horneroctl appearance accent clear --dry-run
'
		}
		'appearance night-mode' {
			return 'Usage: horneroctl appearance night-mode <status> [options]

  status [--dry-run]  Show whether the temperature backend is active (read-only)

Backend: dots-night-mode (HORNERO_NIGHT_MODE_BIN). Toggles
(on/off) stay in the backend for now: no verified portable
surface yet. Every backend call runs under HORNEROCTL_DELEGATED=1
so the delegating dots-* shims run their legacy body.

Examples:
  horneroctl appearance night-mode status
  horneroctl appearance night-mode status --dry-run
'
		}
		'scheme' {
			return 'Usage: horneroctl scheme <status|set-mode|set-variant> [options]

Compat shortcut for `horneroctl appearance scheme`.

Examples:
  horneroctl scheme status
  horneroctl scheme set-mode dark --dry-run
'
		}
		'config' {
			return 'Usage: horneroctl config <paths|validate|show|snapshot|default-apps|materialize|gui|migrate> [key]

  paths               Print the resolved XDG path contract
  validate            Check materialized config (read-only)
  show [key]          Show materialized shell.json values (read-only);
                      with a dot-notation key (bar.position) show one value
  snapshot ...        Configuration snapshots (create, list, restore)
  default-apps ...    Default applications (list; set needs a backend)
  materialize ...     Install curated defaults into --dest (needs --yes)
  gui [--pane <name>] Open the settings hub
  migrate ...         One-shot dots/* to hornero/* move (needs --yes)

Later phases: default-apps set (no verified backend yet).

Examples:
  horneroctl config paths
  horneroctl config validate --json
  horneroctl config show
  horneroctl config show bar.position
  horneroctl config show --json
  horneroctl config snapshot list
  horneroctl config default-apps list
  horneroctl config materialize --dest /tmp/hx-dest --dry-run
  horneroctl config gui --pane appearance
  horneroctl config migrate --dry-run
'
		}
		'config default-apps' {
			return 'Usage: horneroctl config default-apps <list|set> [options]

  list [--dry-run]  List current default applications (read-only)
  set <mime> <app>  Not yet available: needs a pinned backend
                    (dots-default-apps exposes no verified
                    non-interactive set verb; handlr stays internal)

Default source: handlr/XDG MIME associations via dots-default-apps
(HORNERO_DEFAULT_APPS_BIN).

Examples:
  horneroctl config default-apps list
  horneroctl config default-apps list --dry-run
  horneroctl config default-apps list --json
'
		}
		'config materialize' {
			return 'Usage: horneroctl config materialize --dest <dir> [--dry-run|--yes]

  Install the curated config defaults into <dir> via the config
  repo materialize.sh (HORNERO_MATERIALIZE_BIN). Mutating: needs
  --yes; --dry-run previews (passed through to the backend, which
  stays hermetic for --dest outside the real HOME).

Examples:
  horneroctl config materialize --dest /tmp/hx-dest --dry-run
  horneroctl config materialize --dest /tmp/hx-dest --yes
  horneroctl config materialize --dest /tmp/hx-dest --dry-run --json
'
		}
		'config gui' {
			return 'Usage: horneroctl config gui [--pane <name>] [--dry-run]

  Open the settings hub via dots-settings-gui
  (HORNERO_SETTINGS_GUI_BIN). Panes: network, bluetooth, audio,
  appearance, taskbar, launcher, dashboard, system.

Examples:
  horneroctl config gui --dry-run
  horneroctl config gui --pane appearance
  horneroctl config gui --pane launcher --json
'
		}
		'config migrate' {
			return 'Usage: horneroctl config migrate [--dry-run|--yes] [--helper PATH]

  Move legacy dots/* state into the canonical hornero/* locations via
  the config repo migrate-to-hornero.sh backend (HORNERO_MIGRATE_BIN,
  or --helper PATH for one invocation). Copy-if-absent over the
  Hornero-owned rows only: themes, presets, the preset pointer,
  scheme.json plus scheme state, the wallpaper pointer, and notifs.
  Mutating: needs --yes; --dry-run previews (passed through to the
  backend). The backend reports one ROW line per row; --json carries
  them as row.<domain> entries plus a rows count.

Examples:
  horneroctl config migrate --dry-run
  horneroctl config migrate --yes
  horneroctl config migrate --dry-run --helper /tmp/migrate-to-hornero.sh
  horneroctl config migrate --yes --json
'
		}
		'config snapshot' {
			return 'Usage: horneroctl config snapshot <create|list|restore> [options]

  create [--dry-run]  Create a configuration snapshot (needs --yes)
  list                List materialized snapshots (read-only)
  restore <id> [--dry-run]
                      Restore one snapshot (needs --yes)

Snapshot source: HORNERO_SNAPSHOTS_DIR, else the XDG cache catalogue
(hornero/snapshots, legacy dots/snapshots as read-only fallback);
create/restore delegate to dots-config-manager
(HORNERO_CONFIG_MANAGER_BIN).

Examples:
  horneroctl config snapshot list
  horneroctl config snapshot create --dry-run
  horneroctl config snapshot create --yes
  horneroctl config snapshot restore config_20260101_020000 --dry-run
  horneroctl config snapshot list --json
'
		}
		'package' {
			return 'Usage: horneroctl package <check|updates> [options]

  check [--dry-run]   List pending system updates (read-only)
  updates [--dry-run] Pending-update count readout (read-only)

Update source: dots-checkupdates or checkupdates on PATH
(HORNERO_CHECKUPDATES_BIN override). Read-only and unprivileged.

Later phases: upgrade (needs a polkit backend), deps (installer-owned).

Examples:
  horneroctl package check
  horneroctl package check --dry-run
  horneroctl package updates
  horneroctl package updates --json
'
		}
		'backup' {
			return 'Usage: horneroctl backup <list|schedule>

  list                List materialized backups (read-only)
  schedule            Print the cron/systemd recipe (documented, not installed)

Backup source: HORNERO_BACKUP_DIR, else the dotfiles backup directory
(~/.dotfiles/backup). Scheduling is never installed by horneroctl:
copy-paste the printed recipe instead (legacy dots-backup
--register-cron flow).

Later phases: create/restore (need a pinned non-interactive backend).

Examples:
  horneroctl backup list
  horneroctl backup list --json
  horneroctl backup schedule
'
		}
		'power' {
			return 'Usage: horneroctl power <lock|suspend|reboot|shutdown|logout|status> [--dry-run|--yes]

  lock                Lock the screen via the shared lock plan (needs --yes)
  suspend             Suspend the machine via systemctl (needs --yes)
  reboot              Reboot the machine via systemctl (needs --yes)
  shutdown            Power off the machine via systemctl (needs --yes)
  logout              End the current login session via loginctl (needs --yes)
  status              Show session and power backend state (read-only)

Mutating actions need --yes; --dry-run only previews. The lock plan
prefers dots-lockscreen --lock (HORNERO_LOCKSCREEN_BIN), then bare
hyprlock (HORNERO_HYPRLOCK_BIN), then loginctl lock-session;
suspend/reboot/shutdown use systemctl (HORNERO_SYSTEMCTL_BIN) and
logout uses loginctl (HORNERO_LOGINCTL_BIN).

Examples:
  horneroctl power status
  horneroctl power lock --dry-run
  horneroctl power lock --yes
  horneroctl power suspend --dry-run
  horneroctl power reboot --yes
  horneroctl power shutdown --yes
  horneroctl power logout --yes
'
		}
		'hypr' {
			return 'Usage: horneroctl hypr <animations|layout|monitors|workspace|plugins> [options]

  animations        Animation profiles (list, current, set, next, restore)
  layout            Layout profiles (current, status, set, toggle, restore)
  monitors          Monitor arrangements (list, status, set)
  workspace         Next/prev workspace cycling (next, prev)
  plugins           Hyprland plugin status (list, status; install stays legacy)

Reads (list/current/status) never touch the compositor state;
mutations need --yes and --dry-run only previews. Plugin install,
enable, and reload stay in dots-hyprland-plugins (hyprpm/AUR-helper
flow): horneroctl only reports plugin status.

Examples:
  horneroctl hypr animations list
  horneroctl hypr animations set cozy --dry-run
  horneroctl hypr layout toggle --dry-run
  horneroctl hypr monitors status
  horneroctl hypr monitors set extend-right --dry-run
  horneroctl hypr workspace next --dry-run
  horneroctl hypr plugins status
'
		}
		'hypr animations' {
			return 'Usage: horneroctl hypr animations <list|current|set|next|restore> [options]

  list                List available profiles (read-only)
  current             Print the persisted profile (read-only)
  set <profile> [--dry-run]
                      Apply default|cozy|cyberpunk|nature|minimal|vaporwave
                      live via hyprctl keywords (needs --yes)
  next [--dry-run]    Cycle to the next profile (needs --yes)
  restore [--dry-run] Re-apply the persisted profile (needs --yes)

Options:
  --ephemeral         Do not persist the selection to disk
  --dry-run           Preview the hyprctl invocations without running them
  --yes               Confirm a mutating action

Profiles come from hyprland.conf.d/animations[-<profile>].conf under
\$XDG_CONFIG_HOME/hypr; the selection persists under \$XDG_STATE_HOME
(dots/hypr-animations/current).

Examples:
  horneroctl hypr animations list
  horneroctl hypr animations current
  horneroctl hypr animations set cozy --dry-run
  horneroctl hypr animations set cozy --yes
  horneroctl hypr animations next --yes
  horneroctl hypr animations restore --yes
'
		}
		'hypr layout' {
			return 'Usage: horneroctl hypr layout <current|status|set|toggle|restore> [options]

  current             Print the live layout, else persisted (read-only)
  status              Live layout, persisted pointer, backend state (read-only)
  set <layout> [--dry-run]
                      Apply scrolling|dwindle|master (needs --yes)
  toggle [--dry-run]  Flip scrolling to dwindle and back (needs --yes)
  restore [--dry-run] Re-apply the persisted layout (needs --yes)

Options:
  --ephemeral         Do not persist the selection to disk
  --dry-run           Preview the hyprctl invocations without running them
  --yes               Confirm a mutating action

The scrolling profile sets general:layout plus the scrolling tunables;
dwindle/master set one keyword. The selection persists under
\$XDG_STATE_HOME (dots/hypr-layout/current).

Examples:
  horneroctl hypr layout status
  horneroctl hypr layout current
  horneroctl hypr layout set scrolling --dry-run
  horneroctl hypr layout set dwindle --yes
  horneroctl hypr layout toggle --yes
  horneroctl hypr layout restore --yes
'
		}
		'hypr monitors' {
			return 'Usage: horneroctl hypr monitors <list|status|set> [options]

  list                List monitors from hyprctl (read-only)
  status              Internal/external split and backend state (read-only)
  set <mode> [--dry-run]
                      Apply one arrangement (needs --yes):
                      internal-only, external-only, extend-right,
                      extend-left, extend-above, extend-below, mirror,
                      disable-external

Options:
  --dry-run           Preview the hyprctl invocations without running them
  --yes               Confirm a mutating action

Internal is the first eDP* monitor (else the first entry); external
is the first non-eDP monitor (else the second entry). Extend modes
place displays using live geometry from `hyprctl monitors -j`.

Examples:
  horneroctl hypr monitors list
  horneroctl hypr monitors status
  horneroctl hypr monitors set extend-right --dry-run
  horneroctl hypr monitors set mirror --yes
  horneroctl hypr monitors set internal-only --yes
'
		}
		'hypr workspace' {
			return 'Usage: horneroctl hypr workspace <next|prev> [--dry-run|--yes]

  next [--dry-run]    Switch to the next workspace, wrapping (needs --yes)
  prev [--dry-run]    Switch to the previous workspace, wrapping (needs --yes)

Options:
  --previous, --left  Alias for prev (legacy dots-next-workspace flags)
  --dry-run           Preview the i3-msg invocation without running it
  --yes               Confirm a mutating action

Backend: i3-msg (HORNERO_I3_MSG_BIN). Order comes from the ordered
`set \$WS` names in the i3 config, the focused workspace from
get_workspaces; the target wraps around at either end.

Examples:
  horneroctl hypr workspace next --dry-run
  horneroctl hypr workspace next --yes
  horneroctl hypr workspace prev --yes
'
		}
		'hypr plugins' {
			return 'Usage: horneroctl hypr plugins <list|status>

  list                Print the hyprpm plugin list (read-only)
  status              hyprpm presence plus ScrollOverview installed/enabled
                      (read-only, never fails)

Plugin install, enable, and reload stay in dots-hyprland-plugins
(hyprpm/AUR-helper flow) and are intentionally not ported: there is
no verified non-interactive install backend for horneroctl to own.

Examples:
  horneroctl hypr plugins status
  horneroctl hypr plugins list
  horneroctl hypr plugins status --json
'
		}
		'lock' {
			return 'Usage: horneroctl lock <now|status> [--dry-run|--yes]

  now [--dry-run]     Lock the screen now (needs --yes)
  status              Show lock backend state (read-only)

Backend: dots-lockscreen --lock (HORNERO_LOCKSCREEN_BIN), else bare
hyprlock (HORNERO_HYPRLOCK_BIN), else loginctl lock-session
(HORNERO_LOGINCTL_BIN).

Examples:
  horneroctl lock status
  horneroctl lock now --dry-run
  horneroctl lock now --yes
'
		}
		'wallpaper' {
			return 'Usage: horneroctl wallpaper <set|current|reload> [options]

  set <path> [--dry-run]    Apply a wallpaper image (needs --yes)
  current [path]            Print the current wallpaper path (read-only)
  reload [--dry-run]        Re-apply the color pipeline (needs --yes)

Reads resolve canonical-first: the hornero/* pointer, then the legacy
dots/* pointer, then the pywal link. Mutations delegate to the verified
dots-wallpaper-set / dots-wal-reload backends (HORNERO_WALLPAPER_SET_BIN,
HORNERO_WAL_RELOAD_BIN), which own the Quickshell appearance IPC verbs
plus the wal+M3 fallback; every backend call carries
HORNEROCTL_DELEGATED=1 so the delegating dots-* shims run their legacy
body instead of calling back.

Mutations need --yes; --dry-run only previews.

Examples:
  horneroctl wallpaper current
  horneroctl wallpaper current --json
  horneroctl wallpaper set ~/wall.jpg --dry-run
  horneroctl wallpaper set ~/wall.jpg --yes
  horneroctl wallpaper reload --dry-run
  horneroctl wallpaper reload --yes
'
		}
		'hardware' {
			return 'Usage: horneroctl hardware <brightness|battery|mic|keyboard|network> ... [--dry-run|--yes]

  brightness    Display brightness (status, set, up, down)
  battery       Battery charge (status, monitor)
  mic           Microphone mute state (status, toggle)
  keyboard      Keyboard layout, settings GUI, keybindings (layout, settings, keys)
  network       Connectivity probe (status)

Reads report backend state; mutating leaves need --yes and preview
with --dry-run. Backends mirror the dots-* scripts (brightnessctl /
xrandr, acpi / upower, wpctl, hyprctl / setxkbmap, ping), each with a
HORNERO_*_BIN override.

Examples:
  horneroctl hardware brightness status
  horneroctl hardware brightness set 0.8 --dry-run
  horneroctl hardware battery status
  horneroctl hardware mic toggle --dry-run
  horneroctl hardware keyboard layout --current
  horneroctl hardware network status
'
		}
		'hardware brightness' {
			return 'Usage: horneroctl hardware brightness <status|set|up|down> [--display NAME] [--dry-run|--yes]

  status [--display NAME]
                Show current brightness (read-only); without --display,
                xrandr lists every connected display
  set <0.0-1.0> [--display NAME]
                Set brightness fraction, clamped into range (needs --yes)
  up [--step 0.1] [--display NAME]
                Raise brightness by step (needs --yes)
  down [--step 0.1] [--display NAME]
                Lower brightness by step (needs --yes)

Backend precedence (dots-brightness): brightnessctl, blight,
xbacklight, xrandr (HORNERO_BRIGHTNESSCTL_BIN and siblings override).
xbacklight/xrandr need a display: --display, else the first connected
output. Color-temperature (--temp) stays in dots-brightness.

Examples:
  horneroctl hardware brightness status
  horneroctl hardware brightness status --display eDP-1
  horneroctl hardware brightness set 0.8 --dry-run
  horneroctl hardware brightness set 0.8 --yes
  horneroctl hardware brightness up --step 0.05 --dry-run
  horneroctl hardware brightness down --display eDP-1 --yes
'
		}
		'hardware battery' {
			return 'Usage: horneroctl hardware battery <status|monitor> [options]

  status              Show charge percent and state (read-only)
  monitor [--low 20] [--crit 10] [--interval 120] [--daemon]
                      Poll with low/critical notifications (needs --yes)

Charge source: acpi, else upower (HORNERO_ACPI_BIN /
HORNERO_UPOWER_BIN); machines with no battery report as such instead
of 100%. With poweralertd present the monitor stays idle. --daemon
detaches a background copy via nohup.

Examples:
  horneroctl hardware battery status
  horneroctl hardware battery monitor --dry-run
  horneroctl hardware battery monitor --low=25 --crit=15 --dry-run
  horneroctl hardware battery monitor --yes
  horneroctl hardware battery monitor --interval=60 --daemon --yes
'
		}
		'hardware mic' {
			return 'Usage: horneroctl hardware mic <status|toggle> [--dry-run|--yes]

  status              Show muted/unmuted via wpctl (read-only)
  toggle [--dry-run]  Flip the default-source mute (needs --yes)

Source: HORNERO_MIC_SOURCE, else the wpctl default-source
placeholder (HORNERO_WPCTL_BIN override). The event-driven listen
loop stays in dots-microphone.

Examples:
  horneroctl hardware mic status
  horneroctl hardware mic toggle --dry-run
  horneroctl hardware mic toggle --yes
'
		}
		'hardware keyboard' {
			return 'Usage: horneroctl hardware keyboard <layout|settings|keys> [options]

  layout [--current|--get|--toggle] [--dry-run]
                      Toggle the us/latam cycle (needs --yes);
                      --current shows info, --get prints the name
  settings [--dry-run]
                      Open the LXQt keyboard settings GUI
  keys [--category CAT] [--search TERM] [--dry-run]
                      List Hyprland keybindings, optionally filtered

Layout backend: hyprctl on Hyprland, else setxkbmap
(HORNERO_HYPRCTL_BIN / HORNERO_SETXKBMAP_BIN). settings opens
dots-keyboard-settings, else lxqt-config-input. keys parses the
Hyprland keybindings file (HORNERO_KEYBINDINGS_FILE override),
rewriting \$mainMod to SUPER; with quickshell running it asks the
settings GUI instead (DOTS_BYPASS_QUICKSHELL=1 forces parsing).

Examples:
  horneroctl hardware keyboard layout --current
  horneroctl hardware keyboard layout --get
  horneroctl hardware keyboard layout --dry-run
  horneroctl hardware keyboard layout --yes
  horneroctl hardware keyboard settings --dry-run
  horneroctl hardware keyboard keys --search workspace
  horneroctl hardware keyboard keys --category=Window
'
		}
		'hardware network' {
			return 'Usage: horneroctl hardware network status [--timeout 5] [--dry-run]

  status              Ping the probe host once and classify the first
                      UP interface as wired/wireless (read-only)

Target: DOTS_PING_HOST, else 1.1.1.1; --timeout is the ping deadline
in seconds. The polling loop stays in dots-check-network.

Examples:
  horneroctl hardware network status
  horneroctl hardware network status --timeout=2
  horneroctl hardware network status --dry-run
  horneroctl hardware network status --json
'
		}
		'capture' {
			return 'Usage: horneroctl capture <screenshot|record|clipboard> [options]

  screenshot [--fullscreen|--region] [--output PATH] [--dry-run]
                      Take a screenshot via sss (needs --yes)
  record <start|stop|pause> [--region] [--sound] [--sr] [--fps N] [--dry-run]
                      Drive gpu-screen-recorder (needs --yes)
  clipboard [--backend NAME] [--dry-run]
                      Open the clipboard picker view (read-only, no --yes)

Screenshot defaults to fullscreen (\$XDG_PICTURES_DIR, else ~/Pictures,
screenshot_YYYYMMDD_HHMMSS.png); --region takes an interactive region
instead (--region wins when both are given). Recordings land in
\$CAELESTIA_RECORDINGS_DIR, else \$XDG_VIDEOS_DIR/Recordings, as
recording_YYYYMMDD_HH-MM-SS.mp4; start reuses fps 30 unless --fps sets
it, and --sr selects region plus desktop audio together. start is an
ok no-op while a recording runs; stop and pause are ok no-ops with
none running. Clipboard resolves like dots-clipboard (Wayland:
copyq, cliphist, minimal; otherwise copyq, minimal): copyq opens the
picker, cliphist lists history (top 25, no interactive pick), minimal
previews the paste.

Mutations (screenshot, every record leaf) need --yes; --dry-run only
previews. Backend overrides: HORNERO_SSS_BIN,
HORNERO_GPU_SCREEN_RECORDER_BIN, HORNERO_RECORDER_MATCH (pgrep/pkill
pattern, default gpu-screen-recorder), HORNERO_COPYQ_BIN,
HORNERO_CLIPHIST_BIN, HORNERO_WL_PASTE_BIN.

Examples:
  horneroctl capture screenshot --dry-run
  horneroctl capture screenshot --yes
  horneroctl capture screenshot --region --dry-run
  horneroctl capture screenshot --output ~/shot.png --yes
  horneroctl capture record start --dry-run
  horneroctl capture record start --region --sound --yes
  horneroctl capture record start --fps 60 --dry-run
  horneroctl capture record stop --yes
  horneroctl capture record pause --yes
  horneroctl capture clipboard
  horneroctl capture clipboard --backend copyq --dry-run
  horneroctl capture clipboard --backend minimal
'
		}
		'apps' {
			return 'Usage: horneroctl apps <files|terminal-file|weather|git-status|audit|launch|toggle|switcher|performance> ... [--dry-run|--yes]

  files [--path PATH] [--info]
                      Open the default file manager (view-open, no --yes)
                      or show it with --info (read-only)
  terminal-file [--path PATH] [--select FILE] [--last-dir]
                      Open yazi, show the cheatsheet, or diagnose previews
                      (view-open and reads, no --yes)
  weather <--getdata|--icon|--temp|--hex|--stat|--loc|--quote|--quote2>
                      Read one cached weather field or refresh (read-only)
  git-status [watch|jobs|stop] [--branch B] [--repository R]
                      Watch a repo with desktop notifications (needs --yes),
                      list watchers (jobs, read-only), or stop them (needs --yes)
  audit [--permissions|--secrets|--system]
                      Read-only security checks (fix and report stay legacy)
  launch [--backend NAME] [--list]
                      Open the app launcher or list backends (no --yes)
  toggle <component>  Toggle a shell component or daemon (needs --yes)
  switcher <leaf>     Drive the window switcher; status is read-only,
                      control leaves need --yes
  performance <leaf>  Shell/memory/benchmark/report reads plus the
                      power-profile mode (set needs --yes)

Reads and view-opens need no --yes; mutations need --yes and preview
with --dry-run. Backends mirror the dots-* scripts, each with a
HORNERO_*_BIN override; dots-* calls carry HORNEROCTL_DELEGATED=1.

Later phases: default-apps set (no verified backend yet; list lives
under `config default-apps list`).

Examples:
  horneroctl apps files --dry-run
  horneroctl apps files --info
  horneroctl apps terminal-file --cheatsheet
  horneroctl apps weather --temp
  horneroctl apps git-status jobs
  horneroctl apps audit --dry-run
  horneroctl apps launch --list
  horneroctl apps toggle bar --dry-run
  horneroctl apps switcher status
  horneroctl apps performance memory
  horneroctl apps performance mode
'
		}
		'apps files' {
			return 'Usage: horneroctl apps files [--path PATH] [--info] [--dry-run]

  open (default)      Open the default file manager at --path, else the
                      working directory (view-open, no --yes)
  --info              Show the current default file manager (read-only)

Backend chain (dots-file-manager): exo-open --launch FileManager,
handlr open, xdg-open (HORNERO_EXO_OPEN_BIN / HORNERO_HANDLR_BIN /
HORNERO_XDG_OPEN_BIN); --info reads via dots-file-manager
(HORNERO_FILE_MANAGER_BIN).

Examples:
  horneroctl apps files --dry-run
  horneroctl apps files --path ~/Documents --dry-run
  horneroctl apps files --info
  horneroctl apps files --info --json
'
		}
		'apps terminal-file' {
			return 'Usage: horneroctl apps terminal-file [--path PATH] [--select FILE] [--last-dir] [--cheatsheet] [--fix-previews] [--dry-run]

  open (default)      Open yazi via dots-yazi (view-open, no --yes)
  --cheatsheet        Print the keybinding reference (read-only)
  --fix-previews      Diagnose preview dependencies (read-only)

Launch wraps dots-yazi (HORNERO_DOTS_YAZI_BIN), falling back to bare
yazi (HORNERO_YAZI_BIN).

Examples:
  horneroctl apps terminal-file --dry-run
  horneroctl apps terminal-file --path ~/Documents --dry-run
  horneroctl apps terminal-file --select ~/notes.txt --dry-run
  horneroctl apps terminal-file --last-dir --dry-run
  horneroctl apps terminal-file --cheatsheet
  horneroctl apps terminal-file --fix-previews
'
		}
		'apps weather' {
			return 'Usage: horneroctl apps weather <--getdata|--icon|--temp|--hex|--stat|--loc|--quote|--quote2> [--dry-run]

  --getdata           Refresh the cache from OpenWeatherMap (read-only)
  --icon --temp --hex --stat --loc --quote --quote2
                      Read one cached field (read-only)

Exactly one field per invocation. Reads resolve via dots-weather-info
(HORNERO_WEATHER_BIN); refresh needs a WEATHER_API_KEY like the script.

Examples:
  horneroctl apps weather --temp
  horneroctl apps weather --icon --json
  horneroctl apps weather --getdata --dry-run
  horneroctl apps weather --loc
'
		}
		'apps git-status' {
			return 'Usage: horneroctl apps git-status [watch|jobs|stop] [--branch B] [--repository R] [--interval N] [--async] [--verbose] [--dry-run|--yes]

  watch (default)     Notify on new commits in this repo (needs --yes)
  jobs                List running watcher jobs (read-only)
  stop                Kill running watcher jobs (needs --yes)

Options:
  --branch B          Branch to watch (default origin/main)
  --repository R      Revision to watch (default origin/main)
  --interval N        Poll seconds (default 60)
  --async             Detach the watcher into the background
  --verbose           Timestamped logging

Backend: dots-git-notify (HORNERO_GIT_NOTIFY_BIN); watch runs inside
the current git repository.

Examples:
  horneroctl apps git-status jobs
  horneroctl apps git-status watch --dry-run
  horneroctl apps git-status watch --interval 30 --async --yes
  horneroctl apps git-status stop --dry-run
  horneroctl apps git-status stop --yes
'
		}
		'apps audit' {
			return 'Usage: horneroctl apps audit [--permissions|--secrets|--system] [--dry-run]

  audit (default)     Full read-only security audit
  --permissions       File permission checks only (read-only)
  --secrets           Exposed-secret scan only (read-only)
  --system            Firewall, updates, SSH, MAC checks only (read-only)

At most one check per invocation. Backend: dots-security-audit
(HORNERO_SECURITY_AUDIT_BIN). --fix (permission changes, history
scrub) and --report stay in dots-security-audit and are intentionally
not ported.

Examples:
  horneroctl apps audit
  horneroctl apps audit --dry-run
  horneroctl apps audit --permissions
  horneroctl apps audit --system --json
'
		}
		'apps launch' {
			return 'Usage: horneroctl apps launch [--backend NAME] [--list] [--dry-run]

  launch (default)    Open the app launcher (view-open, no --yes)
  --list              Print detected backends in priority order (read-only)

Backends: quickshell, minimal (else auto). Backend: dots-launcher
(HORNERO_LAUNCHER_BIN).

Examples:
  horneroctl apps launch --dry-run
  horneroctl apps launch --backend quickshell --dry-run
  horneroctl apps launch --list
'
		}
		'apps toggle' {
			return 'Usage: horneroctl apps toggle <bar|launcher|dashboard|sidebar|session|utilities|redshift|caffeine> [--dry-run|--yes]

  bar launcher dashboard sidebar session utilities
                      Toggle one quickshell component via ipc (needs --yes)
  redshift caffeine   Toggle the daemon once via --toggle (needs --yes);
                      the monitor loops stay in dots-toggle

Backend: dots-toggle (HORNERO_TOGGLE_BIN).

Examples:
  horneroctl apps toggle bar --dry-run
  horneroctl apps toggle bar --yes
  horneroctl apps toggle launcher --yes
  horneroctl apps toggle redshift --dry-run
  horneroctl apps toggle caffeine --yes
'
		}
		'apps switcher' {
			return 'Usage: horneroctl apps switcher [daemon|next|prev|toggle|hide|select|quit|status|apply-theme|apply-theme-pack] [arg] [--dry-run|--yes]

  status              Show whether the daemon runs (read-only)
  daemon next prev toggle hide select quit
                      Drive the switcher (needs --yes)
  apply-theme <file>  Apply an explicit theme file (needs --yes)
  apply-theme-pack [id]
                      Apply a theme from the appearance pack (needs --yes)

Default leaf is toggle. Backend: dots-snappy-switcher
(HORNERO_SNAPPY_BIN).

Examples:
  horneroctl apps switcher status
  horneroctl apps switcher next --dry-run
  horneroctl apps switcher toggle --yes
  horneroctl apps switcher apply-theme nord.ini --dry-run
  horneroctl apps switcher apply-theme-pack --dry-run
'
		}
		'apps performance' {
			return 'Usage: horneroctl apps performance <startup|memory|benchmark|report|mode> [set <profile>] [--dry-run|--yes]

  startup             Measure shell startup (read-only)
  memory              Wayland stack memory readout (read-only)
  benchmark           Full benchmark suite (read-only)
  report              Generate the markdown report (read-only)
  mode                Show the power profile and available ones (read-only)
  mode set <profile>  Switch the power profile via powerprofilesctl
                      (needs --yes)

Reads delegate to dots-performance (HORNERO_PERFORMANCE_BIN); mode
uses powerprofilesctl get/list/set
(HORNERO_POWERPROFILESCTL_BIN). The interactive menu, quickshell
pane, and auto-cpufreq GUI stay in dots-performance-mode.

Examples:
  horneroctl apps performance memory
  horneroctl apps performance startup --dry-run
  horneroctl apps performance mode
  horneroctl apps performance mode set balanced --dry-run
  horneroctl apps performance mode set balanced --yes
'
		}
		'completion' {
			return 'Usage: horneroctl completion <bash|zsh|fish>

Print a shell completion script to stdout.

Examples:
  horneroctl completion bash > /etc/bash_completion.d/horneroctl
  horneroctl completion zsh > ~/.zsh/completions/_horneroctl
'
		}
		'welcome' {
			return 'Usage: horneroctl welcome <status|set-show-on-login|mark-seen|open|reset> [options]

Hornero-wide first-login onboarding state (docs/PATH_CONTRACT.md).
The state file is the single source of truth every frontend reads;
the Shell never shells out for it at startup.

  status                        Show the current state (read-only)
  set-show-on-login <bool>      Opt in/out of login-time Welcome [--dry-run] [--yes]
  mark-seen [--revision <r>]    Record content revision as seen [--dry-run] [--yes]
  open [page]                   Ask the shell to open Welcome [--dry-run]
  reset                         Restore defaults (show on login) [--dry-run] [--yes]

Mutations need --yes; --dry-run only previews. An explicit opt-out
always wins, even when content is updated.

Examples:
  horneroctl welcome status
  horneroctl welcome status --json
  horneroctl welcome set-show-on-login false --dry-run
  horneroctl welcome set-show-on-login false --yes
  horneroctl welcome mark-seen --dry-run
  horneroctl welcome open --dry-run
  horneroctl welcome reset --dry-run
'
		}
		'welcome status' {
			return 'Usage: horneroctl welcome status [--json]

Show the Welcome state (read-only): whether Welcome opens at login,
which content revision shipped vs was seen, and the state file path.
Missing or malformed state behaves as defaults (first login shows).

Examples:
  horneroctl welcome status
  horneroctl welcome status --json
'
		}
		'welcome set-show-on-login' {
			return 'Usage: horneroctl welcome set-show-on-login <true|false> [--dry-run] [--yes]

Opt in or out of login-time Welcome. Idempotent: setting the current
value succeeds without rewriting the file.

Examples:
  horneroctl welcome set-show-on-login false --dry-run
  horneroctl welcome set-show-on-login false --yes
  horneroctl welcome set-show-on-login true --yes
'
		}
		'welcome mark-seen' {
			return 'Usage: horneroctl welcome mark-seen [--revision <r>] [--dry-run] [--yes]

Record a content revision as seen (defaults to the shipped revision)
and refresh open timestamps. Never flips showOnLogin.

Examples:
  horneroctl welcome mark-seen --dry-run
  horneroctl welcome mark-seen --yes
  horneroctl welcome mark-seen --revision p1 --yes
'
		}
		'welcome open' {
			return 'Usage: horneroctl welcome open [page] [--dry-run]

Ask a running Hornero Shell to open Welcome (optional page id) via
`qs ipc call welcome open`. Needs no --yes; --dry-run previews.

Examples:
  horneroctl welcome open --dry-run
  horneroctl welcome open navigate
'
		}
		'welcome reset' {
			return 'Usage: horneroctl welcome reset [--dry-run] [--yes]

Restore defaults (show on login). The only path back to auto-show;
content updates never flip the flag.

Examples:
  horneroctl welcome reset --dry-run
  horneroctl welcome reset --yes
'
		}
		else {
			return ''
		}
	}
}

pub fn bash_completion() string {
	return '# horneroctl bash completion
_horneroctl_completions() {
  local cur cmds="version doctor shell appearance scheme config package backup power lock hypr hardware completion wallpaper capture apps help"
  cur="\${COMP_WORDS[COMP_CWORD]}"
  if [ \$COMP_CWORD -eq 1 ]; then
    COMPREPLY=(\$(compgen -W "\$cmds" -- "\$cur"))
  fi
}
complete -F _horneroctl_completions horneroctl
'
}

pub fn zsh_completion() string {
	return '#compdef horneroctl
_horneroctl() {
  local -a cmds
  cmds=(version doctor shell appearance scheme config package backup power lock hypr hardware completion wallpaper capture apps help)
  _describe "command" cmds
}
_horneroctl
'
}

pub fn fish_completion() string {
	return '# horneroctl fish completion
complete -c horneroctl -f -n __fish_use_subcommand -a version -d "Print version"
complete -c horneroctl -f -n __fish_use_subcommand -a doctor -d "Health checks"
complete -c horneroctl -f -n __fish_use_subcommand -a shell -d "Shell integration"
complete -c horneroctl -f -n __fish_use_subcommand -a appearance -d "Appearance backend"
complete -c horneroctl -f -n __fish_use_subcommand -a scheme -d "Color scheme shortcut"
complete -c horneroctl -f -n __fish_use_subcommand -a config -d "Configuration"
complete -c horneroctl -f -n __fish_use_subcommand -a package -d "Package updates"
complete -c horneroctl -f -n __fish_use_subcommand -a backup -d "Backups"
complete -c horneroctl -f -n __fish_use_subcommand -a power -d "Power actions"
complete -c horneroctl -f -n __fish_use_subcommand -a lock -d "Screen lock"
complete -c horneroctl -f -n __fish_use_subcommand -a hypr -d "Hyprland controls"
complete -c horneroctl -f -n __fish_use_subcommand -a hardware -d "Hardware controls"
complete -c horneroctl -f -n __fish_use_subcommand -a completion -d "Completions"
complete -c horneroctl -f -n __fish_use_subcommand -a wallpaper -d "Wallpaper image"
complete -c horneroctl -f -n __fish_use_subcommand -a capture -d "Screenshot, recording, clipboard"
complete -c horneroctl -f -n __fish_use_subcommand -a apps -d "Everyday apps"
'
}
