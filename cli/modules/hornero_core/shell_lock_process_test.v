module hornero_core

import os

fn lock_process_test_save_env(keys []string) map[string]string {
	mut saved := map[string]string{}
	for k in keys {
		saved[k] = os.getenv(k)
	}
	return saved
}

fn lock_process_test_restore_env(saved map[string]string) {
	for k, v in saved {
		if v.len == 0 {
			os.unsetenv(k)
		} else {
			os.setenv(k, v, true)
		}
	}
}

fn test_lock_process_enable_disable_need_yes() {
	r1 := shell_lock_process_enable(ShellLockProcessOptions{
		leaf: 'enable'
	})
	assert !r1.ok
	assert r1.message.contains('--yes')
	r2 := shell_lock_process_disable(ShellLockProcessOptions{
		leaf: 'disable'
	})
	assert !r2.ok
	assert r2.message.contains('--yes')
}

fn test_lock_process_dry_run_previews_pair() {
	r1 := shell_lock_process_enable(ShellLockProcessOptions{
		leaf:    'enable'
		dry_run: true
	})
	assert r1.ok
	assert r1.message.contains('enable --now ${lock_process_unit_name}')
	assert r1.message.contains('set-environment HORNERO_EXTERNAL_LOCK=1')
	r2 := shell_lock_process_disable(ShellLockProcessOptions{
		leaf:    'disable'
		dry_run: true
	})
	assert r2.ok
	assert r2.message.contains('disable --now ${lock_process_unit_name}')
	assert r2.message.contains('unset-environment HORNERO_EXTERNAL_LOCK')
}

fn test_lock_process_enable_requires_shipped_pair() {
	// Hermetic: config dir without lock.qml must fail with guidance,
	// before any systemctl call.
	saved := lock_process_test_save_env(['HORNERO_QUICKSHELL_CONFIG_DIR', 'HORNERO_LOCK_UNIT_FILE',
		'HORNERO_SYSTEMCTL_BIN', 'HORNERO_PGREP_BIN', 'HORNERO_QUICKSHELL_BIN'])
	os.setenv('HORNERO_QUICKSHELL_CONFIG_DIR', '/nonexistent-conf-hornero-test', true)
	os.setenv('HORNERO_SYSTEMCTL_BIN', '/nonexistent-systemctl-hornero-test', true)
	r := shell_lock_process_enable(ShellLockProcessOptions{
		leaf: 'enable'
		yes:  true
	})
	assert !r.ok
	assert r.message.contains('lock.qml not found')
	lock_process_test_restore_env(saved)
}

fn test_lock_process_status_fails_open() {
	saved := lock_process_test_save_env(['HORNERO_QUICKSHELL_CONFIG_DIR', 'HORNERO_LOCK_UNIT_FILE',
		'HORNERO_SYSTEMCTL_BIN'])
	os.setenv('HORNERO_QUICKSHELL_CONFIG_DIR', '/nonexistent-conf-hornero-test', true)
	os.setenv('HORNERO_LOCK_UNIT_FILE', '/nonexistent-unit-hornero-test.service', true)
	os.setenv('HORNERO_SYSTEMCTL_BIN', '/nonexistent-systemctl-hornero-test', true)
	r := shell_lock_process_status()
	assert r.ok
	assert r.data['unit_shipped'] == 'false'
	assert r.data['enabled'] == 'unknown'
	assert r.data['lock_qml'] == ''
	lock_process_test_restore_env(saved)
}

fn test_lock_process_refuses_while_locked() {
	// Fake hyprlock probe: session reads locked, enable/disable must
	// refuse before touching systemctl (broken binary proves it).
	saved := lock_process_test_save_env(['HORNERO_PGREP_BIN', 'HORNERO_QUICKSHELL_BIN',
		'HORNERO_SYSTEMCTL_BIN', 'HORNERO_QUICKSHELL_CONFIG_DIR', 'HORNERO_LOCK_UNIT_FILE'])
	dir := os.join_path(os.temp_dir(), 'hornero-lock-process-test')
	os.mkdir_all(dir) or { assert false, 'mkdir ${dir}' }
	fake_pgrep := os.join_path(dir, 'pgrep')
	os.write_file(fake_pgrep, '#!/bin/sh\nexit 0\n') or { assert false, 'write pgrep' }
	os.chmod(fake_pgrep, 0o755) or { assert false, 'chmod pgrep' }
	os.write_file(os.join_path(dir, 'lock.qml'), '// lock entry') or { assert false }
	os.write_file(os.join_path(dir, 'shell.qml'), '// shell entry') or { assert false }
	unit := os.join_path(dir, lock_process_unit_name)
	os.write_file(unit, '[Unit]\n') or { assert false, 'write unit' }
	os.setenv('HORNERO_PGREP_BIN', fake_pgrep, true)
	os.setenv('HORNERO_QUICKSHELL_BIN', '/nonexistent-quickshell-hornero-test', true)
	os.setenv('HORNERO_SYSTEMCTL_BIN', '/nonexistent-systemctl-hornero-test', true)
	os.setenv('HORNERO_QUICKSHELL_CONFIG_DIR', dir, true)
	os.setenv('HORNERO_LOCK_UNIT_FILE', unit, true)
	r1 := shell_lock_process_enable(ShellLockProcessOptions{
		leaf: 'enable'
		yes:  true
	})
	assert !r1.ok
	assert r1.message.contains('session is locked')
	r2 := shell_lock_process_disable(ShellLockProcessOptions{
		leaf: 'disable'
		yes:  true
	})
	assert !r2.ok
	assert r2.message.contains('session is locked')
	os.rmdir_all(dir) or {}
	lock_process_test_restore_env(saved)
}
