module hornero_core

import os

const hx_rebind_root = '/tmp/hx-rebind-test'

const hx_rebind_defaults = '# Defaults
bind = \$mainMod, Return, exec, exo-open --launch TerminalEmulator
bind = \$mainMod, T, exec, exo-open --launch TerminalEmulator
bind = CTRL, Space, exec, horneroctl apps launch
binde = , XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
'

fn rebind_test_setup() {
	os.mkdir_all(hx_rebind_root + '/bin') or { assert false }
	os.write_file(hx_rebind_root + '/bin/hyprctl', '#!/bin/sh\nprintf "%s\\n" "$*" >> ' +
		hx_rebind_root + '/calls\nexit 0\n') or { assert false }
	os.chmod(hx_rebind_root + '/bin/hyprctl', 0o755) or { assert false }
	os.rm(hx_rebind_root + '/calls') or {}
	os.write_file(hx_rebind_root + '/keybindings.conf', hx_rebind_defaults) or { assert false }
	os.rm(hx_rebind_root + '/keybindings-user.conf') or {}
	os.setenv('HORNERO_HYPRCTL_BIN', hx_rebind_root + '/bin/hyprctl', true)
	os.setenv('HORNERO_KEYBINDINGS_FILE', hx_rebind_root + '/keybindings.conf', true)
	os.setenv('HORNERO_KEYBINDINGS_USER_FILE', hx_rebind_root + '/keybindings-user.conf', true)
	os.setenv('XDG_CONFIG_HOME', hx_rebind_root + '/config', true)
}

fn rebind_test_teardown() {
	os.unsetenv('HORNERO_HYPRCTL_BIN')
	os.unsetenv('HORNERO_KEYBINDINGS_FILE')
	os.unsetenv('HORNERO_KEYBINDINGS_USER_FILE')
	os.unsetenv('XDG_CONFIG_HOME')
	os.rmdir_all(hx_rebind_root) or {}
}

fn test_rebind_parse_entries_and_combos() {
	entries := parse_bind_entries(hx_rebind_defaults)
	assert entries.len == 4
	assert bind_combo(entries[0]) == 'SUPER + Return'
	assert entries[0].dispatcher == 'exec'
	assert entries[0].arg == 'exo-open --launch TerminalEmulator'
	assert bind_combo(entries[2]) == 'CTRL + Space'
	assert entries[3].verb == 'binde'
	assert entries[3].key == 'XF86AudioRaiseVolume'
	mods, key, ok := parse_combo('shift + super + x')
	assert ok && mods == 'SHIFT + SUPER' && key == 'x'
	m2, k2, ok2 := parse_combo('XF86AudioMute')
	assert ok2 && m2 == '' && k2 == 'XF86AudioMute'
	_, _, bad := parse_combo('  ')
	assert !bad
}

fn test_rebind_set_writes_pair_and_applies_live() {
	rebind_test_setup()
	rep := keyboard_rebind_set_report(RebindSetOptions{
		old_combo: 'SUPER + Return'
		new_combo: 'SUPER + X'
		yes:       true
	})
	assert rep.ok, rep.message
	text := os.read_file(hx_rebind_root + '/keybindings-user.conf') or { '' }
	assert text.contains('unbind = SUPER, Return')
	assert text.contains('bind = SUPER, X, exec, exo-open --launch TerminalEmulator')
	calls := os.read_file(hx_rebind_root + '/calls') or { '' }
	assert calls.contains('keyword unbind SUPER, Return')
	assert calls.contains('keyword bind SUPER, X, exec, exo-open --launch TerminalEmulator')
	// Effective set: old combo gone, new combo present exactly once.
	status := keyboard_rebind_status_report()
	assert status.ok
	assert status.data['overrides'] == '1'
	rebind_test_teardown()
}

fn test_rebind_conflict_and_missing_fail() {
	rebind_test_setup()
	conflict := keyboard_rebind_set_report(RebindSetOptions{
		old_combo: 'SUPER + Return'
		new_combo: 'SUPER + T'
		yes:       true
	})
	assert !conflict.ok
	assert conflict.message.contains('already bound')
	missing := keyboard_rebind_set_report(RebindSetOptions{
		old_combo: 'SUPER + Z'
		new_combo: 'SUPER + X'
		yes:       true
	})
	assert !missing.ok
	assert missing.message.contains('not bound')
	no_yes := keyboard_rebind_set_report(RebindSetOptions{
		old_combo: 'SUPER + Return'
		new_combo: 'SUPER + X'
	})
	assert !no_yes.ok
	assert !os.is_file(hx_rebind_root + '/keybindings-user.conf')
	rebind_test_teardown()
}

fn test_rebind_reset_restores_defaults() {
	rebind_test_setup()
	keyboard_rebind_set_report(RebindSetOptions{
		old_combo: 'SUPER + Return'
		new_combo: 'SUPER + X'
		yes:       true
	})
	rep := keyboard_rebind_reset_report(false, true)
	assert rep.ok, rep.message
	text := os.read_file(hx_rebind_root + '/keybindings-user.conf') or { '' }
	assert !text.contains('bind = SUPER, X')
	status := keyboard_rebind_status_report()
	assert status.data['overrides'] == '0'
	calls := os.read_file(hx_rebind_root + '/calls') or { '' }
	assert calls.contains('keyword bind SUPER, Return, exec, exo-open --launch TerminalEmulator')
	rebind_test_teardown()
}

fn test_rebind_keys_lines_reflect_overrides() {
	lines := ['[Window] SUPER + Return -> exec, kitty', '[Window] SUPER + T -> exec, kitty',
		'XF86AudioMute -> exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle']
	user := 'unbind = SUPER, Return\nbind = SUPER, X, exec, kitty\n'
	out := apply_overrides_to_lines(lines, user)
	assert out.len == 3
	assert !out.any(it.contains('SUPER + Return'))
	assert out.any(it.contains('SUPER + X -> exec, kitty'))
	assert out.any(it.contains('XF86AudioMute'))
}

fn test_rebind_dry_run_writes_nothing() {
	rebind_test_setup()
	rep := keyboard_rebind_set_report(RebindSetOptions{
		old_combo: 'SUPER + Return'
		new_combo: 'SUPER + X'
		dry_run:   true
	})
	assert rep.ok, rep.message
	assert rep.message.contains('unbind = SUPER, Return')
	assert !os.is_file(hx_rebind_root + '/keybindings-user.conf')
	rebind_test_teardown()
}
