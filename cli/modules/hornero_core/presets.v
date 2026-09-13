module hornero_core

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
// Later phase: `shell preset apply <name>` mutates the materialized
// shell.json through the dotfiles merger script; it stays out until that
// path is pinned behind a verified backend with --yes/--dry-run semantics.

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
	name        string
	display     string
	description string
	position    string
	active      bool
}

// current_preset_name returns the active preset id, or '' when unset.
// Canonical-first: the legacy pointer is read only when no canonical one
// exists.
pub fn current_preset_name() string {
	raw := os.read_file(resolve_preset_state_file_for_read()) or { return '' }
	return raw.trim_space()
}

// preset_entry_from_map builds one catalogue entry from a parsed preset.
fn preset_entry_from_map(name string, m map[string]json2.Any, current string) PresetEntry {
	mut title := name
	if '_name' in m && m['_name'].str().len > 0 {
		title = m['_name'].str()
	}
	mut about := ''
	if '_description' in m {
		about = m['_description'].str()
	}
	mut position := ''
	if 'bar' in m && m['bar'] is map[string]json2.Any {
		bar := m['bar'].as_map()
		if 'position' in bar {
			position = bar['position'].str()
		}
	}
	return PresetEntry{
		name:        name
		display:     title
		description: about
		position:    position
		active:      name == current
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
