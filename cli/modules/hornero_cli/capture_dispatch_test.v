module hornero_cli

import os

// Capture dispatch fixtures: fake backends under /tmp plus an isolated
// XDG tree. The fakes never record, capture, or notify: fake-gsr answers
// --list-monitors and otherwise exits at once (so a real start --yes
// fails its pgrep confirmation), fake-sss touches the --output file.
// HORNERO_RECORDER_MATCH points at a pattern nothing matches, so stop
// and pause --yes runs are safe no-ops. Each test restores the
// environment it found.
const cap_dtest_base = '/tmp/hx-capture-dtest'

fn cap_dispatch_keys() []string {
	return ['HORNERO_SSS_BIN', 'HORNERO_GPU_SCREEN_RECORDER_BIN', 'HORNERO_RECORDER_MATCH',
		'HORNERO_COPYQ_BIN', 'HORNERO_CLIPHIST_BIN', 'HORNERO_WL_PASTE_BIN', 'XDG_SESSION_TYPE',
		'XDG_PICTURES_DIR', 'XDG_VIDEOS_DIR', 'CAELESTIA_RECORDINGS_DIR', 'XDG_STATE_HOME']
}

fn cap_dispatch_setup() map[string]string {
	mut saved := map[string]string{}
	for k in cap_dispatch_keys() {
		saved[k] = os.getenv(k)
	}
	base := cap_dtest_base
	os.rmdir_all(base) or {}
	os.mkdir_all(base + '/bin') or { assert false }
	os.mkdir_all(base + '/pictures') or { assert false }
	os.mkdir_all(base + '/videos') or { assert false }
	os.mkdir_all(base + '/state') or { assert false }
	os.write_file(base + '/bin/fake-sss', '#!/bin/sh\nout=""\nprev=""\nfor a in "\$@"; do\n  if [ "\$prev" = "--output" ]; then out="\$a"; fi\n  prev="\$a"\ndone\n[ -n "\$out" ] && : > "\$out"\necho "fake-sss \$*"\nexit 0\n') or {
		assert false
	}
	os.write_file(base + '/bin/fake-gsr', '#!/bin/sh\nif [ "\$1" = "--list-monitors" ]; then echo "eDP-1|1920x1080+0+0"; exit 0; fi\necho "fake-gsr \$*"\nexit 0\n') or {
		assert false
	}
	os.write_file(base + '/bin/fake-copyq', '#!/bin/sh\necho "fake-copyq \$*"\nexit 0\n') or {
		assert false
	}
	os.write_file(base + '/bin/fake-cliphist', '#!/bin/sh\nif [ "\$1" = "list" ]; then printf "1\\tfirst entry\\n2\\tsecond entry\\n"; exit 0; fi\necho "fake-cliphist \$*"\nexit 0\n') or {
		assert false
	}
	os.write_file(base + '/bin/fake-wl-paste', '#!/bin/sh\nprintf "hello-clipboard"\nexit 0\n') or {
		assert false
	}
	for b in ['fake-sss', 'fake-gsr', 'fake-copyq', 'fake-cliphist', 'fake-wl-paste'] {
		os.chmod(base + '/bin/' + b, 0o755) or { assert false }
	}
	os.setenv('HORNERO_SSS_BIN', base + '/bin/fake-sss', true)
	os.setenv('HORNERO_GPU_SCREEN_RECORDER_BIN', base + '/bin/fake-gsr', true)
	os.setenv('HORNERO_RECORDER_MATCH', 'hornero-test-no-such-recorder', true)
	os.setenv('HORNERO_COPYQ_BIN', base + '/bin/fake-copyq', true)
	os.setenv('HORNERO_CLIPHIST_BIN', base + '/bin/fake-cliphist', true)
	os.setenv('HORNERO_WL_PASTE_BIN', base + '/bin/fake-wl-paste', true)
	os.setenv('XDG_SESSION_TYPE', 'x11', true)
	os.setenv('XDG_PICTURES_DIR', base + '/pictures', true)
	os.setenv('XDG_VIDEOS_DIR', base + '/videos', true)
	os.setenv('CAELESTIA_RECORDINGS_DIR', '', true)
	os.setenv('XDG_STATE_HOME', base + '/state', true)
	return saved
}

fn cap_dispatch_break_backends() {
	os.setenv('HORNERO_SSS_BIN', '/nonexistent-sss-hornero-test', true)
	os.setenv('HORNERO_GPU_SCREEN_RECORDER_BIN', '/nonexistent-gsr-hornero-test', true)
	os.setenv('HORNERO_COPYQ_BIN', '/nonexistent-copyq-hornero-test', true)
	os.setenv('HORNERO_CLIPHIST_BIN', '/nonexistent-cliphist-hornero-test', true)
	os.setenv('HORNERO_WL_PASTE_BIN', '/nonexistent-wl-paste-hornero-test', true)
}

fn cap_dispatch_teardown(saved map[string]string) {
	for k, v in saved {
		if v.len == 0 {
			os.unsetenv(k)
		} else {
			os.setenv(k, v, true)
		}
	}
}

fn test_dispatch_capture_usage() {
	saved := cap_dispatch_setup()
	assert dispatch(['horneroctl', 'capture']) == 2
	assert dispatch(['horneroctl', 'capture', 'bogus']) == 2
	assert dispatch(['horneroctl', 'capture', 'record']) == 2
	assert dispatch(['horneroctl', 'capture', 'record', 'bogus']) == 2
	assert dispatch(['horneroctl', 'capture', '--help']) == 0
	assert dispatch(['horneroctl', 'help', 'capture']) == 0
	cap_dispatch_teardown(saved)
}

fn test_capture_help_has_examples() {
	h := command_help('capture')
	assert h.contains('Examples:')
}

fn test_dispatch_screenshot() {
	saved := cap_dispatch_setup()
	assert dispatch(['horneroctl', 'capture', 'screenshot', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'capture', 'screenshot', '--region', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'capture', 'screenshot']) == 1
	assert dispatch(['horneroctl', 'capture', 'screenshot', '--bogus']) == 2
	assert dispatch(['horneroctl', 'capture', 'screenshot', '--fps', '30']) == 2
	assert dispatch(['horneroctl', 'capture', 'screenshot', '--output']) == 2
	assert dispatch(['horneroctl', 'capture', 'screenshot', 'extra']) == 2
	// Real run against the fake backend writes the explicit output file.
	out := cap_dtest_base + '/shot.png'
	os.rm(out) or {}
	assert dispatch(['horneroctl', 'capture', 'screenshot', '--output', out, '--yes']) == 0
	assert os.is_file(out)
	cap_dispatch_teardown(saved)
}

fn test_screenshot_dry_run_needs_no_backend() {
	saved := cap_dispatch_setup()
	cap_dispatch_break_backends()
	assert dispatch(['horneroctl', 'capture', 'screenshot', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'capture', 'screenshot', '--region', '--dry-run']) == 0
	cap_dispatch_teardown(saved)
}

fn test_dispatch_record_start() {
	saved := cap_dispatch_setup()
	assert dispatch(['horneroctl', 'capture', 'record', 'start', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'capture', 'record', 'start', '--region', '--sound', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'capture', 'record', 'start', '--sr', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'capture', 'record', 'start', '--fps', '60', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'capture', 'record', 'start', '--fps=60', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'capture', 'record', 'start']) == 1
	assert dispatch(['horneroctl', 'capture', 'record', 'start', '--fps', 'abc']) == 2
	assert dispatch(['horneroctl', 'capture', 'record', 'start', '--fps', '0']) == 2
	assert dispatch(['horneroctl', 'capture', 'record', 'start', '--fps']) == 2
	assert dispatch(['horneroctl', 'capture', 'record', 'start', '--bogus']) == 2
	assert dispatch(['horneroctl', 'capture', 'record', 'start', '--output', 'x']) == 2
	assert dispatch(['horneroctl', 'capture', 'record', 'start', '--backend', 'copyq']) == 2
	assert dispatch(['horneroctl', 'capture', 'record', 'start', 'extra']) == 2
	cap_dispatch_teardown(saved)
}

fn test_record_start_dry_run_needs_no_backend() {
	saved := cap_dispatch_setup()
	cap_dispatch_break_backends()
	assert dispatch(['horneroctl', 'capture', 'record', 'start', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'capture', 'record', 'start', '--sr', '--fps', '60', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'capture', 'record', 'stop', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'capture', 'record', 'pause', '--dry-run']) == 0
	cap_dispatch_teardown(saved)
}

fn test_record_start_confirms_launch() {
	// The fake backend exits at once, so the pgrep confirmation fails:
	// no real recording is ever started, and the run reports failure.
	saved := cap_dispatch_setup()
	assert dispatch(['horneroctl', 'capture', 'record', 'start', '--yes']) == 1
	assert !os.is_file(cap_dtest_base + '/state/dots/recorder/current_file')
	cap_dispatch_teardown(saved)
}

fn test_dispatch_record_stop_pause() {
	saved := cap_dispatch_setup()
	assert dispatch(['horneroctl', 'capture', 'record', 'stop', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'capture', 'record', 'pause', '--dry-run']) == 0
	// Safe no-ops: the match pattern hits no real process.
	assert dispatch(['horneroctl', 'capture', 'record', 'stop', '--yes']) == 0
	assert dispatch(['horneroctl', 'capture', 'record', 'pause', '--yes']) == 0
	assert dispatch(['horneroctl', 'capture', 'record', 'stop']) == 1
	assert dispatch(['horneroctl', 'capture', 'record', 'pause']) == 1
	assert dispatch(['horneroctl', 'capture', 'record', 'stop', '--region']) == 2
	assert dispatch(['horneroctl', 'capture', 'record', 'pause', '--fps', '30']) == 2
	assert dispatch(['horneroctl', 'capture', 'record', 'stop', '--bogus']) == 2
	cap_dispatch_teardown(saved)
}

fn test_dispatch_clipboard() {
	saved := cap_dispatch_setup()
	assert dispatch(['horneroctl', 'capture', 'clipboard']) == 0
	assert dispatch(['horneroctl', 'capture', 'clipboard', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'capture', 'clipboard', '--backend', 'copyq', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'capture', 'clipboard', '--backend', 'copyq']) == 0
	assert dispatch(['horneroctl', 'capture', 'clipboard', '--backend', 'minimal']) == 0
	assert dispatch(['horneroctl', 'capture', 'clipboard', '--backend', 'bogus']) == 2
	assert dispatch(['horneroctl', 'capture', 'clipboard', '--backend']) == 2
	assert dispatch(['horneroctl', 'capture', 'clipboard', '--backend', 'copyq', '--yes']) == 2
	assert dispatch(['horneroctl', 'capture', 'clipboard', '--region']) == 2
	assert dispatch(['horneroctl', 'capture', 'clipboard', 'extra']) == 2
	// cliphist is Wayland-only: x11 here, so it fails without running.
	assert dispatch(['horneroctl', 'capture', 'clipboard', '--backend', 'cliphist']) == 1
	// Under Wayland the fake lists history read-only.
	os.setenv('XDG_SESSION_TYPE', 'wayland', true)
	assert dispatch(['horneroctl', 'capture', 'clipboard', '--backend', 'cliphist']) == 0
	assert dispatch(['horneroctl', 'capture', 'clipboard', '--backend', 'cliphist', '--dry-run']) == 0
	cap_dispatch_teardown(saved)
}

fn test_clipboard_dry_run_needs_no_backend() {
	saved := cap_dispatch_setup()
	cap_dispatch_break_backends()
	assert dispatch(['horneroctl', 'capture', 'clipboard', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'capture', 'clipboard', '--backend', 'copyq', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'capture', 'clipboard', '--backend', 'minimal', '--dry-run']) == 0
	os.setenv('XDG_SESSION_TYPE', 'wayland', true)
	assert dispatch(['horneroctl', 'capture', 'clipboard', '--backend', 'cliphist', '--dry-run']) == 0
	cap_dispatch_teardown(saved)
}

fn test_capture_json_and_quiet_modes() {
	saved := cap_dispatch_setup()
	assert dispatch(['horneroctl', '--json', 'capture', 'screenshot', '--dry-run']) == 0
	assert dispatch(['horneroctl', '--quiet', 'capture', 'screenshot', '--dry-run']) == 0
	assert dispatch(['horneroctl', '--json', 'capture', 'record', 'start', '--dry-run']) == 0
	assert dispatch(['horneroctl', '--quiet', 'capture', 'record', 'stop', '--dry-run']) == 0
	assert dispatch(['horneroctl', '--json', 'capture', 'clipboard']) == 0
	assert dispatch(['horneroctl', '--quiet', 'capture', 'clipboard', '--dry-run']) == 0
	cap_dispatch_teardown(saved)
}
