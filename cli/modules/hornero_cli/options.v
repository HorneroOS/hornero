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
	yes         bool
	lines       int
	passthrough []string
}

pub fn parse_shell_cmd(args []string) !ShellCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl shell status')
	}
	sub := args[0]
	if sub !in ['status', 'ipc', 'start', 'stop', 'restart', 'logs'] {
		return error('unknown shell subcommand: ${sub}.\nRun: horneroctl shell --help')
	}
	mut dry_run := false
	mut yes := false
	mut lines := 0
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
		if a == '--yes' {
			yes = true
			i++
			continue
		}
		if a == '--lines' {
			if sub != 'logs' {
				return error('--lines belongs to shell logs.\nExample: horneroctl shell logs --lines 100')
			}
			if i + 1 >= args.len || args[i + 1].starts_with('-') || args[i + 1].len == 0 {
				return error('missing value for --lines.\nExample: horneroctl shell logs --lines 100')
			}
			lines = args[i + 1].int()
			if lines <= 0 {
				return error('invalid value for --lines: ${args[i + 1]}.\nExample: horneroctl shell logs --lines 100')
			}
			i += 2
			continue
		}
		if a.starts_with('--lines=') {
			if sub != 'logs' {
				return error('--lines belongs to shell logs.\nExample: horneroctl shell logs --lines 100')
			}
			lines = a.all_after('=').int()
			if lines <= 0 {
				return error('invalid value for --lines: ${a}.\nExample: horneroctl shell logs --lines 100')
			}
			i++
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl shell ipc --dry-run -- show')
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl shell --help')
	}
	if sub == 'ipc' && (yes || lines > 0) {
		return error('shell ipc takes no --yes/--lines.\nExample: horneroctl shell ipc --dry-run -- show')
	}
	if sub == 'status' && (dry_run || yes || lines > 0 || passthrough.len > 0) {
		return error('shell status takes no arguments.\nExample: horneroctl shell status')
	}
	if sub in ['start', 'stop', 'restart'] && passthrough.len > 0 {
		return error('unexpected argument: ${passthrough[0]}.\nRun: horneroctl shell --help')
	}
	if sub == 'logs' && (yes || passthrough.len > 0) {
		return error('shell logs takes no --yes or passthrough arguments.\nExample: horneroctl shell logs --lines 100')
	}
	return ShellCmdOptions{
		sub:         sub
		dry_run:     dry_run
		yes:         yes
		lines:       lines
		passthrough: passthrough
	}
}

pub struct AppearanceCmdOptions {
pub:
	sub     string
	value   string
	dry_run bool
	yes     bool
}

// parse_appearance_cmd parses `appearance <status|sync|doctor|
// set-wallpaper|set-gtk|set-icons|set-gtk-color-scheme>` arguments.
pub fn parse_appearance_cmd(args []string) !AppearanceCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl appearance status')
	}
	sub := args[0]
	if sub !in ['status', 'sync', 'doctor', 'set-wallpaper', 'set-gtk', 'set-icons',
		'set-gtk-color-scheme'] {
		return error('unknown appearance subcommand: ${sub}.\nRun: horneroctl appearance --help')
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
			return error('unknown flag: ${a}.\nExample: horneroctl appearance sync --dry-run')
		}
		if value.len > 0 {
			return error('unexpected argument: ${a}.\nRun: horneroctl appearance --help')
		}
		value = a
		i++
	}
	if sub in ['status', 'sync', 'doctor'] && value.len > 0 {
		return error('appearance ${sub} takes no value.\nExample: horneroctl appearance ${sub} --dry-run')
	}
	if sub.starts_with('set-') && value.len == 0 {
		return error('missing value.\nExample: horneroctl appearance ${sub} <value> --dry-run')
	}
	return AppearanceCmdOptions{
		sub:     sub
		value:   value
		dry_run: dry_run
		yes:     yes
	}
}

// ThemeCmdOptions covers `appearance theme <list|show|get|apply|set>`.
pub struct ThemeCmdOptions {
pub:
	leaf      string // list | show | get | apply | set
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
	if leaf !in ['list', 'show', 'get', 'apply', 'set'] {
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
	if leaf in ['show', 'apply', 'set'] && id.len == 0 {
		if leaf == 'set' {
			return error('missing theme id.\nExample: horneroctl appearance theme set hornero-dark --dry-run')
		}
		return error('missing theme id.\nExample: horneroctl appearance theme ${leaf} vapor-dreams')
	}
	if leaf == 'list' && (dry_run || yes || wallpaper.len > 0) {
		return error('theme list takes no flags.\nExample: horneroctl appearance theme list')
	}
	if leaf == 'show' && (dry_run || yes || wallpaper.len > 0) {
		return error('theme show takes no flags.\nExample: horneroctl appearance theme show vapor-dreams')
	}
	if leaf == 'get' && (id.len > 0 || yes || wallpaper.len > 0) {
		return error('theme get takes no arguments.\nExample: horneroctl appearance theme get')
	}
	if leaf == 'set' && wallpaper.len > 0 {
		return error('theme set applies the official pack as-is; custom wallpaper needs apply.\nExample: horneroctl appearance theme apply ${id} --wallpaper ~/wall.jpg --dry-run')
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
	if leaf !in ['status', 'list', 'current', 'set-mode', 'set-variant', 'regenerate', 'sync-state'] {
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
	if leaf in ['status', 'list', 'current', 'regenerate', 'sync-state'] && value.len > 0 {
		return error('scheme ${leaf} takes no value.\nExample: horneroctl appearance scheme ${leaf} --dry-run')
	}
	if leaf in ['status', 'list', 'current'] && (dry_run || yes) {
		return error('scheme ${leaf} takes no flags.\nExample: horneroctl appearance scheme ${leaf}')
	}
	return SchemeCmdOptions{
		leaf:    leaf
		value:   value
		dry_run: dry_run
		yes:     yes
	}
}

// ColorsCmdOptions covers `appearance colors <status|generate|m3|
// concept|export>`. `status` previews the palette (read-only);
// `generate` rewrites the smart-color files (--m3 also refreshes
// scheme.json, needs --yes); `m3 -- <args>` passes through to the M3
// synthesizer (needs --yes); `concept <name>` resolves one semantic
// color; `export` prints shell variables.
pub struct ColorsCmdOptions {
pub:
	leaf      string // status | generate | m3 | concept | export
	value     string // concept name for `concept`
	m3        bool
	dry_run   bool
	yes       bool
	call_args []string
}

// parse_appearance_colors parses `appearance colors <...>` arguments.
pub fn parse_appearance_colors(args []string) !ColorsCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl appearance colors status')
	}
	leaf := args[0]
	if leaf !in ['status', 'generate', 'm3', 'concept', 'export'] {
		return error('unknown colors subcommand: ${leaf}.\nRun: horneroctl appearance colors --help')
	}
	mut value := ''
	mut m3 := false
	mut dry_run := false
	mut yes := false
	mut call_args := []string{}
	mut sep := false
	mut i := 1
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
		if a == '--m3' {
			m3 = true
			i++
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl appearance colors ${leaf} --dry-run')
		}
		if leaf != 'concept' || value.len > 0 {
			return error('unexpected argument: ${a}.\nRun: horneroctl appearance colors --help')
		}
		value = a
		i++
	}
	if leaf == 'status' && (m3 || yes || call_args.len > 0 || value.len > 0) {
		return error('colors status takes no arguments.\nExample: horneroctl appearance colors status --dry-run')
	}
	if leaf == 'generate' && (call_args.len > 0 || value.len > 0) {
		return error('colors generate takes no passthrough arguments.\nExample: horneroctl appearance colors generate --m3 --dry-run')
	}
	if leaf == 'm3' && (m3 || value.len > 0) {
		return error('colors m3 passes through; --m3 belongs to generate.\nExample: horneroctl appearance colors generate --m3 --dry-run')
	}
	if leaf == 'concept' && value.len == 0 {
		return error('missing concept.\nExample: horneroctl appearance colors concept error')
	}
	if leaf == 'export' && (m3 || value.len > 0 || call_args.len > 0) {
		return error('colors export takes no arguments.\nExample: horneroctl appearance colors export')
	}
	return ColorsCmdOptions{
		leaf:      leaf
		value:     value
		m3:        m3
		dry_run:   dry_run
		yes:       yes
		call_args: call_args
	}
}

// AccentCmdOptions covers `appearance accent <show|set|clear>`.
// `show` is read-only; `set <hex>`/`clear` mutate (need --yes).
pub struct AccentCmdOptions {
pub:
	leaf    string // show | set | clear
	value   string
	dry_run bool
	yes     bool
}

// parse_appearance_accent parses `appearance accent <show|set|clear>` arguments.
pub fn parse_appearance_accent(args []string) !AccentCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl appearance accent show')
	}
	leaf := args[0]
	if leaf !in ['show', 'set', 'clear'] {
		return error('unknown accent subcommand: ${leaf}.\nRun: horneroctl appearance accent --help')
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
			return error('unknown flag: ${a}.\nExample: horneroctl appearance accent ${leaf} --dry-run')
		}
		if value.len > 0 {
			return error('unexpected argument: ${a}.\nRun: horneroctl appearance accent --help')
		}
		value = a
		i++
	}
	if leaf == 'show' && (value.len > 0 || yes) {
		return error('accent show takes no arguments.\nExample: horneroctl appearance accent show')
	}
	if leaf == 'set' && value.len == 0 {
		return error('missing hex color.\nExample: horneroctl appearance accent set "#8839ef" --dry-run')
	}
	if leaf == 'clear' && value.len > 0 {
		return error('accent clear takes no value.\nExample: horneroctl appearance accent clear --dry-run')
	}
	return AccentCmdOptions{
		leaf:    leaf
		value:   value
		dry_run: dry_run
		yes:     yes
	}
}

// NightModeCmdOptions covers `appearance night-mode <verb>`: status and
// the bar helpers are read-only; toggle/on/off mutate (need --yes).
pub struct NightModeCmdOptions {
pub:
	leaf    string // status | toggle | auto | on | enable | off | disable | status-icon | status-text | backends
	dry_run bool
	yes     bool
}

// parse_appearance_night_mode parses `appearance night-mode <verb>` arguments.
pub fn parse_appearance_night_mode(args []string) !NightModeCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl appearance night-mode status')
	}
	leaf := args[0]
	if leaf !in ['status', 'toggle', 'auto', 'on', 'enable', 'off', 'disable', 'status-icon',
		'status-text', 'backends'] {
		return error('unknown night-mode subcommand: ${leaf}.\nRun: horneroctl appearance night-mode --help')
	}
	mut dry_run := false
	mut yes := false
	for i in 1 .. args.len {
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
			return error('unknown flag: ${a}.\nExample: horneroctl appearance night-mode status --dry-run')
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl appearance night-mode --help')
	}
	if leaf in ['status', 'status-icon', 'status-text', 'backends'] && yes {
		return error('night-mode ${leaf} takes no --yes.\nExample: horneroctl appearance night-mode ${leaf}')
	}
	return NightModeCmdOptions{
		leaf:    leaf
		dry_run: dry_run
		yes:     yes
	}
}

// GtkCmdOptions covers `appearance gtk <verb>`: the dots-gtk-theme verbs
// (list, current, apply, set-icons, color-scheme, sync-color-scheme,
// detect, theme, auto, icons, info), all native.
pub struct GtkCmdOptions {
pub:
	leaf    string
	value   string
	extra   []string
	dry_run bool
	yes     bool
}

// parse_appearance_gtk parses `appearance gtk <verb>` arguments.
pub fn parse_appearance_gtk(args []string) !GtkCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl appearance gtk list')
	}
	leaf := args[0]
	if leaf !in ['list', 'current', 'current-icon', 'current-color-scheme', 'apply', 'set-icons',
		'color-scheme', 'sync-color-scheme', 'detect', 'theme', 'auto', 'icons', 'info', 'select'] {
		return error('unknown gtk subcommand: ${leaf}.\nRun: horneroctl appearance gtk --help')
	}
	mut value := ''
	mut extra := []string{}
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
			return error('unknown flag: ${a}.\nExample: horneroctl appearance gtk ${leaf} --dry-run')
		}
		if value.len == 0 {
			value = a
		} else {
			extra << a
		}
		i++
	}
	if leaf in ['list', 'icons', 'current', 'current-icon', 'current-color-scheme', 'sync-color-scheme',
		'auto']
		&& (value.len > 0 || extra.len > 0) {
		return error('gtk ${leaf} takes no value.\nExample: horneroctl appearance gtk ${leaf} --dry-run')
	}
	if leaf == 'select' && (value.len > 0 || extra.len > 0) {
		return error('gtk select takes no value.\nExample: horneroctl appearance gtk select --dry-run')
	}
	if leaf in ['apply', 'set-icons', 'color-scheme', 'info'] && value.len == 0 {
		return error('missing value.\nExample: horneroctl appearance gtk ${leaf} <value> --dry-run')
	}
	if leaf == 'apply' && extra.len > 2 {
		return error('too many values.\nExample: horneroctl appearance gtk apply Orchis-Dark Numix-Circle prefer-dark --dry-run')
	}
	return GtkCmdOptions{
		leaf:    leaf
		value:   value
		extra:   extra
		dry_run: dry_run
		yes:     yes
	}
}

// HyprlockCmdOptions covers `appearance hyprlock` (regenerate
// colors-hyprlock.conf from the live scheme).
pub struct HyprlockCmdOptions {
pub:
	wallpaper string
	dry_run   bool
	yes       bool
}

// parse_appearance_hyprlock parses `appearance hyprlock` arguments.
pub fn parse_appearance_hyprlock(args []string) !HyprlockCmdOptions {
	mut wallpaper := ''
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
		if a == '--wallpaper' {
			if i + 1 >= args.len || args[i + 1].starts_with('-') {
				return error('missing value for --wallpaper.\nExample: horneroctl appearance hyprlock --wallpaper ~/wall.jpg --dry-run')
			}
			wallpaper = args[i + 1]
			i += 2
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl appearance hyprlock --dry-run')
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl appearance hyprlock --help')
	}
	return HyprlockCmdOptions{
		wallpaper: wallpaper
		dry_run:   dry_run
		yes:       yes
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

// WelcomeCmdOptions covers
// `welcome <status|set-show-on-login|mark-seen|open|reset>`.
pub struct WelcomeCmdOptions {
pub:
	leaf     string
	value    string // set-show-on-login bool arg | open page | mark-seen --revision
	revision string // mark-seen --revision value
	dry_run  bool
	yes      bool
}

pub fn parse_welcome(args []string) !WelcomeCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl welcome status')
	}
	leaf := args[0]
	if leaf !in ['status', 'set-show-on-login', 'mark-seen', 'open', 'reset'] {
		return error('unknown welcome subcommand: ${leaf}.\nRun: horneroctl welcome --help')
	}
	mut value := ''
	mut revision := ''
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
		if a == '--revision' {
			if i + 1 >= args.len || args[i + 1].starts_with('-') {
				return error('missing value for --revision.\nExample: horneroctl welcome mark-seen --revision p1 --dry-run')
			}
			revision = args[i + 1]
			i += 2
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl welcome status')
		}
		if value.len > 0 {
			return error('unexpected argument: ${a}.\nRun: horneroctl welcome --help')
		}
		value = a
		i++
	}
	if leaf == 'status' && (value.len > 0 || revision.len > 0 || dry_run || yes) {
		return error('welcome status takes no arguments.\nExample: horneroctl welcome status')
	}
	if leaf == 'reset' && (value.len > 0 || revision.len > 0) {
		return error('welcome reset takes no arguments.\nExample: horneroctl welcome reset --dry-run')
	}
	if leaf == 'set-show-on-login' && value.len == 0 {
		return error('missing value (true|false).\nExample: horneroctl welcome set-show-on-login false --dry-run')
	}
	if leaf == 'set-show-on-login' && revision.len > 0 {
		return error('welcome set-show-on-login takes no --revision.\nExample: horneroctl welcome set-show-on-login false --dry-run')
	}
	if leaf == 'mark-seen' && value.len > 0 {
		return error('welcome mark-seen takes --revision, not a positional.\nExample: horneroctl welcome mark-seen --revision p1 --dry-run')
	}
	if leaf == 'open' && revision.len > 0 {
		return error('welcome open takes no --revision.\nExample: horneroctl welcome open --dry-run')
	}
	if leaf == 'open' && yes {
		return error('welcome open needs no --yes (it only asks the shell).\nExample: horneroctl welcome open --dry-run')
	}
	return WelcomeCmdOptions{
		leaf:     leaf
		value:    value
		revision: revision
		dry_run:  dry_run
		yes:      yes
	}
}
