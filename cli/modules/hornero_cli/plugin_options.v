module hornero_cli

pub struct PluginCmdOptions {
pub:
	leaf    string
	value   string
	dry_run bool
	yes     bool
}

pub fn parse_plugin(args []string) !PluginCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl plugin list')
	}
	leaf := args[0]
	if leaf !in ['install', 'remove', 'list', 'validate'] {
		return error('unknown plugin subcommand: ${leaf}.\nRun: horneroctl plugin --help')
	}
	mut value := ''
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
			return error('unknown flag: ${arg}.\nExample: horneroctl plugin install https://github.com/example/plugin.git --dry-run')
		}
		if value.len > 0 {
			return error('unexpected argument: ${arg}.\nRun: horneroctl plugin --help')
		}
		value = arg
	}
	if leaf == 'list' && (value.len > 0 || dry_run || yes) {
		return error('plugin list takes no arguments.\nExample: horneroctl plugin list --json')
	}
	if leaf in ['install', 'remove', 'validate'] && value.len == 0 {
		return error('missing value.\nExample: horneroctl plugin ${leaf} <source-or-id>')
	}
	if leaf in ['validate', 'list'] && (dry_run || yes) {
		return error('plugin ${leaf} is read-only and takes no mutation flags.\nExample: horneroctl plugin ${leaf}')
	}
	return PluginCmdOptions{
		leaf:    leaf
		value:   value
		dry_run: dry_run
		yes:     yes
	}
}
