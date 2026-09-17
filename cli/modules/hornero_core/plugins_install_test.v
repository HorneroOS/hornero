module hornero_core

import os

fn plugins_install_test_save_env(keys []string) map[string]string {
	mut saved := map[string]string{}
	for k in keys {
		saved[k] = os.getenv(k)
	}
	return saved
}

fn plugins_install_test_restore_env(saved map[string]string) {
	for k, v in saved {
		if v.len == 0 {
			os.unsetenv(k)
		} else {
			os.setenv(k, v, true)
		}
	}
}

fn test_plugins_install_needs_yes() {
	r := plugins_install_report(PluginsInstallOptions{})
	assert !r.ok
	assert r.message.contains('--yes')
}

fn test_plugins_install_dry_run_needs_no_backend() {
	// Hermetic: nonexistent hyprpm; dry-run still previews the plan.
	saved := plugins_install_test_save_env(['HORNERO_HYPRPM_BIN'])
	os.setenv('HORNERO_HYPRPM_BIN', '/nonexistent-hyprpm-hornero-test', true)
	r := plugins_install_report(PluginsInstallOptions{
		dry_run: true
	})
	assert r.ok
	assert r.message.contains('would run:')
	assert r.message.contains('update')
	assert r.message.contains('scrolloverview')
	plugins_install_test_restore_env(saved)
}

fn test_plugins_install_dry_run_no_update_skips_update() {
	saved := plugins_install_test_save_env(['HORNERO_HYPRPM_BIN'])
	os.setenv('HORNERO_HYPRPM_BIN', '/nonexistent-hyprpm-hornero-test', true)
	r := plugins_install_report(PluginsInstallOptions{
		dry_run:   true
		no_update: true
	})
	assert r.ok
	assert !r.message.contains('would run: /nonexistent-hyprpm-hornero-test update')
	assert r.message.contains('reload -n')
	plugins_install_test_restore_env(saved)
}

fn test_plugins_install_dry_run_force_rebuilds() {
	saved := plugins_install_test_save_env(['HORNERO_HYPRPM_BIN'])
	os.setenv('HORNERO_HYPRPM_BIN', '/nonexistent-hyprpm-hornero-test', true)
	r := plugins_install_report(PluginsInstallOptions{
		dry_run: true
		force:   true
	})
	assert r.ok
	assert r.message.contains('update -f')
	plugins_install_test_restore_env(saved)
}

fn test_plugins_install_missing_backend() {
	saved := plugins_install_test_save_env(['HORNERO_HYPRPM_BIN'])
	os.setenv('HORNERO_HYPRPM_BIN', '/nonexistent-hyprpm-hornero-test', true)
	r := plugins_install_report(PluginsInstallOptions{
		yes:       true
		no_update: true
	})
	assert !r.ok
	assert r.message.contains('could not read plugin list')
	plugins_install_test_restore_env(saved)
}
