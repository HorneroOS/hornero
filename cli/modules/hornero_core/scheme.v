module hornero_core

import os
import x.json2

// Scheme state: the live Hornero Signal scheme (signal.v) plus the
// persisted appearance state file, which records the selected theme and
// the independent GTK color-scheme policy.

pub struct SchemeState {
pub:
	theme            string
	theme_source     string
	mode             string
	gtk_color_scheme string
	state_file       string
	scheme_file      string
	state_present    bool
	scheme_present   bool
	scheme_valid     bool
	scheme_error     string
}

// scheme_state_file is the canonical appearance state location
// (docs/PATH_CONTRACT.md) and the WRITE TARGET.
pub fn scheme_state_file() string {
	base := xdg_or_home('XDG_STATE_HOME', '.local/state')
	return os.join_path(base, 'hornero', 'scheme', 'state.json')
}

// smart_colors_dir is the derived colour-file cache (WRITE TARGET):
// Hyprland, hyprlock, kitty and the smart-color files live here.
// Override with HORNERO_SMART_COLORS_DIR.
pub fn smart_colors_dir() string {
	env := os.getenv('HORNERO_SMART_COLORS_DIR')
	if env.len > 0 {
		return env
	}
	base := xdg_or_home('XDG_CACHE_HOME', '.cache')
	return os.join_path(base, 'hornero', 'smart-colors')
}

fn scheme_json_field(path string, key string) string {
	raw := os.read_file(path) or { return '' }
	parsed := json2.decode[json2.Any](raw) or { return '' }
	if parsed is map[string]json2.Any {
		if value := parsed[key] {
			return value.str()
		}
	}
	return ''
}

// read_scheme_state loads the live scheme (validated) and the persisted
// selection without writing anything. Mode comes from the live scheme.
pub fn read_scheme_state() SchemeState {
	state := scheme_state_file()
	scheme := signal_scheme_file()
	sel := resolve_signal_selection()
	mut mode := ''
	mut valid := false
	mut scheme_error := ''
	if live := read_signal_scheme() {
		mode = live.mode
		valid = true
	} else {
		scheme_error = err.msg()
	}
	policy := scheme_json_field(state, 'gtkColorScheme')
	return SchemeState{
		theme:            sel.id
		theme_source:     sel.source
		mode:             mode
		gtk_color_scheme: if policy.len > 0 { policy } else { 'follow' }
		state_file:       state
		scheme_file:      scheme
		state_present:    os.is_file(state)
		scheme_present:   os.is_file(scheme)
		scheme_valid:     valid
		scheme_error:     scheme_error
	}
}

fn or_unknown(v string) string {
	if v.len == 0 {
		return '(unknown)'
	}
	return v
}

// scheme_status_report implements `appearance scheme status` (read-only).
pub fn scheme_status_report() CommandResult {
	s := read_scheme_state()
	validity := if s.scheme_valid { 'valid' } else { 'invalid: ${s.scheme_error}' }
	lines := [
		'theme: ${s.theme} (${s.theme_source})',
		'mode: ${or_unknown(s.mode)}',
		'scheme: ${s.scheme_file} (${validity})',
		'gtkColorScheme: ${s.gtk_color_scheme}',
	]
	return ok_result('appearance scheme status', lines.join('\n'), {
		'theme':            s.theme
		'theme_source':     s.theme_source
		'mode':             s.mode
		'scheme_file':      s.scheme_file
		'scheme_valid':     s.scheme_valid.str()
		'gtk_color_scheme': s.gtk_color_scheme
		'state_file':       s.state_file
	})
}

// scheme_current_report implements `appearance scheme current`: the live
// theme id and mode, one per line.
pub fn scheme_current_report() CommandResult {
	s := read_scheme_state()
	return ok_result('appearance scheme current', '${s.theme}\n${or_unknown(s.mode)}', {
		'theme': s.theme
		'mode':  s.mode
	})
}
