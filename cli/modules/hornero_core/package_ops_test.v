module hornero_core

import os

fn package_ops_test_save_env(keys []string) map[string]string {
	mut saved := map[string]string{}
	for k in keys {
		saved[k] = os.getenv(k)
	}
	return saved
}

fn package_ops_test_restore_env(saved map[string]string) {
	for k, v in saved {
		if v.len == 0 {
			os.unsetenv(k)
		} else {
			os.setenv(k, v, true)
		}
	}
}

fn package_ops_test_break_privilege() {
	os.setenv('HORNERO_PKEXEC_BIN', '/nonexistent-pkexec-hornero-test', true)
	os.setenv('HORNERO_PACMAN_BIN', '/nonexistent-pacman-hornero-test', true)
	os.setenv('HORNERO_PARU_BIN', '/nonexistent-paru-hornero-test', true)
}

fn test_package_upgrade_needs_yes() {
	r := package_upgrade_report(PackageUpgradeOptions{})
	assert !r.ok
	assert r.message.contains('--yes')
}

fn test_package_upgrade_dry_run_needs_no_backend() {
	// Hermetic: nonexistent privilege backends; dry-run still previews.
	saved := package_ops_test_save_env(['HORNERO_PKEXEC_BIN', 'HORNERO_PACMAN_BIN'])
	package_ops_test_break_privilege()
	r := package_upgrade_report(PackageUpgradeOptions{
		dry_run: true
	})
	assert r.ok
	assert r.message.contains('would run:')
	assert r.message.contains('-Syu')
	assert r.message.contains('polkit')
	package_ops_test_restore_env(saved)
}

fn test_package_upgrade_missing_pkexec() {
	// Hermetic: no override and an empty PATH, so pkexec cannot
	// resolve and the command fails with polkit guidance.
	saved := package_ops_test_save_env(['HORNERO_PKEXEC_BIN', 'HORNERO_PACMAN_BIN', 'PATH'])
	os.unsetenv('HORNERO_PKEXEC_BIN')
	os.unsetenv('HORNERO_PACMAN_BIN')
	os.setenv('PATH', '/nonexistent-hx-path-test', true)
	r := package_upgrade_report(PackageUpgradeOptions{
		yes: true
	})
	assert !r.ok
	assert r.message.contains('pkexec')
	assert r.message.contains('polkit')
	package_ops_test_restore_env(saved)
}

fn test_package_deps_check_empty_path_reports_missing() {
	// Hermetic: empty PATH makes every pinned command missing.
	saved := package_ops_test_save_env(['PATH'])
	os.setenv('PATH', '/nonexistent-hx-path-test', true)
	r := package_deps_check_report(PackageDepsOptions{})
	assert r.ok
	assert r.message.contains('git (core, missing)')
	assert r.message.contains('quickshell (wayland, missing)')
	assert r.data['count'] == '10'
	package_ops_test_restore_env(saved)
}

fn test_package_deps_check_optional_adds_groups() {
	saved := package_ops_test_save_env(['PATH'])
	os.setenv('PATH', '/nonexistent-hx-path-test', true)
	r := package_deps_check_report(PackageDepsOptions{
		optional: true
	})
	assert r.ok
	assert r.message.contains('(dev, missing)')
	assert r.message.contains('(media, missing)')
	assert r.message.contains('(ai, missing)')
	package_ops_test_restore_env(saved)
}

fn test_package_deps_install_needs_yes() {
	r := package_deps_install_report(PackageDepsOptions{
		install: true
	})
	assert !r.ok
	assert r.message.contains('--yes')
}

fn test_package_deps_install_dry_run_previews() {
	// Hermetic: empty PATH (everything missing) + broken privilege
	// backends; dry-run still previews both install steps.
	saved := package_ops_test_save_env(['PATH', 'HORNERO_PKEXEC_BIN', 'HORNERO_PACMAN_BIN',
		'HORNERO_PARU_BIN'])
	os.setenv('PATH', '/nonexistent-hx-path-test', true)
	package_ops_test_break_privilege()
	r := package_deps_install_report(PackageDepsOptions{
		install: true
		dry_run: true
	})
	assert r.ok
	assert r.message.contains('would run:')
	assert r.message.contains('-S --needed')
	package_ops_test_restore_env(saved)
}
