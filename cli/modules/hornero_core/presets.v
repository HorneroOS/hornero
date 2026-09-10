module hornero_core

import os
import x.json2

// Shell-preset backend: installed preset files plus the current-preset
// pointer. Both are materialized files, so listing is native (no backend
// process needed).
//
// `dots-quickshell preset list/current` (dotfiles reference) reads the same
// paths: `$XDG_DATA_HOME/dots/shell-presets/*.json` for the catalogue
// (the shell repo vendors the same dataset under `presets/*.json` as its
// in-shell fallback) and `$XDG_STATE_HOME/dots/current-shell-preset` for
// the active pointer. Unparseable preset files are skipped, mirroring the
// backend.
//
// Later phase: `shell preset apply <name>` mutates the materialized
// shell.json through the dotfiles merger script; it stays out until that
// path is pinned behind a verified backend with --yes/--dry-run semantics.

// resolve_presets_dir locates installed shell presets.
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
	return os.join_path(base, 'dots', 'shell-presets')
}

// resolve_preset_state_file locates the active-preset pointer.
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
	return os.join_path(base, 'dots', 'current-shell-preset')
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
pub fn current_preset_name() string {
	raw := os.read_file(resolve_preset_state_file()) or { return '' }
	return raw.trim_space()
}

// list_presets returns installed presets sorted by name.
pub fn list_presets() ![]PresetEntry {
	dir := resolve_presets_dir()
	if !os.is_dir(dir) {
		return error('no presets installed at ${dir}. Set HORNERO_PRESETS_DIR.\nExample: horneroctl shell preset list --json')
	}
	current := current_preset_name()
	mut files := os.ls(dir)!
	files.sort()
	mut presets := []PresetEntry{}
	for f in files {
		if !f.ends_with('.json') {
			continue
		}
		raw := os.read_file(os.join_path(dir, f)) or { continue }
		parsed := json2.decode[json2.Any](raw) or { continue }
		if parsed is map[string]json2.Any {
			m := parsed.clone()
			name := f.all_before('.json')
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
			presets << PresetEntry{
				name:        name
				display:     title
				description: about
				position:    position
				active:      name == current
			}
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
