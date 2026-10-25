module hornero_core

import os

// Studio mode lifecycle tests. The power profile backend is a fake
// powerprofilesctl on a temp path; everything lives under /tmp.

const mode_test_root = '/tmp/hx-studio-mode-test'

fn mode_setup(tag string) string {
	root := '${mode_test_root}/${tag}'
	if os.exists(root) {
		os.rmdir_all(root) or {}
	}
	os.mkdir_all(root) or { assert false }
	profile_file := '${root}/profile.txt'
	os.write_file(profile_file, 'balanced\n') or { assert false }
	fake := '#!/bin/sh\nif [ "$1" = get ]; then cat "${profile_file}"; elif [ "$1" = set ]; then printf "%s\\n" "$2" > "${profile_file}"; fi\n'
	fake_path := '${root}/powerprofilesctl'
	os.write_file(fake_path, fake) or { assert false }
	os.chmod(fake_path, 0o755) or {}
	os.setenv('HORNERO_POWERPROFILESCTL_BIN', fake_path, true)
	os.setenv('HORNERO_STUDIO_MODE_FILE', '${root}/studio-mode.json', true)
	return root
}

fn mode_teardown() {
	os.unsetenv('HORNERO_POWERPROFILESCTL_BIN')
	os.unsetenv('HORNERO_STUDIO_MODE_FILE')
}

fn test_audio_mode_opt_in_and_restore() {
	mode_setup('audio')
	defer {
		mode_teardown()
	}
	// Defaults: Balanced, nothing recorded.
	show := studio_mode_show_result()
	assert show.ok
	assert show.data['audio_mode'] == 'balanced'
	// Opt-in modes refuse without --yes; unknown ids fail.
	assert !studio_audio_mode_set_result('low-latency', false).ok
	assert !studio_audio_mode_set_result('loud', true).ok
	// Opt-in with --yes records mode + previous for exact restore.
	set := studio_audio_mode_set_result('low-latency', true)
	assert set.ok
	assert set.data['audio_mode'] == 'low-latency'
	assert set.data['previous_audio_mode'] == 'balanced'
	// Same mode again is a no-op that keeps the restore target.
	assert studio_audio_mode_set_result('low-latency', true).data['previous_audio_mode'] == 'balanced'
	restored := studio_mode_restore_result()
	assert restored.ok
	assert restored.data['audio_mode'] == 'balanced'
	assert restored.data['previous_audio_mode'] == ''
	// Nothing left to restore is a successful no-op.
	assert studio_mode_restore_result().ok
}

fn test_performance_mode_records_and_restores_previous_profile() {
	root := mode_setup('perf')
	defer {
		mode_teardown()
	}
	// Requires explicit opt-in.
	assert !studio_performance_set_result(false, 0).ok
	on := studio_performance_set_result(true, 60)
	assert on.ok
	assert on.data['performance_active'] == 'true'
	assert on.data['performance_previous'] == 'balanced'
	assert os.read_file('${root}/profile.txt') or { '' }.trim_space() == 'performance'
	// Second enable refuses; restore returns the exact previous profile.
	assert !studio_performance_set_result(true, 0).ok
	off := studio_mode_restore_result()
	assert off.ok
	assert off.data['performance_active'] == 'false'
	assert os.read_file('${root}/profile.txt') or { '' }.trim_space() == 'balanced'
}

fn test_mode_state_fails_closed_on_corrupt_file() {
	root := mode_setup('corrupt')
	defer {
		mode_teardown()
	}
	os.write_file('${root}/studio-mode.json', '{"schemaVersion": 99}') or { assert false }
	assert !studio_mode_show_result().ok
	os.write_file('${root}/studio-mode.json', '{"schemaVersion": 1, "audioMode": "loud"}') or {
		assert false
	}
	assert !studio_audio_mode_set_result('balanced', true).ok
}
