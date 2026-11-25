module hornero_cli

import hornero_core

// Github option parsers: `github <status|stats|inbox|refresh|export>
// ...`. All leaves are read-only against GitHub; refresh/export only
// write Hornero's own XDG cache or an explicit local --output file.
// Error strings always carry a correct Example (exit-2 contract).

pub const github_verbs = ['status', 'stats', 'inbox', 'refresh', 'export']

pub struct GithubCmdOptions {
pub:
	verb    string
	options hornero_core.GithubOptions
	format  string = 'markdown'
	output  string
	public  bool
	clear   bool
}

fn github_validate_name(value string, what string) ! {
	if value.starts_with('-') {
		return error('${what} must not start with -\nExample: horneroctl github stats --repo owner/name --json')
	}
	for c in value {
		if !(c.is_alnum() || c in [`-`, `_`, `.`, `/`]) {
			return error('invalid ${what}: ${value}\nExample: horneroctl github stats --repo owner/name --json')
		}
	}
}

// parse_github_cmd parses `github <verb> [flags]` with Example-carrying errors.
pub fn parse_github_cmd(args []string) !GithubCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl github status --json')
	}
	verb := args[0]
	if verb !in github_verbs {
		return error('unknown github subcommand: ${verb}.\nRun: horneroctl github --help')
	}
	mut days := 90
	mut org := ''
	mut repo := ''
	mut visibility := 'all'
	mut force := false
	mut dry_run := false
	mut format := 'markdown'
	mut output := ''
	mut public_only := false
	mut clear := false
	mut i := 1
	for i < args.len {
		a := args[i]
		match a {
			'--force-refresh', '--force' {
				force = true
			}
			'--dry-run' {
				dry_run = true
			}
			'--clear-cache' {
				clear = true
			}
			'--public-only' {
				public_only = true
			}
			'--days' {
				i++
				if i >= args.len {
					return error('--days needs a value.\nExample: horneroctl github stats --days 30 --json')
				}
				days = args[i].int()
				if days < 1 || days > 3650 {
					return error('--days must be 1..3650.\nExample: horneroctl github stats --days 30 --json')
				}
			}
			'--org' {
				i++
				if i >= args.len {
					return error('--org needs a value.\nExample: horneroctl github stats --org HorneroOS --json')
				}
				github_validate_name(args[i], 'org')!
				org = args[i]
			}
			'--repo' {
				i++
				if i >= args.len {
					return error('--repo needs owner/name.\nExample: horneroctl github stats --repo owner/name --json')
				}
				// An empty value means "no filter" (the shell's
				// literal-argv processes always pass the flag).
				if args[i].len > 0 {
					if !args[i].contains('/') {
						return error('--repo needs owner/name.\nExample: horneroctl github stats --repo owner/name --json')
					}
					github_validate_name(args[i], 'repo')!
					repo = args[i]
				}
			}
			'--visibility' {
				i++
				if i >= args.len || args[i] !in ['all', 'public', 'private'] {
					return error('--visibility must be all|public|private.\nExample: horneroctl github stats --visibility public --json')
				}
				visibility = args[i]
			}
			'--format' {
				i++
				if i >= args.len || args[i] !in ['json', 'csv', 'markdown'] {
					return error('--format must be json|csv|markdown.\nExample: horneroctl github export --format markdown')
				}
				format = args[i]
			}
			'--output' {
				i++
				if i >= args.len {
					return error('--output needs a path.\nExample: horneroctl github export --output report.md')
				}
				output = args[i]
			}
			else {
				return error('unknown flag for github ${verb}: ${a}.\nExample: horneroctl github ${verb} --json')
			}
		}
		i++
	}
	return GithubCmdOptions{
		verb:    verb
		format:  format
		output:  output
		public:  public_only
		clear:   clear
		options: hornero_core.GithubOptions{
			days:       days
			org:        org
			repo:       repo
			visibility: visibility
			force:      force
			dry_run:    dry_run
		}
	}
}
