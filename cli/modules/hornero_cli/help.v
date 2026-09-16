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
  welcome       First-login onboarding state (status, set-show-on-login, mark-seen, open, reset)
  wallpaper     Wallpaper image (set, current, reload)
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
			return 'Usage: horneroctl appearance <status|sync|call|theme|scheme> [options]

  status              Show current appearance state (read-only)
  sync [--dry-run]    Apply the pending color scheme (needs --yes)
  call [--dry-run] -- <backend-args...>
                      Pass arguments to the appearance backend directly
  theme ...           Installed theme packs (list, show, get, apply, set)
  scheme ...          Color scheme state and setters (status, set-mode, set-variant)

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
  local cur cmds="version doctor shell appearance scheme config package backup power lock completion wallpaper help"
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
  cmds=(version doctor shell appearance scheme config package backup power lock completion wallpaper help)
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
complete -c horneroctl -f -n __fish_use_subcommand -a completion -d "Completions"
complete -c horneroctl -f -n __fish_use_subcommand -a wallpaper -d "Wallpaper image"
'
}
