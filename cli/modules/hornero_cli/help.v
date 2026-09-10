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
  config        Configuration paths, values, and validation
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
'
}

pub fn command_help(name string) string {
	match name {
		'version' {
			return 'Usage: horneroctl version [--json]

Print the horneroctl version and build commit.

Examples:
  horneroctl version
  horneroctl version --json
'
		}
		'doctor' {
			return 'Usage: horneroctl doctor [--json]

Read-only health checks: Wayland/Hyprland session, required binaries,
shell configuration presence. Never changes anything.

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
(dots/shell-presets); the active pointer lives under XDG state.

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
  theme ...           Installed theme packs (list, show, apply)
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
			return 'Usage: horneroctl appearance theme <list|show|apply> [options]

  list                List installed theme packs (read-only)
  show <id>           Show one theme pack (read-only)
  apply <id> [--wallpaper <path>] [--dry-run]
                      Apply a theme pack (needs --yes)

Pack source: HORNERO_THEMES_DIR, else the XDG data catalogue
(dots/themes). Reads parse the installed theme.json manifests;
apply delegates to dots-appearance (HORNERO_DOTS_APPEARANCE_BIN).

Examples:
  horneroctl appearance theme list
  horneroctl appearance theme show vapor-dreams
  horneroctl appearance theme apply vapor-dreams --dry-run
  horneroctl appearance theme apply vapor-dreams --yes
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
			return 'Usage: horneroctl config <paths|validate|show> [key]

  paths               Print the resolved XDG path contract
  validate            Check materialized config (read-only)
  show [key]          Show materialized shell.json values (read-only);
                      with a dot-notation key (bar.position) show one value

Examples:
  horneroctl config paths
  horneroctl config validate --json
  horneroctl config show
  horneroctl config show bar.position
  horneroctl config show --json
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
  local cur cmds="version doctor shell appearance scheme config completion help"
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
  cmds=(version doctor shell appearance scheme config completion help)
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
complete -c horneroctl -f -n __fish_use_subcommand -a completion -d "Completions"
'
}
