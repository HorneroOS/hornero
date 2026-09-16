module hornero_core

import os

fn capture_test_save_env(keys []string) map[string]string {
	mut saved := map[string]string{}
	for k in keys {
		saved[k] = os.getenv(k)
	}
	return saved
}

fn capture_test_restore_env(saved map[string]string) {
	for k, v in saved {
		if v.len == 0 {
			os.unsetenv(k)
		} else {
			os.setenv(k, v, true)
		}
	}
}

const capture_test_keys = ['HORNERO_SSS_BIN', 'HORNERO_GPU_SCREEN_RECORDER_BIN',
	'HORNERO_RECORDER_MATCH', 'HORNERO_COPYQ_BIN', 'HORNERO_CLIPHIST_BIN', 'HORNERO_WL_PASTE_BIN',
	'XDG_SESSION_TYPE', 'XDG_PICTURES_DIR', 'XDG_VIDEOS_DIR', 'CAELESTIA_RECORDINGS_DIR',
	'XDG_STATE_HOME']

fn capture_test_break_backends() {
	os.setenv('HORNERO_SSS_BIN', '/nonexistent-sss-hornero-test', true)
	os.setenv('HORNERO_GPU_SCREEN_RECORDER_BIN', '/nonexistent-gsr-hornero-test', true)
	os.setenv('HORNERO_RECORDER_MATCH', 'hornero-test-no-such-recorder', true)
	os.setenv('HORNERO_COPYQ_BIN', '/nonexistent-copyq-hornero-test', true)
	os.setenv('HORNERO_CLIPHIST_BIN', '/nonexistent-cliphist-hornero-test', true)
	os.setenv('HORNERO_WL_PASTE_BIN', '/nonexistent-wl-paste-hornero-test', true)
}

fn capture_test_isolate_paths() {
	base := '/tmp/hx-capture-test'
	os.mkdir_all(base + '/pictures') or { assert false }
	os.mkdir_all(base + '/videos') or { assert false }
	os.mkdir_all(base + '/recs') or { assert false }
	os.mkdir_all(base + '/state') or { assert false }
	os.setenv('XDG_PICTURES_DIR', base + '/pictures', true)
	os.setenv('XDG_VIDEOS_DIR', base + '/videos', true)
	os.setenv('CAELESTIA_RECORDINGS_DIR', '', true)
	os.setenv('XDG_STATE_HOME', base + '/state', true)
	os.setenv('XDG_SESSION_TYPE', 'x11', true)
}

fn test_screenshot_needs_yes() {
	r := screenshot_report(ScreenshotOptions{})
	assert !r.ok
	assert r.message.contains('--yes')
}

fn test_screenshot_dry_run_needs_no_backend() {
	saved := capture_test_save_env(capture_test_keys)
	capture_test_break_backends()
	capture_test_isolate_paths()
	r := screenshot_report(ScreenshotOptions{
		dry_run: true
	})
	assert r.ok
	assert r.message.contains('would run:')
	assert r.message.contains('--screen')
	assert r.message.contains('--output')
	assert r.data['output'].ends_with('.png')
	capture_test_restore_env(saved)
}

fn test_screenshot_region_dry_run() {
	saved := capture_test_save_env(capture_test_keys)
	capture_test_break_backends()
	capture_test_isolate_paths()
	r := screenshot_report(ScreenshotOptions{
		region:  true
		dry_run: true
	})
	assert r.ok
	assert r.message.contains('would run:')
	capture_test_restore_env(saved)
}

fn test_screenshot_missing_backend_fails() {
	saved := capture_test_save_env(capture_test_keys)
	capture_test_break_backends()
	capture_test_isolate_paths()
	r := screenshot_report(ScreenshotOptions{
		yes: true
	})
	assert !r.ok
	assert r.message.contains('HORNERO_SSS_BIN')
	capture_test_restore_env(saved)
}

fn test_record_start_needs_yes() {
	r := record_start_report(RecordStartOptions{})
	assert !r.ok
	assert r.message.contains('--yes')
}

fn test_record_start_dry_run_needs_no_backend() {
	saved := capture_test_save_env(capture_test_keys)
	capture_test_break_backends()
	capture_test_isolate_paths()
	r := record_start_report(RecordStartOptions{
		dry_run: true
	})
	assert r.ok
	assert r.message.contains('would run:')
	assert r.message.contains('-w eDP-1')
	assert r.message.contains('-f 30')
	assert r.message.contains('-o ')
	assert r.data['file'].ends_with('.mp4')
	capture_test_restore_env(saved)
}

fn test_record_start_dry_run_flags() {
	saved := capture_test_save_env(capture_test_keys)
	capture_test_break_backends()
	capture_test_isolate_paths()
	r := record_start_report(RecordStartOptions{
		region:  true
		sound:   true
		fps:     60
		dry_run: true
	})
	assert r.ok
	assert r.message.contains('-w region')
	assert r.message.contains('-f 60')
	assert r.message.contains('-a default_output')
	capture_test_restore_env(saved)
}

fn test_record_start_missing_backend_fails() {
	saved := capture_test_save_env(capture_test_keys)
	capture_test_break_backends()
	capture_test_isolate_paths()
	r := record_start_report(RecordStartOptions{
		yes: true
	})
	assert !r.ok
	assert r.message.contains('HORNERO_GPU_SCREEN_RECORDER_BIN')
	capture_test_restore_env(saved)
}

fn test_record_stop_needs_yes() {
	r := record_stop_report(RecordStopOptions{})
	assert !r.ok
	assert r.message.contains('--yes')
}

fn test_record_stop_dry_run() {
	saved := capture_test_save_env(capture_test_keys)
	capture_test_break_backends()
	capture_test_isolate_paths()
	r := record_stop_report(RecordStopOptions{
		dry_run: true
	})
	assert r.ok
	assert r.message.contains('would run:')
	assert r.message.contains('pkill')
	capture_test_restore_env(saved)
}

fn test_record_pause_needs_yes() {
	r := record_pause_report(RecordPauseOptions{})
	assert !r.ok
	assert r.message.contains('--yes')
}

fn test_record_pause_dry_run() {
	saved := capture_test_save_env(capture_test_keys)
	capture_test_break_backends()
	capture_test_isolate_paths()
	r := record_pause_report(RecordPauseOptions{
		dry_run: true
	})
	assert r.ok
	assert r.message.contains('would pause:')
	assert r.message.contains('-STOP')
	capture_test_restore_env(saved)
}

fn test_recorder_pgrep_pattern_is_self_match_free() {
	saved := capture_test_save_env(['HORNERO_RECORDER_MATCH'])
	os.setenv('HORNERO_RECORDER_MATCH', 'hornero-test-no-such-recorder', true)
	pat := recorder_pgrep_pattern()
	assert pat == '[h]ornero-test-no-such-recorder'
	// The pgrep shell wrapper carries the pattern on its own command
	// line; the bracket form must not match itself (regression: a bare
	// pattern always matched and faked a live recording).
	r := os.execute("pgrep -f '${pat}'")
	assert r.exit_code != 0
	capture_test_restore_env(saved)
}

fn test_recorder_pgrep_pattern_matches_live_target() {
	saved := capture_test_save_env(['HORNERO_RECORDER_MATCH'])
	os.unsetenv('HORNERO_RECORDER_MATCH')
	pat := recorder_pgrep_pattern()
	assert pat == '[g]pu-screen-recorder'
	// Fake one recorder command line via argv[0]; it must be found,
	// then reaped so no stray process survives the test.
	os.execute("bash -c 'exec -a gpu-screen-recorder sleep 30' >/dev/null 2>&1 &")
	mut found := false
	for _ in 0 .. 50 {
		r := os.execute("pgrep -f '${pat}'")
		if r.exit_code == 0 {
			found = true
			break
		}
		os.execute('sleep 0.1')
	}
	os.execute("pkill -f '${pat}' >/dev/null 2>&1")
	assert found
	assert os.execute("pgrep -f '${pat}'").exit_code != 0
	capture_test_restore_env(saved)
}

fn test_clipboard_unknown_backend() {
	r := clipboard_report(ClipboardOptions{
		backend: 'bogus'
	})
	assert !r.ok
	assert r.message.contains('unknown backend')
}

fn test_clipboard_dry_run_needs_no_backend() {
	saved := capture_test_save_env(capture_test_keys)
	capture_test_break_backends()
	capture_test_isolate_paths()
	for backend in ['copyq', 'cliphist', 'minimal'] {
		if backend == 'cliphist' {
			os.setenv('XDG_SESSION_TYPE', 'wayland', true)
		}
		r := clipboard_report(ClipboardOptions{
			backend: backend
			dry_run: true
		})
		assert r.ok
		assert r.message.contains('would run:')
		assert r.data['backend'] == backend
		os.setenv('XDG_SESSION_TYPE', 'x11', true)
	}
	capture_test_restore_env(saved)
}

fn test_clipboard_cliphist_wayland_only() {
	saved := capture_test_save_env(capture_test_keys)
	capture_test_break_backends()
	capture_test_isolate_paths()
	r := clipboard_report(ClipboardOptions{
		backend: 'cliphist'
		dry_run: true
	})
	assert !r.ok
	assert r.message.contains('Wayland-only')
	capture_test_restore_env(saved)
}

fn test_clipboard_minimal_no_backend() {
	saved := capture_test_save_env(capture_test_keys)
	capture_test_break_backends()
	capture_test_isolate_paths()
	r := clipboard_report(ClipboardOptions{
		backend: 'minimal'
	})
	assert r.ok
	assert r.message.contains('(no data)')
	capture_test_restore_env(saved)
}

fn test_clipboard_copyq_missing_fails() {
	saved := capture_test_save_env(capture_test_keys)
	capture_test_break_backends()
	capture_test_isolate_paths()
	r := clipboard_report(ClipboardOptions{
		backend: 'copyq'
	})
	assert !r.ok
	assert r.message.contains('HORNERO_COPYQ_BIN')
	capture_test_restore_env(saved)
}
