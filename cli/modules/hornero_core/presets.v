module hornero_core

import math
import os
import x.json2

// Shell-preset backend: installed preset files plus the current-preset
// pointer. Both are materialized files, so listing is native (no backend
// process needed).
//
// `dots-quickshell preset list/current` (dotfiles reference) reads the same
// catalogue: `$XDG_DATA_HOME/hornero/shell-presets/*.json` canonical
// (docs/PATH_CONTRACT.md row 2, WRITE TARGET) with the legacy
// `$XDG_DATA_HOME/dots/shell-presets/*.json` as read-only fallback
// (the shell repo vendors the same dataset under `presets/*.json` as its
// in-shell fallback); `$XDG_STATE_HOME/hornero/current-shell-preset` for
// the active pointer (row 3) with `$XDG_STATE_HOME/dots/...` fallback.
// Unparseable preset files are skipped, mirroring the backend.
//
// `shell preset apply <name>` mutates the materialized shell.json through
// the native merger below (a fresh V port of the dotfiles
// apply-shell-preset.py reference): validate, reset owned settings,
// deep-merge, atomic write, pointer update. Mutating: needs --yes;
// --dry-run only previews.

// resolve_presets_dir locates installed shell presets: the canonical
// `hornero/*` location (docs/PATH_CONTRACT.md row 2) and the WRITE TARGET.
// Override with HORNERO_PRESETS_DIR.
pub fn resolve_presets_dir() string {
	env := os.getenv('HORNERO_PRESETS_DIR')
	if env.len > 0 {
		return env
	}
	mut base := os.getenv('XDG_DATA_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.local', 'share')
	}
	return os.join_path(base, 'hornero', 'shell-presets')
}

// resolve_presets_dir_fallback is the legacy `dots/*` location (row 2).
// Reads only: nothing new is ever written here.
pub fn resolve_presets_dir_fallback() string {
	mut base := os.getenv('XDG_DATA_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.local', 'share')
	}
	return os.join_path(base, 'dots', 'shell-presets')
}

// resolve_presets_dirs_for_read lists the directories actually read,
// canonical-first. An explicit HORNERO_PRESETS_DIR override wins outright;
// otherwise every existing directory is returned so readers merge both
// locations with canonical precedence.
pub fn resolve_presets_dirs_for_read() []string {
	env := os.getenv('HORNERO_PRESETS_DIR')
	if env.len > 0 {
		return [env]
	}
	mut dirs := []string{}
	canonical := resolve_presets_dir()
	fallback := resolve_presets_dir_fallback()
	if os.is_dir(canonical) {
		dirs << canonical
	}
	if os.is_dir(fallback) && fallback != canonical {
		dirs << fallback
	}
	return dirs
}

// resolve_preset_state_file locates the active-preset pointer: the canonical
// `hornero/*` location (docs/PATH_CONTRACT.md row 3) and the WRITE TARGET.
// Override with HORNERO_PRESET_STATE_FILE.
pub fn resolve_preset_state_file() string {
	env := os.getenv('HORNERO_PRESET_STATE_FILE')
	if env.len > 0 {
		return env
	}
	mut base := os.getenv('XDG_STATE_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.local', 'state')
	}
	return os.join_path(base, 'hornero', 'current-shell-preset')
}

// resolve_preset_state_file_fallback is the legacy read-only location.
pub fn resolve_preset_state_file_fallback() string {
	mut base := os.getenv('XDG_STATE_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.local', 'state')
	}
	return os.join_path(base, 'dots', 'current-shell-preset')
}

// resolve_preset_state_file_for_read picks the pointer actually read:
// the explicit override, else canonical-first with legacy fallback.
pub fn resolve_preset_state_file_for_read() string {
	env := os.getenv('HORNERO_PRESET_STATE_FILE')
	if env.len > 0 {
		return env
	}
	canonical := resolve_preset_state_file()
	if os.is_file(canonical) {
		return canonical
	}
	fallback := resolve_preset_state_file_fallback()
	if os.is_file(fallback) {
		return fallback
	}
	return canonical
}

pub struct PresetEntry {
pub:
	name          string
	display       string
	description   string
	icon          string
	icon_material string
	position      string
	style         string
	active        bool
}

// current_preset_name returns the active preset id, or '' when unset.
// Canonical-first: the legacy pointer is read only when no canonical one
// exists.
pub fn current_preset_name() string {
	raw := os.read_file(resolve_preset_state_file_for_read()) or { return '' }
	return raw.trim_space()
}

// preset_entry_from_map builds one catalogue entry from a parsed preset.
// Field defaults mirror the `dots-quickshell preset list --json` backend
// (dotfiles reference): 📦 icon, widgets material icon, left/attached bar.
fn preset_entry_from_map(name string, m map[string]json2.Any, current string) PresetEntry {
	mut title := name
	if '_name' in m && m['_name'].str().len > 0 {
		title = m['_name'].str()
	}
	mut about := ''
	if '_description' in m {
		about = m['_description'].str()
	}
	mut icon := '📦'
	if '_icon' in m && m['_icon'].str().len > 0 {
		icon = m['_icon'].str()
	}
	mut icon_material := 'widgets'
	if '_iconMaterial' in m && m['_iconMaterial'].str().len > 0 {
		icon_material = m['_iconMaterial'].str()
	}
	mut position := 'left'
	mut style := 'attached'
	if 'bar' in m && m['bar'] is map[string]json2.Any {
		bar := m['bar'].as_map()
		if 'position' in bar && bar['position'].str().len > 0 {
			position = bar['position'].str()
		}
		if 'style' in bar && bar['style'].str().len > 0 {
			style = bar['style'].str()
		}
	}
	return PresetEntry{
		name:          name
		display:       title
		description:   about
		icon:          icon
		icon_material: icon_material
		position:      position
		style:         style
		active:        name == current
	}
}

// list_presets returns installed presets sorted by name.
// Canonical-first with legacy fallback: both directories are merged and a
// preset present in both resolves from the canonical side.
pub fn list_presets() ![]PresetEntry {
	dirs := resolve_presets_dirs_for_read().filter(os.is_dir(it))
	if dirs.len == 0 {
		explicit := resolve_presets_dirs_for_read()
		dir := if explicit.len > 0 { explicit[0] } else { resolve_presets_dir() }
		return error('no presets installed at ${dir}. Set HORNERO_PRESETS_DIR.\nExample: horneroctl shell preset list --json')
	}
	current := current_preset_name()
	mut seen := map[string]bool{}
	mut raws := map[string]string{}
	for dir in dirs {
		mut files := os.ls(dir) or { continue }
		files.sort()
		for f in files {
			if !f.ends_with('.json') {
				continue
			}
			name := f.all_before('.json')
			if name in seen {
				continue
			}
			raw := os.read_file(os.join_path(dir, f)) or { continue }
			parsed := json2.decode[json2.Any](raw) or { continue }
			if parsed is map[string]json2.Any {
				seen[name] = true
				raws[name] = raw
			}
		}
	}
	mut names := seen.keys()
	names.sort()
	mut presets := []PresetEntry{}
	for name in names {
		parsed := json2.decode[json2.Any](raws[name]) or { continue }
		if parsed is map[string]json2.Any {
			presets << preset_entry_from_map(name, parsed.clone(), current)
		}
	}
	return presets
}

// preset_list_report implements `shell preset list` (read-only).
pub fn preset_list_report() CommandResult {
	presets := list_presets() or { return fail_result('shell preset list', err.msg()) }
	mut lines := []string{}
	mut names := []string{}
	mut active := 'none'
	for p in presets {
		names << p.name
		mut line := '${p.name}: ${p.display}'
		if p.position.len > 0 {
			line += ' [${p.position}]'
		}
		if p.active {
			line += ' (active)'
			active = p.name
		}
		lines << line
	}
	lines << '${presets.len} preset(s), active: ${active}'
	return ok_result('shell preset list', lines.join('\n'), {
		'count':  presets.len.str()
		'names':  names.join(',')
		'active': active
	})
}

// preset_current_report implements `shell preset current` (read-only).
// No pointer file means `none`, mirroring the backend.
pub fn preset_current_report() CommandResult {
	name := current_preset_name()
	if name.len == 0 {
		return ok_result('shell preset current', 'none', {
			'preset': 'none'
		})
	}
	return ok_result('shell preset current', name, {
		'preset': name
	})
}

// preset_list_full_report implements `shell preset list --full`
// (read-only). The message is the full entry array as JSON — same shape
// as the retired `dots-quickshell preset list --json` backend the
// in-shell layout picker consumes: name, display, description, icon,
// iconMaterial, position, style, active.
pub fn preset_list_full_report() CommandResult {
	presets := list_presets() or { return fail_result('shell preset list', err.msg()) }
	mut names := []string{}
	mut active := 'none'
	mut arr := []json2.Any{}
	for p in presets {
		names << p.name
		if p.active {
			active = p.name
		}
		arr << json2.Any({
			'name':         json2.Any(p.name)
			'display':      json2.Any(p.display)
			'description':  json2.Any(p.description)
			'icon':         json2.Any(p.icon)
			'iconMaterial': json2.Any(p.icon_material)
			'position':     json2.Any(p.position)
			'style':        json2.Any(p.style)
			'active':       json2.Any(p.active)
		})
	}
	return ok_result('shell preset list', json2.encode(arr, escape_unicode: true), {
		'count':  presets.len.str()
		'names':  names.join(',')
		'active': active
		'format': 'full'
	})
}

// preset_owned_defaults_json mirrors OWNED_DEFAULTS in the dotfiles
// apply-shell-preset.py reference: owned settings reset before a preset
// merges over them, so stale keys from a previous preset never linger.
const preset_owned_defaults_json = '{"appearance":{"padding":{"scale":1.0},"rounding":{"scale":1.0},"spacing":{"scale":1.0},"transparency":{"base":0.85,"enabled":false,"layers":0.4}},"background":{"desktopClock":{"enabled":false},"visualiser":{"autoHide":true,"enabled":false}},"bar":{"floatingMargin":14,"perScreen":[],"persistent":true,"position":"left","scrollActions":{"brightness":true,"volume":true,"workspaces":true},"showOnHover":true,"sizes":{"innerWidth":40},"status":{"showAudio":false,"showBattery":true,"showBluetooth":true,"showKbLayout":false,"showLockStatus":true,"showMicrophone":false,"showNetwork":true,"showWifi":true},"style":"attached"},"border":{"frameEnabled":true},"notifs":{"defaultExpireTimeout":5000},"osd":{"hideDelay":2000}}'

// preset_owned_defaults decodes a fresh copy of the owned defaults.
fn preset_owned_defaults() map[string]json2.Any {
	parsed := json2.decode[json2.Any](preset_owned_defaults_json) or {
		return map[string]json2.Any{}
	}
	if parsed is map[string]json2.Any {
		return parsed.as_map()
	}
	return map[string]json2.Any{}
}

// preset_deep_merge merges override over base, skipping `_` metadata keys.
// Dict-over-dict recurses; anything else replaces. Result is a new map.
fn preset_deep_merge(base map[string]json2.Any, override map[string]json2.Any) map[string]json2.Any {
	mut out := map[string]json2.Any{}
	for k, v in base {
		out[k] = v
	}
	for k, v in override {
		if k.starts_with('_') {
			continue
		}
		if k in out && out[k] is map[string]json2.Any && v is map[string]json2.Any {
			out[k] = preset_deep_merge(out[k].as_map(), v.as_map())
		} else {
			out[k] = v
		}
	}
	return out
}

// preset_is_int reports whether v is an integer number (i64, or a finite
// whole f64). Booleans never count, mirroring the reference merger.
fn preset_is_int(v json2.Any) bool {
	if v is i64 {
		return true
	}
	if v is f64 {
		f := v.f64()
		return !math.is_nan(f) && !math.is_inf(f, 0) && f == math.floor(f)
	}
	return false
}

// preset_as_i64 reads an integer number validated by preset_is_int.
fn preset_as_i64(v json2.Any) i64 {
	if v is i64 {
		return v.i64()
	}
	return i64(v.f64())
}

// preset_is_num reports whether v is any finite number.
fn preset_is_num(v json2.Any) bool {
	if v is i64 {
		return true
	}
	if v is f64 {
		f := v.f64()
		return !math.is_nan(f) && !math.is_inf(f, 0)
	}
	return false
}

// preset_as_f64 reads a number validated by preset_is_num.
fn preset_as_f64(v json2.Any) f64 {
	if v is i64 {
		return f64(v.i64())
	}
	return v.f64()
}

// preset_validate normalizes a parsed preset against the owned defaults
// and checks every owned range. Returns the normalized preset (with the
// original `_name` kept) or a `<source>: <reason>` error.
fn preset_validate(preset map[string]json2.Any, source string) !map[string]json2.Any {
	name_ok := '_name' in preset && preset['_name'] is string
		&& preset['_name'].str().len > 0
	bar_ok := 'bar' in preset && preset['bar'] is map[string]json2.Any
	if !name_ok || !bar_ok {
		return error('${source}: missing _name or bar object')
	}
	mut normalized := preset_deep_merge(preset_owned_defaults(), preset)
	normalized['_name'] = preset['_name']
	bar := normalized['bar'].as_map()
	if bar['position'].str() !in ['left', 'right', 'top', 'bottom'] {
		return error('${source}: invalid bar.position')
	}
	if bar['style'].str() !in ['attached', 'floating', 'dock'] {
		return error('${source}: invalid bar.style')
	}
	if 'floatingMargin' !in bar || !preset_is_int(bar['floatingMargin'])
		|| preset_as_i64(bar['floatingMargin']) < 0
		|| preset_as_i64(bar['floatingMargin']) > 256 {
		return error('${source}: bar.floatingMargin must be an integer from 0 to 256')
	}
	hover_ok := 'showOnHover' in bar && bar['showOnHover'] is bool
	entries_ok := 'entries' in bar && bar['entries'] is []json2.Any
		&& bar['entries'].arr().len > 0
	if !hover_ok {
		return error('${source}: bar.showOnHover must be a boolean')
	}
	if !entries_ok {
		return error('${source}: bar.entries must be a non-empty list')
	}
	for entry in bar['entries'].arr() {
		entry_ok := entry is map[string]json2.Any
		mut em := map[string]json2.Any{}
		if entry_ok {
			em = entry.as_map()
		}
		id_ok := entry_ok && 'id' in em && em['id'] is string
		enabled_ok := entry_ok && 'enabled' in em && em['enabled'] is bool
		if !id_ok || !enabled_ok {
			return error('${source}: each bar entry requires a string id and boolean enabled')
		}
	}
	mut inner_width := i64(0)
	width_ok := 'sizes' in bar && bar['sizes'] is map[string]json2.Any
		&& 'innerWidth' in bar['sizes'].as_map()
		&& preset_is_int(bar['sizes'].as_map()['innerWidth'])
	if width_ok {
		inner_width = preset_as_i64(bar['sizes'].as_map()['innerWidth'])
	}
	if !width_ok || inner_width < 16 || inner_width > 256 {
		return error('${source}: bar.sizes.innerWidth must be an integer from 16 to 256')
	}
	border_ok := 'border' in normalized && normalized['border'] is map[string]json2.Any
		&& normalized['border'].as_map()['frameEnabled'] is bool
	if !border_ok {
		return error('${source}: border.frameEnabled must be a boolean')
	}
	appearance := normalized['appearance'].as_map()
	for name in ['rounding', 'padding', 'spacing'] {
		scale_ok := name in appearance && appearance[name] is map[string]json2.Any
			&& 'scale' in appearance[name].as_map()
			&& preset_is_num(appearance[name].as_map()['scale'])
		mut scale := 0.0
		if scale_ok {
			scale = preset_as_f64(appearance[name].as_map()['scale'])
		}
		if !scale_ok || scale < 0.25 || scale > 4 {
			return error('${source}: appearance.${name}.scale must be finite and between 0.25 and 4')
		}
	}
	transparency := appearance['transparency'].as_map()
	transparency_ok := 'enabled' in transparency && transparency['enabled'] is bool
	if !transparency_ok {
		return error('${source}: appearance.transparency.enabled must be a boolean')
	}
	for name in ['base', 'layers'] {
		val_ok := name in transparency && preset_is_num(transparency[name])
		mut val := 0.0
		if val_ok {
			val = preset_as_f64(transparency[name])
		}
		if !val_ok || val < 0 || val > 1 {
			return error('${source}: appearance.transparency.${name} must be finite and between 0 and 1')
		}
	}
	for pair in [['notifs', 'defaultExpireTimeout'], ['osd', 'hideDelay']] {
		section := pair[0]
		field := pair[1]
		timeout_ok := section in normalized
			&& normalized[section] is map[string]json2.Any
			&& field in normalized[section].as_map()
			&& preset_is_int(normalized[section].as_map()[field])
		mut timeout := i64(-1)
		if timeout_ok {
			timeout = preset_as_i64(normalized[section].as_map()[field])
		}
		if !timeout_ok || timeout < 0 || timeout > 600000 {
			return error('${source}: ${section}.${field} must be an integer from 0 to 600000')
		}
	}
	return normalized
}

// preset_find_file locates `<name>.json` canonical-first across the
// readable preset directories. Empty string when absent.
fn preset_find_file(name string) string {
	for dir in resolve_presets_dirs_for_read() {
		candidate := os.join_path(dir, '${name}.json')
		if os.is_file(candidate) {
			return candidate
		}
	}
	return ''
}

// preset_write_file_atomic writes content via temp-file rename,
// mirroring the state-file pattern. No lock file: single-user CLI.
fn preset_write_file_atomic(path string, content string) ! {
	os.mkdir_all(os.dir(path)) or { return error('cannot create ${os.dir(path)}: ${err}') }
	tmp := os.join_path(os.dir(path), '.${os.file_name(path)}.tmp')
	os.write_file(tmp, content) or { return error('cannot write ${tmp}: ${err}') }
	os.mv(tmp, path) or { return error('cannot move ${tmp} to ${path}: ${err}') }
}

pub struct PresetApplyOptions {
pub:
	name    string
	dry_run bool
	yes     bool
}

// preset_apply_report implements `shell preset apply <name>`: validate the
// preset, reset owned settings in shell.json, deep-merge, atomic write,
// update the active-preset pointer. Quickshell reloads on shell.json
// change, so no IPC is needed. Mutating: needs --yes; --dry-run validates
// and previews without writing.
pub fn preset_apply_report(opts PresetApplyOptions) CommandResult {
	if opts.name.len == 0 {
		return fail_result('shell preset apply', 'missing preset name.\nExample: horneroctl shell preset apply hornero-left --dry-run')
	}
	if !opts.yes && !opts.dry_run {
		return fail_result('shell preset apply', 'refusing to apply preset ${opts.name} without --yes (preview with --dry-run).\nExample: horneroctl shell preset apply ${opts.name} --dry-run')
	}
	preset_file := preset_find_file(opts.name)
	if preset_file.len == 0 {
		known := list_presets() or { []PresetEntry{} }
		mut names := []string{}
		for p in known {
			names << p.name
		}
		hint := if names.len > 0 {
			'Available presets: ${names.join(', ')}.\nList them: horneroctl shell preset list'
		} else {
			'No presets installed. Set HORNERO_PRESETS_DIR.\nExample: horneroctl shell preset list --json'
		}
		return fail_result('shell preset apply', 'preset not found: ${opts.name}\n${hint}')
	}
	raw := os.read_file(preset_file) or {
		return fail_result('shell preset apply', 'cannot read ${preset_file}: ${err}')
	}
	parsed := json2.decode[json2.Any](raw) or {
		return fail_result('shell preset apply', '${preset_file}: invalid JSON: ${err}')
	}
	parsed_ok := parsed is map[string]json2.Any
	if !parsed_ok {
		return fail_result('shell preset apply', '${preset_file}: preset must be a JSON object')
	}
	normalized := preset_validate(parsed.as_map(), preset_file) or {
		return fail_result('shell preset apply', err.msg())
	}
	conf := shell_config_file(resolve_paths())
	marker := resolve_preset_state_file()
	if opts.dry_run {
		return ok_result('shell preset apply', 'would run: merge ${preset_file} into ${conf}, write pointer ${marker}', {
			'preset':       opts.name
			'preset_file':  preset_file
			'config':       conf
			'marker':       marker
			'command_line': 'merge ${preset_file} into ${conf}'
			'dry_run':      'true'
		})
	}
	mut config := map[string]json2.Any{}
	if os.is_file(conf) {
		config_raw := os.read_file(conf) or {
			return fail_result('shell preset apply', 'cannot read ${conf}: ${err}')
		}
		config_parsed := json2.decode[json2.Any](config_raw) or {
			return fail_result('shell preset apply', '${conf}: invalid JSON: ${err}')
		}
		config_ok := config_parsed is map[string]json2.Any
		if !config_ok {
			return fail_result('shell preset apply', '${conf}: config must be a JSON object')
		}
		config = config_parsed.as_map()
	}
	reset := preset_deep_merge(config, preset_owned_defaults())
	merged := preset_deep_merge(reset, normalized)
	mut clean := map[string]json2.Any{}
	for k, v in merged {
		if k.starts_with('_') {
			continue
		}
		clean[k] = v
	}
	preset_write_file_atomic(conf, json2.encode(clean, escape_unicode: true) + '\n') or {
		return fail_result('shell preset apply', err.msg())
	}
	preset_write_file_atomic(marker, '${opts.name}\n') or {
		return fail_result('shell preset apply', err.msg())
	}
	display := if '_name' in normalized { normalized['_name'].str() } else { opts.name }
	return ok_result('shell preset apply', 'applied preset ${display} (${opts.name})', {
		'preset': opts.name
		'config': conf
		'marker': marker
	})
}
