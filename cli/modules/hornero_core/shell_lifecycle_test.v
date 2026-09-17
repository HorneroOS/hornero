module hornero_core

import os

fn shell_lifecycle_test_save_env(keys []string) map[string]string {
	mut saved := map[string]string{}
	for k in keys {
		saved[k] = os.getenv(k)
	}
	return saved
}

fn shell_lifecycle_test_restore_env(saved map[string]string) {
	for k, v in saved {
		if v.len == 0 {
			os.unsetenv(k)
		} else {
			os.setenv(k, v, true)
		}
	}
}

fn shell_lifecycle_test_break_backend() {
	os.setenv('HORNERO_QUICKSHELL_BIN', '/nonexistent-quickshell-hornero-test', true)
	os.setenv('HORNERO_PGREP_BIN', '/nonexistent-pgrep-hornero-test', true)
}

fn test_shell_start_needs_yes() {
	r := shell_start_report(ShellStartOptions{})
	assert !r.ok
	assert r.message.contains('--yes')
}

fn test_shell_stop_needs_yes() {
	r := shell_stop_report(ShellStopOptions{})
	assert !r.ok
	assert r.message.contains('--yes')
}

fn test_shell_restart_needs_yes() {
	r := shell_restart_report(ShellRestartOptions{})
	assert !r.ok
	assert r.message.contains('--yes')
}

fn test_shell_lifecycle_dry_run_needs_no_backend() {
	// Hermetic: nonexistent binaries; dry-run previews must still pass
	// and never touch the process table.
	saved := shell_lifecycle_test_save_env(['HORNERO_QUICKSHELL_BIN', 'HORNERO_PGREP_BIN',
		'HORNERO_QUICKSHELL_CONFIG_DIR', 'HORNERO_SHELL_LOG_FILE'])
	shell_lifecycle_test_break_backend()
	os.setenv('HORNERO_QUICKSHELL_CONFIG_DIR', '/nonexistent-conf-hornero-test', true)
	os.setenv('HORNERO_SHELL_LOG_FILE', '/nonexistent-log-hornero-test.log', true)
	r1 := shell_start_report(ShellStartOptions{
		dry_run: true
	})
	assert r1.ok
	assert r1.message.contains('would run:')
	assert r1.message.contains('nohup')
	r2 := shell_stop_report(ShellStopOptions{
		dry_run: true
	})
	assert r2.ok
	assert r2.message.contains('would run:')
	assert r2.message.contains('kill')
	r3 := shell_restart_report(ShellRestartOptions{
		dry_run: true
	})
	assert r3.ok
	assert r3.message.contains('would run:')
	assert r3.message.contains('sleep 1')
	r4 := shell_logs_report(ShellLogsOptions{
		dry_run: true
	})
	assert r4.ok
	assert r4.message.contains('would read:')
	shell_lifecycle_test_restore_env(saved)
}

fn test_shell_start_missing_config_dir() {
	// Nothing running (pgrep finds nothing), missing config dir fails
	// with guidance instead of launching.
	saved := shell_lifecycle_test_save_env(['HORNERO_QUICKSHELL_BIN', 'HORNERO_PGREP_BIN',
		'HORNERO_QUICKSHELL_CONFIG_DIR', 'HORNERO_SHELL_LOG_FILE'])
	os.setenv('HORNERO_QUICKSHELL_BIN', '/bin/true', true)
	os.setenv('HORNERO_PGREP_BIN', '/bin/false', true)
	os.setenv('HORNERO_QUICKSHELL_CONFIG_DIR', '/nonexistent-conf-hornero-test', true)
	os.setenv('HORNERO_SHELL_LOG_FILE', '/tmp/hx-shell-test.log', true)
	r := shell_start_report(ShellStartOptions{
		yes: true
	})
	assert !r.ok
	assert r.message.contains('config directory not found')
	shell_lifecycle_test_restore_env(saved)
}

fn test_shell_stop_idle_is_success() {
	// Nothing running: stop is a no-op success.
	saved := shell_lifecycle_test_save_env(['HORNERO_QUICKSHELL_BIN', 'HORNERO_PGREP_BIN'])
	os.setenv('HORNERO_QUICKSHELL_BIN', '/bin/true', true)
	os.setenv('HORNERO_PGREP_BIN', '/bin/false', true)
	r := shell_stop_report(ShellStopOptions{
		yes: true
	})
	assert r.ok
	assert r.message.contains('not running')
	shell_lifecycle_test_restore_env(saved)
}

fn test_shell_logs_roundtrip() {
	saved := shell_lifecycle_test_save_env(['HORNERO_SHELL_LOG_FILE'])
	os.setenv('HORNERO_SHELL_LOG_FILE', '/tmp/hx-shell-logs-test.log', true)
	os.write_file('/tmp/hx-shell-logs-test.log', 'line1\nline2\nline3\n') or { assert false }
	r := shell_logs_report(ShellLogsOptions{
		lines: 2
	})
	assert r.ok
	assert r.message == 'line2\nline3'
	assert r.data['lines'] == '2'
	os.rm('/tmp/hx-shell-logs-test.log') or {}
	shell_lifecycle_test_restore_env(saved)
}

fn test_shell_logs_missing_file() {
	saved := shell_lifecycle_test_save_env(['HORNERO_SHELL_LOG_FILE'])
	os.setenv('HORNERO_SHELL_LOG_FILE', '/nonexistent-hx-shell-log-test.log', true)
	r := shell_logs_report(ShellLogsOptions{})
	assert !r.ok
	assert r.message.contains('no shell log')
	shell_lifecycle_test_restore_env(saved)
}
