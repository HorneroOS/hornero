module hornero_core

import os

// Fixture-backed tests for the native audit checks: a redirected HOME
// with controlled modes plus fake leaf tools keep runs hermetic.

const audit_test_keys = ['HOME', 'XDG_CONFIG_HOME', 'HORNERO_UFW_BIN', 'HORNERO_SYSTEMCTL_BIN',
	'HORNERO_APPARMOR_BIN', 'HORNERO_SS_BIN', 'HORNERO_PACMAN_BIN', 'HORNERO_SSHD_CONFIG',
	'HORNERO_STAT_BIN', 'HORNERO_FIND_BIN']

fn audit_test_save_env() map[string]string {
	mut saved := map[string]string{}
	for k in audit_test_keys {
		saved[k] = os.getenv(k)
	}
	return saved
}

fn audit_test_restore_env(saved map[string]string) {
	for k, v in saved {
		if v.len == 0 {
			os.unsetenv(k)
		} else {
			os.setenv(k, v, true)
		}
	}
}

fn audit_test_setup_home() string {
	home := '/tmp/hx-audit-test/home'
	os.rmdir_all(home) or {}
	os.mkdir_all(home + '/.ssh') or { assert false }
	os.chmod(home + '/.ssh', 0o700) or { assert false }
	os.write_file(home + '/.ssh/id_ed25519', 'fake-key') or { assert false }
	os.chmod(home + '/.ssh/id_ed25519', 0o600) or { assert false }
	os.write_file(home + '/.ssh/config', 'Host x') or { assert false }
	os.chmod(home + '/.ssh/config', 0o600) or { assert false }
	os.mkdir_all(home + '/.config') or { assert false }
	os.setenv('HOME', home, true)
	os.setenv('XDG_CONFIG_HOME', home + '/.config', true)
	return home
}

fn audit_test_setup_system_fakes() {
	base := '/tmp/hx-audit-test/bin'
	os.mkdir_all(base) or { assert false }
	os.write_file(base + '/ufw', '#!/bin/sh\necho "Status: active"\nexit 0\n') or {
		assert false
	}
	os.write_file(base + '/systemctl', '#!/bin/sh\nexit 0\n') or { assert false }
	os.write_file(base + '/apparmor_status', '#!/bin/sh\nexit 0\n') or { assert false }
	os.write_file(base + '/ss', '#!/bin/sh\nexit 0\n') or { assert false }
	for b in ['ufw', 'systemctl', 'apparmor_status', 'ss'] {
		os.chmod(base + '/' + b, 0o755) or { assert false }
	}
	os.setenv('HORNERO_UFW_BIN', base + '/ufw', true)
	os.setenv('HORNERO_SYSTEMCTL_BIN', base + '/systemctl', true)
	os.setenv('HORNERO_APPARMOR_BIN', base + '/apparmor_status', true)
	os.setenv('HORNERO_SS_BIN', base + '/ss', true)
	os.setenv('HORNERO_PACMAN_BIN', '/nonexistent-pacman-hornero-test', true)
	os.setenv('HORNERO_SSHD_CONFIG', '/nonexistent-sshd-hornero-test', true)
}

fn test_audit_permissions_native_clean() {
	saved := audit_test_save_env()
	audit_test_setup_home()
	r := audit_report(AuditOptions{ check: 'permissions' })
	assert r.ok
	assert r.message.contains('SSH directory permissions correct')
	audit_test_restore_env(saved)
}

fn test_audit_permissions_native_bad_key() {
	saved := audit_test_save_env()
	home := audit_test_setup_home()
	os.chmod(home + '/.ssh/id_ed25519', 0o644) or { assert false }
	r := audit_report(AuditOptions{ check: 'permissions' })
	assert !r.ok
	assert r.message.contains('incorrect permissions')
	audit_test_restore_env(saved)
}

fn test_audit_permissions_native_world_readable() {
	saved := audit_test_save_env()
	home := audit_test_setup_home()
	os.write_file(home + '/leak.key', 'x') or { assert false }
	os.chmod(home + '/leak.key', 0o644) or { assert false }
	r := audit_report(AuditOptions{ check: 'permissions' })
	assert !r.ok
	assert r.message.contains('world-readable')
	audit_test_restore_env(saved)
}

fn test_audit_secrets_native_simplified() {
	saved := audit_test_save_env()
	audit_test_setup_home()
	r := audit_report(AuditOptions{ check: 'secrets' })
	assert r.ok
	assert r.message.contains('simplified')
	audit_test_restore_env(saved)
}

fn test_audit_system_native_completes() {
	saved := audit_test_save_env()
	audit_test_setup_home()
	// Host-dependent verdict: the check always completes with its header.
	r := audit_report(AuditOptions{ check: 'system' })
	assert r.message.contains('Checking system security')
	audit_test_restore_env(saved)
}

fn test_audit_full_native_clean_with_fakes() {
	saved := audit_test_save_env()
	audit_test_setup_home()
	audit_test_setup_system_fakes()
	r := audit_report(AuditOptions{ check: 'full' })
	assert r.ok, r.message
	assert r.message.contains('Running comprehensive security audit')
	assert r.message.contains('Security audit completed.')
	assert os.is_file(r.data['log'])
	assert r.data['log'].contains('security_audit_')
	os.read_file(r.data['log']) or { assert false }
	audit_test_restore_env(saved)
}
