module hornero_core

import os

// Appearance-plus native tests: colors guards and dry-run previews proving
// non-execution, plus night-mode. XDG overrides isolate every write.

fn ap_with_xdg(tmp string, body fn ()) {
	os.mkdir_all(tmp) or {}
	os.setenv('XDG_CONFIG_HOME', os.join_path(tmp, 'config'), true)
	os.setenv('XDG_DATA_HOME', os.join_path(tmp, 'data'), true)
	os.setenv('XDG_STATE_HOME', os.join_path(tmp, 'state'), true)
	os.setenv('XDG_CACHE_HOME', os.join_path(tmp, 'cache'), true)
	os.setenv('HORNERO_GTK2_FILE', os.join_path(tmp, 'gtkrc-2.0'), true)
	os.setenv('HORNERO_GSETTINGS_BIN', '/nonexistent-gsettings', true)
	os.setenv('HORNERO_SHELL_RUNNING', '0', true)
	body()
	for name in ['XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_CACHE_HOME',
		'HORNERO_GTK2_FILE', 'HORNERO_GSETTINGS_BIN', 'HORNERO_SHELL_RUNNING'] {
		os.unsetenv(name)
	}
}

fn test_colors_status_dry_run_proves_no_execution() {
	r := colors_report(ColorsOptions{
		action:  'status'
		dry_run: true
	})
	assert r.ok
	assert r.data['dry_run'] == 'true'
	assert r.message.contains('signal/scheme.json')
}

fn test_colors_status_without_scheme_fails_cleanly() {
	tmp := os.join_path(os.temp_dir(), 'hx-ap-plus-noscheme')
	os.rmdir_all(tmp) or {}
	ap_with_xdg(tmp, fn () {
		r := colors_report(ColorsOptions{
			action: 'status'
		})
		assert !r.ok
		assert r.message.contains('appearance sync --yes')
	})
	os.rmdir_all(tmp) or {}
}

fn test_colors_generate_needs_yes() {
	r := colors_report(ColorsOptions{
		action: 'generate'
	})
	assert !r.ok
	assert r.message.contains('--yes')
}

fn test_colors_concept_validates() {
	missing := colors_report(ColorsOptions{
		action: 'concept'
	})
	assert !missing.ok
	bad := colors_concept_native('bogus')
	assert !bad.ok
	assert bad.message.contains('unknown concept')
}

fn test_colors_unknown_action() {
	for action in ['bogus', 'm3'] {
		r := colors_report(ColorsOptions{
			action: action
		})
		assert !r.ok
		assert r.message.contains('unknown action')
	}
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
