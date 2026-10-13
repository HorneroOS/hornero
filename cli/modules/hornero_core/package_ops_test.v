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
	saved := package_ops_test_save_env(['PATH', 'HORNERO_DEPENDENCY_ROOT'])
	os.setenv('PATH', '/nonexistent-hx-path-test', true)
	os.setenv('HORNERO_DEPENDENCY_ROOT', '/nonexistent-hx-root-test', true)
	r := package_deps_check_report(PackageDepsOptions{})
	assert r.ok
	assert r.message.contains('git (core, missing)')
	assert r.message.contains('quickshell (wayland, missing)')
	assert r.data['count'] == '12'
	package_ops_test_restore_env(saved)
}

fn test_package_deps_check_optional_adds_groups() {
	saved := package_ops_test_save_env(['PATH', 'HORNERO_DEPENDENCY_ROOT'])
	os.setenv('PATH', '/nonexistent-hx-path-test', true)
	os.setenv('HORNERO_DEPENDENCY_ROOT', '/nonexistent-hx-root-test', true)
	r := package_deps_check_report(PackageDepsOptions{
		optional: true
	})
	assert r.ok
	assert r.message.contains('(dev, missing)')
	assert r.message.contains('(media, missing)')
	assert r.message.contains('(ai, missing)')
	package_ops_test_restore_env(saved)
}

fn test_package_deps_niri_checks_niri_runtime_instead_of_hyprland() {
	saved := package_ops_test_save_env(['PATH', 'HORNERO_DEPENDENCY_ROOT'])
	os.setenv('PATH', '/nonexistent-hx-path-test', true)
	os.setenv('HORNERO_DEPENDENCY_ROOT', '/nonexistent-hx-root-test', true)
	r := package_deps_check_report(PackageDepsOptions{
		compositor: 'niri'
	})
	assert r.ok
	assert r.data['compositor'] == 'niri'
	assert r.data['count'] == '12'
	assert r.data['missing'].contains('niri')
	assert r.data['missing'].contains('xwayland-satellite')
	assert r.data['missing'].contains('xdg-desktop-portal-gnome')
	assert r.data['missing'].contains('xdg-desktop-portal-gtk')
	assert !r.data['missing'].contains('hyprland')
	assert r.message.contains('Compositor: niri (experimental)')
	package_ops_test_restore_env(saved)
}

fn test_package_deps_follows_installed_profile_compositor() {
	saved := package_ops_test_save_env([
		'PATH',
		'HORNERO_SYSTEM_PROFILE_FILE',
		'HORNERO_DEPENDENCY_ROOT',
		'NIRI_SOCKET',
		'HYPRLAND_INSTANCE_SIGNATURE',
	])
	path := os.join_path(os.getwd(), '.hornero-package-profile-test-${os.getpid()}.json')
	defer {
		os.rm(path) or {}
	}
	os.setenv('HORNERO_SYSTEM_PROFILE_FILE', path, true)
	os.unsetenv('NIRI_SOCKET')
	os.setenv('HYPRLAND_INSTANCE_SIGNATURE', 'inherited-parent-session', true)
	profile_json := '{"apiVersion":"hornero.os/v1","kind":"InstalledProfile","sourceRevision":"0123456789abcdef0123456789abcdef01234567","profilePackage":"hornero-profile-desktop-niri","edition":{"edition":"desktop","title":"HorneroOS Desktop","role":"desktop","maturity":"preview","compositor":"niri","compositorMaturity":"experimental","packageSets":["base","desktop","compositor:niri"]}}'
	os.write_file(path, profile_json) or {
		assert false, err.msg()
	}
	written := os.read_file(path) or { '' }
	assert written == profile_json
	os.setenv('PATH', '/nonexistent-hx-path-test', true)
	os.setenv('HORNERO_DEPENDENCY_ROOT', '/nonexistent-hx-root-test', true)
	profile := system_profile_result()
	assert profile.ok, profile.message
	assert profile.data['compositor'] == 'niri'
	r := package_deps_check_report(PackageDepsOptions{})
	assert r.ok
	assert r.data['compositor'] == 'niri'
	assert r.data['missing'].contains('niri')
	assert !r.data['missing'].contains('hyprland')
	package_ops_test_restore_env(saved)
}

fn test_package_deps_detects_portal_service_binary_outside_path() {
	saved := package_ops_test_save_env(['PATH', 'HORNERO_DEPENDENCY_ROOT'])
	root := os.join_path(os.getwd(), '.hornero-package-portal-test-${os.getpid()}')
	defer {
		os.rmdir_all(root) or {}
	}
	os.setenv('PATH', '/nonexistent-hx-path-test', true)
	os.setenv('HORNERO_DEPENDENCY_ROOT', root, true)
	portal_dir := os.join_path(root, 'lib')
	os.mkdir_all(portal_dir) or { assert false, err.msg() }
	portal := os.join_path(portal_dir, 'xdg-desktop-portal-gnome')
	os.write_file(portal, 'fixture') or { assert false, err.msg() }
	assert package_dep_available(DepEntry{'xdg-desktop-portal-gnome', 'xdg-desktop-portal-gnome', '', 'wayland'})
	assert !package_dep_available(DepEntry{'xdg-desktop-portal-gtk', 'xdg-desktop-portal-gtk', '', 'wayland'})
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
