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
		'completion' {
			return 'Usage: horneroctl completion <bash|zsh|fish>

Print a shell completion script to stdout.

Examples:
  horneroctl completion bash > /etc/bash_completion.d/horneroctl
  horneroctl completion zsh > ~/.zsh/completions/_horneroctl
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
  local cur cmds="version doctor shell appearance scheme config package backup completion help"
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
  cmds=(version doctor shell appearance scheme config package backup completion help)
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
complete -c horneroctl -f -n __fish_use_subcommand -a completion -d "Completions"
'
}
