module hornero_cli

// Wallpaper option parser: `wallpaper <set|current>`.
// Error strings always carry a correct Example (exit-2 contract).

// WallpaperCmdOptions covers `wallpaper set <path> | current [path]`.
// `current` accepts one optional explicit path candidate and no flags;
// `set` mutates and takes --dry-run/--yes.
pub struct WallpaperCmdOptions {
pub:
	action  string // set | current
	path    string
	dry_run bool
	yes     bool
}

// parse_wallpaper_cmd parses `wallpaper <set|current>` arguments.
pub fn parse_wallpaper_cmd(args []string) !WallpaperCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl wallpaper current')
	}
	action := args[0]
	if action !in ['set', 'current'] {
		return error('unknown wallpaper subcommand: ${action}.\nRun: horneroctl wallpaper --help')
	}
	mut path := ''
	mut dry_run := false
	mut yes := false
	mut i := 1
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
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl wallpaper ${action} --dry-run')
		}
		if path.len > 0 {
			return error('unexpected argument: ${a}.\nRun: horneroctl wallpaper --help')
		}
		path = a
		i++
	}
	if action == 'set' && path.len == 0 {
		return error('missing wallpaper path.\nExample: horneroctl wallpaper set ~/wall.jpg --dry-run')
	}
	if action == 'current' && (dry_run || yes) {
		return error('wallpaper current takes no flags.\nExample: horneroctl wallpaper current')
	}
	return WallpaperCmdOptions{
		action:  action
		path:    path
		dry_run: dry_run
		yes:     yes
	}
}
