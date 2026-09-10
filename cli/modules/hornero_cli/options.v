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
		sub:         sub
		dry_run:     dry_run
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

// ThemeCmdOptions covers `appearance theme <list|show|apply>`.
pub struct ThemeCmdOptions {
pub:
	leaf      string // list | show | apply
	id        string
	wallpaper string
	dry_run   bool
	yes       bool
}

pub fn parse_appearance_theme(args []string) !ThemeCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl appearance theme list')
	}
	leaf := args[0]
	if leaf !in ['list', 'show', 'apply'] {
		return error('unknown theme subcommand: ${leaf}.\nRun: horneroctl appearance theme --help')
	}
	mut id := ''
	mut wallpaper := ''
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
		if a == '--wallpaper' {
			if i + 1 >= args.len || args[i + 1].starts_with('-') {
				return error('missing value for --wallpaper.\nExample: horneroctl appearance theme apply vapor-dreams --wallpaper ~/wall.jpg --dry-run')
			}
			wallpaper = args[i + 1]
			i += 2
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl appearance theme list')
		}
		if id.len > 0 {
			return error('unexpected argument: ${a}.\nRun: horneroctl appearance theme --help')
		}
		id = a
		i++
	}
	if leaf in ['show', 'apply'] && id.len == 0 {
		return error('missing theme id.\nExample: horneroctl appearance theme ${leaf} vapor-dreams')
	}
	if leaf == 'list' && (dry_run || yes || wallpaper.len > 0) {
		return error('theme list takes no flags.\nExample: horneroctl appearance theme list')
	}
	if leaf == 'show' && (dry_run || yes || wallpaper.len > 0) {
		return error('theme show takes no flags.\nExample: horneroctl appearance theme show vapor-dreams')
	}
	return ThemeCmdOptions{
		leaf:      leaf
		id:        id
		wallpaper: wallpaper
		dry_run:   dry_run
		yes:       yes
	}
}

// SchemeCmdOptions covers `appearance scheme <status|set-mode|set-variant>`.
pub struct SchemeCmdOptions {
pub:
	leaf    string // status | set-mode | set-variant
	value   string
	dry_run bool
	yes     bool
}

pub fn parse_appearance_scheme(args []string) !SchemeCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl appearance scheme status')
	}
	leaf := args[0]
	if leaf !in ['status', 'set-mode', 'set-variant'] {
		return error('unknown scheme subcommand: ${leaf}.\nRun: horneroctl appearance scheme --help')
	}
	mut value := ''
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
			return error('unknown flag: ${a}.\nExample: horneroctl appearance scheme status')
		}
		if value.len > 0 {
			return error('unexpected argument: ${a}.\nRun: horneroctl appearance scheme --help')
		}
		value = a
		i++
	}
	if leaf in ['set-mode', 'set-variant'] && value.len == 0 {
		return error('missing value.\nExample: horneroctl appearance scheme ${leaf} dark --dry-run')
	}
	if leaf == 'status' && (value.len > 0 || dry_run || yes) {
		return error('scheme status takes no arguments.\nExample: horneroctl appearance scheme status')
	}
	return SchemeCmdOptions{
		leaf:    leaf
		value:   value
		dry_run: dry_run
		yes:     yes
	}
}

// PresetCmdOptions covers `shell preset <list|current>` (read-only).
pub struct PresetCmdOptions {
pub:
	leaf string // list | current
}

pub fn parse_shell_preset(args []string) !PresetCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl shell preset list')
	}
	leaf := args[0]
	if leaf !in ['list', 'current'] {
		return error('unknown preset subcommand: ${leaf}.\nRun: horneroctl shell preset --help')
	}
	if args.len > 1 {
		if args[1].starts_with('-') {
			return error('unknown flag: ${args[1]}.\nExample: horneroctl shell preset ${leaf}')
		}
		return error('unexpected argument: ${args[1]}.\nExample: horneroctl shell preset ${leaf}')
	}
	return PresetCmdOptions{
		leaf: leaf
	}
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
		sub:       sub
		dry_run:   dry_run
		yes:       yes
		call_args: call_args
	}
}
