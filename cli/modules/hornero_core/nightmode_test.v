module hornero_core

import os

fn with_night_xdg(tmp string, body fn ()) {
	os.mkdir_all(tmp) or {}
	os.setenv('XDG_CACHE_HOME', os.join_path(tmp, 'cache'), true)
	os.setenv('HORNERO_REDSHIFT_BIN', '', true)
	os.setenv('HORNERO_GAMMASSTEP_BIN', '', true)
	os.setenv('HORNERO_WLSUNSET_BIN', '', true)
	os.setenv('HORNERO_XRANDR_BIN', '', true)
	os.setenv('HORNERO_PKILL_BIN', '', true)
	os.setenv('HORNERO_NOTIFY_BIN', '', true)
	body()
	os.unsetenv('XDG_CACHE_HOME')
	os.unsetenv('HORNERO_REDSHIFT_BIN')
	os.unsetenv('HORNERO_GAMMASSTEP_BIN')
	os.unsetenv('HORNERO_WLSUNSET_BIN')
	os.unsetenv('HORNERO_XRANDR_BIN')
	os.unsetenv('HORNERO_PKILL_BIN')
	os.unsetenv('HORNERO_NOTIFY_BIN')
}

fn test_classify_night_procs_vectors() {
	active, backend := classify_night_procs(['redshift -O 4000K'], '', '')
	assert active == true
	assert backend == 'redshift (manual)'
	active2, backend2 := classify_night_procs(['gammastep -O 4000K'], '', '')
	assert active2 == true
	assert backend2 == 'gammastep (manual)'
	active3, backend3 := classify_night_procs(['wlsunset -T 4000'], '', '')
	assert active3 == true
	assert backend3 == 'wlsunset'
	// Daemon modes consult the state file.
	active4, _ := classify_night_procs(['redshift -l 10:20'], 'enabled', '')
	assert active4 == true
	active5, _ := classify_night_procs(['redshift -l 10:20'], 'disabled', '')
	assert active5 == false
	// Gamma heuristic: blue channel above 1.2.
	active6, backend6 := classify_night_procs([], '', '1.0:1.0:1.35')
	assert active6 == true
	assert backend6 == 'xrandr'
	active7, _ := classify_night_procs([], '', '1.0:1.0:1.0')
	assert active7 == false
	// State fallback.
	active8, _ := classify_night_procs([], 'enabled', '')
	assert active8 == true
	active9, backend9 := classify_night_procs([], '', '')
	assert active9 == false
	assert backend9 == 'none'
}

fn test_parse_xrandr_vectors() {
	out := 'Screen 0: minimum 8 x 8\nHDMI-1 connected primary 1920x1080+0+0\n   Gamma: 1.0:0.9:0.7\nDP-1 disconnected\n'
	assert parse_xrandr_gamma(out) == '1.0:0.9:0.7'
	assert parse_xrandr_displays(out) == ['HDMI-1']
	assert parse_xrandr_gamma('nope') == ''
}

fn test_night_status_icon_vectors() {
	rep := night_mode_run(NightModeCmd{
		verb:    'status-icon'
		dry_run: true
	})
	assert rep.ok
	assert rep.message == '󰖙'
	rep2 := night_mode_run(NightModeCmd{
		verb:    'status-text'
		dry_run: true
	})
	assert rep2.ok
	assert rep2.message.contains('Day Mode')
	rep3 := night_mode_run(NightModeCmd{
		verb:    'backends'
		dry_run: true
	})
	assert rep3.ok
	assert rep3.message.contains('Available backends:')
	rep4 := night_mode_run(NightModeCmd{
		verb:    'bogus'
		dry_run: true
	})
	assert !rep4.ok
}

fn test_night_toggle_needs_yes() {
	rep := night_mode_run(NightModeCmd{
		verb: 'toggle'
	})
	assert !rep.ok
	assert rep.message.contains('--yes')
}

fn test_night_toggle_dry_run_proves_no_execution() {
	tmp := os.join_path(os.temp_dir(), 'hornero-night-test')
	os.rmdir_all(tmp) or {}
	old_path := os.getenv('PATH')
	os.setenv('PATH', tmp, true)
	with_night_xdg(tmp, fn [tmp] () {
		rep := night_mode_run(NightModeCmd{
			verb:    'toggle'
			dry_run: true
		})
		assert rep.ok, rep.message
		assert rep.data['dry_run'] == 'true'
		assert !os.is_file(resolve_night_state_file())
	})
	os.setenv('PATH', old_path, true)
	os.rmdir_all(tmp) or {}
}

fn test_night_no_backends_fails() {
	tmp := os.join_path(os.temp_dir(), 'hornero-night-noback')
	os.rmdir_all(tmp) or {}
	old_path := os.getenv('PATH')
	os.setenv('PATH', tmp, true)
	with_night_xdg(tmp, fn [tmp] () {
		mut lines := []string{}
		rep := night_enable_native(false, mut lines)
		assert !rep.ok
		assert rep.message.contains('No supported night mode backends')
	})
	os.setenv('PATH', old_path, true)
	os.rmdir_all(tmp) or {}
}
