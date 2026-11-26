module hornero_core

import os

fn make_fake_sysfs_root(base string) {
	// kernel
	os.mkdir_all(os.join_path(base, 'proc/sys/kernel')) or { panic(err) }
	os.write_file(os.join_path(base, 'proc/sys/kernel/osrelease'), '6.12.1-arch1-1\n') or {
		panic(err)
	}
	// wifi
	os.mkdir_all(os.join_path(base, 'sys/class/net/wlan0/wireless')) or { panic(err) }
	os.mkdir_all(os.join_path(base, 'sys/class/net/wlan0/device')) or { panic(err) }
	os.write_file(os.join_path(base, 'sys/class/net/wlan0/operstate'), 'up\n') or { panic(err) }
	os.write_file(os.join_path(base, 'sys/class/net/wlan0/device/uevent'), 'DRIVER=iwlwifi\n') or {
		panic(err)
	}
	// bluetooth
	os.mkdir_all(os.join_path(base, 'sys/class/bluetooth/hci0/device')) or { panic(err) }
	os.write_file(os.join_path(base, 'sys/class/bluetooth/hci0/type'), 'PRIMARY\n') or { panic(err) }
	os.write_file(os.join_path(base, 'sys/class/bluetooth/hci0/device/uevent'), 'DRIVER=btusb\n') or {
		panic(err)
	}
	// audio playback & capture
	os.mkdir_all(os.join_path(base, 'proc/asound/card0/pcm0p')) or { panic(err) }
	os.mkdir_all(os.join_path(base, 'proc/asound/card0/pcm0c')) or { panic(err) }
	os.write_file(os.join_path(base, 'proc/asound/card0/id'), 'PCH\n') or { panic(err) }
	// drm panel & graphics
	os.mkdir_all(os.join_path(base, 'sys/class/drm/card0/device')) or { panic(err) }
	os.write_file(os.join_path(base, 'sys/class/drm/card0/device/uevent'), 'DRIVER=i915\nPCI_ID=8086:9A49\n') or {
		panic(err)
	}
	os.mkdir_all(os.join_path(base, 'sys/class/drm/card0-eDP-1')) or { panic(err) }
	os.write_file(os.join_path(base, 'sys/class/drm/card0-eDP-1/status'), 'connected\n') or {
		panic(err)
	}
	os.write_file(os.join_path(base, 'sys/class/drm/card0-eDP-1/modes'), '1920x1080\n1280x720\n') or {
		panic(err)
	}
	// backlight
	os.mkdir_all(os.join_path(base, 'sys/class/backlight/intel_backlight')) or { panic(err) }
	os.write_file(os.join_path(base, 'sys/class/backlight/intel_backlight/brightness'), '500\n') or {
		panic(err)
	}
	os.write_file(os.join_path(base, 'sys/class/backlight/intel_backlight/max_brightness'),
		'1000\n') or { panic(err) }
	// touchpad
	os.mkdir_all(os.join_path(base, 'sys/class/input/input5')) or { panic(err) }
	os.write_file(os.join_path(base, 'sys/class/input/input5/name'), 'ELAN0672:00 Touchpad\n') or {
		panic(err)
	}
	// battery
	os.mkdir_all(os.join_path(base, 'sys/class/power_supply/BAT0')) or { panic(err) }
	os.write_file(os.join_path(base, 'sys/class/power_supply/BAT0/status'), 'Discharging\n') or {
		panic(err)
	}
	os.write_file(os.join_path(base, 'sys/class/power_supply/BAT0/capacity'), '84\n') or {
		panic(err)
	}
	// services
	os.mkdir_all(os.join_path(base, 'run/systemd/system')) or { panic(err) }
}

fn test_hardware_rollcall_fake_sysfs_all_categories() {
	tmp := os.join_path(os.temp_dir(), 'hornero_rollcall_test_${os.getpid()}')
	os.rmdir_all(tmp) or {}
	defer {
		os.rmdir_all(tmp) or {}
	}
	make_fake_sysfs_root(tmp)
	os.setenv('HORNERO_ROLLCALL_ROOT', tmp, true)
	defer {
		os.unsetenv('HORNERO_ROLLCALL_ROOT')
	}

	report := hardware_rollcall(RollcallOptions{})
	assert report.kernel == '6.12.1-arch1-1'
	assert report.entries.len == rollcall_categories.len
	for e in report.entries {
		assert e.status == 'ok', 'expected ok for ${e.category}, got ${e.status}: ${e.summary}'
	}

	md := format_rollcall_markdown(report)
	assert md.contains('## Hardware Rollcall (Redacted)')
	assert md.contains('| `wifi` | `ok` |')
	assert md.contains('| `battery` | `ok` |')

	js := format_rollcall_json(report)
	assert js.contains('"wifi"')
	assert js.contains('"6.12.1-arch1-1"')
}

fn test_hardware_rollcall_redaction() {
	sample := 'MAC aa:bb:cc:dd:ee:ff SSID: MyHomeNet, serial: SN-99887766, token=supersecret123'
	redacted := redact_rollcall_value(sample)
	assert !redacted.contains('aa:bb:cc:dd:ee:ff')
	assert redacted.contains('[redacted-mac]')
	assert !redacted.contains('MyHomeNet')
	assert redacted.contains('[redacted-ssid]')
	assert !redacted.contains('SN-99887766')
	assert redacted.contains('[redacted-serial]')
	assert !redacted.contains('supersecret123')
}

fn test_hardware_rollcall_result_list_and_markdown() {
	res_list := hardware_rollcall_result(RollcallOptions{
		list_only: true
	})
	assert res_list.ok
	assert res_list.message.contains('wifi')
	assert res_list.message.contains('services')
}
