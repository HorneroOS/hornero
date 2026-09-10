module hornero_cli

import hornero_core

pub fn root_help() string {
	ver := hornero_core.cli_version()
	return 'horneroctl — Hornero OS system CLI (${ver})

Usage: horneroctl [--json|--quiet] <command> [options]

Commands:
  version       Print version
  doctor        Read-only environment health checks
  shell         Desktop shell integration (status, ipc)
  appearance    Appearance backend (status, sync, call)
  config        Configuration paths and validation
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
			return 'Usage: horneroctl shell <status|ipc> [options]

  status              Summarize shell session reachability
  ipc [--dry-run] -- <qs-args...>
                      Pass arguments through to `qs ipc`

Options:
  --dry-run           Preview the qs invocation without running it

Examples:
  horneroctl shell status
  horneroctl shell ipc -- show
  horneroctl shell ipc --dry-run -- call bar toggleLauncher
'
		}
		'appearance' {
			return 'Usage: horneroctl appearance <status|sync|call> [options]

  status              Show current appearance state (read-only)
  sync [--dry-run]    Apply the pending color scheme (needs --yes)
  call [--dry-run] -- <backend-args...>
                      Pass arguments to the appearance backend directly

Options:
  --dry-run           Preview without changing anything
  --yes               Confirm a mutating action

Examples:
  horneroctl appearance status
  horneroctl appearance sync --dry-run
  horneroctl appearance sync --yes
  horneroctl appearance call -- theme list
'
		}
		'config' {
			return 'Usage: horneroctl config <paths|validate|show>

  paths               Print the resolved XDG path contract
  validate            Check materialized config (read-only)
  show                Alias for paths (reserved for future values)

Examples:
  horneroctl config paths
  horneroctl config validate --json
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
  local cur cmds="version doctor shell appearance config completion help"
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
  cmds=(version doctor shell appearance config completion help)
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
complete -c horneroctl -f -n __fish_use_subcommand -a config -d "Configuration"
complete -c horneroctl -f -n __fish_use_subcommand -a completion -d "Completions"
'
}
