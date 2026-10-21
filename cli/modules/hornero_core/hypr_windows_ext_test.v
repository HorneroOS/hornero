module hornero_core

import os

const hx_wrules_root = '/tmp/hx-wrules-test'

fn wrules_test_setup() {
	os.mkdir_all(hx_wrules_root + '/bin') or { assert false }
	os.mkdir_all(hx_wrules_root + '/config') or { assert false }
	os.write_file(hx_wrules_root + '/bin/hyprctl', '#!/bin/sh\nprintf "%s\\n" "$*" >> ' +
		hx_wrules_root + '/calls\ncase "$*" in *follow_mouse*) echo \'{"int":1}\' ;; *) echo \'{"int":2}\' ;; esac\nexit 0\n') or {
		assert false
	}
	os.chmod(hx_wrules_root + '/bin/hyprctl', 0o755) or { assert false }
	os.rm(hx_wrules_root + '/calls') or {}
	os.rm(hx_wrules_root + '/rules-user.conf') or {}
	os.rm(hx_wrules_root + '/windows-state') or {}
	os.setenv('HORNERO_HYPRCTL_BIN', hx_wrules_root + '/bin/hyprctl', true)
	os.setenv('XDG_CONFIG_HOME', hx_wrules_root + '/config', true)
	os.setenv('HORNERO_WINDOW_RULES_USER_FILE', hx_wrules_root + '/rules-user.conf', true)
	os.setenv('HORNERO_HYPR_WINDOWS_STATE_FILE', hx_wrules_root + '/windows-state', true)
}

fn wrules_test_teardown() {
	for k in ['HORNERO_HYPRCTL_BIN', 'XDG_CONFIG_HOME', 'HORNERO_WINDOW_RULES_USER_FILE',
		'HORNERO_HYPR_WINDOWS_STATE_FILE'] {
		os.unsetenv(k)
	}
	os.rmdir_all(hx_wrules_root) or {}
}

fn test_wrules_parse_render_roundtrip() {
	text := '# header\nwindowrule {\n    name = hornero-user-kitty\n    match:class = ^kitty$\n\n    float = true\n}\n'
	rules := parse_window_rules(text)
	assert rules.len == 1
	assert rules[0].match_kind == 'class'
	assert rules[0].pattern == '^kitty$'
	assert rules[0].effect == 'float'
	out := render_window_rules(rules)
	again := parse_window_rules(out)
	assert again.len == 1 && again[0].name == rules[0].name
}

fn test_wrules_add_remove() {
	wrules_test_setup()
	rep := windows_rules_add_report(WindowsRulesAddOptions{
		match_kind: 'class'
		pattern:    '^kitty$'
		effect:     'float'
		yes:        true
	})
	assert rep.ok, rep.message
	assert rep.message.contains('reload')
	text := os.read_file(hx_wrules_root + '/rules-user.conf') or { '' }
	assert text.contains('name = hornero-user-kitty')
	dup := windows_rules_add_report(WindowsRulesAddOptions{
		match_kind: 'class'
		pattern:    '^kitty$'
		effect:     'pin'
		yes:        true
	})
	assert !dup.ok
	bad := windows_rules_add_report(WindowsRulesAddOptions{
		match_kind: 'class'
		pattern:    'a{b'
		effect:     'float'
		yes:        true
	})
	assert !bad.ok
	list := windows_rules_list_report()
	assert list.ok && list.data['count'] == '1'
	rem := windows_rules_remove_report('hornero-user-kitty', false, true)
	assert rem.ok, rem.message
	assert windows_rules_list_report().data['count'] == '0'
	wrules_test_teardown()
}

fn test_windows_live_gaps_parse_vec2_custom() {
	wrules_test_setup()
	os.write_file(hx_wrules_root + '/bin/hyprctl', '#!/bin/sh\ncase "$*" in *gaps_in*) echo \'{"custom":"6 6 6 6"}\' ;; *gaps_out*) echo \'{"custom":"18 18 18 18"}\' ;; *follow_mouse*) echo \'{"int":1}\' ;; *) echo \'{"int":2}\' ;; esac\nexit 0\n') or {
		assert false
	}
	status := windows_status_report()
	assert status.data['gaps_in'] == '6', status.message
	assert status.data['gaps_out'] == '18'
	wrules_test_teardown()
}

fn test_windows_follow_mouse_applies_and_persists() {
	wrules_test_setup()
	assert windows_settings_valid(WindowsSettings{ follow_mouse: 2 })
	assert !windows_settings_valid(WindowsSettings{ follow_mouse: 3 })
	rep := windows_apply_report(WindowsApplyOptions{
		settings: WindowsSettings{
			gaps_in:      5
			gaps_out:     20
			border_size:  2
			rounding:     10
			follow_mouse: 2
		}
		yes:      true
	})
	assert rep.ok, rep.message
	calls := os.read_file(hx_wrules_root + '/calls') or { '' }
	assert calls.contains('keyword input:follow_mouse 2')
	state := os.read_file(hx_wrules_root + '/windows-state') or { '' }
	assert state.contains('follow_mouse=2')
	assert windows_restore_value().follow_mouse == 2
	status := windows_status_report()
	assert status.data['follow_mouse'] == '1' // fake hyprctl live value
	wrules_test_teardown()
}
