module hornero_core

import os

fn compositor_test_save_env() map[string]string {
	mut saved := map[string]string{}
	for key in ['NIRI_SOCKET', 'HYPRLAND_INSTANCE_SIGNATURE', 'HORNERO_QS_BIN'] {
		saved[key] = os.getenv(key)
	}
	return saved
}

fn compositor_test_restore_env(saved map[string]string) {
	for key, value in saved {
		if value.len == 0 {
			os.unsetenv(key)
		} else {
			os.setenv(key, value, true)
		}
	}
}

fn test_active_compositor_prioritizes_niri_in_a_nested_session() {
	saved := compositor_test_save_env()
	os.setenv('NIRI_SOCKET', '/run/user/1000/niri.1', true)
	os.setenv('HYPRLAND_INSTANCE_SIGNATURE', 'parent-hypr-session', true)
	assert active_compositor() == 'niri'
	compositor_test_restore_env(saved)
}

fn test_active_compositor_reports_hyprland_only_with_its_session_signature() {
	saved := compositor_test_save_env()
	os.unsetenv('NIRI_SOCKET')
	os.setenv('HYPRLAND_INSTANCE_SIGNATURE', 'hypr-session', true)
	assert active_compositor() == 'hyprland'
	compositor_test_restore_env(saved)
}

fn test_active_compositor_does_not_infer_support_from_wayland_alone() {
	saved := compositor_test_save_env()
	os.unsetenv('NIRI_SOCKET')
	os.unsetenv('HYPRLAND_INSTANCE_SIGNATURE')
	assert active_compositor() == 'unknown'
	compositor_test_restore_env(saved)
}

fn test_read_only_status_reports_niri_instead_of_hyprland() {
	saved := compositor_test_save_env()
	os.setenv('NIRI_SOCKET', '/run/user/1000/niri.1', true)
	os.setenv('HYPRLAND_INSTANCE_SIGNATURE', 'parent-hypr-session', true)
	os.setenv('HORNERO_QS_BIN', '/usr/bin/qs', true)
	shell := shell_status()
	power := power_status_report()
	assert shell.data['compositor'] == 'niri'
	assert shell.message.contains('compositor: niri')
	assert power.data['compositor'] == 'niri'
	assert power.message.contains('compositor: niri')
	compositor_test_restore_env(saved)
}
