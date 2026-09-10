module hornero_cli

import os

fn test_dispatch_version_exit_zero() {
	assert dispatch(['horneroctl', 'version']) == 0
}

fn test_dispatch_help_exit_zero() {
	assert dispatch(['horneroctl', '--help']) == 0
	assert dispatch(['horneroctl', 'help', 'doctor']) == 0
	assert dispatch(['horneroctl', 'doctor', '--help']) == 0
}

fn test_dispatch_unknown_command_exit_one() {
	assert dispatch(['horneroctl', 'not-a-real-command']) == 1
}

fn test_dispatch_unknown_flag_exit_two() {
	assert dispatch(['horneroctl', '--bogus-flag']) == 2
	assert dispatch(['horneroctl', 'shell', 'ipc', '--bogus']) == 2
}

fn test_dispatch_leading_json_before_command() {
	assert dispatch(['horneroctl', '--json', 'version']) == 0
}

fn test_dispatch_leading_quiet_before_command() {
	assert dispatch(['horneroctl', '--quiet', 'version']) == 0
}

fn test_dispatch_shell_status_codes() {
	code := dispatch(['horneroctl', 'shell', 'status'])
	assert code == 0
}

fn test_dispatch_shell_ipc_dry_run() {
	code := dispatch(['horneroctl', 'shell', 'ipc', '--dry-run', '--', 'show'])
	assert code == 0
}

fn test_dry_run_needs_no_backend() {
	// Hermetic: point both backends at nonexistent paths; dry-run must
	// still preview successfully on any machine (CI has no qs/dots-*).
	os.setenv('HORNERO_QS_BIN', '/nonexistent-qs-hornero-test', true)
	assert dispatch(['horneroctl', 'shell', 'ipc', '--dry-run', '--', 'show']) == 0
	os.unsetenv('HORNERO_QS_BIN')
	os.setenv('HORNERO_APPEARANCE_BIN', '/nonexistent-appearance-hornero-test', true)
	assert dispatch(['horneroctl', 'appearance', 'sync', '--dry-run']) == 0
	os.unsetenv('HORNERO_APPEARANCE_BIN')
}

fn test_dispatch_appearance_sync_needs_yes() {
	// Without --yes/--dry-run this must refuse (exit 1), never apply.
	code := dispatch(['horneroctl', 'appearance', 'sync'])
	assert code == 1
}

fn test_dispatch_config_paths() {
	assert dispatch(['horneroctl', 'config', 'paths']) == 0
}

fn test_dispatch_completion() {
	assert dispatch(['horneroctl', 'completion', 'bash']) == 0
	assert dispatch(['horneroctl', 'completion', 'powershell']) == 1
}

fn test_every_help_has_examples() {
	for cmd in ['version', 'doctor', 'shell', 'appearance', 'config', 'completion'] {
		h := command_help(cmd)
		assert h.contains('Examples:')
	}
	assert root_help().contains('Examples:')
}
