module hornero_core

import os

const hx_cursor_root = '/tmp/hx-cursor-test'

fn cursor_test_setup() {
	os.mkdir_all(hx_cursor_root + '/bin') or { assert false }
	os.write_file(hx_cursor_root + '/bin/hyprctl', '#!/bin/sh\nprintf "%s\\n" "$*" >> ' +
		hx_cursor_root + '/calls\nexit 0\n') or { assert false }
	os.chmod(hx_cursor_root + '/bin/hyprctl', 0o755) or { assert false }
	os.rm(hx_cursor_root + '/calls') or {}
	os.rm(hx_cursor_root + '/state') or {}
	os.setenv('HORNERO_HYPRCTL_BIN', hx_cursor_root + '/bin/hyprctl', true)
	os.setenv('HORNERO_CURSOR_STATE_FILE', hx_cursor_root + '/state', true)
	os.setenv('XCURSOR_THEME', 'elementary', true)
	os.setenv('XCURSOR_SIZE', '24', true)
}

fn cursor_test_teardown() {
	for k in ['HORNERO_HYPRCTL_BIN', 'HORNERO_CURSOR_STATE_FILE', 'XCURSOR_THEME', 'XCURSOR_SIZE'] {
		os.unsetenv(k)
	}
	os.rmdir_all(hx_cursor_root) or {}
}

fn test_cursor_status_reports_env_defaults() {
	cursor_test_setup()
	rep := cursor_status_report()
	assert rep.ok, rep.message
	assert rep.data['theme'] == 'elementary'
	assert rep.data['size'] == '24'
	assert rep.data['size_source'] == 'env'
	cursor_test_teardown()
}

fn test_cursor_set_applies_and_persists() {
	cursor_test_setup()
	rep := cursor_set_report(32, false, true)
	assert rep.ok, rep.message
	calls := os.read_file(hx_cursor_root + '/calls') or { '' }
	assert calls.contains('setcursor elementary 32')
	state := os.read_file(hx_cursor_root + '/state') or { '' }
	assert state.contains('size=32')
	status := cursor_status_report()
	assert status.data['size'] == '32'
	assert status.data['size_source'] == 'persisted'
	cursor_test_teardown()
}

fn test_cursor_set_bounds_and_gate() {
	cursor_test_setup()
	assert !cursor_set_report(4, false, true).ok
	assert !cursor_set_report(128, false, true).ok
	assert !cursor_set_report(32, false, false).ok
	dry := cursor_set_report(32, true, false)
	assert dry.ok, dry.message
	assert !os.is_file(hx_cursor_root + '/state')
	cursor_test_teardown()
}

fn test_cursor_restore_reapplies() {
	cursor_test_setup()
	os.write_file(hx_cursor_root + '/state', 'size=40 theme=elementary\n') or { assert false }
	rep := cursor_restore_report(false, true)
	assert rep.ok, rep.message
	calls := os.read_file(hx_cursor_root + '/calls') or { '' }
	assert calls.contains('setcursor elementary 40')
	os.rm(hx_cursor_root + '/state') or {}
	noop := cursor_restore_report(false, true)
	assert noop.ok
	assert noop.data['restored'] == 'false'
	cursor_test_teardown()
}
