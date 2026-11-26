module hornero_core

import os
import x.json2

// Compositor abstraction supporting both Hyprland (`hyprctl`) and Niri
// (`niri msg --json`) for monitor/window queries and window focus.

pub enum CompositorKind {
	unknown
	hyprland
	niri
}

pub fn (k CompositorKind) str() string {
	return match k {
		.hyprland { 'hyprland' }
		.niri { 'niri' }
		.unknown { 'unknown' }
	}
}

pub struct CompositorMonitor {
pub:
	name    string
	width   int
	height  int
	scale   f64 = 1.0
	focused bool
}

pub struct CompositorWindow {
pub:
	id        string
	title     string
	app_id    string
	workspace string
	focused   bool
}

// active_compositor identifies the session from compositor-owned environment.
// Prefer Niri when nested sessions inherit a parent's Hyprland signature.
// Unknown compositors remain unknown until an adapter is implemented.
pub fn active_compositor() string {
	if os.getenv('NIRI_SOCKET').len > 0 {
		return 'niri'
	}
	if os.getenv('HYPRLAND_INSTANCE_SIGNATURE').len > 0 {
		return 'hyprland'
	}
	return 'unknown'
}

// detect_compositor_from_env determines the active Wayland compositor from
// session environment variables without mutating process state.
// Prefers Niri when nested sessions inherit a parent's Hyprland signature.
pub fn detect_compositor_from_env(hypr_sig string, niri_sock string, current_desktop string) CompositorKind {
	if niri_sock.trim_space().len > 0 {
		return .niri
	}
	if hypr_sig.trim_space().len > 0 {
		return .hyprland
	}
	lower := current_desktop.to_lower()
	if lower.contains('niri') {
		return .niri
	}
	if lower.contains('hyprland') {
		return .hyprland
	}
	return .unknown
}

// detect_compositor detects the active compositor from the current process environment.
pub fn detect_compositor() CompositorKind {
	return detect_compositor_from_env(os.getenv('HYPRLAND_INSTANCE_SIGNATURE'), os.getenv('NIRI_SOCKET'),
		os.getenv('XDG_CURRENT_DESKTOP'))
}

// parse_hypr_monitors_json parses the JSON output of `hyprctl monitors -j`.
pub fn parse_hypr_monitors_json(raw string) ![]CompositorMonitor {
	decoded := json2.decode[json2.Any](raw) or {
		return error('failed to parse hyprctl monitors JSON: ${err}')
	}
	arr := decoded.as_array()
	mut out := []CompositorMonitor{}
	for item in arr {
		m := item.as_map()
		name := m['name'] or { json2.Any('') }.str()
		if name.len == 0 {
			continue
		}
		width := m['width'] or { json2.Any(0) }.int()
		height := m['height'] or { json2.Any(0) }.int()
		mut scale := m['scale'] or { json2.Any(1.0) }.f64()
		if scale <= 0 {
			scale = 1.0
		}
		focused := m['focused'] or { json2.Any(false) }.bool()
		out << CompositorMonitor{
			name:    name
			width:   width
			height:  height
			scale:   scale
			focused: focused
		}
	}
	return out
}

// parse_niri_outputs_json parses the JSON output of `niri msg --json outputs`.
pub fn parse_niri_outputs_json(raw string) ![]CompositorMonitor {
	decoded := json2.decode[json2.Any](raw) or {
		return error('failed to parse niri outputs JSON: ${err}')
	}
	obj := decoded.as_map()
	mut out := []CompositorMonitor{}
	for key, val in obj {
		m := val.as_map()
		mut name := m['name'] or { json2.Any(key) }.str()
		if name.len == 0 {
			name = key
		}
		mut width := 0
		mut height := 0
		mut scale := 1.0
		if logical_any := m['logical'] {
			logical := logical_any.as_map()
			width = logical['width'] or { json2.Any(0) }.int()
			height = logical['height'] or { json2.Any(0) }.int()
			s := logical['scale'] or { json2.Any(1.0) }.f64()
			if s > 0 {
				scale = s
			}
		}
		focused := m['focused'] or { json2.Any(false) }.bool()
		out << CompositorMonitor{
			name:    name
			width:   width
			height:  height
			scale:   scale
			focused: focused
		}
	}
	return out
}

// parse_hypr_windows_json parses the JSON output of `hyprctl clients -j`.
pub fn parse_hypr_windows_json(raw string) ![]CompositorWindow {
	decoded := json2.decode[json2.Any](raw) or {
		return error('failed to parse hyprctl clients JSON: ${err}')
	}
	arr := decoded.as_array()
	mut out := []CompositorWindow{}
	for item in arr {
		m := item.as_map()
		addr := m['address'] or { json2.Any('') }.str()
		if addr.len == 0 {
			continue
		}
		title := m['title'] or { json2.Any('') }.str()
		app_id := m['class'] or { json2.Any('') }.str()
		mut ws_name := ''
		if ws_any := m['workspace'] {
			ws_map := ws_any.as_map()
			ws_name = ws_map['name'] or { json2.Any('') }.str()
			if ws_name.len == 0 {
				ws_id := ws_map['id'] or { json2.Any(0) }.int()
				if ws_id != 0 {
					ws_name = '${ws_id}'
				}
			}
		}
		focus_hist := m['focusHistoryID'] or { json2.Any(-1) }.int()
		out << CompositorWindow{
			id:        addr
			title:     title
			app_id:    app_id
			workspace: ws_name
			focused:   focus_hist == 0
		}
	}
	return out
}

// parse_niri_windows_json parses the JSON output of `niri msg --json windows`.
pub fn parse_niri_windows_json(raw string) ![]CompositorWindow {
	decoded := json2.decode[json2.Any](raw) or {
		return error('failed to parse niri windows JSON: ${err}')
	}
	arr := decoded.as_array()
	mut out := []CompositorWindow{}
	for item in arr {
		m := item.as_map()
		id_val := m['id'] or { json2.Any('') }.str()
		if id_val.len == 0 {
			continue
		}
		title := m['title'] or { json2.Any('') }.str()
		app_id := m['app_id'] or { json2.Any('') }.str()
		ws_id := m['workspace_id'] or { json2.Any('') }.str()
		focused := m['is_focused'] or { json2.Any(false) }.bool()
		out << CompositorWindow{
			id:        id_val
			title:     title
			app_id:    app_id
			workspace: ws_id
			focused:   focused
		}
	}
	return out
}

// compositor_focus_window_argv builds the command argv to focus a window on the given compositor.
pub fn compositor_focus_window_argv(kind CompositorKind, id string) ![]string {
	clean_id := id.trim_space()
	if clean_id.len == 0 {
		return error('window id must not be empty')
	}
	match kind {
		.hyprland {
			bin := resolve_hyprctl_bin()
			exe := if bin.len > 0 { bin } else { 'hyprctl' }
			return [exe, 'dispatch', 'focuswindow', 'address:${clean_id}']
		}
		.niri {
			bin := resolve_niri_bin()
			exe := if bin.len > 0 { bin } else { 'niri' }
			return [exe, 'msg', 'action', 'focus-window', '--id', clean_id]
		}
		.unknown {
			return error('unsupported or undetected compositor')
		}
	}
}

// compositor_list_monitors queries the active compositor for connected monitors/outputs.
pub fn compositor_list_monitors(kind CompositorKind) ![]CompositorMonitor {
	match kind {
		.hyprland {
			bin := resolve_hyprctl_bin()
			if bin.len == 0 {
				return error('hyprctl not found on PATH')
			}
			res := run_exec(ExecSpec{
				prog: bin
				args: ['monitors', '-j']
			})
			if res.exit_code != 0 {
				return error('hyprctl monitors -j failed: ${res.output.trim_space()}')
			}
			return parse_hypr_monitors_json(res.output)
		}
		.niri {
			bin := resolve_niri_bin()
			if bin.len == 0 {
				return error('niri not found on PATH')
			}
			res := run_exec(ExecSpec{
				prog: bin
				args: ['msg', '--json', 'outputs']
			})
			if res.exit_code != 0 {
				return error('niri msg --json outputs failed: ${res.output.trim_space()}')
			}
			return parse_niri_outputs_json(res.output)
		}
		.unknown {
			return error('unsupported or undetected compositor')
		}
	}
}

// compositor_list_windows queries the active compositor for open windows.
pub fn compositor_list_windows(kind CompositorKind) ![]CompositorWindow {
	match kind {
		.hyprland {
			bin := resolve_hyprctl_bin()
			if bin.len == 0 {
				return error('hyprctl not found on PATH')
			}
			res := run_exec(ExecSpec{
				prog: bin
				args: ['clients', '-j']
			})
			if res.exit_code != 0 {
				return error('hyprctl clients -j failed: ${res.output.trim_space()}')
			}
			return parse_hypr_windows_json(res.output)
		}
		.niri {
			bin := resolve_niri_bin()
			if bin.len == 0 {
				return error('niri not found on PATH')
			}
			res := run_exec(ExecSpec{
				prog: bin
				args: ['msg', '--json', 'windows']
			})
			if res.exit_code != 0 {
				return error('niri msg --json windows failed: ${res.output.trim_space()}')
			}
			return parse_niri_windows_json(res.output)
		}
		.unknown {
			return error('unsupported or undetected compositor')
		}
	}
}

// compositor_focus_window focuses a window by compositor-specific ID.
pub fn compositor_focus_window(kind CompositorKind, id string) ! {
	argv := compositor_focus_window_argv(kind, id)!
	res := run_exec(ExecSpec{
		prog: argv[0]
		args: argv[1..]
	})
	if res.exit_code != 0 {
		return error('focus window failed (${kind}): ${res.output.trim_space()}')
	}
}
