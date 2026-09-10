module hornero_core

import os

fn test_exit_codes() {
	assert ErrorClass.ok.exit_code() == 0
	assert ErrorClass.usage_flags.exit_code() == 2
	assert ErrorClass.user.exit_code() == 1
	assert ErrorClass.config.exit_code() == 1
	assert ErrorClass.env.exit_code() == 1
	assert ErrorClass.external.exit_code() == 1
	assert ErrorClass.internal.exit_code() == 1
	assert err_usage('flag.unknown', 'x').exit_code() == 2
	assert err_user('command.failed', 'x').msg() == 'x'
}

fn test_paths_honor_xdg_overrides() {
	os.setenv('XDG_CONFIG_HOME', '/tmp/hx-xdg-test-config', true)
	os.setenv('XDG_DATA_HOME', '/tmp/hx-xdg-test-data', true)
	p := resolve_paths()
	assert p.config_dir == '/tmp/hx-xdg-test-config'
	assert p.data_dir == '/tmp/hx-xdg-test-data'
	assert shell_config_file(p) == '/tmp/hx-xdg-test-config/hornero/shell.json'
	os.unsetenv('XDG_CONFIG_HOME')
	os.unsetenv('XDG_DATA_HOME')
}

fn test_dry_run_never_executes() {
	// /nonexistent-prog would fail if executed; dry-run must still report ok.
	rep := run_exec(ExecSpec{
		prog:    '/nonexistent-prog-hornero-test'
		args:    ['--do-something-dangerous']
		dry_run: true
	})
	assert rep.ok
	assert rep.was_dry_run
	assert rep.command_line == '/nonexistent-prog-hornero-test --do-something-dangerous'
}

fn test_version_result_shape() {
	r := version_result()
	assert r.ok
	assert r.command == 'version'
	assert r.data['version'] == cli_version()
	assert r.message.contains('horneroctl')
}

fn test_doctor_returns_checks() {
	checks := run_doctor()
	assert checks.len >= 5
	names := checks.map(it.name)
	assert 'wayland-session' in names
	assert 'shell-config' in names
	r := doctor_result(checks)
	assert r.command == 'doctor'
	// exit-worthiness follows the worst check, deterministically
	failed := checks.filter(!it.ok).len
	assert r.ok == (failed == 0)
}

fn test_ipc_missing_binary_fails_cleanly() {
	r := ipc_report(IpcOptions{
		passthrough: ['show']
		qs_bin:      '/nonexistent-qs-hornero-test'
	})
	// binary missing but explicitly given: execution fails, no panic
	assert r.command == 'shell ipc'
	assert !r.ok || r.message.contains('qs ipc failed')
}

fn test_ipc_dry_run_ok_without_binary() {
	r := ipc_report(IpcOptions{
		passthrough: ['show']
		dry_run:     true
		qs_bin:      '/nonexistent-qs-hornero-test'
	})
	assert r.ok
	assert r.data['dry_run'] == 'true'
}

fn test_appearance_requires_yes_for_sync() {
	r := appearance_report(AppearanceOptions{
		action:  'sync'
		helper:  '/nonexistent-helper-hornero-test'
		dry_run: false
		yes:     false
	})
	assert !r.ok
	assert r.message.contains('--yes')
}

fn test_config_paths_report() {
	r := config_paths_report()
	assert r.ok
	assert r.message.contains('shell config:')
}
