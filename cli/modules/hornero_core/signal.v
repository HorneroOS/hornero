module hornero_core

import os
import x.json2

// Hornero Signal appearance contract (RFC 0001 §3, mission
// HorneroOS/.github#28). A theme pack is a schema-v2 `theme.json` with the
// fixed `palette` role set plus a 16-colour `terminal` array. Applying one
// writes the live scheme the shell watches:
//
//   ${XDG_STATE_HOME:-~/.local/state}/hornero/signal/scheme.json
//   {"schemaVersion":2,"id":...,"mode":...,"palette":{role:"#RRGGBB"},"terminal":[16]}
//
// Colours come from the selected theme only. Wallpapers never recolour.

// signal_schema_version is the only accepted theme/scheme schema version.
pub const signal_schema_version = 2

// signal_default_theme_id is the factory default theme.
pub const signal_default_theme_id = 'hornero-signal-night'

// signal_builtin_theme_ids are the first-party Signal themes, default first.
pub const signal_builtin_theme_ids = ['hornero-signal-night', 'hornero-signal-day',
	'hornero-signal-contrast']

// signal_roles is the exact palette role set, in contract order.
pub const signal_roles = ['ground', 'sunken', 'base', 'panel', 'raised', 'lifted', 'ink', 'inkMuted',
	'inkFaint', 'rule', 'ruleStrong', 'signal', 'onSignal', 'signalWell', 'onSignalWell', 'cue',
	'onCue', 'cueWell', 'onCueWell', 'phosphor', 'onPhosphor', 'phosphorWell', 'onPhosphorWell',
	'alert', 'onAlert', 'alertWell', 'onAlertWell', 'inverse', 'onInverse', 'inverseSignal', 'scrim',
	'shadow', 'focus']

// signal_optional_roles are palette roles a theme may omit, with the role
// they fall back to (RFC 0001 amendment 2: `glow` defaults to `signal`).
pub const signal_optional_roles = {
	'glow': 'signal'
}

// signal_retired_theme_ids maps removed theme ids to their Signal
// replacement. It is used only by the one-shot migration of persisted
// selections; typed ids are never silently rewritten.
const signal_retired_theme_ids = {
	'hornero-dark':  'hornero-signal-night'
	'hornero-light': 'hornero-signal-day'
	'hornero-199x':  'hornero-signal-night'
	'neon-city':     'hornero-signal-night'
	'vapor-dreams':  'hornero-signal-night'
	'soft-morning':  'hornero-signal-night'
	'warm-sunset':   'hornero-signal-night'
}

// SignalTheme is one validated schema-v2 theme (or live scheme).
pub struct SignalTheme {
pub:
	id       string
	name     string
	mode     string // dark | light
	palette  map[string]string
	terminal []string
}

// role returns one palette role; an omitted optional role resolves to its
// fallback role. Required roles are always present after validation.
pub fn (t SignalTheme) role(name string) string {
	if v := t.palette[name] {
		return v
	}
	if fallback := signal_optional_roles[name] {
		return t.palette[fallback] or { '' }
	}
	return ''
}

// signal_scheme_file is the live scheme location (WRITE TARGET).
pub fn signal_scheme_file() string {
	base := xdg_or_home('XDG_STATE_HOME', '.local/state')
	return os.join_path(base, 'hornero', 'signal', 'scheme.json')
}

// signal_hex validates `#RRGGBB` and returns it upper-cased.
pub fn signal_hex(raw string) !string {
	if raw.len != 7 || !raw.starts_with('#') {
		return error('want #RRGGBB, got "${raw}"')
	}
	parse_hex6(raw[1..]) or { return error('want #RRGGBB, got "${raw}"') }
	return raw.to_upper()
}

// retired_theme_replacement reports the Signal replacement for a removed
// theme id, or '' when the id is current.
pub fn retired_theme_replacement(id string) string {
	return signal_retired_theme_ids[id] or { '' }
}

// migrate_theme_id maps a persisted theme id once: retired ids become their
// Signal equivalent, an empty id becomes the factory default.
pub fn migrate_theme_id(id string) string {
	if id.len == 0 {
		return signal_default_theme_id
	}
	replacement := retired_theme_replacement(id)
	return if replacement.len > 0 { replacement } else { id }
}

// parse_signal_theme validates one decoded theme or scheme document.
// `want_id` (when non-empty) must equal the document id.
pub fn parse_signal_theme(want_id string, m map[string]json2.Any) !SignalTheme {
	label := if want_id.len > 0 { want_id } else { 'scheme' }
	version := m['schemaVersion'] or {
		return error('${label}: missing schemaVersion (want ${signal_schema_version})')
	}
	if version.str() != signal_schema_version.str() {
		return error('${label}: schemaVersion ${version.str()} is not a Hornero Signal theme (want ${signal_schema_version})')
	}
	id := (m['id'] or { json2.Any('') }).str()
	if id.len == 0 {
		return error('${label}: missing id')
	}
	if want_id.len > 0 && id != want_id {
		return error('${label}: id "${id}" does not match its directory')
	}
	mode := (m['mode'] or { json2.Any('') }).str()
	if mode !in ['dark', 'light'] {
		return error('${label}: mode must be dark or light, got "${mode}"')
	}
	raw_palette := m['palette'] or { return error('${label}: missing palette') }
	if raw_palette !is map[string]json2.Any {
		return error('${label}: palette must be an object')
	}
	pal_map := raw_palette.as_map()
	mut palette := map[string]string{}
	for role in signal_roles {
		value := pal_map[role] or { return error('${label}: palette is missing role ${role}') }
		palette[role] = signal_hex(value.str()) or {
			return error('${label}: palette.${role}: ${err.msg()}')
		}
	}
	for key, value in pal_map {
		if key in signal_roles {
			continue
		}
		if key !in signal_optional_roles {
			return error('${label}: palette has unknown role ${key}')
		}
		palette[key] = signal_hex(value.str()) or {
			return error('${label}: palette.${key}: ${err.msg()}')
		}
	}
	raw_terminal := m['terminal'] or { return error('${label}: missing terminal') }
	if raw_terminal !is []json2.Any {
		return error('${label}: terminal must be an array of 16 colours')
	}
	term_arr := raw_terminal.as_array()
	if term_arr.len != 16 {
		return error('${label}: terminal must hold 16 colours, got ${term_arr.len}')
	}
	mut terminal := []string{}
	for i, value in term_arr {
		terminal << signal_hex(value.str()) or {
			return error('${label}: terminal[${i}]: ${err.msg()}')
		}
	}
	name := (m['name'] or { json2.Any(id) }).str()
	return SignalTheme{
		id:       id
		name:     if name.len > 0 { name } else { id }
		mode:     mode
		palette:  palette
		terminal: terminal
	}
}

// load_signal_theme reads one installed pack canonical-first and validates
// it as a schema-v2 Signal theme.
pub fn load_signal_theme(id string) !SignalTheme {
	m := read_pack_map(id)!
	return parse_signal_theme(id, m)
}

// signal_scheme_json renders the live scheme document (stable key order).
pub fn signal_scheme_json(t SignalTheme) string {
	mut palette := map[string]json2.Any{}
	for role in signal_roles {
		palette[role] = json2.Any(t.role(role))
	}
	// Optional roles are written only when the theme defines them.
	for role, _ in signal_optional_roles {
		if v := t.palette[role] {
			palette[role] = json2.Any(v)
		}
	}
	mut terminal := []json2.Any{}
	for c in t.terminal {
		terminal << json2.Any(c)
	}
	doc := {
		'schemaVersion': json2.Any(signal_schema_version)
		'id':            json2.Any(t.id)
		'mode':          json2.Any(t.mode)
		'palette':       json2.Any(palette)
		'terminal':      json2.Any(terminal)
	}
	return json2.encode(doc, escape_unicode: true) + '\n'
}

// write_file_atomic replaces path with content through a same-directory
// temp file plus rename, so readers never observe a partial file.
pub fn write_file_atomic(path string, content string) ! {
	os.mkdir_all(os.dir(path)) or { return error('cannot create ${os.dir(path)}: ${err.msg()}') }
	tmp := os.join_path(os.dir(path), '.${os.file_name(path)}.tmp.${os.getpid()}')
	os.write_file(tmp, content) or {
		os.rm(tmp) or {}
		return error('cannot write ${tmp}: ${err.msg()}')
	}
	os.rename(tmp, path) or {
		os.rm(tmp) or {}
		return error('cannot replace ${path}: ${err.msg()}')
	}
}

// write_signal_scheme atomically writes the live scheme for one theme.
pub fn write_signal_scheme(t SignalTheme) !string {
	path := signal_scheme_file()
	write_file_atomic(path, signal_scheme_json(t))!
	return path
}

// read_signal_scheme loads and validates the live scheme file.
pub fn read_signal_scheme() !SignalTheme {
	path := signal_scheme_file()
	raw := os.read_file(path) or { return error('live scheme missing at ${path}') }
	parsed := json2.decode[json2.Any](raw) or {
		return error('live scheme at ${path} is not JSON')
	}
	if parsed is map[string]json2.Any {
		return parse_signal_theme('', parsed) or {
			return error('live scheme at ${path} is invalid: ${err.msg()}')
		}
	}
	return error('live scheme at ${path} is not an object')
}

// SignalSelection is the resolved current theme id plus where it came from.
pub struct SignalSelection {
pub:
	id            string
	source        string // scheme | state | shell | default
	migrated_from string // retired id the persisted value still names, else ''
}

// state_theme_value reads the persisted selection from the appearance state
// file: the current `theme` key, else the retired `name` key.
fn state_theme_value() string {
	raw := os.read_file(scheme_state_file()) or { return '' }
	parsed := json2.decode[json2.Any](raw) or { return '' }
	if parsed is map[string]json2.Any {
		m := parsed.as_map()
		for key in ['theme', 'name'] {
			if v := m[key] {
				s := v.str()
				if s.len > 0 && s != 'dynamic' {
					return s
				}
			}
		}
	}
	return ''
}

// shell_theme_value reads `appearance.theme` from the user shell.json.
fn shell_theme_value() string {
	raw := os.read_file(shell_config_file(resolve_paths())) or { return '' }
	parsed := json2.decode[json2.Any](raw) or { return '' }
	if parsed is map[string]json2.Any {
		appearance := parsed.as_map()['appearance'] or { return '' }
		if appearance is map[string]json2.Any {
			if v := appearance.as_map()['theme'] {
				return v.str()
			}
		}
	}
	return ''
}

// resolve_signal_selection finds the current theme without writing:
// the live scheme first, then persisted state, then the user shell
// setting, then the factory default. Retired ids resolve to their Signal
// replacement and report what they migrate from.
pub fn resolve_signal_selection() SignalSelection {
	if live := read_signal_scheme() {
		return SignalSelection{
			id:     live.id
			source: 'scheme'
		}
	}
	for source, value in {
		'state': state_theme_value()
		'shell': shell_theme_value()
	} {
		if value.len == 0 {
			continue
		}
		replacement := retired_theme_replacement(value)
		return SignalSelection{
			id:            if replacement.len > 0 { replacement } else { value }
			source:        source
			migrated_from: if replacement.len > 0 { value } else { '' }
		}
	}
	return SignalSelection{
		id:     signal_default_theme_id
		source: 'default'
	}
}

// LegacyMigration describes the one-shot rewrite of persisted selections.
pub struct LegacyMigration {
pub:
	changes []string
}

// plan_legacy_migration lists what migrate_legacy_appearance would change.
pub fn plan_legacy_migration() LegacyMigration {
	mut changes := []string{}
	state := scheme_state_file()
	if raw := os.read_file(state) {
		if m := json2.decode[map[string]json2.Any](raw) {
			old := (m['theme'] or { m['name'] or { json2.Any('') } }).str()
			if retired_theme_replacement(old).len > 0 {
				changes << '${state}: theme ${old} -> ${retired_theme_replacement(old)}'
			}
			for key in ['name', 'flavour', 'variant', 'mode'] {
				if key in m {
					changes << '${state}: drop retired key ${key}'
				}
			}
		}
	}
	shell := shell_theme_value()
	if retired_theme_replacement(shell).len > 0 {
		changes << '${shell_config_file(resolve_paths())}: appearance.theme ${shell} -> ${retired_theme_replacement(shell)}'
	}
	return LegacyMigration{
		changes: changes
	}
}

// migrate_legacy_appearance performs the one-shot data migration: retired
// theme ids in the appearance state and the user shell.json become their
// Signal equivalent, and retired scheme-state keys (name, flavour, variant,
// mode) are dropped. Every other key is preserved. Idempotent.
pub fn migrate_legacy_appearance() !LegacyMigration {
	plan := plan_legacy_migration()
	if plan.changes.len == 0 {
		return plan
	}
	state := scheme_state_file()
	if raw := os.read_file(state) {
		if mut m := json2.decode[map[string]json2.Any](raw) {
			old := (m['theme'] or { m['name'] or { json2.Any('') } }).str()
			for key in ['name', 'flavour', 'variant', 'mode'] {
				m.delete(key)
			}
			if old.len > 0 && old != 'dynamic' {
				m['theme'] = json2.Any(migrate_theme_id(old))
			}
			write_file_atomic(state, json2.encode(m, escape_unicode: true) + '\n')!
		}
	}
	shell := shell_theme_value()
	if retired_theme_replacement(shell).len > 0 {
		persist_shell_theme(migrate_theme_id(shell))!
	}
	return plan
}

// persist_state_theme records the selected theme in the appearance state
// file, preserving every other key (gtkColorScheme).
pub fn persist_state_theme(id string) !string {
	return update_state_json_fields({
		'theme': id
	}, {})
}

// persist_shell_theme sets `appearance.theme` in the user shell.json,
// preserving every other setting. A missing file is created with only that
// key (the shell merges user settings over its factory default). An
// unparseable file is never overwritten.
pub fn persist_shell_theme(id string) !string {
	path := shell_config_file(resolve_paths())
	mut doc := map[string]json2.Any{}
	if os.is_file(path) {
		raw := os.read_file(path) or { return error('cannot read ${path}: ${err.msg()}') }
		parsed := json2.decode[json2.Any](raw) or {
			return error('${path} is not valid JSON; not touching it')
		}
		if parsed !is map[string]json2.Any {
			return error('${path} is not a JSON object; not touching it')
		}
		doc = parsed.as_map()
	}
	mut appearance := map[string]json2.Any{}
	if existing := doc['appearance'] {
		if existing is map[string]json2.Any {
			appearance = existing.as_map()
		}
	}
	if current := appearance['theme'] {
		if current.str() == id {
			return path
		}
	}
	appearance['theme'] = json2.Any(id)
	doc['appearance'] = json2.Any(appearance)
	write_file_atomic(path, json2.encode(doc, escape_unicode: true) + '\n')!
	return path
}

// hypr_rgba renders `#RRGGBB` plus a hex alpha as Hyprland `rgba(rrggbbaa)`.
fn hypr_rgba(hex string, alpha string) string {
	return 'rgba(${hex.trim_left('#').to_lower()}${alpha})'
}

fn signal_header(t SignalTheme, comment string) string {
	return '${comment} Hornero Signal palette for ${t.id} — GENERATED by horneroctl from schema-v2 roles\n${comment} (mirrors HorneroOS/config lib/hornero/signal_render.py); do not hand-edit.'
}

// render_signal_hyprland_lua renders colors-hyprland.lua, loaded by
// HorneroOS/config desktop/hypr/hyprland.lua.d/smart-colors.lua: 1 px matte
// borders, active = signal, inactive = rule, locked groups = cue.
pub fn render_signal_hyprland_lua(t SignalTheme) string {
	return signal_header(t, '--') + '\n-- luacheck: globals hl\n' + 'hl.config({\n' +
		'\tgeneral = {\n' + '\t\tcol = {\n' +
		'\t\t\tactive_border = "${hypr_rgba(t.role('signal'), 'ee')}",\n' +
		'\t\t\tinactive_border = "${hypr_rgba(t.role('rule'), 'cc')}",\n' + '\t\t},\n' +
		'\t},\n' + '\tgroup = {\n' + '\t\tcol = {\n' +
		'\t\t\tborder_active = "${hypr_rgba(t.role('signal'), 'ee')}",\n' +
		'\t\t\tborder_inactive = "${hypr_rgba(t.role('ruleStrong'), 'aa')}",\n' +
		'\t\t\tborder_locked_active = "${hypr_rgba(t.role('cue'), 'ee')}",\n' +
		'\t\t\tborder_locked_inactive = "${hypr_rgba(t.role('cueWell'), 'aa')}",\n' +
		'\t\t},\n' + '\t\tgroupbar = {\n' + '\t\t\tcol = {\n' +
		'\t\t\t\tactive = "${hypr_rgba(t.role('signal'), 'ee')}",\n' +
		'\t\t\t\tinactive = "${hypr_rgba(t.role('raised'), 'ee')}",\n' +
		'\t\t\t\tlocked_active = "${hypr_rgba(t.role('cue'), 'ee')}",\n' +
		'\t\t\t\tlocked_inactive = "${hypr_rgba(t.role('cueWell'), 'ee')}",\n' + '\t\t\t},\n' +
		'\t\t},\n' + '\t},\n' + '\tdecoration = {\n' + '\t\tshadow = {\n' +
		'\t\t\tcolor = "${hypr_rgba(t.role('shadow'), '59')}",\n' + '\t\t},\n' + '\t},\n' +
		'})\n'
}

// render_signal_hyprland_conf renders the hyprlang colors-hyprland.conf
// with the same role mapping as the Lua module.
pub fn render_signal_hyprland_conf(t SignalTheme) string {
	mut out := signal_header(t, '#') + '\n\n'
	out += 'general {\n    col.active_border = ${hypr_rgba(t.role('signal'), 'ee')}\n'
	out += '    col.inactive_border = ${hypr_rgba(t.role('rule'), 'cc')}\n}\n\n'
	out += 'group {\n    col.border_active = ${hypr_rgba(t.role('signal'), 'ee')}\n'
	out += '    col.border_inactive = ${hypr_rgba(t.role('ruleStrong'), 'aa')}\n'
	out += '    col.border_locked_active = ${hypr_rgba(t.role('cue'), 'ee')}\n'
	out += '    col.border_locked_inactive = ${hypr_rgba(t.role('cueWell'), 'aa')}\n\n'
	out += '    groupbar {\n        col.active = ${hypr_rgba(t.role('signal'), 'ee')}\n'
	out += '        col.inactive = ${hypr_rgba(t.role('raised'), 'ee')}\n'
	out += '        col.locked_active = ${hypr_rgba(t.role('cue'), 'ee')}\n'
	out += '        col.locked_inactive = ${hypr_rgba(t.role('cueWell'), 'ee')}\n    }\n}\n'
	return out
}

// signal_hyprlock_vars are the hyprlang variables HorneroOS/config's
// desktop/hypr/hyprlock.conf reads (variable name, role).
const signal_hyprlock_vars = [['hs_ground', 'ground'], ['hs_sunken', 'sunken'], ['hs_panel', 'panel'],
	['hs_ink', 'ink'], ['hs_ink_muted', 'inkMuted'], ['hs_rule_strong', 'ruleStrong'],
	['hs_signal', 'signal'], ['hs_glow', 'glow'], ['hs_cue', 'cue'], ['hs_alert', 'alert']]

// render_signal_hyprlock_conf renders colors-hyprlock.conf: hyprlang
// variables only. hyprlock.conf sources it before declaring its widgets,
// so a refresh never duplicates widgets.
pub fn render_signal_hyprlock_conf(t SignalTheme) string {
	mut lines := [signal_header(t, '#')]
	for pair in signal_hyprlock_vars {
		lines << '$' + '${pair[0]} = ${hypr_rgba(t.role(pair[1]), 'ff')}'
	}
	return lines.join('\n') + '\n'
}

// render_signal_kitty renders a kitty colour file (the smart-color copy;
// kitty itself includes the pack's shipped `<id>.conf`).
pub fn render_signal_kitty(t SignalTheme) string {
	mut lines := [signal_header(t, '#'), 'background ${t.role('base')}', 'foreground ${t.role('ink')}',
		'cursor ${t.role('signal')}', 'cursor_text_color ${t.role('onSignal')}',
		'selection_background ${t.role('cueWell')}', 'selection_foreground ${t.role('onCueWell')}',
		'url_color ${t.role('cue')}', 'active_border_color ${t.role('signal')}',
		'inactive_border_color ${t.role('rule')}', 'active_tab_foreground ${t.role('ink')}',
		'active_tab_background ${t.role('raised')}', 'inactive_tab_foreground ${t.role('inkMuted')}',
		'inactive_tab_background ${t.role('base')}', 'tab_bar_background ${t.role('ground')}',
		'mark1_background ${t.role('signal')}', 'mark1_foreground ${t.role('onSignal')}']
	for i, c in t.terminal {
		lines << 'color${i} ${c}'
	}
	return lines.join('\n') + '\n'
}

const ansi_names = ['black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white']

// render_signal_alacritty renders the Alacritty `hornero-colors.toml` import.
pub fn render_signal_alacritty(t SignalTheme) string {
	mut lines := [signal_header(t, '#'), '[colors.primary]', 'background = "${t.role('base')}"',
		'foreground = "${t.role('ink')}"', '', '[colors.cursor]', 'cursor = "${t.role('signal')}"',
		'text = "${t.role('onSignal')}"', '', '[colors.selection]',
		'background = "${t.role('cueWell')}"', 'text = "${t.role('onCueWell')}"']
	for group, start in {
		'normal': 0
		'bright': 8
	} {
		lines << ''
		lines << '[colors.${group}]'
		for i, name in ansi_names {
			lines << '${name} = "${t.terminal[start + i]}"'
		}
	}
	return lines.join('\n') + '\n'
}

// render_signal_ghostty renders the Ghostty "Hornero Dynamic" theme.
pub fn render_signal_ghostty(t SignalTheme) string {
	mut lines := [signal_header(t, '#')]
	for i, c in t.terminal {
		lines << 'palette = ${i}=${c}'
	}
	lines << 'background = ${t.role('base')}'
	lines << 'foreground = ${t.role('ink')}'
	lines << 'cursor-color = ${t.role('signal')}'
	lines << 'cursor-text = ${t.role('onSignal')}'
	lines << 'selection-background = ${t.role('cueWell')}'
	lines << 'selection-foreground = ${t.role('onCueWell')}'
	return lines.join('\n') + '\n'
}

// signal_btop_keys maps btop's native theme keys to roles ('' = unset).
const signal_btop_keys = [['main_bg', ''], ['main_fg', 'ink'], ['title', 'ink'], ['hi_fg', 'signal'],
	['selected_bg', 'cueWell'], ['selected_fg', 'onCueWell'], ['inactive_fg', 'inkFaint'],
	['graph_text', 'inkMuted'], ['meter_bg', 'sunken'], ['proc_misc', 'cue'],
	['cpu_box', 'ruleStrong'], ['mem_box', 'ruleStrong'], ['net_box', 'ruleStrong'],
	['proc_box', 'ruleStrong'], ['div_line', 'rule'], ['temp_start', 'phosphor'],
	['temp_mid', 'signal'], ['temp_end', 'alert'], ['cpu_start', 'phosphor'], ['cpu_mid', 'signal'],
	['cpu_end', 'alert'], ['free_start', 'phosphorWell'], ['free_mid', 'phosphor'],
	['free_end', 'phosphor'], ['cached_start', 'cueWell'], ['cached_mid', 'cue'],
	['cached_end', 'cue'], ['available_start', 'phosphorWell'], ['available_mid', 'phosphor'],
	['available_end', 'cue'], ['used_start', 'signalWell'], ['used_mid', 'signal'],
	['used_end', 'alert'], ['download_start', 'cueWell'], ['download_mid', 'cue'],
	['download_end', 'ink'], ['upload_start', 'signalWell'], ['upload_mid', 'signal'],
	['upload_end', 'ink'], ['process_start', 'phosphor'], ['process_mid', 'signal'],
	['process_end', 'alert']]

// render_signal_btop renders the btop "Hornero Dynamic" theme (VU meters).
pub fn render_signal_btop(t SignalTheme) string {
	mut lines := [signal_header(t, '#')]
	for pair in signal_btop_keys {
		value := if pair[1].len > 0 { t.role(pair[1]) } else { '' }
		lines << 'theme[${pair[0]}]="${value}"'
	}
	return lines.join('\n') + '\n'
}

// render_signal_cava renders the Cava "Hornero Dynamic" colour fragment.
pub fn render_signal_cava(t SignalTheme) string {
	lines := [signal_header(t, '#'), '[color]', "background = '${t.role('base')}'",
		"foreground = '${t.role('ink')}'", 'gradient = 1', 'gradient_count = 4',
		"gradient_color_1 = '${t.role('phosphor')}'", "gradient_color_2 = '${t.role('cue')}'",
		"gradient_color_3 = '${t.role('signal')}'", "gradient_color_4 = '${t.role('alert')}'"]
	return lines.join('\n') + '\n'
}

// SignalOutputs are the derived colour files one apply writes. Paths match
// HorneroOS/config lib/hornero/apply-appearance.sh.
pub struct SignalOutputs {
pub:
	scheme         string
	hyprland_lua   string
	hyprlock_conf  string
	alacritty_toml string
	ghostty_theme  string
	btop_theme     string
	cava_theme     string
}

// signal_output_paths lists every derived file.
pub fn signal_output_paths() SignalOutputs {
	dir := smart_colors_dir()
	config_home := xdg_or_home('XDG_CONFIG_HOME', '.config')
	return SignalOutputs{
		scheme:         signal_scheme_file()
		hyprland_lua:   os.join_path(dir, 'colors-hyprland.lua')
		hyprlock_conf:  os.join_path(dir, 'colors-hyprlock.conf')
		alacritty_toml: os.join_path(config_home, 'alacritty', 'hornero-colors.toml')
		ghostty_theme:  os.join_path(config_home, 'ghostty', 'themes', 'Hornero Dynamic')
		btop_theme:     os.join_path(config_home, 'btop', 'themes', 'Hornero Dynamic.theme')
		cava_theme:     os.join_path(config_home, 'cava', 'themes', 'Hornero Dynamic')
	}
}

// write_signal_outputs renders everything first, then writes the live
// scheme (the shell reacts to it) followed by every derived file, each
// atomically.
pub fn write_signal_outputs(t SignalTheme) !SignalOutputs {
	out := signal_output_paths()
	files := [
		[out.scheme, signal_scheme_json(t)],
		[out.hyprland_lua, render_signal_hyprland_lua(t)],
		[out.hyprlock_conf, render_signal_hyprlock_conf(t)],
		[out.alacritty_toml, render_signal_alacritty(t)],
		[out.ghostty_theme, render_signal_ghostty(t)],
		[out.btop_theme, render_signal_btop(t)],
		[out.cava_theme, render_signal_cava(t)],
	]
	for f in files {
		write_file_atomic(f[0], f[1])!
	}
	return out
}

// signal_output_preview lists what write_signal_outputs would write.
pub fn signal_output_preview() []string {
	out := signal_output_paths()
	return [
		'would write ${out.scheme} (atomic)',
		'would write ${out.hyprland_lua}',
		'would write ${out.hyprlock_conf}',
		'would write ${out.alacritty_toml}',
		'would write ${out.ghostty_theme}',
		'would write ${out.btop_theme}',
		'would write ${out.cava_theme}',
	]
}
