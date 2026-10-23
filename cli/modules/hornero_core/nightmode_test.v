module hornero_core

import os
import time

fn with_night_xdg(tmp string, body fn ()) {
	keys := ['XDG_CACHE_HOME', 'HORNERO_REDSHIFT_BIN', 'HORNERO_GAMMASSTEP_BIN', 'HORNERO_WLSUNSET_BIN',
		'HORNERO_XRANDR_BIN', 'HORNERO_PKILL_BIN', 'HORNERO_NOTIFY_BIN', 'HORNERO_NIGHT_MODE_STATE_FILE']
	mut saved := map[string]string{}
	for key in keys {
		saved[key] = os.getenv(key)
	}
	os.mkdir_all(tmp) or {}
	os.setenv('XDG_CACHE_HOME', os.join_path(tmp, 'cache'), true)
	os.setenv('HORNERO_NIGHT_MODE_STATE_FILE', '', true)
	os.setenv('HORNERO_REDSHIFT_BIN', '', true)
	os.setenv('HORNERO_GAMMASSTEP_BIN', '', true)
	os.setenv('HORNERO_WLSUNSET_BIN', '', true)
	os.setenv('HORNERO_XRANDR_BIN', '', true)
	os.setenv('HORNERO_PKILL_BIN', '', true)
	os.setenv('HORNERO_NOTIFY_BIN', '', true)
	body()
	for key, value in saved {
		if value.len == 0 {
			os.unsetenv(key)
		} else {
			os.setenv(key, value, true)
		}
	}
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
	tmp := os.join_path(os.temp_dir(), 'hornero-night-status-${os.getpid()}-${time.now().unix_milli()}')
	defer { os.rmdir_all(tmp) or {} }
	with_night_xdg(tmp, fn () {
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
	})
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

fn test_night_temperature_clamp_and_defaults() {
	assert night_clamp_temperature(0) == night_default_temperature
	assert night_clamp_temperature(4000) == 4000
	assert night_clamp_temperature(500) == night_min_temperature
	assert night_clamp_temperature(9000) == night_max_temperature
}

fn test_night_temperature_backend_args() {
	assert night_backend_temp_args('redshift', 3500) == ['-O', '3500K']
	assert night_backend_temp_args('gammastep', 3500) == ['-O', '3500K']
	assert night_backend_temp_args('wlsunset', 3500) == ['-T', '3500']
	assert night_backend_temp_args('xrandr', 3500).len == 0
}

fn test_night_xrandr_gamma_vectors() {
	assert night_xrandr_gamma(6500) == '1:1:1'
	assert night_xrandr_gamma(4000) == '1:0.85:0.6'
	assert night_xrandr_gamma(1000) == '1:0.65:0.35'
	warm := night_xrandr_gamma(2500)
	assert warm.starts_with('1:0.')
}

fn test_night_temperature_persists_next_to_state() {
	tmp := os.join_path(os.temp_dir(), 'hornero-night-temp')
	os.rmdir_all(tmp) or {}
	with_night_xdg(tmp, fn [tmp] () {
		assert read_night_temperature() == night_default_temperature
		write_night_temperature(3200) or { panic(err) }
		assert read_night_temperature() == 3200
		assert resolve_night_temperature_file().ends_with('night_mode_temperature')
	})
	os.rmdir_all(tmp) or {}
}

fn test_night_parse_hhmm_vectors() {
	mut mins, mut ok := night_parse_hhmm('22:00')
	assert ok && mins == 1320
	mins, ok = night_parse_hhmm('7:05')
	assert ok && mins == 425
	mins, ok = night_parse_hhmm('00:00')
	assert ok && mins == 0
	_, ok = night_parse_hhmm('24:00')
	assert !ok
	_, ok = night_parse_hhmm('12:60')
	assert !ok
	_, ok = night_parse_hhmm('noon')
	assert !ok
	_, ok = night_parse_hhmm('1200')
	assert !ok
	assert night_format_hhmm(1320) == '22:00'
	assert night_format_hhmm(425) == '07:05'
	assert night_format_hhmm(0) == '00:00'
}

fn test_night_schedule_active_at_windows() {
	// Same-day window 08:00-17:00.
	assert night_schedule_active_at(480, 1020, 600)
	assert !night_schedule_active_at(480, 1020, 479)
	assert !night_schedule_active_at(480, 1020, 1020)
	// Overnight window 22:00-07:00 wraps midnight.
	assert night_schedule_active_at(1320, 420, 1380)
	assert night_schedule_active_at(1320, 420, 60)
	assert !night_schedule_active_at(1320, 420, 720)
	assert !night_schedule_active_at(1320, 420, 420)
	// Empty window never active.
	assert !night_schedule_active_at(600, 600, 600)
}

fn test_night_schedule_file_roundtrip() {
	tmp := os.join_path(os.temp_dir(), 'hornero-night-sched')
	os.rmdir_all(tmp) or {}
	with_night_xdg(tmp, fn [tmp] () {
		on, off, present := read_night_schedule()
		assert !present && on == -1 && off == -1
		write_night_schedule(1320, 420) or { panic(err) }
		on2, off2, present2 := read_night_schedule()
		assert present2 && on2 == 1320 && off2 == 420
		assert resolve_night_schedule_file().ends_with('night_mode_schedule')
		clear_night_schedule()
		_, _, present3 := read_night_schedule()
		assert !present3
	})
	os.rmdir_all(tmp) or {}
}

fn test_night_schedule_unit_contents() {
	svc := night_schedule_service_content('/home/user/.local/bin/horneroctl', 'on')
	assert svc.contains('Type=oneshot')
	assert svc.contains('ExecStart=/home/user/.local/bin/horneroctl appearance night-mode on --yes')
	timer := night_schedule_timer_content('22:00', 'on')
	assert timer.contains('OnCalendar=*-*-* 22:00:00')
	assert timer.contains('Persistent=true')
	assert timer.contains('Unit=hornero-nightlight-on.service')
	assert timer.contains('WantedBy=timers.target')
	assert night_schedule_unit_name('off', true) == 'hornero-nightlight-off.timer'
	assert night_schedule_unit_name('on', false) == 'hornero-nightlight-on.service'
}

fn test_night_set_stores_temperature_when_inactive() {
	tmp := os.join_path(os.temp_dir(), 'hornero-night-set')
	os.rmdir_all(tmp) or {}
	old_path := os.getenv('PATH')
	os.setenv('PATH', tmp, true)
	with_night_xdg(tmp, fn [tmp] () {
		rep := night_mode_run(NightModeCmd{
			verb:        'set'
			temperature: 3000
			yes:         true
		})
		assert rep.ok, rep.message
		assert read_night_temperature() == 3000
		assert rep.data['temperature'] == '3000'
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
		rep := night_enable_native(false, mut lines, 4000)
		assert !rep.ok
		assert rep.message.contains('No supported night mode backends')
	})
	os.setenv('PATH', old_path, true)
	os.rmdir_all(tmp) or {}
}
