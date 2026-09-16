module hornero_cli

import hornero_core

// Deferred groups (locked in docs/cli-architecture.md, no verified backend yet,
// so no leaves here): device (brightness/monitors/hardware needs a pinned IPC
// path first), system, and setup (installer-owned namespace). Batch 1 ships
// `package check|updates`, `backup list|schedule`, and `config snapshot`;
// batch 2 ships `config default-apps list`, `config materialize`, and
// `config gui`; preview 1 adds `config migrate`. The remaining
// mutating/privileged siblings (package
// upgrade/deps, backup create/restore, config default-apps set) stay
// usage-error deferrals until a pinned backend lands (`set` has no
// verified upstream verb: `dots-default-apps --set` never binds its
// arguments, and handlr stays internal).
// Each future leaf needs the same treatment as below: a verified backend,
// core result + dispatch + help with Examples + unit tests, and
// --json/--quiet/--dry-run semantics per cli/AGENTS.md.
const known_commands = ['version', 'doctor', 'shell', 'appearance', 'scheme', 'config', 'package',
	'backup', 'power', 'lock', 'completion', 'welcome', 'wallpaper', 'help']

// dispatch is the testable entry point: it returns the process exit code and
// never calls exit() itself. cmd/agent entry maps the return to exit(code).
pub fn dispatch(args []string) int {
	mut argv := []string{}
	if args.len > 1 {
		argv = args[1..].clone()
	}
	mode, rest := split_globals(argv)
	if rest.len == 0 {
		print(root_help())
		return 0
	}
	first := rest[0]
	if first in ['-h', '--help', 'help'] {
		if rest.len >= 2 {
			h := command_help(rest[1])
			if h.len == 0 {
				eprintln('Unknown command: ${rest[1]}')
				eprintln("Run 'horneroctl help' for usage.")
				return 1
			}
			print(h)
			return 0
		}
		print(root_help())
		return 0
	}
	if first in ['-V', '--version', 'version'] {
		if wants_help(rest) {
			print(command_help('version'))
			return 0
		}
		return render(hornero_core.version_result(), mode)
	}
	if first !in known_commands {
		if first.starts_with('-') {
			return render_error(hornero_core.err_usage('flag.unknown', "unknown flag: ${first}.\nRun 'horneroctl --help' for usage."),
				mode)
		}
		eprintln('Unknown command: ${first}')
		eprintln("Run 'horneroctl help' for usage.")
		return 1
	}
	if wants_help(rest) {
		print(command_help(first))
		return 0
	}
	return match first {
		'doctor' {
			render(hornero_core.doctor_result(hornero_core.run_doctor()), mode)
		}
		'shell' {
			run_shell(rest[1..], mode)
		}
		'appearance' {
			run_appearance(rest[1..], mode)
		}
		'scheme' {
			// Compat shortcut: top-level `scheme` is `appearance scheme`.
			if wants_help(rest) {
				print(command_help('scheme'))
				return 0
			}
			run_appearance_scheme(rest[1..], mode)
		}
		'config' {
			run_config(rest[1..], mode)
		}
		'package' {
			run_package(rest[1..], mode)
		}
		'backup' {
			run_backup(rest[1..], mode)
		}
		'power' {
			run_power(rest[1..], mode)
		}
		'lock' {
			run_lock(rest[1..], mode)
		}
		'completion' {
			run_completion(rest[1..], mode)
		}
		'welcome' {
			run_welcome(rest[1..], mode)
		}
		'wallpaper' {
			run_wallpaper(rest[1..], mode)
		}
		'help' {
			print(root_help())
			0
		}
		else {
			render_error(hornero_core.err_user('command.unknown', 'Unknown command: ${first}'),
				mode)
		}
	}
}

fn run_shell(args []string, mode hornero_core.RenderMode) int {
	if args.len > 0 && args[0] == 'preset' {
		if wants_help(args) {
			print(command_help('shell preset'))
			return 0
		}
		return run_shell_preset(args[1..], mode)
	}
	opts := parse_shell_cmd(args) or {
		return render_error(hornero_core.err_usage('shell.usage', err.msg()), mode)
	}
	if opts.sub == 'status' {
		return render(hornero_core.shell_status(), mode)
	}
	return render(hornero_core.ipc_report(hornero_core.IpcOptions{
		passthrough: opts.passthrough
		dry_run:     opts.dry_run
	}), mode)
}

fn run_shell_preset(args []string, mode hornero_core.RenderMode) int {
	opts := parse_shell_preset(args) or {
		return render_error(hornero_core.err_usage('shell.preset.usage', err.msg()), mode)
	}
	if opts.leaf == 'current' {
		return render(hornero_core.preset_current_report(), mode)
	}
	return render(hornero_core.preset_list_report(), mode)
}

fn run_appearance(args []string, mode hornero_core.RenderMode) int {
	if args.len > 0 && args[0] in ['theme', 'scheme'] {
		if wants_help(args) {
			print(command_help('appearance ' + args[0]))
			return 0
		}
		if args[0] == 'theme' {
			return run_appearance_theme(args[1..], mode)
		}
		return run_appearance_scheme(args[1..], mode)
	}
	opts := parse_appearance_cmd(args) or {
		return render_error(hornero_core.err_usage('appearance.usage', err.msg()), mode)
	}
	return render(hornero_core.appearance_report(hornero_core.AppearanceOptions{
		action:  opts.sub
		call:    opts.call_args
		dry_run: opts.dry_run
		yes:     opts.yes
	}), mode)
}

fn run_appearance_theme(args []string, mode hornero_core.RenderMode) int {
	opts := parse_appearance_theme(args) or {
		return render_error(hornero_core.err_usage('appearance.theme.usage', err.msg()),
			mode)
	}
	if opts.leaf == 'list' {
		return render(hornero_core.themes_list_report(), mode)
	}
	if opts.leaf == 'show' {
		return render(hornero_core.theme_show_report(opts.id), mode)
	}
	if opts.leaf == 'get' {
		return render(hornero_core.theme_get_report(hornero_core.ThemeGetOptions{
			dry_run: opts.dry_run
		}), mode)
	}
	if opts.leaf == 'set' {
		return render(hornero_core.theme_set_report(hornero_core.ThemeSetOptions{
			id:      opts.id
			dry_run: opts.dry_run
			yes:     opts.yes
		}), mode)
	}
	return render(hornero_core.theme_apply_report(hornero_core.ThemeApplyOptions{
		id:        opts.id
		wallpaper: opts.wallpaper
		dry_run:   opts.dry_run
		yes:       opts.yes
	}), mode)
}

fn run_appearance_scheme(args []string, mode hornero_core.RenderMode) int {
	opts := parse_appearance_scheme(args) or {
		return render_error(hornero_core.err_usage('appearance.scheme.usage', err.msg()),
			mode)
	}
	if opts.leaf == 'status' {
		return render(hornero_core.scheme_status_report(), mode)
	}
	kind := if opts.leaf == 'set-mode' { 'mode' } else { 'variant' }
	return render(hornero_core.scheme_set_report(hornero_core.SchemeSetOptions{
		kind:    kind
		value:   opts.value
		dry_run: opts.dry_run
		yes:     opts.yes
	}), mode)
}

fn run_config(args []string, mode hornero_core.RenderMode) int {
	if args.len == 0 {
		return render_error(hornero_core.err_usage('config.usage', 'missing subcommand.\nExample: horneroctl config validate'),
			mode)
	}
	if args[0] == 'snapshot' {
		if wants_help(args) {
			print(command_help('config snapshot'))
			return 0
		}
		return run_config_snapshot(args[1..], mode)
	}
	if args[0] == 'default-apps' {
		if wants_help(args) {
			print(command_help('config default-apps'))
			return 0
		}
		return run_config_default_apps(args[1..], mode)
	}
	if args[0] == 'materialize' {
		if wants_help(args) {
			print(command_help('config materialize'))
			return 0
		}
		return run_config_materialize(args[1..], mode)
	}
	if args[0] == 'gui' {
		if wants_help(args) {
			print(command_help('config gui'))
			return 0
		}
		return run_config_gui(args[1..], mode)
	}
	if args[0] == 'migrate' {
		if wants_help(args) {
			print(command_help('config migrate'))
			return 0
		}
		return run_config_migrate(args[1..], mode)
	}
	match args[0] {
		'paths' {
			return render(hornero_core.config_paths_report(), mode)
		}
		'show' {
			if args.len > 2 {
				return render_error(hornero_core.err_usage('config.usage', 'too many arguments.\nExample: horneroctl config show bar.position'),
					mode)
			}
			if args.len == 2 && args[1].starts_with('-') {
				return render_error(hornero_core.err_usage('config.usage', 'unknown flag: ${args[1]}.\nExample: horneroctl config show bar.position'),
					mode)
			}
			key := if args.len == 2 { args[1] } else { '' }
			return render(hornero_core.config_show_report(key), mode)
		}
		'validate' {
			return render(hornero_core.config_validate_report(), mode)
		}
		else {
			return render_error(hornero_core.err_user('config.unknown', 'unknown config subcommand: ${args[0]}.\nRun: horneroctl config --help'),
				mode)
		}
	}
}

fn run_config_snapshot(args []string, mode hornero_core.RenderMode) int {
	opts := parse_config_snapshot(args) or {
		return render_error(hornero_core.err_usage('config.snapshot.usage', err.msg()),
			mode)
	}
	if opts.leaf == 'list' {
		return render(hornero_core.snapshot_list_report(), mode)
	}
	if opts.leaf == 'create' {
		return render(hornero_core.snapshot_create_report(hornero_core.SnapshotCreateOptions{
			dry_run: opts.dry_run
			yes:     opts.yes
		}), mode)
	}
	return render(hornero_core.snapshot_restore_report(hornero_core.SnapshotRestoreOptions{
		id:      opts.id
		dry_run: opts.dry_run
		yes:     opts.yes
	}), mode)
}

fn run_config_default_apps(args []string, mode hornero_core.RenderMode) int {
	opts := parse_default_apps_cmd(args) or {
		return render_error(hornero_core.err_usage('default-apps.usage', err.msg()), mode)
	}
	return render(hornero_core.default_apps_list_report(hornero_core.DefaultAppsListOptions{
		dry_run: opts.dry_run
	}), mode)
}

fn run_config_materialize(args []string, mode hornero_core.RenderMode) int {
	opts := parse_materialize_cmd(args) or {
		return render_error(hornero_core.err_usage('config.materialize.usage', err.msg()),
			mode)
	}
	return render(hornero_core.materialize_report(hornero_core.MaterializeOptions{
		dest:    opts.dest
		dry_run: opts.dry_run
		yes:     opts.yes
	}), mode)
}

fn run_config_migrate(args []string, mode hornero_core.RenderMode) int {
	opts := parse_migrate_cmd(args) or {
		return render_error(hornero_core.err_usage('config.migrate.usage', err.msg()),
			mode)
	}
	return render(hornero_core.migrate_report(hornero_core.MigrateOptions{
		dry_run: opts.dry_run
		yes:     opts.yes
		helper:  opts.helper
	}), mode)
}

fn run_config_gui(args []string, mode hornero_core.RenderMode) int {
	opts := parse_gui_cmd(args) or {
		return render_error(hornero_core.err_usage('config.gui.usage', err.msg()), mode)
	}
	return render(hornero_core.settings_gui_report(hornero_core.SettingsGuiOptions{
		pane:    opts.pane
		dry_run: opts.dry_run
	}), mode)
}

fn run_package(args []string, mode hornero_core.RenderMode) int {
	opts := parse_package_cmd(args) or {
		return render_error(hornero_core.err_usage('package.usage', err.msg()), mode)
	}
	check := hornero_core.PackageCheckOptions{
		dry_run: opts.dry_run
	}
	if opts.leaf == 'updates' {
		return render(hornero_core.package_updates_report(check), mode)
	}
	return render(hornero_core.package_check_report(check), mode)
}

fn run_backup(args []string, mode hornero_core.RenderMode) int {
	opts := parse_backup_cmd(args) or {
		return render_error(hornero_core.err_usage('backup.usage', err.msg()), mode)
	}
	if opts.leaf == 'schedule' {
		return render(hornero_core.backup_schedule_report(), mode)
	}
	return render(hornero_core.backup_list_report(), mode)
}

fn run_power(args []string, mode hornero_core.RenderMode) int {
	opts := parse_power_cmd(args) or {
		return render_error(hornero_core.err_usage('power.usage', err.msg()), mode)
	}
	if opts.leaf == 'status' {
		return render(hornero_core.power_status_report(), mode)
	}
	return render(hornero_core.power_action_report(hornero_core.PowerActionOptions{
		action:  opts.leaf
		dry_run: opts.dry_run
		yes:     opts.yes
	}), mode)
}

fn run_lock(args []string, mode hornero_core.RenderMode) int {
	opts := parse_lock_cmd(args) or {
		return render_error(hornero_core.err_usage('lock.usage', err.msg()), mode)
	}
	if opts.leaf == 'status' {
		return render(hornero_core.lock_status_report(), mode)
	}
	return render(hornero_core.lock_now_report(hornero_core.LockNowOptions{
		dry_run: opts.dry_run
		yes:     opts.yes
	}), mode)
}

fn run_welcome(args []string, mode hornero_core.RenderMode) int {
	opts := parse_welcome(args) or {
		return render_error(hornero_core.err_usage('welcome.usage', err.msg()), mode)
	}
	match opts.leaf {
		'status' {
			return render(hornero_core.welcome_status_report(), mode)
		}
		'set-show-on-login' {
			value := hornero_core.welcome_parse_cli_bool(opts.value) or {
				return render_error(hornero_core.err_usage('welcome.usage', 'invalid value: ${opts.value} (use true|false).\nExample: horneroctl welcome set-show-on-login false --dry-run'),
					mode)
			}
			return render(hornero_core.welcome_set_show_report(hornero_core.WelcomeSetOptions{
				value:   value
				dry_run: opts.dry_run
				yes:     opts.yes
			}), mode)
		}
		'mark-seen' {
			return render(hornero_core.welcome_mark_seen_report(hornero_core.WelcomeSeenOptions{
				revision: opts.revision
				dry_run:  opts.dry_run
				yes:      opts.yes
			}), mode)
		}
		'open' {
			return render(hornero_core.welcome_open_report(hornero_core.WelcomeOpenOptions{
				page:    opts.value
				dry_run: opts.dry_run
			}), mode)
		}
		'reset' {
			return render(hornero_core.welcome_reset_report(opts.dry_run, opts.yes), mode)
		}
		else {
			return render_error(hornero_core.err_usage('welcome.usage', 'unknown welcome leaf.\nExample: horneroctl welcome status'),
				mode)
		}
	}
}

fn run_wallpaper(args []string, mode hornero_core.RenderMode) int {
	opts := parse_wallpaper_cmd(args) or {
		return render_error(hornero_core.err_usage('wallpaper.usage', err.msg()), mode)
	}
	return render(hornero_core.wallpaper_report(hornero_core.WallpaperOptions{
		action:  opts.action
		path:    opts.path
		dry_run: opts.dry_run
		yes:     opts.yes
	}), mode)
}

fn run_completion(args []string, mode hornero_core.RenderMode) int {
	if args.len == 0 {
		return render_error(hornero_core.err_usage('completion.usage', 'missing shell.\nExample: horneroctl completion bash'),
			mode)
	}
	match args[0] {
		'bash' {
			print(bash_completion())
			return 0
		}
		'zsh' {
			print(zsh_completion())
			return 0
		}
		'fish' {
			print(fish_completion())
			return 0
		}
		else {
			return render_error(hornero_core.err_user('completion.unknown', 'unknown shell: ${args[0]} (bash, zsh, fish).\nExample: horneroctl completion bash'),
				mode)
		}
	}
}
