module hornero_cli

import hornero_core

// split_globals extracts --json/--quiet anywhere before a `--` separator.
// Everything after `--` is passthrough and left untouched.
pub fn split_globals(argv []string) (hornero_core.RenderMode, []string) {
	mut mode := hornero_core.RenderMode.human
	mut rest := []string{}
	mut passthrough := false
	for a in argv {
		if passthrough {
			rest << a
			continue
		}
		if a == '--' {
			passthrough = true
			rest << a
			continue
		}
		if a == '--json' {
			mode = .json
			continue
		}
		if a == '--quiet' {
			mode = .quiet
			continue
		}
		rest << a
	}
	return mode, rest
}

pub fn wants_help(args []string) bool {
	for a in args {
		if a in ['-h', '--help'] {
			return true
		}
		if a == '--' {
			return false
		}
	}
	return false
}

pub struct ShellCmdOptions {
pub:
	sub         string
	dry_run     bool
	passthrough []string
}

pub fn parse_shell_cmd(args []string) !ShellCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl shell status')
	}
	sub := args[0]
	if sub !in ['status', 'ipc'] {
		return error('unknown shell subcommand: ${sub}.\nRun: horneroctl shell --help')
	}
	mut dry_run := false
	mut passthrough := []string{}
	mut i := 1
	mut sep := false
	for i < args.len {
		a := args[i]
		if sep {
			passthrough << a
			i++
			continue
		}
		if a == '--' {
			sep = true
			i++
			continue
		}
		if a == '--dry-run' {
			dry_run = true
			i++
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl shell ipc --dry-run -- show')
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl shell --help')
	}
	return ShellCmdOptions{
		sub: sub
		dry_run: dry_run
		passthrough: passthrough
	}
}

pub struct AppearanceCmdOptions {
pub:
	sub       string
	dry_run   bool
	yes       bool
	call_args []string
}

pub fn parse_appearance_cmd(args []string) !AppearanceCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl appearance status')
	}
	sub := args[0]
	if sub !in ['status', 'sync', 'call'] {
		return error('unknown appearance subcommand: ${sub}.\nRun: horneroctl appearance --help')
	}
	mut dry_run := false
	mut yes := false
	mut call_args := []string{}
	mut i := 1
	mut sep := false
	for i < args.len {
		a := args[i]
		if sep {
			call_args << a
			i++
			continue
		}
		if a == '--' {
			sep = true
			i++
			continue
		}
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
			return error('unknown flag: ${a}.\nExample: horneroctl appearance sync --dry-run')
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl appearance --help')
	}
	return AppearanceCmdOptions{
		sub: sub
		dry_run: dry_run
		yes: yes
		call_args: call_args
	}
}
