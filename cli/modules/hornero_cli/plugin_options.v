module hornero_cli

pub struct PluginCmdOptions {
pub:
	leaf              string
	value             string
	dry_run           bool
	yes               bool
	name              string
	author            string
	desc              string
	license           string
	dir               string
	expected_revision string
}

pub fn parse_plugin(args []string) !PluginCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl plugin list')
	}
	leaf := args[0]
	if leaf !in ['install', 'remove', 'list', 'validate', 'new', 'enable', 'disable', 'trust',
		'catalog'] {
		return error('unknown plugin subcommand: ${leaf}.\nRun: horneroctl plugin --help')
	}
	mut value := ''
	mut name := ''
	mut author := ''
	mut desc := ''
	mut license := ''
	mut dir := ''
	mut expected_revision := ''
	mut dry_run := false
	mut yes := false
	mut i := 1
	for i < args.len {
		arg := args[i]
		if arg == '--dry-run' {
			dry_run = true
			i++
			continue
		}
		if arg == '--yes' {
			yes = true
			i++
			continue
		}
		if arg == '--revision' {
			if i + 1 >= args.len || args[i + 1].starts_with('--') {
				return error('missing value for --revision.\nExample: horneroctl plugin catalog install hornero-pomodoro --revision <catalogue-commit> --yes')
			}
			expected_revision = args[i + 1]
			i += 2
			continue
		}
		if arg in ['--name', '--author', '--description', '--license', '--dir'] {
			if i + 1 >= args.len || args[i + 1].starts_with('--') {
				return error('missing value for ${arg}.\nExample: horneroctl plugin new example-clock --name "Example Clock" --author "Your Name" --description "A clock widget" --license MIT --dir ./example-clock --dry-run')
			}
			option_value := args[i + 1]
			match arg {
				'--name' { name = option_value }
				'--author' { author = option_value }
				'--description' { desc = option_value }
				'--license' { license = option_value }
				'--dir' { dir = option_value }
				else {}
			}
			i += 2
			continue
		}
		if arg.starts_with('-') {
			return error('unknown flag: ${arg}.\nExample: horneroctl plugin install https://github.com/example/plugin.git --dry-run')
		}
		if value.len > 0 {
			if leaf == 'catalog' && name.len == 0 {
				// plugin catalog install <id>: second positional is the id.
				name = arg
				i++
				continue
			}
			return error('unexpected argument: ${arg}.\nRun: horneroctl plugin --help')
		}
		value = arg
		i++
	}
	if leaf == 'new' {
		if value.len == 0 {
			return error('missing plugin id.\nExample: horneroctl plugin new example-clock --name "Example Clock" --author "Your Name" --description "A clock widget" --license MIT --dir ./example-clock --dry-run')
		}
		if name.trim_space().len == 0 || author.trim_space().len == 0 || desc.trim_space().len == 0 || license.len == 0 || dir.len == 0 {
			return error('plugin new requires --name, --author, --description, --license, and --dir.\nExample: horneroctl plugin new example-clock --name "Example Clock" --author "Your Name" --description "A clock widget" --license MIT --dir ./example-clock --dry-run')
		}
		if license != 'MIT' {
			return error('plugin new currently generates the MIT license text only; create other license files manually and validate the package.')
		}
		if dry_run == yes {
			return error('plugin new requires exactly one of --dry-run or --yes.')
		}
	} else if leaf != 'catalog' && (name.len > 0 || author.len > 0 || desc.len > 0 || license.len > 0 || dir.len > 0) {
		return error('plugin metadata flags are only valid with plugin new.\nRun: horneroctl plugin new --help')
	}
	if leaf == 'list' && (value.len > 0 || dry_run || yes) {
		return error('plugin list takes no arguments.\nExample: horneroctl plugin list --json')
	}
	if expected_revision.len > 0 && (leaf != 'catalog' || value !in ['install', 'update']) {
		return error('--revision is only valid with plugin catalog install/update')
	}
	if leaf in ['install', 'remove', 'validate'] && value.len == 0 {
		return error('missing value.\nExample: horneroctl plugin ${leaf} <source-or-id>')
	}
	if leaf in ['validate', 'list'] && (dry_run || yes) {
		return error('plugin ${leaf} is read-only and takes no mutation flags.\nExample: horneroctl plugin ${leaf}')
	}
	return PluginCmdOptions{
		leaf:              leaf
		value:             value
		dry_run:           dry_run
		yes:               yes
		name:              name
		author:            author
		desc:              desc
		license:           license
		dir:               dir
		expected_revision: expected_revision
	}
}
