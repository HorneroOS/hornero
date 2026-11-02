module hornero_core

import os

fn healthy_bt_probe() BluetoothProbe {
	return BluetoothProbe{
		adapter_present:     true
		adapters:            ['hci0']
		service_active:      true
		service_state:       'active'
		rfkill_present:      true
		powered:             true
		bluez_version:       '5.72'
		wp_bluez_nodes:      ['bluez_card.00_11 (A2DP, LDAC)']
		audio_profiles:      ['A2DP', 'LDAC']
		agent_registered:    true
		pipewire_present:    true
		wireplumber_present: true
	}
}

fn bt_check(checks []DoctorCheck, name string) DoctorCheck {
	for c in checks {
		if c.name == name {
			return c
		}
	}
	return DoctorCheck{
		name:   name
		ok:     false
		detail: 'missing check'
	}
}

fn test_bluetooth_doctor_healthy_probe_passes() {
	checks := bluetooth_doctor_checks(healthy_bt_probe())
	assert checks.len >= 10
	for c in checks {
		assert c.ok, c.name
	}
	res := bluetooth_doctor_result_from_probe(healthy_bt_probe())
	assert res.ok
	assert res.data['bluez_version'] == '5.72'
	assert res.data['bluetooth-adapter'] == 'ok'
	assert res.message.contains('bluetooth doctor: all')
}

fn test_bluetooth_doctor_no_adapter_reports_fix_and_firmware_hint() {
	mut p := healthy_bt_probe()
	p.adapter_present = false
	p.adapters = []string{}
	p.firmware_missing = true
	checks := bluetooth_doctor_checks(p)
	assert !bt_check(checks, 'bluetooth-adapter').ok
	assert bt_check(checks, 'bluetooth-adapter').detail.contains('fix:')
	assert bt_check(checks, 'bluetooth-adapter').detail.contains('linux-firmware')
	assert !bt_check(checks, 'bluetooth-firmware').ok
	assert !bluetooth_doctor_result_from_probe(p).ok
}

fn test_bluetooth_doctor_service_down_and_rfkill_blocked() {
	mut p := healthy_bt_probe()
	p.service_active = false
	p.service_state = 'inactive'
	p.rfkill_soft = true
	p.powered = false
	checks := bluetooth_doctor_checks(p)
	assert !bt_check(checks, 'bluetooth-service').ok
	assert bt_check(checks, 'bluetooth-service').detail.contains('bluetooth.service')
	assert bt_check(checks, 'bluetooth-service').detail.contains('fix:')
	assert !bt_check(checks, 'rfkill').ok
	assert bt_check(checks, 'rfkill').detail.contains('soft-blocked')
	assert bt_check(checks, 'rfkill').detail.contains('power on')
	assert !bt_check(checks, 'bluetooth-powered').ok
	p.rfkill_soft = false
	p.rfkill_hard = true
	assert bt_check(bluetooth_doctor_checks(p), 'rfkill').detail.contains('hard-blocked')
}

fn test_bluetooth_doctor_missing_bluez_and_audio_stack() {
	mut p := healthy_bt_probe()
	p.bluez_version = ''
	p.pipewire_present = false
	p.wireplumber_present = false
	p.wp_bluez_nodes = []string{}
	p.audio_profiles = []string{}
	checks := bluetooth_doctor_checks(p)
	assert !bt_check(checks, 'bluez-version').ok
	assert bt_check(checks, 'bluez-version').detail.contains('bluez-utils')
	assert !bt_check(checks, 'pipewire').ok
	assert !bt_check(checks, 'wireplumber').ok
	assert !bt_check(checks, 'wireplumber-bluez').ok
}

fn test_bluetooth_doctor_no_audio_node_is_not_failure_when_wp_present() {
	// No connected audio device yet, but the BlueZ5 monitor is loaded:
	// integration is proven, absence of nodes is not a failure.
	mut p := healthy_bt_probe()
	p.wp_bluez_nodes = []string{}
	p.audio_profiles = []string{}
	p.wp_bluez_monitor = true
	c := bt_check(bluetooth_doctor_checks(p), 'wireplumber-bluez')
	assert c.ok
	assert c.detail.contains('BlueZ5 monitor loaded')
}

fn test_bluetooth_doctor_audio_unproven_without_monitor_or_nodes() {
	// WirePlumber merely being on PATH must not produce a PASS: with an
	// adapter present but no BlueZ5 monitor and no nodes, Bluetooth
	// audio integration is unproven and the check fails.
	mut p := healthy_bt_probe()
	p.wp_bluez_nodes = []string{}
	p.audio_profiles = []string{}
	p.wp_bluez_monitor = false
	c := bt_check(bluetooth_doctor_checks(p), 'wireplumber-bluez')
	assert !c.ok
	assert c.detail.contains('NOT proven')
}

fn test_bluetooth_doctor_autoenable_false_and_missing_agent_fail() {
	mut p := healthy_bt_probe()
	p.autoenable_false = true
	p.agent_registered = false
	checks := bluetooth_doctor_checks(p)
	assert !bt_check(checks, 'bluetooth-main-conf').ok
	assert bt_check(checks, 'bluetooth-main-conf').detail.contains('AutoEnable=false')
	assert !bt_check(checks, 'bluetooth-agent').ok
	assert bt_check(checks, 'bluetooth-agent').detail.contains('never auto-accepted')
}

fn test_bluetooth_parse_helpers() {
	assert parse_bluetoothctl_version('bluetoothctl: 5.72\n') == '5.72'
	assert parse_bluetoothctl_version('') == ''
	soft := parse_rfkill_bluetooth('0: hci0: Bluetooth\n\tSoft blocked: yes\n\tHard blocked: no\n')
	assert soft.present && soft.soft_blocked && !soft.hard_blocked
	hard := parse_rfkill_bluetooth('Bluetooth\n\tSoft blocked: no\n\tHard blocked: yes\n')
	assert hard.hard_blocked
	show := parse_bluetoothctl_show('Controller AA\n\tPowered: yes\n\tPairable: no\n\tDiscoverable: no\n')
	assert show.powered && !show.pairable && !show.discoverable
	nodes := parse_wpctl_bluez_nodes('  40. bluez_card.AA (A2DP)\n  41. alsa_output\n')
	assert nodes.len == 1
	assert bluetooth_audio_profiles(nodes).contains('A2DP')
	devs := parse_bluetooth_devices('Device AA:BB:CC:DD:EE:FF Headphones\nDevice 11:22 Mouse\n')
	assert devs.len == 2
	assert devs[0].starts_with('AA:BB')
}

fn test_bluetooth_power_and_restart_require_yes_and_dry_run_previews() {
	assert !bluetooth_power_report(BluetoothPowerOptions{
		action: 'on'
	}).ok
	assert bluetooth_power_report(BluetoothPowerOptions{
		action:  'on'
		dry_run: true
	}).ok
	assert bluetooth_power_report(BluetoothPowerOptions{
		action:  'off'
		dry_run: true
	}).message.contains('rfkill')
	assert !bluetooth_power_report(BluetoothPowerOptions{
		action: 'bogus'
		yes:    true
	}).ok
	assert !bluetooth_restart_report(BluetoothRestartOptions{}).ok
	assert bluetooth_restart_report(BluetoothRestartOptions{
		dry_run: true
	}).message.contains('bluetooth.service')
	assert bluetooth_devices_report(BluetoothDevicesOptions{
		dry_run: true
	}).ok
	assert bluetooth_status_report(BluetoothStatusOptions{
		dry_run: true
	}).ok
}

fn test_agent_respond_writes_response_for_pending_request() {
	dir := os.join_path(os.temp_dir(), 'hornero-bt-agent-test-${os.getpid()}')
	os.mkdir_all(dir) or { panic(err) }
	defer { os.rmdir_all(dir) or {} }
	os.setenv('HORNERO_BLUETOOTH_AGENT_DIR', dir, true)
	defer { os.unsetenv('HORNERO_BLUETOOTH_AGENT_DIR') }
	os.write_file(os.join_path(dir, 'request-testreq1.json'), '{"id":"testreq1"}') or { panic(err) }
	res := bluetooth_agent_respond_report(BluetoothAgentRespondOptions{
		id:     'testreq1'
		action: 'confirm'
		yes:    true
	})
	assert res.ok
	body := os.read_file(os.join_path(dir, 'response-testreq1.json')) or { panic(err) }
	assert body.contains('"action":"confirm"')
}

fn test_agent_respond_rejects_unknown_request_and_bad_id() {
	dir := os.join_path(os.temp_dir(), 'hornero-bt-agent-test2-${os.getpid()}')
	os.mkdir_all(dir) or { panic(err) }
	defer { os.rmdir_all(dir) or {} }
	os.setenv('HORNERO_BLUETOOTH_AGENT_DIR', dir, true)
	defer { os.unsetenv('HORNERO_BLUETOOTH_AGENT_DIR') }
	assert !bluetooth_agent_respond_report(BluetoothAgentRespondOptions{
		id:     'missing1'
		action: 'confirm'
		yes:    true
	}).ok
	assert !bluetooth_agent_respond_report(BluetoothAgentRespondOptions{
		id:     '../evil'
		action: 'confirm'
		yes:    true
	}).ok
	assert !bluetooth_agent_respond_report(BluetoothAgentRespondOptions{
		id:     'testreq1'
		action: 'confirm'
	}).ok // no --yes
}
