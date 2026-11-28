module hornero_cli

import os

const playground_dispatch_test_root = '/tmp/hx-playground-dispatch-test'

fn playground_dispatch_setup() string {
	if os.exists(playground_dispatch_test_root) {
		os.rmdir_all(playground_dispatch_test_root) or {}
	}
	os.mkdir_all('${playground_dispatch_test_root}/state/hornero-presenter') or { assert false }
	os.mkdir_all('${playground_dispatch_test_root}/state/hornero-playground') or { assert false }
	os.setenv('XDG_STATE_HOME', '${playground_dispatch_test_root}/state', true)
	os.setenv('HORNERO_PRESENTER_STATE_DIR', '${playground_dispatch_test_root}/state/hornero-presenter',
		true)
	os.setenv('HORNERO_PLAYGROUND_STATE_DIR', '${playground_dispatch_test_root}/state/hornero-playground',
		true)
	os.setenv('HORNERO_BYPASS_QUICKSHELL', '1', true)
	os.setenv('HORNERO_QS_BIN', '/nonexistent-qs-dtest', true)
	os.setenv('HORNERO_PRESENTER_BIN', '/nonexistent-presenter-dtest', true)
	os.setenv('HORNERO_VM_RUN_BIN', '/nonexistent-vm-run-dtest', true)
	os.setenv('HORNERO_GPU_SCREEN_RECORDER_BIN', '/nonexistent-gsr-dtest', true)
	return playground_dispatch_test_root
}

fn playground_dispatch_teardown() {
	for k in ['XDG_STATE_HOME', 'HORNERO_PRESENTER_STATE_DIR', 'HORNERO_PLAYGROUND_STATE_DIR',
		'HORNERO_BYPASS_QUICKSHELL', 'HORNERO_QS_BIN', 'HORNERO_PRESENTER_BIN', 'HORNERO_VM_RUN_BIN',
		'HORNERO_GPU_SCREEN_RECORDER_BIN'] {
		os.unsetenv(k)
	}
	if os.exists(playground_dispatch_test_root) {
		os.rmdir_all(playground_dispatch_test_root) or {}
	}
}

fn test_playground_and_presenter_help_and_completions() {
	assert root_help().contains('playground')
	assert root_help().contains('presenter')
	assert bash_completion().contains('playground')
	assert bash_completion().contains('presenter')
	assert zsh_completion().contains('playground')
	assert zsh_completion().contains('presenter')
	assert fish_completion().contains('-a playground ')
	assert fish_completion().contains('-a presenter ')

	for topic in ['playground', 'playground doctor', 'playground profiles', 'playground scenarios',
		'playground status', 'playground up', 'playground down', 'presenter', 'presenter status',
		'presenter start', 'presenter stop', 'presenter record', 'presenter stop-recording',
		'presenter export'] {
		h := command_help(topic)
		assert h.contains('Examples:'), '${topic} help missing Examples:'
	}
	assert command_help('presenter export').contains('hornero-<scenario>/{recordings/{desktop-master.mkv,desktop-preview.mp4},audio/{system.flac,narration.flac},screenshots/,thumbnails/,chapters.json,subtitles.srt,project.kdenlive,manifest.json}')

	assert dispatch(['horneroctl', 'playground', '--help']) == 0
	assert dispatch(['horneroctl', 'playground', 'doctor', '--help']) == 0
	assert dispatch(['horneroctl', 'playground', 'up', '--help']) == 0
	assert dispatch(['horneroctl', 'presenter', '--help']) == 0
	assert dispatch(['horneroctl', 'presenter', 'start', '--help']) == 0
	assert dispatch(['horneroctl', 'presenter', 'export', '--help']) == 0
	assert dispatch(['horneroctl', 'help', 'playground']) == 0
	assert dispatch(['horneroctl', 'help', 'presenter']) == 0
}

fn test_playground_and_presenter_usage_errors_exit_two() {
	assert dispatch(['horneroctl', 'playground']) == 2
	assert dispatch(['horneroctl', 'playground', 'bogus']) == 2
	assert dispatch(['horneroctl', 'playground', 'doctor', '--bogus']) == 2
	assert dispatch(['horneroctl', 'playground', 'profiles', '--bogus']) == 2
	assert dispatch(['horneroctl', 'playground', 'scenarios', 'extra']) == 2
	assert dispatch(['horneroctl', 'playground', 'status', '--bogus']) == 2
	assert dispatch(['horneroctl', 'playground', 'up', '--bogus']) == 2
	assert dispatch(['horneroctl', 'playground', 'up', '--cpus', 'abc']) == 2
	assert dispatch(['horneroctl', 'playground', 'down', '--bogus']) == 2

	assert dispatch(['horneroctl', 'presenter']) == 2
	assert dispatch(['horneroctl', 'presenter', 'bogus']) == 2
	assert dispatch(['horneroctl', 'presenter', 'status', '--bogus']) == 2
	assert dispatch(['horneroctl', 'presenter', 'start', '--bogus']) == 2
	assert dispatch(['horneroctl', 'presenter', 'start', '--fps', 'abc']) == 2
	assert dispatch(['horneroctl', 'presenter', 'stop', '--resolution', '1920x1080']) == 2
	assert dispatch(['horneroctl', 'presenter', 'export', '--bogus']) == 2
}

fn test_playground_dispatch_reads_dry_run_and_guards() {
	playground_dispatch_setup()
	defer {
		playground_dispatch_teardown()
	}
	assert dispatch(['horneroctl', '--json', 'playground', 'profiles']) == 0
	assert dispatch(['horneroctl', '--json', 'playground', 'scenarios']) == 0
	assert dispatch(['horneroctl', '--json', 'playground', 'status']) == 0
	assert dispatch(['horneroctl', '--json', 'playground', 'up', '--provider', 'local', '--dry-run']) == 0
	assert dispatch(['horneroctl', '--quiet', 'playground', 'up', '--provider', 'local']) == 1
	assert dispatch(['horneroctl', '--json', 'playground', 'up', '--provider', 'hetzner', '--dry-run']) == 1
	assert dispatch(['horneroctl', '--json', 'playground', 'down', '--dry-run']) == 0
	assert dispatch(['horneroctl', '--quiet', 'playground', 'down']) == 1
}

fn test_presenter_dispatch_dry_runs_and_validation() {
	root := playground_dispatch_setup()
	defer {
		playground_dispatch_teardown()
	}
	assert dispatch(['horneroctl', '--json', 'presenter', 'status']) == 0
	assert dispatch(['horneroctl', '--json', 'presenter', 'start', '--resolution', '1920x1080',
		'--dry-run']) == 0
	assert dispatch(['horneroctl', '--json', 'presenter', 'start', '--scenario', 'first-flight',
		'--resolution', '3840x2160', '--fps', '60', '--dry-run']) == 0
	assert dispatch(['horneroctl', '--json', 'presenter', 'stop', '--dry-run']) == 0
	assert dispatch(['horneroctl', '--json', 'presenter', 'record', '--scenario', 'creative-studio',
		'--resolution', 'uhd4k', '--fps', '60', '--output', root, '--dry-run']) == 0
	assert dispatch(['horneroctl', '--json', 'presenter', 'stop-recording', '--dry-run']) == 0
	assert dispatch(['horneroctl', '--json', 'presenter', 'export', '--scenario', 'first-flight',
		'--resolution', '3840x2160', '--fps', '60', '--output', root, '--dry-run']) == 0

	// Mutating actions without --yes (and without --dry-run) refuse with exit 1.
	assert dispatch(['horneroctl', '--quiet', 'presenter', 'start', '--resolution', '1920x1080']) == 1
	assert dispatch(['horneroctl', '--quiet', 'presenter', 'stop']) == 1
	assert dispatch(['horneroctl', '--quiet', 'presenter', 'export', '--scenario', 'first-flight']) == 1

	// Invalid resolution / scenario / fps fail cleanly (exit 1).
	assert dispatch(['horneroctl', '--quiet', 'presenter', 'start', '--resolution', 'invalid-res',
		'--dry-run']) == 1
	assert dispatch(['horneroctl', '--quiet', 'presenter', 'start', '--scenario', 'bogus-scenario',
		'--dry-run']) == 1
	assert dispatch(['horneroctl', '--quiet', 'presenter', 'start', '--fps', '24', '--dry-run']) == 1
}
