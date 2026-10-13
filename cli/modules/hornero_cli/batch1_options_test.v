module hornero_cli

import os

fn package_options_test_save_env(keys []string) map[string]string {
	mut saved := map[string]string{}
	for key in keys {
		saved[key] = os.getenv(key)
	}
	return saved
}

fn package_options_test_restore_env(saved map[string]string) {
	for key, value in saved {
		if value.len == 0 {
			os.unsetenv(key)
		} else {
			os.setenv(key, value, true)
		}
	}
}

fn test_package_deps_parser_accepts_supported_compositor() {
	options := parse_package_cmd(['deps', '--compositor', 'niri']) or {
		assert false, err.msg()
		return
	}
	assert options.leaf == 'deps'
	assert options.compositor == 'niri'
}

fn test_package_deps_parser_rejects_unavailable_compositor() {
	_ := parse_package_cmd(['deps', '--compositor', 'labwc']) or {
		assert err.msg().contains('Choose hyprland or niri')
		return
	}
	assert false, 'an unimplemented compositor must not be accepted'
}

fn test_package_deps_parser_requires_compositor_value() {
	_ := parse_package_cmd(['deps', '--compositor']) or {
		assert err.msg().contains('missing compositor')
		return
	}
	assert false, '--compositor must have a value'
}

fn test_package_check_rejects_compositor_option() {
	_ := parse_package_cmd(['check', '--compositor', 'niri']) or {
		assert err.msg().contains('takes no --yes/--install/--optional')
		return
	}
	assert false, 'the compositor selector only belongs to package deps'
}

fn test_package_deps_dispatches_niri_as_read_only_compositor_check() {
	saved := package_options_test_save_env([
		'PATH',
		'HORNERO_SYSTEM_PROFILE_FILE',
		'HORNERO_DEPENDENCY_ROOT',
		'NIRI_SOCKET',
		'HYPRLAND_INSTANCE_SIGNATURE',
	])
	os.setenv('PATH', '/nonexistent-hx-path-test', true)
	os.setenv('HORNERO_SYSTEM_PROFILE_FILE', '/nonexistent-hx-profile-test', true)
	os.setenv('HORNERO_DEPENDENCY_ROOT', '/nonexistent-hx-root-test', true)
	os.unsetenv('NIRI_SOCKET')
	os.unsetenv('HYPRLAND_INSTANCE_SIGNATURE')
	assert dispatch(['horneroctl', 'package', 'deps', '--compositor', 'niri']) == 0
	assert dispatch(['horneroctl', 'package', 'deps', '--compositor', 'labwc']) == 2
	package_options_test_restore_env(saved)
}
