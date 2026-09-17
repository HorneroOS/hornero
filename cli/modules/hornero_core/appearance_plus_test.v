module hornero_core

import os

// Appearance-plus native tests: guards, dry-run previews proving
// non-execution, and validation. Real-run file behavior lives next to
// the implementations (smartcolor_test, gtk_apply_test,
// appearance_apply_test, nightmode_test). No backends, no processes,
// no HOME mutation: XDG overrides isolate every write.

fn ap_with_xdg(tmp string, body fn ()) {
	os.mkdir_all(tmp) or {}
	os.setenv('XDG_CONFIG_HOME', os.join_path(tmp, 'config'), true)
	os.setenv('XDG_DATA_HOME', os.join_path(tmp, 'data'), true)
	os.setenv('XDG_STATE_HOME', os.join_path(tmp, 'state'), true)
	os.setenv('XDG_CACHE_HOME', os.join_path(tmp, 'cache'), true)
	os.setenv('HORNERO_GTK2_FILE', os.join_path(tmp, 'gtkrc-2.0'), true)
	os.setenv('HORNERO_GSETTINGS_BIN', '/nonexistent-gsettings', true)
	os.setenv('HORNERO_XRDB_BIN', '/nonexistent-xrdb', true)
	os.setenv('HORNERO_M3_PYTHON_BIN', '/nonexistent-py', true)
	os.setenv('HORNERO_M3_SCRIPT', os.join_path(tmp, 'gen-m3.py'), true)
	os.setenv('HORNERO_SHELL_RUNNING', '0', true)
	body()
	os.unsetenv('XDG_CONFIG_HOME')
	os.unsetenv('XDG_DATA_HOME')
	os.unsetenv('XDG_STATE_HOME')
	os.unsetenv('XDG_CACHE_HOME')
	os.unsetenv('HORNERO_GTK2_FILE')
	os.unsetenv('HORNERO_GSETTINGS_BIN')
	os.unsetenv('HORNERO_XRDB_BIN')
	os.unsetenv('HORNERO_M3_PYTHON_BIN')
	os.unsetenv('HORNERO_M3_SCRIPT')
	os.unsetenv('HORNERO_SHELL_RUNNING')
}

fn test_colors_status_dry_run_proves_no_execution() {
	tmp := os.join_path(os.temp_dir(), 'hx-ap-plus-status')
	os.rmdir_all(tmp) or {}
	ap_with_xdg(tmp, fn [tmp] () {
		r := colors_report(ColorsOptions{
			action:  'status'
			dry_run: true
		})
		assert r.ok, r.message
		assert r.command == 'appearance colors status'
		assert r.data['dry_run'] == 'true'
	})
	os.rmdir_all(tmp) or {}
}

fn test_colors_status_without_xrdb_fails_cleanly() {
	tmp := os.join_path(os.temp_dir(), 'hx-ap-plus-status-miss')
	os.rmdir_all(tmp) or {}
	ap_with_xdg(tmp, fn [tmp] () {
		r := colors_report(ColorsOptions{
			action: 'status'
		})
		assert !r.ok
		assert r.message.contains('xrdb')
	})
	os.rmdir_all(tmp) or {}
}

fn test_colors_generate_needs_yes() {
	refused := colors_report(ColorsOptions{
		action: 'generate'
	})
	assert !refused.ok
	assert refused.message.contains('--yes')
}

fn test_colors_generate_dry_run_previews_m3() {
	tmp := os.join_path(os.temp_dir(), 'hx-ap-plus-gen')
	os.rmdir_all(tmp) or {}
	ap_with_xdg(tmp, fn [tmp] () {
		r := colors_report(ColorsOptions{
			action:  'generate'
			m3:      true
			dry_run: true
		})
		assert r.ok, r.message
		assert r.message.contains('gen-m3.py')
		assert r.message.contains('--scheme-type')
	})
	os.rmdir_all(tmp) or {}
}

fn test_colors_m3_needs_call_and_yes() {
	empty := colors_report(ColorsOptions{
		action: 'm3'
		yes:    true
	})
	assert !empty.ok
	assert empty.message.contains('--help')
	refused := colors_report(ColorsOptions{
		action: 'm3'
		call:   ['--help']
	})
	assert !refused.ok
	assert refused.message.contains('--yes')
}

fn test_colors_m3_dry_run_previews_passthrough() {
	tmp := os.join_path(os.temp_dir(), 'hx-ap-plus-m3')
	os.rmdir_all(tmp) or {}
	ap_with_xdg(tmp, fn [tmp] () {
		r := colors_report(ColorsOptions{
			action:  'm3'
			call:    ['--help']
			dry_run: true
		})
		assert r.ok, r.message
		assert r.message.contains('gen-m3.py')
		assert r.message.contains('--help')
	})
	os.rmdir_all(tmp) or {}
}

fn test_colors_concept_validates() {
	missing := colors_report(ColorsOptions{
		action: 'concept'
	})
	assert !missing.ok
	assert missing.message.contains('missing concept')
	bogus := colors_report(ColorsOptions{
		action: 'concept'
		value:  'bogus'
	})
	assert !bogus.ok
}

fn test_colors_unknown_action() {
	r := colors_report(ColorsOptions{
		action: 'bogus'
	})
	assert !r.ok
	assert r.message.contains('unknown action')
}

fn test_accent_show_reports_seed_state() {
	tmp := os.join_path(os.temp_dir(), 'hx-ap-plus-accent')
	os.rmdir_all(tmp) or {}
	ap_with_xdg(tmp, fn [tmp] () {
		r := accent_report(AccentOptions{
			action: 'show'
		})
		assert r.ok, r.message
		assert r.command == 'appearance accent show'
	})
	os.rmdir_all(tmp) or {}
}

fn test_accent_set_validates_hex() {
	bad := accent_report(AccentOptions{
		action:  'set'
		value:   'not-a-color'
		dry_run: true
	})
	assert !bad.ok
	assert bad.message.contains('#RRGGBB')
	short := accent_report(AccentOptions{
		action:  'set'
		value:   '#12345'
		dry_run: true
	})
	assert !short.ok
	tmp := os.join_path(os.temp_dir(), 'hx-ap-plus-accent-hex')
	os.rmdir_all(tmp) or {}
	ap_with_xdg(tmp, fn [tmp] () {
		ok_hash := accent_report(AccentOptions{
			action:  'set'
			value:   '#8839ef'
			dry_run: true
		})
		assert ok_hash.ok, ok_hash.message
		assert ok_hash.message.contains('#8839ef')
		ok_bare := accent_report(AccentOptions{
			action:  'set'
			value:   '8839EF'
			dry_run: true
		})
		assert ok_bare.ok, ok_bare.message
	})
	os.rmdir_all(tmp) or {}
}

fn test_accent_set_and_clear_need_yes() {
	refused_set := accent_report(AccentOptions{
		action: 'set'
		value:  '#8839ef'
	})
	assert !refused_set.ok
	assert refused_set.message.contains('--yes')
	refused_clear := accent_report(AccentOptions{
		action: 'clear'
	})
	assert !refused_clear.ok
	assert refused_clear.message.contains('--yes')
}

fn test_accent_unknown_action() {
	r := accent_report(AccentOptions{
		action: 'bogus'
	})
	assert !r.ok
	assert r.message.contains('unknown action')
}

fn test_night_mode_status_reads() {
	tmp := os.join_path(os.temp_dir(), 'hx-ap-plus-night')
	os.rmdir_all(tmp) or {}
	old_path := os.getenv('PATH')
	os.setenv('PATH', tmp, true)
	ap_with_xdg(tmp, fn [tmp] () {
		write_night_state_file('enabled') or { assert false, err.msg() }
		r := night_mode_report(NightModeOptions{
			action: 'status'
		})
		assert r.ok, r.message
		assert r.command == 'appearance night-mode status'
		assert r.data['active'] == 'true'
	})
	os.setenv('PATH', old_path, true)
	os.rmdir_all(tmp) or {}
}

fn test_night_mode_toggle_needs_yes() {
	r := night_mode_report(NightModeOptions{
		action: 'toggle'
	})
	assert !r.ok
	assert r.message.contains('--yes')
}

fn test_night_mode_unknown_action() {
	r := night_mode_report(NightModeOptions{
		action: 'bogus'
	})
	assert !r.ok
	assert r.message.contains('unknown action')
}
