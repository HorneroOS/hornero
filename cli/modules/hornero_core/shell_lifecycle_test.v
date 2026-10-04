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

fn test_shell_config_prefers_named_system_package_over_bare_user_checkout() {
	saved := shell_lifecycle_test_save_env(['XDG_CONFIG_HOME', 'XDG_CONFIG_DIRS',
		'HORNERO_QUICKSHELL_CONFIG_DIR'])
	dir := os.join_path(os.temp_dir(), 'hornero-packaged-shell-path-test')
	user := os.join_path(dir, 'user', 'quickshell')
	system := os.join_path(dir, 'system', 'quickshell', 'hornero')
	os.rmdir_all(dir) or {}
	os.mkdir_all(user) or { assert false, 'mkdir ${user}' }
	os.mkdir_all(system) or { assert false, 'mkdir ${system}' }
	os.write_file(os.join_path(user, 'shell.qml'), '// legacy dev checkout') or { assert false }
	os.write_file(os.join_path(system, 'shell.qml'), '// packaged Hornero') or { assert false }
	os.setenv('XDG_CONFIG_HOME', os.join_path(dir, 'user'), true)
	os.setenv('XDG_CONFIG_DIRS', os.join_path(dir, 'system'), true)
	os.unsetenv('HORNERO_QUICKSHELL_CONFIG_DIR')
	assert resolve_quickshell_config_dir() == system
	os.rmdir_all(dir) or {}
	shell_lifecycle_test_restore_env(saved)
}

fn test_shell_config_allows_named_user_override() {
	saved := shell_lifecycle_test_save_env(['XDG_CONFIG_HOME', 'XDG_CONFIG_DIRS',
		'HORNERO_QUICKSHELL_CONFIG_DIR'])
	dir := os.join_path(os.temp_dir(), 'hornero-user-shell-override-test')
	user := os.join_path(dir, 'config', 'quickshell', 'hornero')
	os.mkdir_all(user) or { assert false, 'mkdir ${user}' }
	os.write_file(os.join_path(user, 'shell.qml'), '// named user override') or { assert false }
	os.setenv('XDG_CONFIG_HOME', os.join_path(dir, 'config'), true)
	os.setenv('XDG_CONFIG_DIRS', os.join_path(dir, 'missing-system'), true)
	os.unsetenv('HORNERO_QUICKSHELL_CONFIG_DIR')
	assert resolve_quickshell_config_dir() == user
	os.rmdir_all(dir) or {}
	shell_lifecycle_test_restore_env(saved)
}

fn test_quickshell_ipc_uses_packaged_hornero_config_for_sibling_commands() {
	saved := shell_lifecycle_test_save_env(['XDG_CONFIG_HOME', 'XDG_CONFIG_DIRS',
		'HORNERO_QUICKSHELL_CONFIG_DIR', 'QS_CONFIG_PATH'])
	dir := os.join_path(os.temp_dir(), 'hornero-ipc-config-path-test')
	user := os.join_path(dir, 'config', 'quickshell', 'hornero')
	os.mkdir_all(user) or { assert false, 'mkdir ${user}' }
	os.write_file(os.join_path(user, 'shell.qml'), '// packaged Hornero') or { assert false }
	os.setenv('XDG_CONFIG_HOME', os.join_path(dir, 'config'), true)
	os.setenv('XDG_CONFIG_DIRS', os.join_path(dir, 'missing-system'), true)
	os.unsetenv('HORNERO_QUICKSHELL_CONFIG_DIR')
	os.unsetenv('QS_CONFIG_PATH')
	ensure_quickshell_ipc_config()
	assert os.getenv('QS_CONFIG_PATH') == os.join_path(user, 'shell.qml')
	os.setenv('QS_CONFIG_PATH', '/explicit/shell.qml', true)
	ensure_quickshell_ipc_config()
	assert os.getenv('QS_CONFIG_PATH') == '/explicit/shell.qml'
	os.rmdir_all(dir) or {}
	shell_lifecycle_test_restore_env(saved)
}

fn test_shell_restart_dry_run_mentions_cover() {
	r := shell_restart_report(ShellRestartOptions{
		dry_run: true
	})
	assert r.ok
	assert r.message.contains('cover')
}

fn test_shell_cover_up_missing_file_returns_empty() {
	assert shell_cover_up('/bin/true', '/nonexistent-cover-hornero-test/shell.qml',
		'/tmp/hx-cover-test.log') == ''
}

fn test_shell_cover_up_tracks_pid_and_down_is_quiet() {
	// /bin/true ignores argv and exits at once, so the cover PID is
	// already reaped when down runs: kill fails, and must stay quiet.
	dir := os.join_path(os.temp_dir(), 'hornero-cover-test')
	os.mkdir_all(dir) or { assert false, 'mkdir ${dir}' }
	cover := os.join_path(dir, 'shell.qml')
	os.write_file(cover, '// fake cover') or { assert false, 'write ${cover}' }
	pid := shell_cover_up('/bin/true', cover, os.join_path(dir, 'cover.log'))
	assert pid.int() > 0
	shell_cover_down(pid)
	shell_cover_down('')
	os.rmdir_all(dir) or {}
}

fn test_shell_start_guard_and_force() {
	// pgrep always matches, so the shell looks running: plain start
	// refuses, forced start (what restart uses under its cover)
	// launches anyway. /bin/true exits at once and is harmless.
	saved := shell_lifecycle_test_save_env(['HORNERO_QUICKSHELL_BIN', 'HORNERO_PGREP_BIN',
		'HORNERO_QUICKSHELL_CONFIG_DIR', 'HORNERO_SHELL_LOG_FILE', 'QS_CONFIG_PATH',
		'QT_QPA_PLATFORMTHEME'])
	dir := os.join_path(os.temp_dir(), 'hornero-start-force-test')
	os.mkdir_all(dir) or { assert false, 'mkdir ${dir}' }
	os.setenv('HORNERO_QUICKSHELL_BIN', '/bin/true', true)
	os.setenv('HORNERO_PGREP_BIN', '/bin/true', true)
	os.setenv('HORNERO_QUICKSHELL_CONFIG_DIR', dir, true)
	os.unsetenv('QS_CONFIG_PATH')
	os.setenv('HORNERO_SHELL_LOG_FILE', os.join_path(dir, 'shell.log'), true)
	cover_only := shell_start_report(ShellStartOptions{
		yes: true
		bin: '/bin/false'
	})
	assert !cover_only.ok
	assert cover_only.message.contains('Hornero Shell IPC target `drawers` is unavailable')
	guarded := shell_start_report(ShellStartOptions{
		yes: true
	})
	assert guarded.ok
	assert guarded.message.contains('already running')
	forced := shell_start_report(ShellStartOptions{
		yes:   true
		force: true
	})
	assert forced.ok
	assert !forced.message.contains('already running')
	assert os.getenv('QS_CONFIG_PATH') == os.join_path(dir, 'shell.qml')
	os.rmdir_all(dir) or {}
	shell_lifecycle_test_restore_env(saved)
}

fn test_shell_readiness_requires_product_ipc_not_a_quickshell_process() {
	assert shell_wait_for_hornero_ipc('/bin/true', 1)
	assert !shell_wait_for_hornero_ipc('/bin/false', 1)
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
