module hornero_core

import os
import x.json2

// Keyboard backend: layout toggle/readout (Hyprland or X11, mirroring
// dots-keyboard-layout), the LXQt settings GUI opener (mirroring
// dots-keyboard-settings), and the keybindings readout (mirroring
// dots-keyboard-help).

// resolve_hyprctl_bin lives in hypr.v (same HORNERO_HYPRCTL_BIN contract);
// keyboard layout reuses it.

// resolve_setxkbmap_bin locates setxkbmap.
// Override with HORNERO_SETXKBMAP_BIN.
pub fn resolve_setxkbmap_bin() string {
	env := os.getenv('HORNERO_SETXKBMAP_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('setxkbmap')
}

// resolve_lxqt_bin locates lxqt-config-input.
// Override with HORNERO_LXQT_CONFIG_INPUT_BIN.
pub fn resolve_lxqt_bin() string {
	env := os.getenv('HORNERO_LXQT_CONFIG_INPUT_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('lxqt-config-input')
}

// resolve_keyboard_settings_bin locates the keyboard settings GUI:
// the HORNERO_KEYBOARD_SETTINGS_BIN pin (the dots-keyboard-settings
// cycle guard pins it at the real lxqt-config-input binary), else
// lxqt-config-input. The dots-keyboard-settings wrapper is retired.
pub fn resolve_keyboard_settings_bin() string {
	env := os.getenv('HORNERO_KEYBOARD_SETTINGS_BIN')
	if env.len > 0 {
		return env
	}
	return resolve_lxqt_bin()
}

// keyboard_settings_native_bin validates the opener: explicit paths
// must exist (a broken override fails closed instead of spawning
// async, which would hide the failure like bash `&` does).
fn keyboard_settings_native_bin() string {
	for cand in [resolve_keyboard_settings_bin(), resolve_lxqt_bin()] {
		if cand.len == 0 {
			continue
		}
		if !cand.contains('/') || os.is_file(cand) {
			return cand
		}
	}
	return ''
}

// detect_session mirrors dots-keyboard-layout session detection:
// Hyprland signature first, then Wayland, i3, else X11.
fn detect_session() string {
	if os.getenv('HYPRLAND_INSTANCE_SIGNATURE').len > 0 {
		return 'hyprland'
	}
	if os.getenv('WAYLAND_DISPLAY').len > 0 {
		return 'wayland'
	}
	if os.getenv('I3SOCK').len > 0 {
		return 'i3'
	}
	return 'x11'
}

// kb_layout_names mirrors the LAYOUT_NAMES display names in
// dots-keyboard-layout.
fn kb_layout_names() map[string]string {
	return {
		'us:':     'US'
		'us:intl': 'US International'
		'es:':     'Spanish'
		'latam:':  'Spanish LATAM'
		'gb:':     'UK'
		'de:':     'German'
		'fr:':     'French'
	}
}

// kb_preferred_layouts mirrors the PREFERRED_LAYOUTS toggle cycle in
// dots-keyboard-layout ("layout:variant", empty variant unqualified).
fn kb_preferred_layouts() []string {
	return ['us:', 'latam:']
}

// hypr_option_str mirrors one `hyprctl getoption -j` response object;
// unknown keys decode-ignored, so only `str` is declared.
pub struct HyprOptionStr {
pub:
	str string
}

// hypr_opt_str extracts the `str` value from `hyprctl getoption -j`
// output (or the plain `str: value` form).
fn hypr_opt_str(output string) string {
	trimmed := output.trim_space()
	if trimmed.starts_with('{') {
		opt := json2.decode[HyprOptionStr](trimmed) or { HyprOptionStr{} }
		if opt.str.len > 0 {
			return opt.str
		}
	}
	key := '"str"'
	i := output.index(key) or {
		j := output.index('str:') or { return '' }
		rest := output[j + 4..].trim_space()
		if rest.starts_with('"') {
			k := rest[1..].index('"') or { return '' }
			return rest[1..1 + k]
		}
		return rest.split(' ')[0].trim_space()
	}
	mut rest := output[i + key.len..].trim_space()
	if !rest.starts_with(':') {
		return ''
	}
	rest = rest[1..].trim_space()
	if rest.starts_with('"') {
		k := rest[1..].index('"') or { return '' }
		return rest[1..1 + k]
	}
	return rest.split(' ')[0].trim_space().trim('},')
}

// xkb_field extracts a `field: value` line from `setxkbmap -query`.
fn xkb_field(output string, field string) string {
	for line in output.split_into_lines() {
		t := line.trim_space()
		if t.starts_with(field + ':') {
			return t[field.len + 1..].trim_space()
		}
	}
	return ''
}

// current_layout returns the active layout name for a session kind.
fn current_layout(session string) !string {
	if session == 'hyprland' {
		bin := resolve_hyprctl_bin()
		if bin.len == 0 {
			return error('hyprctl not found on PATH. Set HORNERO_HYPRCTL_BIN.\nExample: horneroctl hardware keyboard layout --get')
		}
		rep := run_exec(ExecSpec{
			prog: bin
			args: ['getoption', 'input:kb_layout', '-j']
		})
		if !rep.ok {
			return error('hyprctl backend failed (exit ${rep.exit_code}):\n${rep.output}')
		}
		val := hypr_opt_str(rep.output)
		if val.len == 0 {
			return error('could not parse hyprctl layout output:\n${rep.output}')
		}
		return val
	}
	bin := resolve_setxkbmap_bin()
	if bin.len == 0 {
		return error('setxkbmap not found on PATH. Set HORNERO_SETXKBMAP_BIN.\nExample: horneroctl hardware keyboard layout --get')
	}
	rep := run_exec(ExecSpec{
		prog: bin
		args: ['-query']
	})
	if !rep.ok {
		return error('setxkbmap backend failed (exit ${rep.exit_code}):\n${rep.output}')
	}
	val := xkb_field(rep.output, 'layout')
	if val.len == 0 {
		return error('could not parse setxkbmap layout output:\n${rep.output}')
	}
	return val
}

// current_variant returns the active layout variant for a session kind
// ('' when unset).
fn current_variant(session string) !string {
	if session == 'hyprland' {
		bin := resolve_hyprctl_bin()
		if bin.len == 0 {
			return error('hyprctl not found on PATH. Set HORNERO_HYPRCTL_BIN.\nExample: horneroctl hardware keyboard layout --current')
		}
		rep := run_exec(ExecSpec{
			prog: bin
			args: ['getoption', 'input:kb_variant', '-j']
		})
		if !rep.ok {
			return error('hyprctl backend failed (exit ${rep.exit_code}):\n${rep.output}')
		}
		return hypr_opt_str(rep.output)
	}
	bin := resolve_setxkbmap_bin()
	if bin.len == 0 {
		return error('setxkbmap not found on PATH. Set HORNERO_SETXKBMAP_BIN.\nExample: horneroctl hardware keyboard layout --current')
	}
	rep := run_exec(ExecSpec{
		prog: bin
		args: ['-query']
	})
	if !rep.ok {
		return error('setxkbmap backend failed (exit ${rep.exit_code}):\n${rep.output}')
	}
	return xkb_field(rep.output, 'variant')
}

// layout_read_cmd names the layout probe for dry-run previews.
fn layout_read_cmd(session string) string {
	if session == 'hyprland' {
		bin := resolve_hyprctl_bin()
		prog := if bin.len > 0 { bin } else { 'hyprctl' }
		return command_line(prog, ['getoption', 'input:kb_layout', '-j'])
	}
	bin := resolve_setxkbmap_bin()
	prog := if bin.len > 0 { bin } else { 'setxkbmap' }
	return command_line(prog, ['-query'])
}

pub struct KeyboardLayoutOptions {
pub:
	mode    string // toggle | get | current
	dry_run bool
	yes     bool
}

// keyboard_layout_report implements `hardware keyboard layout`: toggle
// the preferred-layout cycle by default (mutating: needs --yes),
// --get prints the layout name, --current prints the full info readout.
pub fn keyboard_layout_report(opts KeyboardLayoutOptions) CommandResult {
	session := detect_session()
	if opts.mode == 'get' {
		if opts.dry_run {
			return ok_result('hardware keyboard layout', 'would run: ${layout_read_cmd(session)}',
				{
				'command_line': layout_read_cmd(session)
				'dry_run':      'true'
			})
		}
		cur := current_layout(session) or {
			return fail_result('hardware keyboard layout', err.msg())
		}
		return ok_result('hardware keyboard layout', cur, {
			'layout':  cur
			'session': session
		})
	}
	if opts.mode == 'current' {
		if opts.dry_run {
			return ok_result('hardware keyboard layout', 'would run: ${layout_read_cmd(session)}',
				{
				'command_line': layout_read_cmd(session)
				'dry_run':      'true'
			})
		}
		layout := current_layout(session) or {
			return fail_result('hardware keyboard layout', err.msg())
		}
		variant := current_variant(session) or {
			return fail_result('hardware keyboard layout', err.msg())
		}
		full := '${layout}:${variant}'
		display := kb_layout_names()[full] or {
			if variant.len > 0 { '${layout} (${variant})}' } else { layout }
		}
		mut lines := []string{}
		mut data := map[string]string{}
		lines << 'Session: ${session}'
		lines << 'Layout: ${layout}'
		data['session'] = session
		data['layout'] = layout
		if variant.len > 0 {
			lines << 'Variant: ${variant}'
			data['variant'] = variant
		}
		lines << 'Display: ${display}'
		data['display'] = display
		return ok_result('hardware keyboard layout', lines.join('\n'), data)
	}
	if opts.mode != 'toggle' {
		return fail_result('hardware keyboard layout', 'unknown keyboard layout mode: ${opts.mode}.\nRun: horneroctl hardware keyboard --help')
	}
	if !opts.yes && !opts.dry_run {
		return fail_result('hardware keyboard layout', 'refusing to switch layout without --yes (preview with --dry-run).\nExample: horneroctl hardware keyboard layout --dry-run')
	}
	if opts.dry_run {
		return ok_result('hardware keyboard layout', 'would run: ${layout_read_cmd(session)}, then apply next of us, latam',
			{
			'read_command': layout_read_cmd(session)
			'session':      session
			'dry_run':      'true'
		})
	}
	layout := current_layout(session) or {
		return fail_result('hardware keyboard layout', err.msg())
	}
	variant := current_variant(session) or {
		return fail_result('hardware keyboard layout', err.msg())
	}
	full := '${layout}:${variant}'
	prefs := kb_preferred_layouts()
	mut idx := -1
	for i, p in prefs {
		if p == full {
			idx = i
			break
		}
	}
	next := prefs[(idx + 1) % prefs.len]
	parts := next.split(':')
	nlayout := parts[0]
	nvariant := if parts.len > 1 { parts[1] } else { '' }
	if session == 'hyprland' {
		bin := resolve_hyprctl_bin()
		if bin.len == 0 {
			return fail_result('hardware keyboard layout', 'hyprctl not found on PATH. Set HORNERO_HYPRCTL_BIN.\nExample: horneroctl hardware keyboard layout --dry-run')
		}
		rep := run_exec(ExecSpec{
			prog: bin
			args: ['keyword', 'input:kb_layout', nlayout]
		})
		if !rep.ok {
			return fail_result('hardware keyboard layout', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
		}
		rep2 := run_exec(ExecSpec{
			prog: bin
			args: ['keyword', 'input:kb_variant', nvariant]
		})
		if !rep2.ok {
			return fail_result('hardware keyboard layout', 'backend failed (exit ${rep2.exit_code}):\n${rep2.output}')
		}
	} else {
		bin := resolve_setxkbmap_bin()
		if bin.len == 0 {
			return fail_result('hardware keyboard layout', 'setxkbmap not found on PATH. Set HORNERO_SETXKBMAP_BIN.\nExample: horneroctl hardware keyboard layout --dry-run')
		}
		args := if nvariant.len > 0 { [nlayout, nvariant] } else { [nlayout] }
		rep := run_exec(ExecSpec{
			prog: bin
			args: args
		})
		if !rep.ok {
			return fail_result('hardware keyboard layout', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
		}
	}
	names := kb_layout_names()
	display := names[next] or {
		if nvariant.len > 0 { '${nlayout} (${nvariant})' } else { nlayout }
	}
	nb := resolve_notify_bin()
	if nb.len > 0 {
		run_exec(ExecSpec{
			prog: nb
			args: ['-u', 'low', '-i', 'input-keyboard', 'Keyboard Layout', 'Switched to ${display}']
		})
	}
	return ok_result('hardware keyboard layout', 'Switched to ${display}', {
		'layout':  nlayout
		'variant': nvariant
		'display': display
		'session': session
	})
}

pub struct KeyboardSettingsOptions {
pub:
	dry_run bool
}

// keyboard_settings_report implements `hardware keyboard settings`: open
// the LXQt keyboard configuration GUI natively (detached, like the
// script's `lxqt-config-input &`). Opening a GUI needs no --yes
// (config gui precedent); --dry-run only previews.
pub fn keyboard_settings_report(opts KeyboardSettingsOptions) CommandResult {
	bin := keyboard_settings_native_bin()
	if bin.len == 0 {
		if opts.dry_run {
			return ok_result('hardware keyboard settings', 'would run: lxqt-config-input',
				{
				'command_line': 'lxqt-config-input'
				'dry_run':      'true'
			})
		}
		return fail_result('hardware keyboard settings', 'lxqt-config-input not installed. Install it with: sudo pacman -S lxqt-config-input')
	}
	if opts.dry_run {
		rep := spawn_detached(bin, [], true)
		return ok_result('hardware keyboard settings', 'would run: ${rep.command_line}',
			{
			'command_line': rep.command_line
			'dry_run':      'true'
		})
	}
	rep := spawn_detached(bin, [], false)
	if rep.ok {
		return ok_result('hardware keyboard settings', 'keyboard settings opened', {
			'command_line': rep.command_line
		})
	}
	return fail_result('hardware keyboard settings', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
}

// keybindings_path resolves the Hyprland keybindings file: explicit
// HORNERO_KEYBINDINGS_FILE override, else the XDG config path the shim
// reads.
fn keybindings_path() string {
	env := os.getenv('HORNERO_KEYBINDINGS_FILE')
	if env.len > 0 {
		return env
	}
	mut base := os.getenv('XDG_CONFIG_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.config')
	}
	return os.join_path(base, 'hypr', 'hyprland.conf.d', 'keybindings.conf')
}

// is_keybindings_sep matches the `# ===` section separator lines.
fn is_keybindings_sep(line string) bool {
	if !line.starts_with('# ') {
		return false
	}
	rest := line[2..]
	if rest.len == 0 {
		return false
	}
	for c in rest {
		if c != `=` {
			return false
		}
	}
	return true
}

// split_bind_rest strips a `bind[a-z]* = ` prefix, returning the fields
// that follow (or '' when the line is no bind line).
fn split_bind_rest(line string) string {
	if !line.starts_with('bind') {
		return ''
	}
	rest := line[4..]
	mut j := 0
	for j < rest.len && rest[j] >= `a` && rest[j] <= `z` {
		j++
	}
	tail := rest[j..]
	if !tail.starts_with(' = ') {
		return ''
	}
	return tail[3..]
}

// parse_keybindings_text ports the dots-keyboard-help awk parser: 3-line
// `# ===` headers set the category, bind lines render as
// `[cat] mods + key -> action` with $mainMod rewritten to SUPER.
fn parse_keybindings_text(text string) []string {
	mut out := []string{}
	mut stage := 0
	mut candidate := ''
	mut cat := ''
	for raw in text.split_into_lines() {
		line := raw
		if is_keybindings_sep(line) {
			if stage == 2 {
				cat = candidate
			}
			stage = 1
			continue
		}
		if line.starts_with('# ') {
			if stage == 1 {
				candidate = line[2..]
				stage = 2
			} else {
				stage = 0
			}
			continue
		}
		rest := split_bind_rest(line)
		if rest.len == 0 {
			stage = 0
			continue
		}
		stage = 0
		parts := rest.split(',')
		if parts.len < 3 {
			continue
		}
		mods := parts[0].trim_space()
		key := parts[1].trim_space()
		idx := rest.index(parts[2]) or { continue }
		action := rest[idx..].trim_space()
		mut shown := mods.replace('\$mainMod', 'SUPER')
		mut bits := []string{}
		for b in shown.split(' ') {
			if b.len > 0 {
				bits << b
			}
		}
		shown = bits.join(' + ')
		if cat.len > 0 {
			out << '[${cat}] ${shown} + ${key} -> ${action}'
		} else {
			out << '${shown} + ${key} -> ${action}'
		}
	}
	return out
}

// quickshell_running mirrors the dots-keyboard-help quickshell branch.
fn quickshell_running() bool {
	pg := find_on_path('pgrep')
	if pg.len == 0 {
		return false
	}
	r1 := run_exec(ExecSpec{
		prog: pg
		args: ['-x', 'qs']
	})
	if r1.ok {
		return true
	}
	r2 := run_exec(ExecSpec{
		prog: pg
		args: ['-x', 'quickshell']
	})
	return r2.ok
}

pub struct KeyboardKeysOptions {
pub:
	category string
	search   string
	dry_run  bool
}

// keyboard_keys_report implements `hardware keyboard keys`: when a
// quickshell is running (and DOTS_BYPASS_QUICKSHELL is unset) it asks the
// settings GUI for the system pane, else it parses the Hyprland
// keybindings file with optional category/search filters. Read-only;
// --dry-run only previews.
pub fn keyboard_keys_report(opts KeyboardKeysOptions) CommandResult {
	if os.getenv('DOTS_BYPASS_QUICKSHELL') != '1' && quickshell_running() {
		bin := resolve_settings_gui_bin()
		args := ['--pane=system', 'menu']
		if bin.len == 0 {
			if opts.dry_run {
				return ok_result('hardware keyboard keys', 'would run: dots-settings-gui --pane=system menu',
					{
					'command_line': 'dots-settings-gui --pane=system menu'
					'dry_run':      'true'
				})
			}
			return fail_result('hardware keyboard keys', 'quickshell is running but the settings-gui backend is missing. Set HORNERO_SETTINGS_GUI_BIN or DOTS_BYPASS_QUICKSHELL=1.\nExample: horneroctl hardware keyboard keys --dry-run')
		}
		rep := run_exec(ExecSpec{
			prog:    bin
			args:    args
			dry_run: opts.dry_run
		})
		if opts.dry_run {
			return ok_result('hardware keyboard keys', 'would run: ${rep.command_line}',
				{
				'command_line': rep.command_line
				'dry_run':      'true'
			})
		}
		if rep.ok {
			return ok_result('hardware keyboard keys', 'settings opened (quickshell running)',
				{
				'command_line': rep.command_line
			})
		}
		return fail_result('hardware keyboard keys', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
	}
	path := keybindings_path()
	if opts.dry_run {
		return ok_result('hardware keyboard keys', 'would parse: ${path}', {
			'file':    path
			'dry_run': 'true'
		})
	}
	text := os.read_file(path) or {
		return fail_result('hardware keyboard keys', '[ERROR] Keybindings configuration not found (${path}).')
	}
	mut lines := parse_keybindings_text(text)
	if opts.category.len > 0 {
		c := opts.category.to_lower()
		mut kept := []string{}
		for l in lines {
			if l.to_lower().contains('[' + c) {
				kept << l
			}
		}
		lines = kept.clone()
	}
	if opts.search.len > 0 {
		s := opts.search.to_lower()
		mut kept := []string{}
		for l in lines {
			if l.to_lower().contains(s) {
				kept << l
			}
		}
		lines = kept.clone()
	}
	if lines.len == 0 {
		return fail_result('hardware keyboard keys', '[WARN] No keybindings found')
	}
	return ok_result('hardware keyboard keys', lines.join('\n'), {
		'file':  path
		'count': '${lines.len}'
	})
}
