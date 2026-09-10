module hornero_cli

import hornero_core

const known_commands = ['version', 'doctor', 'shell', 'appearance', 'config', 'completion', 'help']

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

fn run_appearance(args []string, mode hornero_core.RenderMode) int {
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

fn run_config(args []string, mode hornero_core.RenderMode) int {
	if args.len == 0 {
		return render_error(hornero_core.err_usage('config.usage', 'missing subcommand.\nExample: horneroctl config validate'),
			mode)
	}
	match args[0] {
		'paths', 'show' {
			return render(hornero_core.config_paths_report(), mode)
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
