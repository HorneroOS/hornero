module hornero_cli

import os

const profile_dispatch_test_root = '/tmp/hx-profile-dispatch-test'

fn profile_dispatch_setup() string {
	root := profile_dispatch_test_root
	if os.exists(root) {
		os.rmdir_all(root) or {}
	}
	os.mkdir_all('${root}/config/hornero') or { assert false }
	os.mkdir_all('${root}/state/hornero') or { assert false }
	os.mkdir_all('${root}/profiles') or { assert false }
	os.mkdir_all('${root}/profiles-state') or { assert false }
	os.setenv('XDG_CONFIG_HOME', '${root}/config', true)
	os.setenv('XDG_STATE_HOME', '${root}/state', true)
	os.setenv('HORNERO_PROFILES_DIR', '${root}/profiles', true)
	os.setenv('HORNERO_PROFILES_STATE_DIR', '${root}/profiles-state', true)
	os.setenv('HORNERO_BYPASS_QUICKSHELL', '1', true)
	os.setenv('HORNERO_PROFILE_RUNNING_PROCS', '', true)
	os.setenv('HORNERO_PACTL_BIN', '/nonexistent-pactl-test', true)
	os.setenv('HORNERO_PW_METADATA_BIN', '/nonexistent-pw-metadata-test', true)
	os.setenv('HORNERO_POWERPROFILESCTL_BIN', '/nonexistent-ppctl-test', true)
	return root
}

fn profile_dispatch_teardown() {
	for k in ['XDG_CONFIG_HOME', 'XDG_STATE_HOME', 'HORNERO_PROFILES_DIR', 'HORNERO_PROFILES_STATE_DIR',
		'HORNERO_BYPASS_QUICKSHELL', 'HORNERO_PROFILE_RUNNING_PROCS', 'HORNERO_PACTL_BIN',
		'HORNERO_PW_METADATA_BIN', 'HORNERO_POWERPROFILESCTL_BIN'] {
		os.unsetenv(k)
	}
}

fn test_profile_help_and_completions() {
	assert root_help().contains('profile')
	assert bash_completion().contains('profile')
	assert zsh_completion().contains('profile')
	assert fish_completion().contains('-a profile ')
	for topic in ['profile', 'profile list', 'profile show', 'profile capture', 'profile diff',
		'profile apply', 'profile revert', 'profile delete', 'profile launch-apps', 'profile export',
		'profile import'] {
		h := command_help(topic)
		assert h.contains('Examples:'), '${topic} help missing Examples:'
	}
	assert dispatch(['horneroctl', 'profile', '--help']) == 0
	assert dispatch(['horneroctl', 'profile', 'capture', '--help']) == 0
	assert dispatch(['horneroctl', 'help', 'profile']) == 0
}

fn test_profile_usage_errors_exit_two() {
	assert dispatch(['horneroctl', 'profile']) == 2
	assert dispatch(['horneroctl', 'profile', 'bogus']) == 2
	assert dispatch(['horneroctl', 'profile', 'list', '--bogus']) == 2
	assert dispatch(['horneroctl', 'profile', 'show']) == 2
	assert dispatch(['horneroctl', 'profile', 'diff']) == 2
	assert dispatch(['horneroctl', 'profile', 'capture']) == 2
	assert dispatch(['horneroctl', 'profile', 'capture', 'demo', '--bogus']) == 2
	assert dispatch(['horneroctl', 'profile', 'apply', 'demo', '--bogus']) == 2
	assert dispatch(['horneroctl', 'profile', 'revert', '--bogus']) == 2
	assert dispatch(['horneroctl', 'profile', 'delete']) == 2
	assert dispatch(['horneroctl', 'profile', 'launch-apps']) == 2
	assert dispatch(['horneroctl', 'profile', 'export', 'demo']) == 2
	assert dispatch(['horneroctl', 'profile', 'import']) == 2
}

fn test_profile_dispatch_lifecycle_yes_gate_and_dry_run() {
	root := profile_dispatch_setup()
	defer {
		profile_dispatch_teardown()
	}
	assert dispatch(['horneroctl', '--json', 'profile', 'list']) == 0
	// Missing --yes fails with 1.
	assert dispatch(['horneroctl', '--quiet', 'profile', 'capture', 'work']) == 1
	// Dry-run succeeds with 0.
	assert dispatch(['horneroctl', '--json', 'profile', 'capture', 'work', '--dry-run']) == 0
	// Real capture with --yes succeeds.
	assert dispatch(['horneroctl', '--json', 'profile', 'capture', 'work', '--name', 'Work', '--yes']) == 0
	assert dispatch(['horneroctl', '--json', 'profile', 'show', 'work']) == 0
	assert dispatch(['horneroctl', '--json', 'profile', 'diff', 'work']) == 0
	// Mutating verbs require --yes.
	assert dispatch(['horneroctl', '--quiet', 'profile', 'apply', 'work']) == 1
	assert dispatch(['horneroctl', '--json', 'profile', 'apply', 'work', '--dry-run']) == 0
	assert dispatch(['horneroctl', '--json', 'profile', 'apply', 'work', '--no-restart-pipewire',
		'--yes']) == 0
	assert dispatch(['horneroctl', '--quiet', 'profile', 'revert']) == 1
	assert dispatch(['horneroctl', '--json', 'profile', 'revert', '--dry-run']) == 0
	assert dispatch(['horneroctl', '--json', 'profile', 'revert', '--to', 'previous',
		'--no-restart-pipewire', '--yes']) == 0
	assert dispatch(['horneroctl', '--quiet', 'profile', 'launch-apps', 'work']) == 1
	assert dispatch(['horneroctl', '--json', 'profile', 'launch-apps', 'work', '--dry-run']) == 0
	bundle := '${root}/work.json'
	assert dispatch(['horneroctl', '--quiet', 'profile', 'export', 'work', bundle]) == 1
	assert dispatch(['horneroctl', '--json', 'profile', 'export', 'work', bundle, '--portable',
		'--dry-run']) == 0
	assert dispatch(['horneroctl', '--json', 'profile', 'export', 'work', bundle, '--portable',
		'--yes']) == 0
	assert dispatch(['horneroctl', '--quiet', 'profile', 'import', bundle, '--id', 'work2']) == 1
	assert dispatch(['horneroctl', '--json', 'profile', 'import', bundle, '--id', 'work2', '--dry-run']) == 0
	assert dispatch(['horneroctl', '--json', 'profile', 'import', bundle, '--id', 'work2', '--yes']) == 0
	assert dispatch(['horneroctl', '--quiet', 'profile', 'delete', 'work2']) == 1
	assert dispatch(['horneroctl', '--json', 'profile', 'delete', 'work2', '--dry-run']) == 0
	assert dispatch(['horneroctl', '--json', 'profile', 'delete', 'work2', '--yes']) == 0
	assert dispatch(['horneroctl', '--quiet', 'profile', 'delete', 'baseline', '--yes']) == 1
}
