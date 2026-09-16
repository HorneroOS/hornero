module hornero_cli

import os

// Hardware dispatch fixtures reuse a /tmp fixture tree; each test sets
// the backend overrides it needs and unsets them afterwards.
fn hw_dispatch_setup() {
	os.mkdir_all('/tmp/hx-hw-dtest/bin') or { assert false }
	os.write_file('/tmp/hx-hw-dtest/bin/brightnessctl', '#!/bin/sh\nif [ "$1" = "-m" ]; then echo "intel_backlight,backlight,60000,50%,120000"; exit 0; fi\nexit 0\n') or {
		assert false
	}
	os.write_file('/tmp/hx-hw-dtest/bin/xrandr', '#!/bin/sh\nif [ "$1" = "--verbose" ]; then printf "eDP-1 connected primary 1920x1080+0+0\\n\\tBrightness: 0.8\\nHDMI-1 disconnected\\n"; exit 0; fi\necho "eDP-1 connected primary 1920x1080+0+0"\nexit 0\n') or {
		assert false
	}
	os.write_file('/tmp/hx-hw-dtest/bin/acpi', '#!/bin/sh\necho "Battery 0: Discharging, 42%, 01:20:00 remaining"\nexit 0\n') or {
		assert false
	}
	os.write_file('/tmp/hx-hw-dtest/bin/wpctl', '#!/bin/sh\nif [ "$1" = "get-volume" ]; then echo "Volume: 0.55"; exit 0; fi\nexit 0\n') or {
		assert false
	}
	os.write_file('/tmp/hx-hw-dtest/bin/setxkbmap', '#!/bin/sh\nif [ "$1" = "-query" ]; then printf "rules:      evdev\\nlayout:     us\\nvariant:\\n"; exit 0; fi\nexit 0\n') or {
		assert false
	}
	os.write_file('/tmp/hx-hw-dtest/bin/ping', '#!/bin/sh\nexit 0\n') or { assert false }
	os.write_file('/tmp/hx-hw-dtest/bin/ip', '#!/bin/sh\necho "2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP mode DEFAULT"\nexit 0\n') or {
		assert false
	}
	os.write_file('/tmp/hx-hw-dtest/bin/notify-send', '#!/bin/sh\nexit 0\n') or { assert false }
	os.write_file('/tmp/hx-hw-dtest/bin/lxqt-config-input', '#!/bin/sh\nexit 0\n') or {
		assert false
	}
	os.write_file('/tmp/hx-hw-dtest/bin/dots-keyboard-settings', '#!/bin/sh\nexit 0\n') or {
		assert false
	}
	os.write_file('/tmp/hx-hw-dtest/bin/dots-settings-gui', '#!/bin/sh\nexit 0\n') or {
		assert false
	}
	for b in ['brightnessctl', 'xrandr', 'acpi', 'wpctl', 'setxkbmap', 'ping', 'ip', 'notify-send',
		'lxqt-config-input', 'dots-keyboard-settings', 'dots-settings-gui'] {
		os.chmod('/tmp/hx-hw-dtest/bin/${b}', 0o755) or { assert false }
	}
	os.mkdir_all('/tmp/hx-hw-dtest/conf') or { assert false }
	os.write_file('/tmp/hx-hw-dtest/conf/keybindings.conf', '# ============\n# Window\n# ============\nbind = \$mainMod, Return, exec, kitty\n# ============\n# Workspace\n# ============\nbind = SUPER, 1, workspace, 1\n') or {
		assert false
	}
	os.setenv('HORNERO_BRIGHTNESSCTL_BIN', '/tmp/hx-hw-dtest/bin/brightnessctl', true)
	os.setenv('HORNERO_BLIGHT_BIN', '/nonexistent-blight-hw-test', true)
	os.setenv('HORNERO_XBACKLIGHT_BIN', '/nonexistent-xbacklight-hw-test', true)
	os.setenv('HORNERO_XRANDR_BIN', '/tmp/hx-hw-dtest/bin/xrandr', true)
	os.setenv('HORNERO_ACPI_BIN', '/tmp/hx-hw-dtest/bin/acpi', true)
	os.setenv('HORNERO_UPOWER_BIN', '/nonexistent-upower-hw-test', true)
	os.setenv('HORNERO_POWERALERTD_BIN', '/nonexistent-poweralertd-hw-test', true)
	os.setenv('HORNERO_NOTIFY_BIN', '/tmp/hx-hw-dtest/bin/notify-send', true)
	os.setenv('HORNERO_WPCTL_BIN', '/tmp/hx-hw-dtest/bin/wpctl', true)
	os.setenv('HORNERO_HYPRCTL_BIN', '/nonexistent-hyprctl-hw-test', true)
	os.setenv('HORNERO_SETXKBMAP_BIN', '/tmp/hx-hw-dtest/bin/setxkbmap', true)
	os.setenv('HORNERO_LXQT_CONFIG_INPUT_BIN', '/tmp/hx-hw-dtest/bin/lxqt-config-input',
		true)
	os.setenv('HORNERO_KEYBOARD_SETTINGS_BIN', '/tmp/hx-hw-dtest/bin/dots-keyboard-settings',
		true)
	os.setenv('HORNERO_SETTINGS_GUI_BIN', '/tmp/hx-hw-dtest/bin/dots-settings-gui', true)
	os.setenv('HORNERO_PING_BIN', '/tmp/hx-hw-dtest/bin/ping', true)
	os.setenv('HORNERO_IP_BIN', '/tmp/hx-hw-dtest/bin/ip', true)
	os.setenv('HORNERO_KEYBINDINGS_FILE', '/tmp/hx-hw-dtest/conf/keybindings.conf', true)
	os.setenv('DOTS_BYPASS_QUICKSHELL', '1', true)
	os.unsetenv('HYPRLAND_INSTANCE_SIGNATURE')
	os.unsetenv('WAYLAND_DISPLAY')
	os.unsetenv('I3SOCK')
}

fn hw_dispatch_teardown() {
	for k in ['HORNERO_BRIGHTNESSCTL_BIN', 'HORNERO_BLIGHT_BIN', 'HORNERO_XBACKLIGHT_BIN',
		'HORNERO_XRANDR_BIN', 'HORNERO_ACPI_BIN', 'HORNERO_UPOWER_BIN', 'HORNERO_POWERALERTD_BIN',
		'HORNERO_NOTIFY_BIN', 'HORNERO_WPCTL_BIN', 'HORNERO_HYPRCTL_BIN', 'HORNERO_SETXKBMAP_BIN',
		'HORNERO_LXQT_CONFIG_INPUT_BIN', 'HORNERO_KEYBOARD_SETTINGS_BIN', 'HORNERO_SETTINGS_GUI_BIN',
		'HORNERO_PING_BIN', 'HORNERO_IP_BIN', 'HORNERO_KEYBINDINGS_FILE', 'DOTS_BYPASS_QUICKSHELL'] {
		os.unsetenv(k)
	}
}

fn test_dispatch_hardware_groups() {
	hw_dispatch_setup()
	assert dispatch(['horneroctl', 'hardware', 'brightness', 'status']) == 0
	assert dispatch(['horneroctl', 'hardware', 'battery', 'status']) == 0
	assert dispatch(['horneroctl', 'hardware', 'mic', 'status']) == 0
	assert dispatch(['horneroctl', 'hardware', 'keyboard', 'layout', '--get']) == 0
	assert dispatch(['horneroctl', 'hardware', 'network', 'status']) == 0
	// Usage errors (exit 2).
	assert dispatch(['horneroctl', 'hardware']) == 2
	assert dispatch(['horneroctl', 'hardware', 'bogus']) == 2
	assert dispatch(['horneroctl', 'hardware', '--help']) == 0
	assert dispatch(['horneroctl', 'hardware', 'brightness', '--help']) == 0
	assert dispatch(['horneroctl', 'hardware', 'battery', '--help']) == 0
	assert dispatch(['horneroctl', 'hardware', 'mic', '--help']) == 0
	assert dispatch(['horneroctl', 'hardware', 'keyboard', '--help']) == 0
	assert dispatch(['horneroctl', 'hardware', 'network', '--help']) == 0
	hw_dispatch_teardown()
}

fn test_dispatch_hardware_brightness() {
	hw_dispatch_setup()
	assert dispatch(['horneroctl', 'hardware', 'brightness', 'status']) == 0
	assert dispatch(['horneroctl', 'hardware', 'brightness', 'status', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hardware', 'brightness', 'set', '0.8', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hardware', 'brightness', 'set', '0.8', '--yes']) == 0
	assert dispatch(['horneroctl', 'hardware', 'brightness', 'up', '--yes']) == 0
	assert dispatch(['horneroctl', 'hardware', 'brightness', 'down', '--step', '0.05', '--dry-run']) == 0
	// Mutations without --yes fail (exit 1).
	assert dispatch(['horneroctl', 'hardware', 'brightness', 'set', '0.8']) == 1
	assert dispatch(['horneroctl', 'hardware', 'brightness', 'up']) == 1
	assert dispatch(['horneroctl', 'hardware', 'brightness', 'down']) == 1
	// Usage errors (exit 2).
	assert dispatch(['horneroctl', 'hardware', 'brightness']) == 2
	assert dispatch(['horneroctl', 'hardware', 'brightness', 'bogus']) == 2
	assert dispatch(['horneroctl', 'hardware', 'brightness', 'set']) == 2
	assert dispatch(['horneroctl', 'hardware', 'brightness', 'set', 'abc', '--dry-run']) == 2
	assert dispatch(['horneroctl', 'hardware', 'brightness', 'set', '0.8', '--bogus']) == 2
	assert dispatch(['horneroctl', 'hardware', 'brightness', 'status', '--yes']) == 2
	assert dispatch(['horneroctl', 'hardware', 'brightness', 'up', '--step', 'abc', '--dry-run']) == 2
	hw_dispatch_teardown()
}

fn test_dispatch_hardware_brightness_xrandr() {
	hw_dispatch_setup()
	// Hermetic xrandr path: a fixture-only PATH plus unset overrides, so
	// the real brightnessctl on the host PATH cannot win precedence.
	os.mkdir_all('/tmp/hx-hw-dtest/xonly') or { assert false }
	os.cp('/tmp/hx-hw-dtest/bin/xrandr', '/tmp/hx-hw-dtest/xonly/xrandr') or { assert false }
	old_path := os.getenv('PATH')
	defer {
		os.setenv('PATH', old_path, true)
	}
	os.unsetenv('HORNERO_BRIGHTNESSCTL_BIN')
	os.unsetenv('HORNERO_BLIGHT_BIN')
	os.unsetenv('HORNERO_XBACKLIGHT_BIN')
	os.setenv('PATH', '/tmp/hx-hw-dtest/xonly', true)
	assert dispatch(['horneroctl', 'hardware', 'brightness', 'status']) == 0
	assert dispatch(['horneroctl', 'hardware', 'brightness', 'status', '--display', 'eDP-1']) == 0
	hw_dispatch_teardown()
}

fn test_dispatch_hardware_battery() {
	hw_dispatch_setup()
	assert dispatch(['horneroctl', 'hardware', 'battery', 'status']) == 0
	assert dispatch(['horneroctl', 'hardware', 'battery', 'status', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hardware', 'battery', 'monitor', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hardware', 'battery', 'monitor', '--low=25', '--crit=15',
		'--dry-run']) == 0
	assert dispatch(['horneroctl', 'hardware', 'battery', 'monitor', '--daemon', '--dry-run']) == 0
	// Monitor without --yes fails (exit 1).
	assert dispatch(['horneroctl', 'hardware', 'battery', 'monitor']) == 1
	// Usage errors (exit 2).
	assert dispatch(['horneroctl', 'hardware', 'battery']) == 2
	assert dispatch(['horneroctl', 'hardware', 'battery', 'bogus']) == 2
	assert dispatch(['horneroctl', 'hardware', 'battery', 'monitor', '--low=abc', '--dry-run']) == 2
	assert dispatch(['horneroctl', 'hardware', 'battery', 'monitor', '--low=10', '--crit=15',
		'--dry-run']) == 2
	assert dispatch(['horneroctl', 'hardware', 'battery', 'status', '--low=25']) == 2
	hw_dispatch_teardown()
}

fn test_dispatch_hardware_mic() {
	hw_dispatch_setup()
	assert dispatch(['horneroctl', 'hardware', 'mic', 'status']) == 0
	assert dispatch(['horneroctl', 'hardware', 'mic', 'status', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hardware', 'mic', 'toggle', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hardware', 'mic', 'toggle', '--yes']) == 0
	assert dispatch(['horneroctl', 'hardware', 'mic', 'toggle']) == 1
	assert dispatch(['horneroctl', 'hardware', 'mic']) == 2
	assert dispatch(['horneroctl', 'hardware', 'mic', 'bogus']) == 2
	assert dispatch(['horneroctl', 'hardware', 'mic', 'toggle', '--bogus']) == 2
	hw_dispatch_teardown()
}

fn test_dispatch_hardware_keyboard() {
	hw_dispatch_setup()
	assert dispatch(['horneroctl', 'hardware', 'keyboard', 'layout', '--get']) == 0
	assert dispatch(['horneroctl', 'hardware', 'keyboard', 'layout', '--current']) == 0
	assert dispatch(['horneroctl', 'hardware', 'keyboard', 'layout', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hardware', 'keyboard', 'layout', '--yes']) == 0
	assert dispatch(['horneroctl', 'hardware', 'keyboard', 'layout']) == 1
	assert dispatch(['horneroctl', 'hardware', 'keyboard', 'settings', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hardware', 'keyboard', 'settings']) == 0
	assert dispatch(['horneroctl', 'hardware', 'keyboard', 'keys']) == 0
	assert dispatch(['horneroctl', 'hardware', 'keyboard', 'keys', '--search=kitty']) == 0
	assert dispatch(['horneroctl', 'hardware', 'keyboard', 'keys', '--category', 'Workspace']) == 0
	assert dispatch(['horneroctl', 'hardware', 'keyboard']) == 2
	assert dispatch(['horneroctl', 'hardware', 'keyboard', 'bogus']) == 2
	assert dispatch(['horneroctl', 'hardware', 'keyboard', 'layout', '--current', '--get']) == 2
	assert dispatch(['horneroctl', 'hardware', 'keyboard', 'settings', '--yes']) == 2
	hw_dispatch_teardown()
}

fn test_dispatch_hardware_network() {
	hw_dispatch_setup()
	assert dispatch(['horneroctl', 'hardware', 'network', 'status']) == 0
	assert dispatch(['horneroctl', 'hardware', 'network', 'status', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hardware', 'network', 'status', '--timeout=2']) == 0
	assert dispatch(['horneroctl', 'hardware', 'network']) == 2
	assert dispatch(['horneroctl', 'hardware', 'network', 'bogus']) == 2
	assert dispatch(['horneroctl', 'hardware', 'network', 'status', '--timeout=abc']) == 2
	assert dispatch(['horneroctl', 'hardware', 'network', 'status', '--bogus']) == 2
	hw_dispatch_teardown()
}

fn test_hardware_dry_run_needs_no_backend() {
	// Hermetic: nonexistent backends; dry-run previews must still pass.
	saved_session := os.getenv('HYPRLAND_INSTANCE_SIGNATURE')
	saved_wayland := os.getenv('WAYLAND_DISPLAY')
	saved_i3 := os.getenv('I3SOCK')
	hw_dispatch_setup()
	for b in ['HORNERO_BRIGHTNESSCTL_BIN', 'HORNERO_BLIGHT_BIN', 'HORNERO_XBACKLIGHT_BIN',
		'HORNERO_XRANDR_BIN', 'HORNERO_ACPI_BIN', 'HORNERO_UPOWER_BIN', 'HORNERO_WPCTL_BIN',
		'HORNERO_HYPRCTL_BIN', 'HORNERO_SETXKBMAP_BIN', 'HORNERO_LXQT_CONFIG_INPUT_BIN',
		'HORNERO_KEYBOARD_SETTINGS_BIN', 'HORNERO_SETTINGS_GUI_BIN', 'HORNERO_PING_BIN',
		'HORNERO_IP_BIN'] {
		os.setenv(b, '/nonexistent-hw-backend-test', true)
	}
	assert dispatch(['horneroctl', 'hardware', 'brightness', 'status', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hardware', 'brightness', 'set', '0.5', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hardware', 'brightness', 'up', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hardware', 'brightness', 'down', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hardware', 'battery', 'status', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hardware', 'battery', 'monitor', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hardware', 'battery', 'monitor', '--daemon', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hardware', 'mic', 'status', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hardware', 'mic', 'toggle', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hardware', 'keyboard', 'layout', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hardware', 'keyboard', 'layout', '--get', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hardware', 'keyboard', 'settings', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hardware', 'keyboard', 'keys', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hardware', 'network', 'status', '--dry-run']) == 0
	hw_dispatch_teardown()
	if saved_session.len > 0 {
		os.setenv('HYPRLAND_INSTANCE_SIGNATURE', saved_session, true)
	}
	if saved_wayland.len > 0 {
		os.setenv('WAYLAND_DISPLAY', saved_wayland, true)
	}
	if saved_i3.len > 0 {
		os.setenv('I3SOCK', saved_i3, true)
	}
}

fn test_hardware_help_has_examples() {
	for cmd in ['hardware', 'hardware brightness', 'hardware battery', 'hardware mic',
		'hardware keyboard', 'hardware network'] {
		h := command_help(cmd)
		assert h.contains('Examples:')
	}
}

fn test_hardware_json_and_quiet_modes() {
	hw_dispatch_setup()
	assert dispatch(['horneroctl', '--json', 'hardware', 'brightness', 'status']) == 0
	assert dispatch(['horneroctl', '--quiet', 'hardware', 'battery', 'status']) == 0
	assert dispatch(['horneroctl', '--json', 'hardware', 'mic', 'toggle', '--dry-run']) == 0
	assert dispatch(['horneroctl', '--quiet', 'hardware', 'keyboard', 'layout', '--get']) == 0
	assert dispatch(['horneroctl', '--json', 'hardware', 'network', 'status']) == 0
	hw_dispatch_teardown()
}
