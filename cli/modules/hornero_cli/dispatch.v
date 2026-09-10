module hornero_cli

import hornero_core

// Deferred groups (locked in docs/cli-architecture.md, no verified backend yet,
// so no leaves here): device (brightness/monitors/hardware needs a pinned IPC
// path first), system, package, backup, and setup (installer-owned namespace).
// Each future leaf needs the same treatment as below: a verified backend,
// core result + dispatch + help with Examples + unit tests, and
// --json/--quiet/--dry-run semantics per cli/AGENTS.md.
const known_commands = ['version', 'doctor', 'shell', 'appearance', 'scheme', 'config', 'completion',
	'help']

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
		'completion' {
			run_completion(rest[1..], mode)
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
