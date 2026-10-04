module hornero_cli

import hornero_core

pub fn root_help() string {
	ver := hornero_core.cli_version()
	return 'horneroctl — Hornero OS system CLI (${ver})

Usage: horneroctl [--json|--quiet] <command> [options]

Commands:
  version       Print version
  doctor        Read-only environment health checks
  shell         Desktop shell integration (status, ipc, preset, lifecycle, logs)
  appearance    Appearance controls (status, sync, theme, scheme, colors, accent, night-mode, gtk, hyprlock)
  config        Configuration paths, values, validation, snapshots
  package       System packages (check, updates, upgrade, deps)
  backup        Config backups (list, schedule, create, restore)
  power         Session power actions (lock, suspend, reboot, shutdown, logout, status)
  lock          Screen lock (now, status)
  hypr          Hyprland controls (animations, layout, monitors, workspace, plugins)
  hardware      Hardware controls (brightness, battery, mic, keyboard, network)
  welcome       First-login onboarding state (status, set-show-on-login, mark-seen, open, reset)
  wallpaper     Wallpaper image (set, current, reload)
  capture       Screenshot, recording, clipboard (screenshot, record, clipboard)
  apps          Everyday apps (files, terminal-file, git-status, audit, launch, toggle, switcher, performance)
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
and shell configuration presence. Never changes anything.

Exit codes:
  0  all checks passed
  1  one or more checks failed (details in output)

Examples:
  horneroctl doctor
  horneroctl doctor --json
'
		}
		'shell' {
			return 'Usage: horneroctl shell <status|ipc|preset|start|stop|restart|logs> [options]

  status              Summarize shell session reachability
  ipc [--dry-run] -- <qs-args...>
                      Pass arguments through to `qs ipc`
  preset list [--full] List installed shell presets (read-only)
  preset current      Show the active preset (read-only)
  preset apply <name> [--dry-run|--yes]
                      Apply a shell preset (needs --yes)
  start [--dry-run|--yes]
                      Start the quickshell daemon (needs --yes)
  stop [--dry-run|--yes]
                      Stop the quickshell daemon (needs --yes)
  restart [--dry-run|--yes]
                      Restart the quickshell daemon: stop, wait, start
                      (needs --yes)
  logs [--lines N] [--dry-run]
                      Tail the shell log (read-only)

Options:
  --dry-run           Preview without changing anything
  --yes               Confirm a mutating action
  --lines N           Tail line count for logs (default 50)

Lifecycle notes: start refuses when the shell already runs and needs
the quickshell config dir; stop tries `quickshell kill` first, then
SIGKILL. Output goes to the shell log (HORNERO_SHELL_LOG_FILE);
binaries via HORNERO_QUICKSHELL_BIN / HORNERO_QS_BIN.

Preset apply validates the preset, resets owned settings in
shell.json, deep-merges, and updates the active-preset pointer
(atomically); quickshell reloads on shell.json change.

Examples:
  horneroctl shell status
  horneroctl shell ipc -- show
  horneroctl shell ipc --dry-run -- call bar toggleLauncher
  horneroctl shell preset list
  horneroctl shell preset current --json
  horneroctl shell preset apply hornero-left --dry-run
  horneroctl shell preset apply hornero-left --yes
  horneroctl shell start --dry-run
  horneroctl shell start --yes
  horneroctl shell restart --yes
  horneroctl shell logs --lines 100
'
		}
		'shell preset' {
			return 'Usage: horneroctl shell preset <list|current|apply> [options]

  list [--full]       List installed shell presets (read-only);
                      --full prints the full entry array as JSON
                      (name, display, description, icon, iconMaterial,
                      position, style, active) for the layout picker
  current             Show the active preset (read-only)
  apply <name> [--dry-run|--yes]
                      Apply a shell preset: validate, reset owned
                      settings in shell.json, deep-merge, update the
                      active-preset pointer (needs --yes)

Preset sources: HORNERO_PRESETS_DIR, else the XDG data catalogue
(hornero/shell-presets);
the active pointer lives under XDG state. Writes go to the canonical
hornero paths only (XDG_CONFIG_HOME/hornero/shell.json plus the state
pointer). Quickshell reloads on shell.json change, so no IPC is needed.

Examples:
  horneroctl shell preset list
  horneroctl shell preset current
  horneroctl shell preset list --full --json
  horneroctl shell preset apply hornero-left --dry-run
  horneroctl shell preset apply hornero-left --yes
'
		}
		'appearance' {
			return 'Usage: horneroctl appearance <status|sync|doctor|set-*|theme|scheme|colors|accent|night-mode|gtk|hyprlock> [options]

  status              Show current appearance state (read-only)
  sync [--dry-run]    Adopt the live scheme meta into state (needs --yes)
  doctor              Check appearance consistency (read-only)
  set-wallpaper <path> [--dry-run]
                      Rebuild the palette from one wallpaper (needs --yes)
  set-gtk <theme> [--dry-run]
                      Set the GTK theme, keep live policy (needs --yes)
  set-icons <theme> [--dry-run]
                      Set the icon theme (needs --yes)
  set-gtk-color-scheme <policy> [--dry-run]
                      Set the GTK color-scheme policy (needs --yes)
  theme ...           Installed theme packs (list, show, get, apply, set)
  scheme ...          Color scheme state (status, list, current, set-mode,
                      set-variant, regenerate, sync-state)
  colors ...          Smart-color palette (status, generate, m3, concept, export)
  accent ...          Accent override seed (show, set, clear)
  night-mode ...      Display temperature (status, toggle, on, off,
                      status-icon, status-text, backends)
  gtk ...             GTK themes (list, current, apply, set-icons,
                      color-scheme, sync-color-scheme, detect, theme,
                      auto, icons, info)
  hyprlock [--dry-run] Regenerate colors-hyprlock.conf (needs --yes)

Native: every verb runs in V. Only external tools stay backends
(wal, xrdb, gsettings, hyprctl, quickshell IPC, the M3 python
synthesizer, night-mode temperature tools), each with a
HORNERO_*_BIN override.

Options:
  --dry-run           Preview without changing anything
  --yes               Confirm a mutating action

Examples:
  horneroctl appearance status
  horneroctl appearance sync --dry-run
  horneroctl appearance sync --yes
  horneroctl appearance doctor
  horneroctl appearance theme list
  horneroctl appearance scheme status
  horneroctl appearance colors status --dry-run
  horneroctl appearance accent show
  horneroctl appearance night-mode status
  horneroctl appearance gtk list
  horneroctl appearance hyprlock --dry-run
'
		}
		'appearance theme' {
			return 'Usage: horneroctl appearance theme <list|show|get|apply|set> [options]

  list [--full]       List installed theme packs (read-only);
                      --full prints every pack manifest as a JSON
                      array (id, name, wallpapers, gtk, darkMode…)
                      for the launcher
  show <id>           Show one theme pack (read-only)
  get [--dry-run]     Show the active official theme (read-only)
  apply <id> [--wallpaper <path>] [--dry-run]
                      Apply a theme pack (needs --yes)
  set <hornero-dark|hornero-light|pampa> [--dry-run]
                      Switch the official theme atomically (needs --yes)

Pack source: HORNERO_THEMES_DIR, else the XDG data catalogue
(hornero/themes).
Reads parse the installed theme.json manifests; apply runs
the native shell pipeline (wal + M3 + GTK). get matches the live
native state against the official hornero-dark/hornero-light/pampa
trio; set validates, applies natively, then verifies GTK/scheme
agree (best-effort rollback to the previous official theme on
failure).

Examples:
  horneroctl appearance theme list
  horneroctl appearance theme list --full --json
  horneroctl appearance theme show vapor-dreams
  horneroctl appearance theme get
  horneroctl appearance theme apply vapor-dreams --dry-run
  horneroctl appearance theme apply vapor-dreams --yes
  horneroctl appearance theme set hornero-dark --dry-run
  horneroctl appearance theme set hornero-light --yes
'
		}
		'appearance scheme' {
			return 'Usage: horneroctl appearance scheme <status|list|current|set-mode|set-variant|regenerate|sync-state> [options]

  status              Show mode/flavour/variant (read-only)
  list                Show live colours under every flavour (read-only)
  current             Show name/flavour/variant (read-only)
  set-mode <dark|light> [--dry-run]
                      Set the color-scheme mode (needs --yes)
  set-variant <name> [--dry-run]
                      Set the color-scheme variant (needs --yes)
  regenerate [--dry-run]
                      Rewrite scheme.json from the wallpaper (needs --yes)
  sync-state [--theme-id <id>] [--dry-run]
                      Adopt scheme.json meta into state; keep selected theme (needs --yes)

State source: the materialized scheme files under XDG state/cache,
all read and written natively.

Later phases: device brightness and other hardware controls (no
verified IPC path yet).

Examples:
  horneroctl appearance scheme status
  horneroctl appearance scheme list
  horneroctl appearance scheme set-mode dark --dry-run
  horneroctl appearance scheme set-mode dark --yes
  horneroctl appearance scheme set-variant tonalspot --yes
  horneroctl appearance scheme regenerate --dry-run
  horneroctl appearance scheme sync-state --theme-id pampa --yes
'
		}
		'appearance colors' {
			return 'Usage: horneroctl appearance colors <status|generate|m3|concept|export> [options]

  status [--dry-run]  Preview the generated palette (read-only)
  generate [--m3] [--dry-run]
                      Rewrite the smart-color files (needs --yes;
                      --m3 also refreshes scheme.json)
  m3 [--dry-run] -- <backend-args...>
                      Pass arguments to the M3 synthesizer (needs --yes)
  concept <name>      Resolve one semantic color (read-only)
  export              Print shell variables for every color (read-only)

Native: the palette engine (luminance, semantic table, contrast,
harmonization) runs in V from xrdb input (HORNERO_XRDB_BIN). Only
the M3 synthesis stays a backend (python + generate-m3-colors.py
via HORNERO_M3_PYTHON_BIN / HORNERO_M3_SCRIPT).

Examples:
  horneroctl appearance colors status
  horneroctl appearance colors status --dry-run
  horneroctl appearance colors generate --dry-run
  horneroctl appearance colors generate --m3 --yes
  horneroctl appearance colors m3 --dry-run -- --help
  horneroctl appearance colors concept error
  horneroctl appearance colors export
'
		}
		'appearance accent' {
			return 'Usage: horneroctl appearance accent <show|set|clear> [options]

  show [--dry-run]    Print the accent override seed (read-only)
  set <hex> [--dry-run]
                      Set the accent seed (needs --yes)
  clear [--dry-run]   Clear the override, regenerate from wallpaper (needs --yes)

Native: the seed file plus the scheme regenerate run in V.
Set/clear trigger a scheme regenerate downstream.

Examples:
  horneroctl appearance accent show
  horneroctl appearance accent set "#8839ef" --dry-run
  horneroctl appearance accent set "#8839ef" --yes
  horneroctl appearance accent clear --dry-run
'
		}
		'appearance night-mode' {
			return 'Usage: horneroctl appearance night-mode <status|toggle|on|off|status-icon|status-text|backends> [options]

  status [--dry-run]  Show whether the temperature backend is active (read-only)
  toggle [--dry-run]  Toggle night mode (needs --yes)
  on [--dry-run]      Force enable night mode (needs --yes)
  off [--dry-run]     Force disable night mode (needs --yes)
  status-icon         Bar icon for the current state (read-only)
  status-text         Bar tooltip for the current state (read-only)
  backends            List available backends (read-only)

Native: process-table detection plus the redshift/gammastep/
wlsunset/xrandr backends (HORNERO_REDSHIFT_BIN and friends).

Examples:
  horneroctl appearance night-mode status
  horneroctl appearance night-mode status --dry-run
  horneroctl appearance night-mode toggle --dry-run
  horneroctl appearance night-mode backends
'
		}
		'appearance gtk' {
			return 'Usage: horneroctl appearance gtk <verb> [options]

  list                List installed GTK themes (read-only)
  current             Show the current GTK theme (read-only)
  current-icon        Show the current icon theme (read-only)
  current-color-scheme
                      Show the persisted color-scheme policy (read-only)
  apply <theme> [icon] [policy] [--dry-run]
                      Apply GTK + icon theme (needs --yes)
  set-icons <icon> [--dry-run]
                      Update the icon theme in place (needs --yes)
  color-scheme <policy> [--dry-run]
                      Set the GTK color-scheme policy (needs --yes)
  sync-color-scheme [--dry-run]
                      Re-apply the persisted policy (needs --yes)
  detect [wallpaper]  Suggest the optimal theme (read-only)
  theme [id]          Apply GTK settings from a theme pack (needs --yes)
  auto [--dry-run]    Auto-detect and apply (needs --yes)
  icons               List installed icon themes (read-only)
  info <theme>        Show theme components and metadata (read-only)
  select [--dry-run]  Numbered menu to pick and apply a theme
                      (needs --yes; pipe the choice on stdin)

Native: INI edits and policy decisions run in V; gsettings stays
a backend (HORNERO_GSETTINGS_BIN).

Examples:
  horneroctl appearance gtk list
  horneroctl appearance gtk current
  horneroctl appearance gtk apply Orchis-Dark --dry-run
  horneroctl appearance gtk color-scheme prefer-light --dry-run
  horneroctl appearance gtk sync-color-scheme --dry-run
'
		}
		'appearance hyprlock' {
			return 'Usage: horneroctl appearance hyprlock [--wallpaper <path>] [options]

  Regenerate colors-hyprlock.conf from the live scheme.json
  colours (needs --yes); --dry-run only previews.

Examples:
  horneroctl appearance hyprlock --dry-run
  horneroctl appearance hyprlock --yes
'
		}
		'config' {
			return 'Usage: horneroctl config <paths|validate|show|snapshot|default-apps|materialize|gui> [key]

  paths               Print the resolved XDG path contract
  validate            Check materialized config (read-only)
  show [key]          Show materialized shell.json values (read-only);
                      with a dot-notation key (bar.position) show one value
  snapshot ...        Configuration snapshots (create, list, restore)
  default-apps ...    Default applications (list, set)
  materialize ...     Install curated defaults into --dest (needs --yes)
  gui [--pane <name>] Open the settings hub

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
'
		}
		'config default-apps' {
			return 'Usage: horneroctl config default-apps <list|set> [options]

  list [--dry-run]  List current default applications (read-only)
  set <mime> <app> [--dry-run|--yes]
                    Set the default .desktop app for a MIME type
                    via xdg-mime (needs --yes)

List source: handlr MIME associations and installed desktop names;
TerminalEmulator comes from the Xfce helper configuration. Set backend:
xdg-mime (HORNERO_XDG_MIME_BIN). The terminal emulator stays out:
it lives in the exo helper configuration, not in MIME.

Examples:
  horneroctl config default-apps list
  horneroctl config default-apps list --dry-run
  horneroctl config default-apps list --json
  horneroctl config default-apps set text/plain nvim.desktop --dry-run
  horneroctl config default-apps set text/plain nvim.desktop --yes
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

  Open Hornero Settings through the running shell.
  `--pane` is validated by the Hornero Shell pane registry. With no shell,
  the command reports that the desktop session is unavailable.

Examples:
  horneroctl config gui --dry-run
  horneroctl config gui --pane appearance
  horneroctl config gui --pane launcher --json
'
		}
		'config snapshot' {
			return 'Usage: horneroctl config snapshot <create|list|restore> [options]

  create [--dry-run]  Create a configuration snapshot (needs --yes)
  list                List materialized snapshots (read-only)
  restore <id> [--dry-run]
                      Restore one snapshot (needs --yes)

Snapshots live under HORNERO_SNAPSHOTS_DIR or the XDG data catalogue
(hornero/snapshots). They archive only Hornero configuration and record
package inventory and host metadata; restore creates a safety snapshot first.

Examples:
  horneroctl config snapshot list
  horneroctl config snapshot create --dry-run
  horneroctl config snapshot create --yes
  horneroctl config snapshot restore config_20260101_020000 --dry-run
  horneroctl config snapshot list --json
'
		}
		'package' {
			return 'Usage: horneroctl package <check|updates|upgrade|deps> [options]

  check [--dry-run]   List pending system updates (read-only)
  updates [--dry-run] Pending-update count readout (read-only)
  upgrade [--dry-run|--yes]
                      Full system upgrade via polkit (needs --yes)
  deps [--optional]   Check pinned dependencies (read-only)
  deps --install [--optional] [--dry-run|--yes]
                      Install missing dependencies (needs --yes)

Update source: checkupdates or checkupdates on PATH
(HORNERO_CHECKUPDATES_BIN override). Upgrade runs
`pkexec pacman -Syu` (HORNERO_PKEXEC_BIN/HORNERO_PACMAN_BIN);
without pkexec it fails with guidance: installs need polkit.
Deps checks the core + Wayland table (git, curl, wget, chezmoi,
zsh, hyprland, quickshell, hyprlock, hypridle, cliphist; dev,
media, and AI groups with --optional) and installs repo
packages via pacman plus AUR-only ones via paru.

Examples:
  horneroctl package check
  horneroctl package check --dry-run
  horneroctl package updates
  horneroctl package updates --json
  horneroctl package upgrade --dry-run
  horneroctl package upgrade --yes
  horneroctl package deps
  horneroctl package deps --optional
  horneroctl package deps --install --dry-run
  horneroctl package deps --install --yes
'
		}
		'backup' {
			return 'Usage: horneroctl backup <list|schedule|create|restore> [options]

  list                List materialized backups (read-only)
  schedule            Print the cron/systemd recipe (documented, not installed)
  create [--name <name>] [--dry-run|--yes]
                      Archive Hornero configuration into a timestamped
                      tarball (needs --yes)
  restore <id> [--dry-run|--yes]
                      Restore one archive into the Hornero configuration directory
                      (needs --yes)

Archives live under HORNERO_BACKUP_DIR or XDG state
(hornero/backups). The source defaults to XDG config/hornero; set
HORNERO_BACKUP_SOURCE to choose another directory explicitly. Only .tar.gz
Hornero archives are listed.
Scheduling is never installed by horneroctl: copy-paste the
printed recipe instead.

Examples:
  horneroctl backup list
  horneroctl backup list --json
  horneroctl backup schedule
  horneroctl backup create --dry-run
  horneroctl backup create --yes
  horneroctl backup create --name pre_upgrade --yes
  horneroctl backup restore pre_upgrade --dry-run
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
prefers horneroctl lock --lock (HORNERO_LOCKSCREEN_BIN), then bare
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
  plugins           Hyprland plugins (list, status, install)

Reads (list/current/status) never touch the compositor state;
mutations need --yes and --dry-run only previews. Plugin install
runs the idempotent hyprpm bootstrap (update, add, enable, reload)
for ScrollOverview; AUR-helper flows stay manual.

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
(hornero/hypr/animations/current).

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
\$XDG_STATE_HOME (hornero/hypr/layout/current).

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
			return 'Usage: horneroctl hypr plugins <list|status|install> [options]

  list                Print the hyprpm plugin list (read-only)
  status              hyprpm presence plus ScrollOverview installed/enabled
                      (read-only, never fails)
  install [--force|--no-update] [--dry-run|--yes]
                      Idempotent ScrollOverview bootstrap via hyprpm
                      (update, add, enable, reload; needs --yes)

Backend: hyprpm (HORNERO_HYPRPM_BIN). --force rebuilds the hyprpm
headers; --no-update skips the header update for the fast
autostart path (reload still runs).

Examples:
  horneroctl hypr plugins status
  horneroctl hypr plugins list
  horneroctl hypr plugins status --json
  horneroctl hypr plugins install --dry-run
  horneroctl hypr plugins install --yes
  horneroctl hypr plugins install --yes --no-update
'
		}
		'lock' {
			return 'Usage: horneroctl lock <now|status|update> [--dry-run|--yes]

  now [--effect NAME] [--dry-run]
                      Lock the screen now (needs --yes)
  status              Show lock backend state (read-only)
  update [path] [--dim N] [--blur N] [--pixel N] [--dry-run]
                      Rebuild cached effect images (needs --yes)

Effects: dim, blur, dimblur, pixel (default blur). With no lockscreen
backend configured, `now` uses the native effect flow when an effect
is requested or cached images exist, else bare hyprlock
(HORNERO_HYPRLOCK_BIN), else loginctl lock-session
(HORNERO_LOGINCTL_BIN). Images live in \$XDG_CACHE_HOME/hornero/lockscreen.

Examples:
  horneroctl lock status
  horneroctl lock now --dry-run
  horneroctl lock now --effect pixel --dry-run
  horneroctl lock update --dry-run
  horneroctl lock update ~/wall.jpg --yes
'
		}
		'wallpaper' {
			return 'Usage: horneroctl wallpaper <set|current|reload> [options]

  set <path> [--dry-run]    Apply a wallpaper image (needs --yes)
  current [path]            Print the current wallpaper path (read-only)
  reload [--dry-run]        Re-apply the color pipeline (needs --yes)

Reads use the Hornero wallpaper pointer, then the pywal link. `set` applies through shell IPC or the native wal+M3 pipeline; `reload`
uses the configured Hornero reload backend (HORNERO_WAL_RELOAD_BIN) or the
native pipeline.

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
with --dry-run. Backends use brightnessctl / xrandr, acpi / upower, wpctl, hyprctl / setxkbmap, and ping, each with a
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
			return 'Usage: horneroctl hardware brightness <status|set|up|down> [--display NAME] [--temp] [--dry-run|--yes]

  status [--display NAME]
                Show current brightness (read-only); without --display,
                xrandr lists every connected display
  set <0.0-1.0> [--display NAME] [--temp]
                Set brightness fraction, clamped into range (needs --yes);
                with --temp, set color temperature instead (0.0 = 3000K,
                0.6 = 6500K neutral, 1.0 = 10000K)
  up [--step 0.1] [--display NAME] [--temp]
                Raise brightness by step (needs --yes); with --temp,
                shift color temperature up the ramp by step
  down [--step 0.1] [--display NAME] [--temp]
                Lower brightness by step (needs --yes); with --temp,
                shift color temperature down the ramp by step

Backend precedence (horneroctl hardware brightness): brightnessctl, blight,
xbacklight, xrandr (HORNERO_BRIGHTNESSCTL_BIN and siblings override).
xbacklight/xrandr need a display: --display, else the first connected
output. --temp always drives xrandr --gamma on one display
(HORNERO_XRANDR_BIN override), mirroring the horneroctl hardware brightness gamma
ramps cribbed from redshift.

Examples:
  horneroctl hardware brightness status
  horneroctl hardware brightness status --display eDP-1
  horneroctl hardware brightness set 0.8 --dry-run
  horneroctl hardware brightness set 0.8 --yes
  horneroctl hardware brightness up --step 0.05 --dry-run
  horneroctl hardware brightness down --display eDP-1 --yes
  horneroctl hardware brightness set 0.6 --temp --display eDP-1 --dry-run
  horneroctl hardware brightness up --temp --display eDP-1 --yes
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
loop stays in horneroctl hardware microphone.

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
lxqt-config-input detached (HORNERO_KEYBOARD_SETTINGS_BIN pin).
keys parses the
Hyprland keybindings file (HORNERO_KEYBINDINGS_FILE override),
rewriting \$mainMod to SUPER; with Hornero Shell running it opens
System Settings. HORNERO_BYPASS_QUICKSHELL=1 forces parsing; the old
HORNERO_BYPASS_QUICKSHELL name remains a compatibility alias.

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

Target: 1.1.1.1; --timeout is the ping deadline
in seconds. The polling loop stays in horneroctl hardware network check.

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
none running. Clipboard resolves like horneroctl capture clipboard (Wayland:
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
			return 'Usage: horneroctl apps <files|terminal-file|git-status|audit|launch|toggle|switcher|performance> ... [--dry-run|--yes]

  files [--path PATH] [--info]
                      Open the default file manager (view-open, no --yes)
                      or show it with --info (read-only)
  terminal-file [--path PATH] [--select FILE] [--last-dir]
                      Open yazi, show the cheatsheet, or diagnose previews
                      (view-open and reads, no --yes)
  git-status [watch|jobs|stop] [--branch B] [--repository R]
                      Watch a repo with desktop notifications (needs --yes),
                      list watchers (jobs, read-only), or stop them (needs --yes)
  audit [--permissions|--secrets|--system] [--fix|--report|--json] [--yes]
                      Security checks, fixes, markdown report, JSON summary
  launch [--backend NAME] [--list]
                      Open the app launcher or list backends (no --yes)
  toggle <component>  Toggle a shell component or daemon (needs --yes)
  switcher <leaf>     Drive the window switcher; status is read-only,
                      control leaves need --yes
  performance <leaf>  Shell/memory/benchmark/report reads plus the
                      power-profile mode (set needs --yes)

Reads and view-opens need no --yes; mutations need --yes and preview
with --dry-run. External tools can be selected with HORNERO_*_BIN overrides.

Examples:
  horneroctl apps files --dry-run
  horneroctl apps files --info
  horneroctl apps terminal-file --cheatsheet
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

Backend chain: exo-open --launch FileManager, handlr open, xdg-open
(HORNERO_EXO_OPEN_BIN / HORNERO_HANDLR_BIN / HORNERO_XDG_OPEN_BIN);
--info reads natively via handlr (else xdg-mime).

Examples:
  horneroctl apps files --dry-run
  horneroctl apps files --path ~/Documents --dry-run
  horneroctl apps files --info
  horneroctl apps files --info --json
'
		}
		'apps terminal-file' {
			return 'Usage: horneroctl apps terminal-file [--path PATH] [--select FILE] [--last-dir] [--cheatsheet] [--fix-previews] [--dry-run]

  open (default)      Open yazi via hornero-yazi (view-open, no --yes)
  --cheatsheet        Print the keybinding reference (read-only)
  --fix-previews      Diagnose preview dependencies (read-only)

Launch wraps hornero-yazi (HORNERO_YAZI_HELPER_BIN), falling back to bare
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

Backend: horneroctl apps git-status (HORNERO_GIT_NOTIFY_BIN); watch runs inside
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
			return 'Usage: horneroctl apps audit [--permissions|--secrets|--system] [--fix|--report|--json] [--yes] [--dry-run]

  audit (default)     Full read-only security audit
  --permissions       File permission checks only (read-only)
  --secrets           Exposed-secret scan only (read-only)
  --system            Firewall, updates, SSH, MAC checks only (read-only)
  --fix               Apply permission fixes, scrub shell history (needs --yes)
  --report            Write a markdown report under $XDG_CACHE_HOME/hornero/security
  --json              Machine-readable summary (exit non-zero on findings)

At most one check and one mode per invocation. Backend: native
(stat/find HOME scan, system leaf checks, os.chmod fixes).

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

Backends: quickshell, minimal (else auto). Backend: native
(quickshell ipc, else a minimal stdin prompt).

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
  redshift caffeine   Toggle the daemon once (needs --yes); the monitor
                      loops stay in horneroctl apps toggle

Backend: native (quickshell ipc; pidof + pkill/killall for daemons).

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

Default leaf is toggle. Backend: native snappy-switcher control
(HORNERO_SNAPPY_SWITCHER_BIN); apply-theme* still delegate to
hornero-snappy-switcher (HORNERO_SNAPPY_BIN).

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

Reads run natively (ps/zsh/free seams); mode
uses powerprofilesctl get/list/set
(HORNERO_POWERPROFILESCTL_BIN). The interactive menu, quickshell
pane, and auto-cpufreq GUI stay in horneroctl apps performance mode.

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
complete -c horneroctl -f -n __fish_use_subcommand -a appearance -d "Appearance controls"
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
