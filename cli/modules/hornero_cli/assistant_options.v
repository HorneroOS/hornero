module hornero_cli

pub struct AssistantCmdOptions {
pub:
	leaf    string
	value   string
	dry_run bool
	yes     bool
}

pub fn parse_assistant(args []string) !AssistantCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl assistant status')
	}
	leaf := args[0]
	if leaf !in ['status', 'enable', 'disable', 'tools', 'ask', 'stop'] {
		return error('unknown assistant subcommand: ${leaf}.\nRun: horneroctl assistant --help')
	}
	mut parts := []string{}
	mut dry_run := false
	mut yes := false
	for arg in args[1..] {
		if arg == '--dry-run' {
			dry_run = true
			continue
		}
		if arg == '--yes' {
			yes = true
			continue
		}
		if arg.starts_with('-') {
			return error('unknown flag: ${arg}.\nExample: horneroctl assistant enable --dry-run')
		}
		parts << arg
	}
	value := parts.join(' ')
	if leaf == 'ask' && value.len == 0 {
		return error('missing prompt.\nExample: horneroctl assistant ask "what updates are available?"')
	}
	if leaf == 'stop' && value.len == 0 {
		return error('missing run id.\nExample: horneroctl assistant stop run_abc123')
	}
	if leaf in ['status', 'tools'] && value.len > 0 {
		return error('unexpected argument: ${value}.\nExample: horneroctl assistant ${leaf}')
	}
	if dry_run && yes {
		return error('--dry-run and --yes are mutually exclusive.\nExample: horneroctl assistant enable --dry-run')
	}
	return AssistantCmdOptions{
		leaf:    leaf
		value:   value
		dry_run: dry_run
		yes:     yes
	}
}
