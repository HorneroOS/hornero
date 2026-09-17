module hornero_core

import os

fn hw_test_save_env(keys []string) map[string]string {
	mut saved := map[string]string{}
	for k in keys {
		saved[k] = os.getenv(k)
	}
	return saved
}

fn hw_test_restore_env(saved map[string]string) {
	for k, v in saved {
		if v.len == 0 {
			os.unsetenv(k)
		} else {
			os.setenv(k, v, true)
		}
	}
}

fn hw_test_keys() []string {
	return ['HORNERO_BRIGHTNESSCTL_BIN', 'HORNERO_BLIGHT_BIN', 'HORNERO_XBACKLIGHT_BIN',
		'HORNERO_XRANDR_BIN', 'HORNERO_ACPI_BIN', 'HORNERO_UPOWER_BIN', 'HORNERO_POWERALERTD_BIN',
		'HORNERO_NOTIFY_BIN', 'HORNERO_WPCTL_BIN', 'HORNERO_MIC_SOURCE', 'HORNERO_HYPRCTL_BIN',
		'HORNERO_SETXKBMAP_BIN', 'HORNERO_LXQT_CONFIG_INPUT_BIN', 'HORNERO_KEYBOARD_SETTINGS_BIN',
		'HORNERO_SETTINGS_GUI_BIN', 'HORNERO_PING_BIN', 'HORNERO_IP_BIN', 'HORNERO_KEYBINDINGS_FILE',
		'DOTS_BYPASS_QUICKSHELL', 'DOTS_PING_HOST', 'HYPRLAND_INSTANCE_SIGNATURE', 'WAYLAND_DISPLAY',
		'I3SOCK', 'XDG_CONFIG_HOME']
}

fn hw_test_break_backends() {
	os.setenv('HORNERO_BRIGHTNESSCTL_BIN', '/nonexistent-brightnessctl-hw-test', true)
	os.setenv('HORNERO_BLIGHT_BIN', '/nonexistent-blight-hw-test', true)
	os.setenv('HORNERO_XBACKLIGHT_BIN', '/nonexistent-xbacklight-hw-test', true)
	os.setenv('HORNERO_XRANDR_BIN', '/nonexistent-xrandr-hw-test', true)
	os.setenv('HORNERO_ACPI_BIN', '/nonexistent-acpi-hw-test', true)
	os.setenv('HORNERO_UPOWER_BIN', '/nonexistent-upower-hw-test', true)
	os.setenv('HORNERO_POWERALERTD_BIN', '/nonexistent-poweralertd-hw-test', true)
	os.setenv('HORNERO_NOTIFY_BIN', '/nonexistent-notify-hw-test', true)
	os.setenv('HORNERO_WPCTL_BIN', '/nonexistent-wpctl-hw-test', true)
	os.setenv('HORNERO_HYPRCTL_BIN', '/nonexistent-hyprctl-hw-test', true)
	os.setenv('HORNERO_SETXKBMAP_BIN', '/nonexistent-setxkbmap-hw-test', true)
	os.setenv('HORNERO_LXQT_CONFIG_INPUT_BIN', '/nonexistent-lxqt-hw-test', true)
	os.setenv('HORNERO_KEYBOARD_SETTINGS_BIN', '/nonexistent-kbsettings-hw-test', true)
	os.setenv('HORNERO_SETTINGS_GUI_BIN', '/nonexistent-settings-gui-hw-test', true)
	os.setenv('HORNERO_PING_BIN', '/nonexistent-ping-hw-test', true)
	os.setenv('HORNERO_IP_BIN', '/nonexistent-ip-hw-test', true)
}

fn test_hw_is_decimal_number() {
	assert is_decimal_number('0.8')
	assert is_decimal_number('1')
	assert is_decimal_number('0.05')
	assert is_decimal_number('100')
	assert !is_decimal_number('')
	assert !is_decimal_number('abc')
	assert !is_decimal_number('0.8.1')
	assert !is_decimal_number('-0.5')
	assert !is_decimal_number('.')
	assert !is_decimal_number('1e3')
}

fn test_hw_brightness_clamp() {
	assert brightness_clamp(0.8) == 0.8
	assert brightness_clamp(-1.0) == 0.0
	assert brightness_clamp(2.5) == 1.0
}

fn test_hw_frac_from_pct() {
	assert frac_from_pct('50')! == 0.5
	assert frac_from_pct('0')! == 0.0
	if _ := frac_from_pct('abc') {
		assert false
	} else {
		assert true
	}
}

fn test_hw_battery_pct_before() {
	assert battery_pct_before('Battery 0: Discharging, 42%, 01:20:00') == 42
	assert battery_pct_before('percentage:          87%') == 87
	assert battery_pct_before('no numbers here') == -1
}

fn test_hw_hypr_opt_str() {
	assert hypr_opt_str('{"option":"input:kb_layout","str":"us"}') == 'us'
	assert hypr_opt_str('str: latam') == 'latam'
	assert hypr_opt_str('{"str": ""}') == ''
	assert hypr_opt_str('nothing here') == ''
}

fn test_hw_xkb_field() {
	out := 'rules:      evdev\nmodel:      pc105\nlayout:     us\nvariant:    \n'
	assert xkb_field(out, 'layout') == 'us'
	assert xkb_field(out, 'variant') == ''
	assert xkb_field(out, 'missing') == ''
}

fn test_hw_keybindings_parse() {
	text := '# ============\n# Window\n# ============\nbind = \$mainMod, Return, exec, kitty\nbind = SUPER SHIFT, Q, killactive\nplain line\n# ============\n# Workspace\n# ============\nbind = SUPER, 1, workspace, 1\n'
	lines := parse_keybindings_text(text)
	assert lines.len == 3
	assert lines[0] == '[Window] SUPER + Return -> exec, kitty'
	assert lines[1] == '[Window] SUPER + SHIFT + Q -> killactive'
	assert lines[2] == '[Workspace] SUPER + 1 -> workspace, 1'
}

fn test_hw_mutations_need_yes() {
	r1 := brightness_set_report(BrightnessSetOptions{
		value: 0.8
	})
	assert !r1.ok
	assert r1.message.contains('--yes')
	r2 := brightness_adjust_report(BrightnessAdjustOptions{
		dir:  'up'
		step: 0.1
	})
	assert !r2.ok
	assert r2.message.contains('--yes')
	r3 := battery_monitor_report(BatteryMonitorOptions{
		low:      20
		crit:     10
		interval: 120
	})
	assert !r3.ok
	assert r3.message.contains('--yes')
	r4 := mic_toggle_report(MicToggleOptions{})
	assert !r4.ok
	assert r4.message.contains('--yes')
	r5 := keyboard_layout_report(KeyboardLayoutOptions{
		mode: 'toggle'
	})
	assert !r5.ok
	assert r5.message.contains('--yes')
}

fn test_hw_adjust_unknown_dir() {
	r := brightness_adjust_report(BrightnessAdjustOptions{
		dir:     'sideways'
		step:    0.1
		dry_run: true
	})
	assert !r.ok
	assert r.message.contains('unknown brightness action')
}

fn test_hw_missing_backends_fail() {
	saved := hw_test_save_env(hw_test_keys())
	hw_test_break_backends()
	os.unsetenv('HYPRLAND_INSTANCE_SIGNATURE')
	os.unsetenv('WAYLAND_DISPLAY')
	os.unsetenv('I3SOCK')
	// Broken overrides (explicit nonexistent paths) fail cleanly instead of
	// executing: every read reports failure, never a fabricated value.
	b := battery_status_report(BatteryStatusOptions{})
	assert !b.ok
	m := mic_status_report(MicStatusOptions{})
	assert !m.ok
	n := network_status_report(NetworkStatusOptions{
		timeout: 5
	})
	assert !n.ok
	assert n.message.contains('ping')
	g := keyboard_layout_report(KeyboardLayoutOptions{
		mode: 'get'
	})
	assert !g.ok
	assert g.message.contains('setxkbmap')
	s := brightness_status_report(BrightnessStatusOptions{})
	assert !s.ok
	hw_test_restore_env(saved)
}

fn test_hw_keyboard_settings_native_opens() {
	// Native port: the pinned opener (/bin/true fixture) launches
	// detached; dots-keyboard-settings is never consulted.
	saved := hw_test_save_env(hw_test_keys())
	hw_test_break_backends()
	os.setenv('HORNERO_KEYBOARD_SETTINGS_BIN', '/bin/true', true)
	r := keyboard_settings_report(KeyboardSettingsOptions{})
	assert r.ok
	assert r.message.contains('keyboard settings opened')
	hw_test_restore_env(saved)
}

fn test_hw_keyboard_settings_native_fails_closed() {
	// Broken overrides (nonexistent paths) fail closed naming the
	// installer instead of spawning async.
	saved := hw_test_save_env(hw_test_keys())
	hw_test_break_backends()
	os.setenv('HORNERO_KEYBOARD_SETTINGS_BIN', '/nonexistent-kbsettings-hw-test', true)
	os.setenv('HORNERO_LXQT_CONFIG_INPUT_BIN', '/nonexistent-lxqt-hw-test', true)
	r := keyboard_settings_report(KeyboardSettingsOptions{})
	assert !r.ok
	assert r.message.contains('lxqt-config-input')
	hw_test_restore_env(saved)
}

fn test_hw_dry_run_needs_no_backend() {
	saved := hw_test_save_env(hw_test_keys())
	hw_test_break_backends()
	os.unsetenv('HYPRLAND_INSTANCE_SIGNATURE')
	os.unsetenv('WAYLAND_DISPLAY')
	os.unsetenv('I3SOCK')
	assert brightness_status_report(BrightnessStatusOptions{
		dry_run: true
	}).ok
	assert brightness_set_report(BrightnessSetOptions{
		value:   0.8
		dry_run: true
	}).ok
	assert brightness_adjust_report(BrightnessAdjustOptions{
		dir:     'up'
		step:    0.1
		dry_run: true
	}).ok
	assert battery_status_report(BatteryStatusOptions{
		dry_run: true
	}).ok
	assert battery_monitor_report(BatteryMonitorOptions{
		low:      25
		crit:     15
		interval: 60
		dry_run:  true
	}).ok
	assert battery_monitor_report(BatteryMonitorOptions{
		low:      20
		crit:     10
		interval: 120
		daemon:   true
		dry_run:  true
	}).ok
	assert mic_status_report(MicStatusOptions{
		dry_run: true
	}).ok
	assert mic_toggle_report(MicToggleOptions{
		dry_run: true
	}).ok
	assert keyboard_layout_report(KeyboardLayoutOptions{
		mode:    'toggle'
		dry_run: true
	}).ok
	assert keyboard_layout_report(KeyboardLayoutOptions{
		mode:    'get'
		dry_run: true
	}).ok
	assert keyboard_layout_report(KeyboardLayoutOptions{
		mode:    'current'
		dry_run: true
	}).ok
	assert keyboard_settings_report(KeyboardSettingsOptions{
		dry_run: true
	}).ok
	assert keyboard_keys_report(KeyboardKeysOptions{
		dry_run: true
	}).ok
	assert network_status_report(NetworkStatusOptions{
		timeout: 5
		dry_run: true
	}).ok
	hw_test_restore_env(saved)
}

fn test_hw_keys_parse_fixture() {
	saved := hw_test_save_env(hw_test_keys())
	os.mkdir_all('/tmp/hx-hw-ctest') or { assert false }
	os.write_file('/tmp/hx-hw-ctest/keybindings.conf', '# ============\n# Window\n# ============\nbind = \$mainMod, Return, exec, kitty\n# ============\n# Workspace\n# ============\nbind = SUPER, 1, workspace, 1\n') or {
		assert false
	}
	os.setenv('HORNERO_KEYBINDINGS_FILE', '/tmp/hx-hw-ctest/keybindings.conf', true)
	os.setenv('DOTS_BYPASS_QUICKSHELL', '1', true)
	r := keyboard_keys_report(KeyboardKeysOptions{})
	assert r.ok
	assert r.message.contains('[Window] SUPER + Return -> exec, kitty')
	c := keyboard_keys_report(KeyboardKeysOptions{
		category: 'workspace'
	})
	assert c.ok
	assert !c.message.contains('[Window]')
	assert c.message.contains('[Workspace]')
	s := keyboard_keys_report(KeyboardKeysOptions{
		search: 'kitty'
	})
	assert s.ok
	assert s.message.contains('kitty')
	assert !s.message.contains('[Workspace]')
	os.setenv('HORNERO_KEYBINDINGS_FILE', '/tmp/hx-hw-ctest/missing.conf', true)
	m := keyboard_keys_report(KeyboardKeysOptions{})
	assert !m.ok
	assert m.message.contains('not found')
	hw_test_restore_env(saved)
}

fn test_hw_brightness_temp_tables() {
	// Ramps cribbed from redshift like dots-brightness: index 0 is
	// 3000K, index 6 neutral 6500K, index 10 is 10000K.
	assert brightness_gamma_of_temp(0.0) == '1.0:0.7:0.4'
	assert brightness_gamma_of_temp(0.6) == '1.0:1.0:1.0'
	assert brightness_gamma_of_temp(1.0) == '0.7:0.8:1.0'
	// Out-of-range clamps like the dots-brightness exec_op.
	assert brightness_gamma_of_temp(-0.5) == '1.0:0.7:0.4'
	assert brightness_gamma_of_temp(2.5) == '0.7:0.8:1.0'
	assert brightness_temp_of_gamma('1.0:1.0:1.0') == 0.6
	assert brightness_temp_of_gamma('1.0:0.7:0.4') == 0.0
	assert brightness_temp_of_gamma('0.7:0.8:1.0') == 1.0
	assert brightness_temp_of_gamma('9.9:9.9:9.9') == -1.0
	assert brightness_temp_kelvin_of(0.0) == 3000
	assert brightness_temp_kelvin_of(0.6) == 6500
	assert brightness_temp_kelvin_of(1.0) == 10000
}

fn test_hw_brightness_invert_gamma() {
	// xrandr --verbose reports inverted gamma: raw 1.0:1.4:2.5 reads
	// back as the corrected 3000K ramp triplet.
	assert brightness_invert_gamma('1.0:1.4:2.5')! == '1.0:0.7:0.4'
	assert brightness_invert_gamma('1.0:1.0:1.0')! == '1.0:1.0:1.0'
	if _ := brightness_invert_gamma('1.0:0.5') {
		assert false
	} else {
		assert true
	}
	if _ := brightness_invert_gamma('1.0:0.0:1.0') {
		assert false
	} else {
		assert true
	}
}

fn test_hw_brightness_temp_mutations_need_yes() {
	r1 := brightness_temp_report(BrightnessTempOptions{
		op:    'set'
		value: 0.6
	})
	assert !r1.ok
	assert r1.message.contains('--yes')
	r2 := brightness_temp_report(BrightnessTempOptions{
		op:    'up'
		value: 0.1
	})
	assert !r2.ok
	assert r2.message.contains('--yes')
}

fn test_hw_brightness_temp_dry_run_needs_no_backend() {
	saved := hw_test_save_env(hw_test_keys())
	hw_test_break_backends()
	os.unsetenv('HYPRLAND_INSTANCE_SIGNATURE')
	os.unsetenv('WAYLAND_DISPLAY')
	os.unsetenv('I3SOCK')
	assert brightness_temp_report(BrightnessTempOptions{
		op:      'set'
		value:   0.6
		display: 'eDP-1'
		dry_run: true
	}).ok
	assert brightness_temp_report(BrightnessTempOptions{
		op:      'up'
		value:   0.1
		dry_run: true
	}).ok
	assert brightness_temp_report(BrightnessTempOptions{
		op:      'down'
		value:   0.1
		dry_run: true
	}).ok
	hw_test_restore_env(saved)
}

fn test_hw_brightness_temp_live() {
	saved := hw_test_save_env(hw_test_keys())
	os.mkdir_all('/tmp/hx-hw-temp-live/bin') or { assert false }
	os.write_file('/tmp/hx-hw-temp-live/bin/xrandr', '#!/bin/sh\nif [ "$1" = "--verbose" ]; then printf "eDP-1 connected primary 1920x1080+0+0\\n\\tBrightness: 0.8\\n\\tGamma: 1.0:1.4:2.5\\n"; exit 0; fi\nexit 0\n') or {
		assert false
	}
	os.chmod('/tmp/hx-hw-temp-live/bin/xrandr', 0o755) or { assert false }
	// Break every backend except xrandr so temperature resolves
	// hermetically (dots-brightness --temp always drives xrandr).
	hw_test_break_backends()
	os.setenv('HORNERO_XRANDR_BIN', '/tmp/hx-hw-temp-live/bin/xrandr', true)
	// set needs no gamma read: the fixture exits 0 on the --gamma call.
	s := brightness_temp_report(BrightnessTempOptions{
		op:      'set'
		value:   0.6
		display: 'eDP-1'
		yes:     true
	})
	assert s.ok
	assert s.message.contains('6500K')
	// up reads the current temp (raw 1.0:1.4:2.5 -> 3000K ramp 0.0)
	// then shifts +0.1 to the 3500K ramp.
	u := brightness_temp_report(BrightnessTempOptions{
		op:      'up'
		value:   0.1
		display: 'eDP-1'
		yes:     true
	})
	assert u.ok
	assert u.message.contains('3500K')
	hw_test_restore_env(saved)
}
