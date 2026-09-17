module hornero_cli

import hornero_core

// Deferred groups (locked in docs/cli-architecture.md, no verified backend yet,
// so no leaves here): device (monitors/compositor needs a pinned IPC path
// first), system, and setup (installer-owned namespace). The dots-*
// hardware surfaces (brightness, battery, mic, keyboard, network) ship
// under `hardware` instead, delegating to the same backend CLIs.
// Batch 1 ships
// `package check|updates`, `backup list|schedule`, and `config snapshot`;
// batch 2 ships `config default-apps list`, `config materialize`, and
// `config gui`; preview 1 adds `config migrate`. R1 (lifecycle +
// privileged) adds `shell start|stop|restart|logs`, `package
// upgrade|deps`, `backup create|restore`, `config default-apps set`,
// and `hypr plugins install`. Still deferred: `shell preset apply`
// and `shell config` (need a pinned merge backend), backup cron
// install (interactive by design), and the dots-default-apps
// gui/info/type modes (interactive).
// Each future leaf needs the same treatment as below: a verified backend,
// core result + dispatch + help with Examples + unit tests, and
// --json/--quiet/--dry-run semantics per cli/AGENTS.md.
const known_commands = ['version', 'doctor', 'shell', 'appearance', 'scheme', 'config', 'package',
	'backup', 'power', 'lock', 'hypr', 'hardware', 'completion', 'welcome', 'wallpaper', 'capture',
	'apps', 'help']

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
		'hypr' {
			run_hypr(rest[1..], mode)
		}
		'hardware' {
			run_hardware(rest[1..], mode)
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
		'capture' {
			run_capture(rest[1..], mode)
		}
		'apps' {
			run_apps(rest[1..], mode)
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
	if opts.sub == 'start' {
		return render(hornero_core.shell_start_report(hornero_core.ShellStartOptions{
			dry_run: opts.dry_run
			yes:     opts.yes
		}), mode)
	}
	if opts.sub == 'stop' {
		return render(hornero_core.shell_stop_report(hornero_core.ShellStopOptions{
			dry_run: opts.dry_run
			yes:     opts.yes
		}), mode)
	}
	if opts.sub == 'restart' {
		return render(hornero_core.shell_restart_report(hornero_core.ShellRestartOptions{
			dry_run: opts.dry_run
			yes:     opts.yes
		}), mode)
	}
	if opts.sub == 'logs' {
		return render(hornero_core.shell_logs_report(hornero_core.ShellLogsOptions{
			lines:   opts.lines
			dry_run: opts.dry_run
		}), mode)
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
	if args.len > 0 && args[0] in ['theme', 'scheme', 'colors', 'accent', 'night-mode'] {
		if wants_help(args) {
			print(command_help('appearance ' + args[0]))
			return 0
		}
		if args[0] == 'theme' {
			return run_appearance_theme(args[1..], mode)
		}
		if args[0] == 'colors' {
			return run_appearance_colors(args[1..], mode)
		}
		if args[0] == 'accent' {
			return run_appearance_accent(args[1..], mode)
		}
		if args[0] == 'night-mode' {
			return run_appearance_night_mode(args[1..], mode)
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

fn run_appearance_colors(args []string, mode hornero_core.RenderMode) int {
	opts := parse_appearance_colors(args) or {
		return render_error(hornero_core.err_usage('appearance.colors.usage', err.msg()),
			mode)
	}
	return render(hornero_core.colors_report(hornero_core.ColorsOptions{
		action:  opts.leaf
		m3:      opts.m3
		call:    opts.call_args
		dry_run: opts.dry_run
		yes:     opts.yes
	}), mode)
}

fn run_appearance_accent(args []string, mode hornero_core.RenderMode) int {
	opts := parse_appearance_accent(args) or {
		return render_error(hornero_core.err_usage('appearance.accent.usage', err.msg()),
			mode)
	}
	return render(hornero_core.accent_report(hornero_core.AccentOptions{
		action:  opts.leaf
		value:   opts.value
		dry_run: opts.dry_run
		yes:     opts.yes
	}), mode)
}

fn run_appearance_night_mode(args []string, mode hornero_core.RenderMode) int {
	opts := parse_appearance_night_mode(args) or {
		return render_error(hornero_core.err_usage('appearance.night-mode.usage', err.msg()),
			mode)
	}
	return render(hornero_core.night_mode_report(hornero_core.NightModeOptions{
		action:  opts.leaf
		dry_run: opts.dry_run
		yes:     opts.yes
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
	if opts.leaf == 'set' {
		return render(hornero_core.default_apps_set_report(hornero_core.DefaultAppsSetOptions{
			mime:    opts.mime
			app:     opts.app
			dry_run: opts.dry_run
			yes:     opts.yes
		}), mode)
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
	if opts.leaf == 'upgrade' {
		return render(hornero_core.package_upgrade_report(hornero_core.PackageUpgradeOptions{
			dry_run: opts.dry_run
			yes:     opts.yes
		}), mode)
	}
	if opts.leaf == 'deps' {
		deps := hornero_core.PackageDepsOptions{
			optional: opts.optional
			install:  opts.install
			dry_run:  opts.dry_run
			yes:      opts.yes
		}
		if opts.install {
			return render(hornero_core.package_deps_install_report(deps), mode)
		}
		return render(hornero_core.package_deps_check_report(deps), mode)
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
	if opts.leaf == 'create' {
		return render(hornero_core.backup_create_report(hornero_core.BackupCreateOptions{
			name:    opts.id
			dry_run: opts.dry_run
			yes:     opts.yes
		}), mode)
	}
	if opts.leaf == 'restore' {
		return render(hornero_core.backup_restore_report(hornero_core.BackupRestoreOptions{
			id:      opts.id
			dry_run: opts.dry_run
			yes:     opts.yes
		}), mode)
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

fn run_hypr(args []string, mode hornero_core.RenderMode) int {
	if args.len > 0 && args[0] in ['animations', 'layout', 'monitors', 'workspace', 'plugins'] {
		if wants_help(args) {
			print(command_help('hypr ' + args[0]))
			return 0
		}
		match args[0] {
			'animations' {
				return run_hypr_animations(args[1..], mode)
			}
			'layout' {
				return run_hypr_layout(args[1..], mode)
			}
			'monitors' {
				return run_hypr_monitors(args[1..], mode)
			}
			'workspace' {
				return run_hypr_workspace(args[1..], mode)
			}
			else {
				return run_hypr_plugins(args[1..], mode)
			}
		}
	}
	if args.len == 0 {
		return render_error(hornero_core.err_usage('hypr.usage', 'missing subcommand.\nExample: horneroctl hypr animations list'),
			mode)
	}
	if wants_help(args) {
		print(command_help('hypr'))
		return 0
	}
	return render_error(hornero_core.err_usage('hypr.usage', 'unknown hypr subcommand: ${args[0]}.\nRun: horneroctl hypr --help'),
		mode)
}

fn run_hypr_animations(args []string, mode hornero_core.RenderMode) int {
	opts := parse_hypr_animations(args) or {
		return render_error(hornero_core.err_usage('hypr.animations.usage', err.msg()),
			mode)
	}
	mut profile := opts.profile
	if opts.leaf == 'next' {
		profile = hornero_core.animation_next_profile()
	} else if opts.leaf == 'restore' {
		profile = hornero_core.animation_current_profile()
	}
	match opts.leaf {
		'list' {
			return render(hornero_core.animation_list_report(), mode)
		}
		'current' {
			return render(hornero_core.animation_current_report(), mode)
		}
		else {
			return render(hornero_core.animation_apply_report(hornero_core.AnimationApplyOptions{
				profile:   profile
				dry_run:   opts.dry_run
				yes:       opts.yes
				ephemeral: opts.ephemeral
			}), mode)
		}
	}
}

fn run_hypr_layout(args []string, mode hornero_core.RenderMode) int {
	opts := parse_hypr_layout(args) or {
		return render_error(hornero_core.err_usage('hypr.layout.usage', err.msg()), mode)
	}
	if opts.leaf == 'current' {
		return render(hornero_core.layout_current_report(), mode)
	}
	if opts.leaf == 'status' {
		return render(hornero_core.layout_status_report(), mode)
	}
	mut layout := opts.layout
	if opts.leaf == 'toggle' {
		layout = hornero_core.layout_toggle_value(hornero_core.layout_current_value())
	} else if opts.leaf == 'restore' {
		layout = hornero_core.layout_restore_value()
	}
	return render(hornero_core.layout_apply_report(hornero_core.LayoutApplyOptions{
		layout:    layout
		dry_run:   opts.dry_run
		yes:       opts.yes
		ephemeral: opts.ephemeral
	}), mode)
}

fn run_hypr_monitors(args []string, mode hornero_core.RenderMode) int {
	opts := parse_hypr_monitors(args) or {
		return render_error(hornero_core.err_usage('hypr.monitors.usage', err.msg()),
			mode)
	}
	if opts.leaf == 'list' {
		return render(hornero_core.monitors_list_report(), mode)
	}
	if opts.leaf == 'status' {
		return render(hornero_core.monitors_status_report(), mode)
	}
	return render(hornero_core.monitors_set_report(hornero_core.MonitorsSetOptions{
		mode:    opts.mode
		dry_run: opts.dry_run
		yes:     opts.yes
	}), mode)
}

fn run_hypr_workspace(args []string, mode hornero_core.RenderMode) int {
	opts := parse_hypr_workspace(args) or {
		return render_error(hornero_core.err_usage('hypr.workspace.usage', err.msg()),
			mode)
	}
	return render(hornero_core.workspace_cycle_report(hornero_core.WorkspaceCycleOptions{
		direction: opts.leaf
		dry_run:   opts.dry_run
		yes:       opts.yes
	}), mode)
}

fn run_hypr_plugins(args []string, mode hornero_core.RenderMode) int {
	opts := parse_hypr_plugins(args) or {
		return render_error(hornero_core.err_usage('hypr.plugins.usage', err.msg()), mode)
	}
	if opts.leaf == 'status' {
		return render(hornero_core.plugins_status_report(), mode)
	}
	if opts.leaf == 'install' {
		return render(hornero_core.plugins_install_report(hornero_core.PluginsInstallOptions{
			force:     opts.force
			no_update: opts.no_update
			dry_run:   opts.dry_run
			yes:       opts.yes
		}), mode)
	}
	return render(hornero_core.plugins_list_report(), mode)
}

fn run_hardware(args []string, mode hornero_core.RenderMode) int {
	if args.len == 0 {
		return render_error(hornero_core.err_usage('hardware.usage', 'missing subcommand.\nExample: horneroctl hardware brightness status'),
			mode)
	}
	group := args[0]
	if group !in ['brightness', 'battery', 'mic', 'keyboard', 'network'] {
		return render_error(hornero_core.err_usage('hardware.usage', 'unknown hardware group: ${group}.\nRun: horneroctl hardware --help'),
			mode)
	}
	if wants_help(args) {
		print(command_help('hardware ' + group))
		return 0
	}
	match group {
		'brightness' {
			return run_hardware_brightness(args[1..], mode)
		}
		'battery' {
			return run_hardware_battery(args[1..], mode)
		}
		'mic' {
			return run_hardware_mic(args[1..], mode)
		}
		'keyboard' {
			return run_hardware_keyboard(args[1..], mode)
		}
		else {
			return run_hardware_network(args[1..], mode)
		}
	}
}

fn run_hardware_brightness(args []string, mode hornero_core.RenderMode) int {
	opts := parse_hardware_brightness(args) or {
		return render_error(hornero_core.err_usage('hardware.brightness.usage', err.msg()),
			mode)
	}
	if opts.leaf == 'status' {
		return render(hornero_core.brightness_status_report(hornero_core.BrightnessStatusOptions{
			display: opts.display
			dry_run: opts.dry_run
		}), mode)
	}
	if opts.leaf == 'set' {
		return render(hornero_core.brightness_set_report(hornero_core.BrightnessSetOptions{
			value:   opts.value
			display: opts.display
			dry_run: opts.dry_run
			yes:     opts.yes
		}), mode)
	}
	return render(hornero_core.brightness_adjust_report(hornero_core.BrightnessAdjustOptions{
		dir:     opts.leaf
		step:    opts.step
		display: opts.display
		dry_run: opts.dry_run
		yes:     opts.yes
	}), mode)
}

fn run_hardware_battery(args []string, mode hornero_core.RenderMode) int {
	opts := parse_hardware_battery(args) or {
		return render_error(hornero_core.err_usage('hardware.battery.usage', err.msg()),
			mode)
	}
	if opts.leaf == 'status' {
		return render(hornero_core.battery_status_report(hornero_core.BatteryStatusOptions{
			dry_run: opts.dry_run
		}), mode)
	}
	return render(hornero_core.battery_monitor_report(hornero_core.BatteryMonitorOptions{
		low:      opts.low
		crit:     opts.crit
		interval: opts.interval
		daemon:   opts.daemon
		dry_run:  opts.dry_run
		yes:      opts.yes
	}), mode)
}

fn run_hardware_mic(args []string, mode hornero_core.RenderMode) int {
	opts := parse_hardware_mic(args) or {
		return render_error(hornero_core.err_usage('hardware.mic.usage', err.msg()), mode)
	}
	if opts.leaf == 'status' {
		return render(hornero_core.mic_status_report(hornero_core.MicStatusOptions{
			dry_run: opts.dry_run
		}), mode)
	}
	return render(hornero_core.mic_toggle_report(hornero_core.MicToggleOptions{
		dry_run: opts.dry_run
		yes:     opts.yes
	}), mode)
}

fn run_hardware_keyboard(args []string, mode hornero_core.RenderMode) int {
	opts := parse_hardware_keyboard(args) or {
		return render_error(hornero_core.err_usage('hardware.keyboard.usage', err.msg()),
			mode)
	}
	if opts.leaf == 'settings' {
		return render(hornero_core.keyboard_settings_report(hornero_core.KeyboardSettingsOptions{
			dry_run: opts.dry_run
		}), mode)
	}
	if opts.leaf == 'keys' {
		return render(hornero_core.keyboard_keys_report(hornero_core.KeyboardKeysOptions{
			category: opts.category
			search:   opts.search
			dry_run:  opts.dry_run
		}), mode)
	}
	mode_name := if opts.get {
		'get'
	} else if opts.current {
		'current'
	} else {
		'toggle'
	}
	return render(hornero_core.keyboard_layout_report(hornero_core.KeyboardLayoutOptions{
		mode:    mode_name
		dry_run: opts.dry_run
		yes:     opts.yes
	}), mode)
}

fn run_hardware_network(args []string, mode hornero_core.RenderMode) int {
	opts := parse_hardware_network(args) or {
		return render_error(hornero_core.err_usage('hardware.network.usage', err.msg()),
			mode)
	}
	return render(hornero_core.network_status_report(hornero_core.NetworkStatusOptions{
		timeout: opts.timeout
		dry_run: opts.dry_run
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

fn run_capture(args []string, mode hornero_core.RenderMode) int {
	opts := parse_capture_cmd(args) or {
		return render_error(hornero_core.err_usage('capture.usage', err.msg()), mode)
	}
	match opts.group {
		'screenshot' {
			return render(hornero_core.screenshot_report(hornero_core.ScreenshotOptions{
				region:  opts.region
				output:  opts.output
				dry_run: opts.dry_run
				yes:     opts.yes
			}), mode)
		}
		'record' {
			match opts.leaf {
				'start' {
					return render(hornero_core.record_start_report(hornero_core.RecordStartOptions{
						region:  opts.region
						sound:   opts.sound
						fps:     opts.fps
						dry_run: opts.dry_run
						yes:     opts.yes
					}), mode)
				}
				'stop' {
					return render(hornero_core.record_stop_report(hornero_core.RecordStopOptions{
						dry_run: opts.dry_run
						yes:     opts.yes
					}), mode)
				}
				else {
					return render(hornero_core.record_pause_report(hornero_core.RecordPauseOptions{
						dry_run: opts.dry_run
						yes:     opts.yes
					}), mode)
				}
			}
		}
		else {
			return render(hornero_core.clipboard_report(hornero_core.ClipboardOptions{
				backend: opts.backend
				dry_run: opts.dry_run
			}), mode)
		}
	}
}

fn run_apps(args []string, mode hornero_core.RenderMode) int {
	if args.len > 0 && args[0] in apps_verbs {
		if wants_help(args) {
			print(command_help('apps ' + args[0]))
			return 0
		}
	}
	opts := parse_apps_cmd(args) or {
		return render_error(hornero_core.err_usage('apps.usage', err.msg()), mode)
	}
	match opts.verb {
		'files' {
			fopts := parse_apps_files(opts.rest) or {
				return render_error(hornero_core.err_usage('apps.files.usage', err.msg()),
					mode)
			}
			return render(hornero_core.files_report(hornero_core.FilesOptions{
				path:    fopts.path
				info:    fopts.info
				dry_run: fopts.dry_run
			}), mode)
		}
		'terminal-file' {
			topts := parse_apps_terminal_file(opts.rest) or {
				return render_error(hornero_core.err_usage('apps.terminal-file.usage',
					err.msg()), mode)
			}
			return render(hornero_core.terminal_file_report(hornero_core.TerminalFileOptions{
				path:         topts.path
				selected:     topts.selected
				last_dir:     topts.last_dir
				cheatsheet:   topts.cheatsheet
				fix_previews: topts.fix_previews
				dry_run:      topts.dry_run
			}), mode)
		}
		'weather' {
			wopts := parse_apps_weather(opts.rest) or {
				return render_error(hornero_core.err_usage('apps.weather.usage', err.msg()),
					mode)
			}
			return render(hornero_core.weather_report(hornero_core.WeatherOptions{
				field:   wopts.field
				dry_run: wopts.dry_run
			}), mode)
		}
		'git-status' {
			gopts := parse_apps_git_status(opts.rest) or {
				return render_error(hornero_core.err_usage('apps.git-status.usage', err.msg()),
					mode)
			}
			return render(hornero_core.git_status_report(hornero_core.GitStatusOptions{
				leaf:       gopts.leaf
				branch:     gopts.branch
				repository: gopts.repository
				interval:   gopts.interval
				async:      gopts.async
				verbose:    gopts.verbose
				dry_run:    gopts.dry_run
				yes:        gopts.yes
			}), mode)
		}
		'audit' {
			aopts := parse_apps_audit(opts.rest) or {
				return render_error(hornero_core.err_usage('apps.audit.usage', err.msg()),
					mode)
			}
			return render(hornero_core.audit_report(hornero_core.AuditOptions{
				check:   aopts.check
				dry_run: aopts.dry_run
			}), mode)
		}
		'launch' {
			lopts := parse_apps_launch(opts.rest) or {
				return render_error(hornero_core.err_usage('apps.launch.usage', err.msg()),
					mode)
			}
			return render(hornero_core.launch_report(hornero_core.LaunchOptions{
				backend: lopts.backend
				list:    lopts.list
				dry_run: lopts.dry_run
			}), mode)
		}
		'toggle' {
			topts := parse_apps_toggle(opts.rest) or {
				return render_error(hornero_core.err_usage('apps.toggle.usage', err.msg()),
					mode)
			}
			return render(hornero_core.toggle_report(hornero_core.ToggleOptions{
				component: topts.component
				dry_run:   topts.dry_run
				yes:       topts.yes
			}), mode)
		}
		'switcher' {
			sopts := parse_apps_switcher(opts.rest) or {
				return render_error(hornero_core.err_usage('apps.switcher.usage', err.msg()),
					mode)
			}
			return render(hornero_core.switcher_report(hornero_core.SwitcherOptions{
				leaf:    sopts.leaf
				arg:     sopts.arg
				dry_run: sopts.dry_run
				yes:     sopts.yes
			}), mode)
		}
		else {
			popts := parse_apps_performance(opts.rest) or {
				return render_error(hornero_core.err_usage('apps.performance.usage', err.msg()),
					mode)
			}
			return render(hornero_core.performance_report(hornero_core.PerformanceOptions{
				leaf:    popts.leaf
				sub:     popts.sub
				profile: popts.profile
				dry_run: popts.dry_run
				yes:     popts.yes
			}), mode)
		}
	}
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
