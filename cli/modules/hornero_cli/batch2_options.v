module hornero_cli

// Batch-2 option parsers: `config default-apps`, `config materialize`,
// `config gui`. Error strings always carry a correct Example (exit-2
// contract); `default-apps set` stays a deferral: the upstream
// `dots-default-apps --set` verb never binds its arguments, and handlr
// stays internal per docs/cli-architecture.md section 5.

// DefaultAppsCmdOptions covers `config default-apps <list|set>`.
// `list` delegates to dots-default-apps; `set <mime> <app>` writes via
// xdg-mime (mutating: needs --yes).
pub struct DefaultAppsCmdOptions {
pub:
	leaf    string // list | set
	mime    string // set target
	app     string // set value
	dry_run bool
	yes     bool
}

pub fn parse_default_apps_cmd(args []string) !DefaultAppsCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl config default-apps list')
	}
	leaf := args[0]
	if leaf !in ['list', 'set'] {
		return error('unknown default-apps subcommand: ${leaf}.\nRun: horneroctl config default-apps --help')
	}
	mut mime := ''
	mut app := ''
	mut dry_run := false
	mut yes := false
	for i := 1; i < args.len; i++ {
		a := args[i]
		if a == '--dry-run' {
			dry_run = true
			continue
		}
		if a == '--yes' {
			yes = true
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl config default-apps ${leaf} --dry-run')
		}
		if leaf == 'list' {
			return error('unexpected argument: ${a}.\nRun: horneroctl config default-apps --help')
		}
		if mime.len == 0 {
			mime = a
			continue
		}
		if app.len == 0 {
			app = a
			continue
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl config default-apps --help')
	}
	if leaf == 'list' && yes {
		return error('default-apps list takes no --yes.\nExample: horneroctl config default-apps list --dry-run')
	}
	if leaf == 'set' && (mime.len == 0 || app.len == 0) {
		return error('missing MIME type or application.\nExample: horneroctl config default-apps set text/plain nvim.desktop --dry-run')
	}
	return DefaultAppsCmdOptions{
		leaf:    leaf
		mime:    mime
		app:     app
		dry_run: dry_run
		yes:     yes
	}
}

// MaterializeCmdOptions covers `config materialize --dest <dir>`
// (mutating: the destination is required up front).
pub struct MaterializeCmdOptions {
pub:
	dest    string
	dry_run bool
	yes     bool
}

pub fn parse_materialize_cmd(args []string) !MaterializeCmdOptions {
	mut dest := ''
	mut dry_run := false
	mut yes := false
	mut i := 0
	for i < args.len {
		a := args[i]
		if a == '--dry-run' {
			dry_run = true
			i++
			continue
		}
		if a == '--yes' {
			yes = true
			i++
			continue
		}
		if a == '--dest' {
			if i + 1 >= args.len || args[i + 1].starts_with('-') || args[i + 1].len == 0 {
				return error('missing value for --dest.\nExample: horneroctl config materialize --dest /tmp/hx-dest --dry-run')
			}
			dest = args[i + 1]
			i += 2
			continue
		}
		if a.starts_with('--dest=') {
			dest = a.all_after('=')
			if dest.len == 0 {
				return error('missing value for --dest.\nExample: horneroctl config materialize --dest /tmp/hx-dest --dry-run')
			}
			i++
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl config materialize --dest /tmp/hx-dest --dry-run')
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl config materialize --help')
	}
	if dest.len == 0 {
		return error('missing --dest.\nExample: horneroctl config materialize --dest /tmp/hx-dest --dry-run')
	}
	return MaterializeCmdOptions{
		dest:    dest
		dry_run: dry_run
		yes:     yes
	}
}

// GuiCmdOptions covers `config gui [--pane <name>]` (launcher: no
// --yes; --dry-run previews the backend invocation).
pub struct GuiCmdOptions {
pub:
	pane    string
	dry_run bool
}

pub fn parse_gui_cmd(args []string) !GuiCmdOptions {
	mut pane := ''
	mut dry_run := false
	mut i := 0
	for i < args.len {
		a := args[i]
		if a == '--dry-run' {
			dry_run = true
			i++
			continue
		}
		if a == '--pane' {
			if i + 1 >= args.len || args[i + 1].starts_with('-') || args[i + 1].len == 0 {
				return error('missing value for --pane.\nExample: horneroctl config gui --pane appearance --dry-run')
			}
			pane = args[i + 1]
			i += 2
			continue
		}
		if a.starts_with('--pane=') {
			pane = a.all_after('=')
			if pane.len == 0 {
				return error('missing value for --pane.\nExample: horneroctl config gui --pane appearance --dry-run')
			}
			i++
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl config gui --dry-run')
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl config gui --help')
	}
	return GuiCmdOptions{
		pane:    pane
		dry_run: dry_run
	}
}
