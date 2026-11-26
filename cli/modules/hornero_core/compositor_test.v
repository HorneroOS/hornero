module hornero_core

fn test_detect_compositor_from_env() {
	assert detect_compositor_from_env('abc123', '', '') == .hyprland
	assert detect_compositor_from_env('', '/run/user/1000/niri.sock', '') == .niri
	assert detect_compositor_from_env('', '', 'Hyprland') == .hyprland
	assert detect_compositor_from_env('', '', 'niri') == .niri
	assert detect_compositor_from_env('', '', 'GNOME') == .unknown
	assert detect_compositor_from_env('', '', '') == .unknown
	assert CompositorKind.hyprland.str() == 'hyprland'
	assert CompositorKind.niri.str() == 'niri'
	assert CompositorKind.unknown.str() == 'unknown'
}

fn test_parse_hypr_monitors_json() {
	raw := '[{"name":"eDP-1","width":1920,"height":1080,"scale":1.5,"focused":true},{"name":"DP-1","width":2560,"height":1440,"scale":1.0,"focused":false}]'
	mons := parse_hypr_monitors_json(raw) or { panic(err) }
	assert mons.len == 2
	assert mons[0].name == 'eDP-1'
	assert mons[0].width == 1920
	assert mons[0].height == 1080
	assert mons[0].scale == 1.5
	assert mons[0].focused == true
	assert mons[1].name == 'DP-1'
	assert mons[1].focused == false
}

fn test_parse_niri_outputs_json() {
	raw := '{"eDP-1":{"name":"eDP-1","logical":{"width":1920,"height":1080,"scale":1.25},"focused":true}}'
	mons := parse_niri_outputs_json(raw) or { panic(err) }
	assert mons.len == 1
	assert mons[0].name == 'eDP-1'
	assert mons[0].width == 1920
	assert mons[0].height == 1080
	assert mons[0].scale == 1.25
	assert mons[0].focused == true
}

fn test_parse_hypr_windows_json() {
	raw := '[{"address":"0x1234","title":"Kitty","class":"kitty","workspace":{"id":1,"name":"1"},"focusHistoryID":0}]'
	wins := parse_hypr_windows_json(raw) or { panic(err) }
	assert wins.len == 1
	assert wins[0].id == '0x1234'
	assert wins[0].title == 'Kitty'
	assert wins[0].app_id == 'kitty'
	assert wins[0].workspace == '1'
	assert wins[0].focused == true
}

fn test_parse_niri_windows_json() {
	raw := '[{"id":42,"title":"Editor","app_id":"code","workspace_id":2,"is_focused":true}]'
	wins := parse_niri_windows_json(raw) or { panic(err) }
	assert wins.len == 1
	assert wins[0].id == '42'
	assert wins[0].title == 'Editor'
	assert wins[0].app_id == 'code'
	assert wins[0].workspace == '2'
	assert wins[0].focused == true
}

fn test_compositor_focus_window_argv() {
	h_argv := compositor_focus_window_argv(.hyprland, '0xdeadbeef') or { panic(err) }
	assert h_argv.len == 4
	assert h_argv[1] == 'dispatch'
	assert h_argv[2] == 'focuswindow'
	assert h_argv[3] == 'address:0xdeadbeef'

	n_argv := compositor_focus_window_argv(.niri, '42') or { panic(err) }
	assert n_argv.len == 6
	assert n_argv[1] == 'msg'
	assert n_argv[2] == 'action'
	assert n_argv[3] == 'focus-window'
	assert n_argv[4] == '--id'
	assert n_argv[5] == '42'

	if _ := compositor_focus_window_argv(.unknown, '42') {
		assert false, 'expected error for unknown compositor'
	}
	if _ := compositor_focus_window_argv(.hyprland, '   ') {
		assert false, 'expected error for empty window id'
	}
}
