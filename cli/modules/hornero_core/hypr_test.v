module hornero_core

import os

const hx_hypr_root = '/tmp/hx-hypr-test'

fn hypr_test_save_env(keys []string) map[string]string {
	mut saved := map[string]string{}
	for k in keys {
		saved[k] = os.getenv(k)
	}
	return saved
}

fn hypr_test_restore_env(saved map[string]string) {
	for k, v in saved {
		if v.len == 0 {
			os.unsetenv(k)
		} else {
			os.setenv(k, v, true)
		}
	}
}

fn hypr_test_keys() []string {
	return ['XDG_CONFIG_HOME', 'XDG_STATE_HOME', 'HORNERO_HYPRCTL_BIN', 'HORNERO_HYPRPM_BIN',
		'HORNERO_I3_MSG_BIN']
}

// hypr_test_setup builds a hermetic fixture tree: profile confs, a canned
// hyprctl (monitors JSON, getoption text, keyword no-op), a canned i3-msg
// (config names, workspaces, switch no-op), and a canned hyprpm. Backends
// default to nonexistent paths; tests opt into fixtures explicitly.
fn hypr_test_setup() {
	os.mkdir_all(hx_hypr_root + '/config/hypr/hyprland.conf.d') or { assert false }
	os.write_file(hx_hypr_root + '/config/hypr/hyprland.conf.d/animations.conf', 'bezier = easeOut, 0.22, 1, 0.36, 1\nanimation = windows, 1, 3, easeOut\n') or {
		assert false
	}
	os.write_file(hx_hypr_root + '/config/hypr/hyprland.conf.d/animations-cozy.conf',
		'bezier = cozy, 0.34, 1.3, 0.64, 1\nanimation = windows, 1, 5, cozy\nanimation = fade, 1, 4, cozy\n') or {
		assert false
	}
	os.write_file(hx_hypr_root + '/monitors.json', '[{"name":"eDP-1","width":1920,"height":1080,"refreshRate":60,"scale":1,"transform":0},{"name":"HDMI-A-1","width":2560,"height":1440,"refreshRate":143.997,"scale":1,"transform":0}]') or {
		assert false
	}
	os.write_file(hx_hypr_root + '/monitors-single.json', '[{"name":"eDP-1","width":1920,"height":1080,"refreshRate":60,"scale":1,"transform":0}]') or {
		assert false
	}
	os.write_file(hx_hypr_root + '/i3-config', 'set \$WS1 1\nset \$WS2 2\nset \$WS3 3\n') or {
		assert false
	}
	os.write_file(hx_hypr_root + '/i3-workspaces', '[{"name":"1","focused":false},{"name":"2","focused":true},{"name":"3","focused":false}]') or {
		assert false
	}
	os.mkdir_all(hx_hypr_root + '/bin') or { assert false }
	os.write_file(hx_hypr_root + '/bin/hyprctl',
		'#!/bin/sh\nif [ "\$1" = "monitors" ]; then cat ' + hx_hypr_root +
			'/monitors.json\necho\nelif [ "\$1" = "getoption" ]; then echo "str: dwindle"\nfi\nexit 0\n') or {
		assert false
	}
	os.write_file(hx_hypr_root + '/bin/i3-msg',
		'#!/bin/sh\nif [ "\$1" = "-t" ] && [ "\$2" = "get_config" ]; then cat ' + hx_hypr_root +
			'/i3-config\nelif [ "\$1" = "-t" ] && [ "\$2" = "get_workspaces" ]; then cat ' +
			hx_hypr_root + '/i3-workspaces\necho\nelse echo "ok"\nfi\nexit 0\n') or { assert false }
	os.write_file(hx_hypr_root + '/bin/hyprpm', '#!/bin/sh\necho "Repository hyprland-scroll-overview (https://github.com/yayuuu/hyprland-scroll-overview.git):"\necho "  Plugin scrolloverview: enabled"\nexit 0\n') or {
		assert false
	}
	os.write_file(hx_hypr_root + '/bin/hyprctl-single',
		'#!/bin/sh\nif [ "\$1" = "monitors" ]; then cat ' + hx_hypr_root +
			'/monitors-single.json\necho\nfi\nexit 0\n') or { assert false }
	os.chmod(hx_hypr_root + '/bin/hyprctl', 0o755) or { assert false }
	os.chmod(hx_hypr_root + '/bin/hyprctl-single', 0o755) or { assert false }
	os.chmod(hx_hypr_root + '/bin/i3-msg', 0o755) or { assert false }
	os.chmod(hx_hypr_root + '/bin/hyprpm', 0o755) or { assert false }
	os.mkdir_all(hx_hypr_root + '/state') or { assert false }
}

fn hypr_test_break_backends() {
	os.setenv('HORNERO_HYPRCTL_BIN', '/nonexistent-hyprctl-hornero-test', true)
	os.setenv('HORNERO_HYPRPM_BIN', '/nonexistent-hyprpm-hornero-test', true)
	os.setenv('HORNERO_I3_MSG_BIN', '/nonexistent-i3-msg-hornero-test', true)
}

fn hypr_test_use_env() {
	os.setenv('XDG_CONFIG_HOME', hx_hypr_root + '/config', true)
	os.setenv('XDG_STATE_HOME', hx_hypr_root + '/state', true)
	hypr_test_break_backends()
}

fn test_animation_list_is_read_only() {
	r := animation_list_report()
	assert r.ok
	assert r.message.contains('cozy')
	assert r.message.contains('vaporwave')
	assert r.data['count'] == '6'
}

fn test_animation_current_defaults_without_state() {
	saved := hypr_test_save_env(hypr_test_keys())
	hypr_test_use_env()
	os.rm(resolve_hypr_animations_state_file()) or {}
	r := animation_current_report()
	assert r.ok
	assert r.message == 'default'
	assert r.data['profile'] == 'default'
	hypr_test_restore_env(saved)
}

fn test_animation_current_reads_persisted() {
	saved := hypr_test_save_env(hypr_test_keys())
	hypr_test_use_env()
	write_state_token(resolve_hypr_animations_state_file(), 'cozy') or { assert false }
	r := animation_current_report()
	assert r.ok
	assert r.message == 'cozy'
	os.rm(resolve_hypr_animations_state_file()) or {}
	hypr_test_restore_env(saved)
}

fn test_animation_next_cycles_and_wraps() {
	saved := hypr_test_save_env(hypr_test_keys())
	hypr_test_use_env()
	write_state_token(resolve_hypr_animations_state_file(), 'cozy') or { assert false }
	assert animation_next_profile() == 'cyberpunk'
	write_state_token(resolve_hypr_animations_state_file(), 'vaporwave') or { assert false }
	assert animation_next_profile() == 'default'
	os.rm(resolve_hypr_animations_state_file()) or {}
	hypr_test_restore_env(saved)
}

fn test_animation_apply_needs_yes() {
	r := animation_apply_report(AnimationApplyOptions{
		profile: 'cozy'
	})
	assert !r.ok
	assert r.message.contains('--yes')
}

fn test_animation_apply_rejects_unknown_profile() {
	r := animation_apply_report(AnimationApplyOptions{
		profile: 'neon'
		dry_run: true
	})
	assert !r.ok
	assert r.message.contains('unsupported profile')
}

fn test_animation_apply_dry_run_previews_keywords() {
	saved := hypr_test_save_env(hypr_test_keys())
	hypr_test_setup()
	hypr_test_use_env()
	r := animation_apply_report(AnimationApplyOptions{
		profile: 'cozy'
		dry_run: true
	})
	assert r.ok
	assert r.message.contains('would run:')
	assert r.message.contains('keyword bezier')
	assert r.message.contains('keyword animation')
	hypr_test_restore_env(saved)
}

fn test_animation_apply_missing_conf_fails() {
	saved := hypr_test_save_env(hypr_test_keys())
	hypr_test_setup()
	hypr_test_use_env()
	r := animation_apply_report(AnimationApplyOptions{
		profile: 'minimal'
		dry_run: true
	})
	assert !r.ok
	assert r.message.contains('not found')
	hypr_test_restore_env(saved)
}

fn test_animation_apply_executes_and_persists() {
	saved := hypr_test_save_env(hypr_test_keys())
	hypr_test_setup()
	hypr_test_use_env()
	os.setenv('HORNERO_HYPRCTL_BIN', hx_hypr_root + '/bin/hyprctl', true)
	os.rm(resolve_hypr_animations_state_file()) or {}
	r := animation_apply_report(AnimationApplyOptions{
		profile: 'cozy'
		yes:     true
	})
	assert r.ok, r.message
	assert animation_current_profile() == 'cozy'
	// Ephemeral applies without persisting.
	r2 := animation_apply_report(AnimationApplyOptions{
		profile:   'default'
		yes:       true
		ephemeral: true
	})
	assert r2.ok, r2.message
	assert animation_current_profile() == 'cozy'
	os.rm(resolve_hypr_animations_state_file()) or {}
	hypr_test_restore_env(saved)
}

fn test_layout_toggle_values() {
	assert layout_toggle_value('scrolling') == 'dwindle'
	assert layout_toggle_value('dwindle') == 'scrolling'
	assert layout_toggle_value('master') == 'scrolling'
}

fn test_layout_current_prefers_live_over_persisted() {
	saved := hypr_test_save_env(hypr_test_keys())
	hypr_test_setup()
	hypr_test_use_env()
	os.setenv('HORNERO_HYPRCTL_BIN', hx_hypr_root + '/bin/hyprctl', true)
	write_state_token(resolve_hypr_layout_state_file(), 'scrolling') or { assert false }
	// Fixture hyprctl reports dwindle via the plain `str:` fallback.
	assert layout_current_value() == 'dwindle'
	assert layout_restore_value() == 'scrolling'
	os.rm(resolve_hypr_layout_state_file()) or {}
	hypr_test_restore_env(saved)
}

fn test_layout_current_falls_back_without_backend() {
	saved := hypr_test_save_env(hypr_test_keys())
	hypr_test_use_env()
	write_state_token(resolve_hypr_layout_state_file(), 'master') or { assert false }
	r := layout_current_report()
	assert r.ok
	assert r.message == 'master'
	os.rm(resolve_hypr_layout_state_file()) or {}
	hypr_test_restore_env(saved)
}

fn test_layout_apply_needs_yes() {
	r := layout_apply_report(LayoutApplyOptions{
		layout: 'scrolling'
	})
	assert !r.ok
	assert r.message.contains('--yes')
}

fn test_layout_apply_rejects_unknown() {
	r := layout_apply_report(LayoutApplyOptions{
		layout:  'tiling'
		dry_run: true
	})
	assert !r.ok
	assert r.message.contains('invalid layout')
}

fn test_layout_apply_dry_run_previews_scrolling_profile() {
	saved := hypr_test_save_env(hypr_test_keys())
	hypr_test_use_env()
	r := layout_apply_report(LayoutApplyOptions{
		layout:  'scrolling'
		dry_run: true
	})
	assert r.ok
	assert r.message.contains('general:layout')
	assert r.message.contains('scrolling:column_width')
	hypr_test_restore_env(saved)
}

fn test_layout_apply_executes_and_persists() {
	saved := hypr_test_save_env(hypr_test_keys())
	hypr_test_setup()
	hypr_test_use_env()
	os.setenv('HORNERO_HYPRCTL_BIN', hx_hypr_root + '/bin/hyprctl', true)
	os.rm(resolve_hypr_layout_state_file()) or {}
	r := layout_apply_report(LayoutApplyOptions{
		layout: 'master'
		yes:    true
	})
	assert r.ok, r.message
	assert layout_restore_value() == 'master'
	os.rm(resolve_hypr_layout_state_file()) or {}
	hypr_test_restore_env(saved)
}

fn test_layout_status_is_read_only() {
	saved := hypr_test_save_env(hypr_test_keys())
	hypr_test_use_env()
	r := layout_status_report()
	assert r.ok
	assert r.message.contains('layout:')
	assert r.message.contains('hyprctl:')
	assert 'layout' in r.data
	hypr_test_restore_env(saved)
}

fn test_monitors_parse_json() {
	mons := parse_monitors_json('[{"name":"eDP-1","width":1920,"height":1080,"refreshRate":60,"scale":1,"transform":0},{"name":"HDMI-A-1","width":2560,"height":1440,"refreshRate":143.997,"scale":1.5,"transform":0},{"name":"","width":1}]')
	assert mons.len == 2
	assert mons[0].is_inner
	assert !mons[1].is_inner
	assert mons[1].refresh == '143.997'
	assert mons[1].scale == '1.5'
	assert parse_monitors_json('not json').len == 0
}

fn test_monitors_list_live() {
	saved := hypr_test_save_env(hypr_test_keys())
	hypr_test_setup()
	hypr_test_use_env()
	os.setenv('HORNERO_HYPRCTL_BIN', hx_hypr_root + '/bin/hyprctl', true)
	r := monitors_list_report()
	assert r.ok, r.message
	assert r.message.contains('eDP-1 - 1920x1080@60 (Scale: 1)')
	assert r.message.contains('HDMI-A-1 - 2560x1440@143.997 (Scale: 1)')
	assert r.data['count'] == '2'
	hypr_test_restore_env(saved)
}

fn test_monitors_list_fails_without_backend() {
	saved := hypr_test_save_env(hypr_test_keys())
	hypr_test_use_env()
	r := monitors_list_report()
	assert !r.ok
	assert r.message.contains('Hyprland')
	hypr_test_restore_env(saved)
}

fn test_monitors_set_needs_yes() {
	r := monitors_set_report(MonitorsSetOptions{
		mode: 'mirror'
	})
	assert !r.ok
	assert r.message.contains('--yes')
}

fn test_monitors_set_rejects_unknown_mode() {
	r := monitors_set_report(MonitorsSetOptions{
		mode:    'sideways'
		dry_run: true
	})
	assert !r.ok
	assert r.message.contains('unknown monitor mode')
}

fn test_monitors_set_dry_run_uses_placeholders() {
	saved := hypr_test_save_env(hypr_test_keys())
	hypr_test_use_env()
	r := monitors_set_report(MonitorsSetOptions{
		mode:    'extend-right'
		dry_run: true
	})
	assert r.ok
	assert r.message.contains('would run:')
	assert r.message.contains('1920x0')
	hypr_test_restore_env(saved)
}

fn test_monitors_set_live_geometry() {
	saved := hypr_test_save_env(hypr_test_keys())
	hypr_test_setup()
	hypr_test_use_env()
	os.setenv('HORNERO_HYPRCTL_BIN', hx_hypr_root + '/bin/hyprctl', true)
	r := monitors_set_report(MonitorsSetOptions{
		mode:    'extend-right'
		dry_run: true
	})
	assert r.ok, r.message
	assert r.message.contains('HDMI-A-1,preferred,1920x0,1')
	r2 := monitors_set_report(MonitorsSetOptions{
		mode: 'mirror'
		yes:  true
	})
	assert r2.ok, r2.message
	hypr_test_restore_env(saved)
}

fn test_monitors_set_needs_external_display() {
	saved := hypr_test_save_env(hypr_test_keys())
	hypr_test_setup()
	hypr_test_use_env()
	os.setenv('HORNERO_HYPRCTL_BIN', hx_hypr_root + '/bin/hyprctl-single', true)
	r := monitors_set_report(MonitorsSetOptions{
		mode:    'extend-right'
		dry_run: true
	})
	assert !r.ok
	assert r.message.contains('only one monitor')
	hypr_test_restore_env(saved)
}

fn test_monitors_set_disable_external_noop_without_external() {
	saved := hypr_test_save_env(hypr_test_keys())
	hypr_test_setup()
	hypr_test_use_env()
	os.setenv('HORNERO_HYPRCTL_BIN', hx_hypr_root + '/bin/hyprctl-single', true)
	r := monitors_set_report(MonitorsSetOptions{
		mode: 'disable-external'
		yes:  true
	})
	assert r.ok, r.message
	assert r.message.contains('no external monitors')
	hypr_test_restore_env(saved)
}

fn test_monitors_set_real_run_needs_live_data() {
	saved := hypr_test_save_env(hypr_test_keys())
	hypr_test_setup()
	hypr_test_use_env()
	os.setenv('HORNERO_HYPRCTL_BIN', '/bin/false', true)
	r := monitors_set_report(MonitorsSetOptions{
		mode: 'mirror'
		yes:  true
	})
	assert !r.ok
	assert r.message.contains('could not read monitor list')
	hypr_test_restore_env(saved)
}

fn test_monitors_status_is_read_only() {
	saved := hypr_test_save_env(hypr_test_keys())
	hypr_test_use_env()
	r := monitors_status_report()
	assert r.ok
	assert r.message.contains('hyprctl:')
	assert 'internal' in r.data
	assert 'external' in r.data
	hypr_test_restore_env(saved)
}

fn test_workspace_target_wraps() {
	names := ['1', '2', '3']
	assert workspace_target(names, '2', false) == '3'
	assert workspace_target(names, '2', true) == '1'
	assert workspace_target(names, '3', false) == '1'
	assert workspace_target(names, '1', true) == '3'
	assert workspace_target(names, 'unknown', false) == '2'
}

fn test_workspace_parse_config_names() {
	names := parse_i3_config_names('bar\nset \$WS1 1\n  set \$WS2 "2: web"\nset \$WSX\n')
	assert names == ['1', '2: web']
}

fn test_workspace_cycle_needs_yes() {
	r := workspace_cycle_report(WorkspaceCycleOptions{
		direction: 'next'
	})
	assert !r.ok
	assert r.message.contains('--yes')
}

fn test_workspace_cycle_rejects_unknown_direction() {
	r := workspace_cycle_report(WorkspaceCycleOptions{
		direction: 'up'
		dry_run:   true
	})
	assert !r.ok
	assert r.message.contains('unknown workspace direction')
}

fn test_workspace_cycle_dry_run_placeholder() {
	saved := hypr_test_save_env(hypr_test_keys())
	hypr_test_use_env()
	r := workspace_cycle_report(WorkspaceCycleOptions{
		direction: 'next'
		dry_run:   true
	})
	assert r.ok
	assert r.message.contains('would run:')
	assert r.message.contains('i3-msg')
	hypr_test_restore_env(saved)
}

fn test_workspace_cycle_live_target() {
	saved := hypr_test_save_env(hypr_test_keys())
	hypr_test_setup()
	hypr_test_use_env()
	os.setenv('HORNERO_I3_MSG_BIN', hx_hypr_root + '/bin/i3-msg', true)
	r := workspace_cycle_report(WorkspaceCycleOptions{
		direction: 'next'
		dry_run:   true
	})
	assert r.ok, r.message
	assert r.data['target'] == '3'
	r2 := workspace_cycle_report(WorkspaceCycleOptions{
		direction: 'prev'
		yes:       true
	})
	assert r2.ok, r2.message
	assert r2.data['target'] == '1'
	hypr_test_restore_env(saved)
}

fn test_plugins_status_without_backend() {
	saved := hypr_test_save_env(hypr_test_keys())
	hypr_test_use_env()
	r := plugins_status_report()
	assert r.ok
	assert r.message.contains('hyprpm:')
	assert r.data['installed'] == 'unknown'
	hypr_test_restore_env(saved)
}

fn test_plugins_status_live() {
	saved := hypr_test_save_env(hypr_test_keys())
	hypr_test_setup()
	hypr_test_use_env()
	os.setenv('HORNERO_HYPRPM_BIN', hx_hypr_root + '/bin/hyprpm', true)
	r := plugins_status_report()
	assert r.ok, r.message
	assert r.message.contains('installed and enabled')
	hypr_test_restore_env(saved)
}

fn test_plugins_list_live() {
	saved := hypr_test_save_env(hypr_test_keys())
	hypr_test_setup()
	hypr_test_use_env()
	os.setenv('HORNERO_HYPRPM_BIN', hx_hypr_root + '/bin/hyprpm', true)
	r := plugins_list_report()
	assert r.ok, r.message
	assert r.message.contains('scrolloverview')
	hypr_test_restore_env(saved)
}

fn test_plugins_list_fails_without_backend() {
	saved := hypr_test_save_env(hypr_test_keys())
	hypr_test_use_env()
	r := plugins_list_report()
	assert !r.ok
	assert r.message.contains('Hyprland')
	hypr_test_restore_env(saved)
}
