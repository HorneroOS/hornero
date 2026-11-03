module hornero_core

import os

// Bluetooth backend: read-only diagnostics (`hardware bluetooth doctor`,
// also exposed as top-level `bluetooth doctor`) plus gated power/restart
// mutations. Doctor follows the studio/gaming pattern: a pure probed
// struct is turned into DoctorChecks, so unit tests need no D-Bus, no
// adapter, and no running bluetooth.service. Live probing is single-shot
// and event-free (no polling loops in core).

pub fn resolve_bluetoothctl_bin() string {
	env := os.getenv('HORNERO_BLUETOOTHCTL_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('bluetoothctl')
}

pub fn resolve_rfkill_bin() string {
	env := os.getenv('HORNERO_RFKILL_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('rfkill')
}

pub struct BluetoothProbe {
pub mut:
	adapter_present     bool
	adapters            []string
	service_active      bool
	service_state       string
	rfkill_present      bool
	rfkill_soft         bool
	rfkill_hard         bool
	powered             bool
	pairable            bool
	discoverable        bool
	bluez_version       string
	wp_bluez_nodes      []string
	wp_bluez_monitor    bool
	audio_profiles      []string
	agent_registered    bool
	pipewire_present    bool
	wireplumber_present bool
	firmware_missing    bool
	autoenable_false    bool
}

pub struct RfkillState {
pub mut:
	present      bool
	soft_blocked bool
	hard_blocked bool
}

pub struct BluetoothShow {
pub mut:
	powered      bool
	pairable     bool
	discoverable bool
}

// parse_bluetoothctl_version extracts the version from
// `bluetoothctl --version` output (e.g. "bluetoothctl: 5.72").
pub fn parse_bluetoothctl_version(output string) string {
	for line in output.split_into_lines() {
		t := line.trim_space()
		if t.len == 0 {
			continue
		}
		parts := t.split(' ')
		last := parts[parts.len - 1].trim_space()
		if last.len > 0 && last[0].is_digit() {
			return last
		}
		return t
	}
	return ''
}

// parse_rfkill_bluetooth parses `rfkill list bluetooth` output.
pub fn parse_rfkill_bluetooth(output string) RfkillState {
	mut st := RfkillState{}
	lower := output.to_lower()
	if lower.contains('bluetooth') {
		st.present = true
	}
	if lower.contains('soft blocked: yes') {
		st.soft_blocked = true
	}
	if lower.contains('hard blocked: yes') {
		st.hard_blocked = true
	}
	return st
}

// parse_bluetoothctl_show parses `bluetoothctl show` Powered/Pairable/
// Discoverable lines.
pub fn parse_bluetoothctl_show(output string) BluetoothShow {
	mut show := BluetoothShow{}
	for line in output.split_into_lines() {
		t := line.trim_space()
		if t.starts_with('Powered:') {
			show.powered = t.all_after(':').trim_space() == 'yes'
		} else if t.starts_with('Pairable:') {
			show.pairable = t.all_after(':').trim_space() == 'yes'
		} else if t.starts_with('Discoverable:') {
			show.discoverable = t.all_after(':').trim_space() == 'yes'
		}
	}
	return show
}

// parse_wpctl_bluez_nodes returns wpctl status lines mentioning BlueZ.
pub fn parse_wpctl_bluez_nodes(output string) []string {
	mut nodes := []string{}
	for line in output.split_into_lines() {
		if line.to_lower().contains('bluez') {
			nodes << line.trim_space()
		}
	}
	return nodes
}

// bluetooth_audio_profiles extracts audio profile/codec tokens where
// detectable from WirePlumber node descriptions.
pub fn bluetooth_audio_profiles(nodes []string) []string {
	mut profiles := []string{}
	known := ['a2dp-sink', 'a2dp-source', 'headset-head-unit', 'handsfree-head-unit', 'A2DP', 'HFP',
		'HSP', 'LDAC', 'aptX', 'SBC', 'AAC', 'mSBC']
	for node in nodes {
		for k in known {
			if node.contains(k) && k !in profiles {
				profiles << k
			}
		}
	}
	return profiles
}

pub fn bluetooth_firmware_hint(probe BluetoothProbe) string {
	if probe.firmware_missing {
		return 'install linux-firmware (and the vendor firmware for your adapter), then run: horneroctl hardware bluetooth restart --yes'
	}
	if !probe.adapter_present {
		return 'check that the adapter is seated/USB-connected and that linux-firmware is installed; laptops may also need the hardware wireless switch enabled'
	}
	return 'no missing-firmware indicator detected'
}

fn bt_fix(ok bool, fix string) string {
	if ok {
		return ''
	}
	return '; fix: ${fix}'
}

// bluetooth_doctor_checks is pure: it maps a probed snapshot to checks.
// Every failing check carries an actionable fix in its detail.
pub fn bluetooth_doctor_checks(probe BluetoothProbe) []DoctorCheck {
	mut checks := []DoctorCheck{}
	adapter_detail := if probe.adapter_present {
		if probe.adapters.len > 0 {
			'adapter(s) present: ${probe.adapters.join(', ')}'
		} else {
			'adapter present in /sys/class/bluetooth'
		}
	} else {
		'no Bluetooth adapter found in /sys/class/bluetooth; fix: ${bluetooth_firmware_hint(probe)}'
	}
	checks << DoctorCheck{
		name:   'bluetooth-adapter'
		ok:     probe.adapter_present
		detail: adapter_detail
	}
	svc_state := if probe.service_state.len > 0 {
		probe.service_state
	} else if probe.service_active {
		'active'
	} else {
		'unknown'
	}
	checks << DoctorCheck{
		name:   'bluetooth-service'
		ok:     probe.service_active
		detail: 'bluetooth.service is ${svc_state}' + bt_fix(probe.service_active,
			'systemctl enable --now bluetooth.service (or horneroctl hardware bluetooth restart --yes)')
	}
	rfkill_ok := probe.rfkill_present && !probe.rfkill_soft && !probe.rfkill_hard
	rfkill_detail := if !probe.rfkill_present {
		'rfkill did not report a Bluetooth device'
	} else if probe.rfkill_hard {
		'Bluetooth is hard-blocked by rfkill (hardware switch/key)'
	} else if probe.rfkill_soft {
		'Bluetooth is soft-blocked by rfkill'
	} else {
		'Bluetooth is not rfkill-blocked'
	}
	rfkill_fix := if probe.rfkill_hard {
		'disable the hardware wireless switch / Fn key, then re-run doctor'
	} else {
		'horneroctl hardware bluetooth power on --yes (rfkill unblock bluetooth)'
	}
	checks << DoctorCheck{
		name:   'rfkill'
		ok:     rfkill_ok
		detail: rfkill_detail + bt_fix(rfkill_ok, rfkill_fix)
	}
	checks << DoctorCheck{
		name:   'bluetooth-powered'
		ok:     probe.powered
		detail: if probe.powered {
			'adapter is powered on (pairable=${probe.pairable}, discoverable=${probe.discoverable}; discoverability must stay time-limited)'
		} else {
			'adapter is powered off'
		} + bt_fix(probe.powered, 'horneroctl hardware bluetooth power on --yes')
	}
	bz_ok := probe.bluez_version.len > 0
	checks << DoctorCheck{
		name:   'bluez-version'
		ok:     bz_ok
		detail: if bz_ok {
			'BlueZ ${probe.bluez_version} (bluetoothctl on PATH)'
		} else {
			'bluetoothctl not found or reported no version'
		} + bt_fix(bz_ok, 'install bluez and bluez-utils (desktop edition package set)')
	}
	checks << DoctorCheck{
		name:   'pipewire'
		ok:     probe.pipewire_present
		detail: if probe.pipewire_present {
			'pipewire on PATH'
		} else {
			'pipewire not found on PATH'
		} +
			bt_fix(probe.pipewire_present, 'install pipewire and pipewire-audio (desktop edition package set)')
	}
	checks << DoctorCheck{
		name:   'wireplumber'
		ok:     probe.wireplumber_present
		detail: if probe.wireplumber_present {
			'wireplumber on PATH'
		} else {
			'wireplumber not found on PATH'
		} + bt_fix(probe.wireplumber_present,
			'install wireplumber (desktop edition package set)')
	}
	audio_ok := probe.wireplumber_present
		&& (probe.wp_bluez_monitor || probe.wp_bluez_nodes.len > 0
			|| !probe.adapter_present)
	audio_detail := if probe.wp_bluez_nodes.len > 0 {
		mut d := 'WirePlumber BlueZ node(s): ${probe.wp_bluez_nodes.join('; ')}'
		if probe.audio_profiles.len > 0 {
			d += ' profiles/codecs: ${probe.audio_profiles.join(', ')}'
		}
		d
	} else if probe.wp_bluez_monitor {
		'WirePlumber BlueZ5 monitor loaded; no Bluetooth audio device connected yet (connect one to see A2DP/HFP profiles)'
	} else {
		'WirePlumber BlueZ5 monitor not detected and no BlueZ audio nodes visible; Bluetooth audio integration is NOT proven (connect an adapter/audio device, then re-run doctor)'
	}
	checks << DoctorCheck{
		name:   'wireplumber-bluez'
		ok:     audio_ok
		detail: audio_detail + bt_fix(audio_ok, 'install wireplumber and restart the user PipeWire stack')
	}
	fw_ok := probe.adapter_present && !probe.firmware_missing
	checks << DoctorCheck{
		name:   'bluetooth-firmware'
		ok:     fw_ok
		detail: bluetooth_firmware_hint(probe) + bt_fix(fw_ok, bluetooth_firmware_hint(probe))
	}
	conf_ok := !probe.autoenable_false
	checks << DoctorCheck{
		name:   'bluetooth-main-conf'
		ok:     conf_ok
		detail: if conf_ok {
			'no AutoEnable=false override in /etc/bluetooth/main.conf (AutoEnable=true powers controllers at boot; a user power-off persists via the rfkill soft-block, not via AutoEnable)'
		} else {
			'/etc/bluetooth/main.conf sets AutoEnable=false, so controllers stay unpowered at boot and panel power toggles may not survive reboot'
		} + bt_fix(conf_ok, 'remove AutoEnable=false from /etc/bluetooth/main.conf [Policy] (keep AutoEnable=true)')
	}
	checks << DoctorCheck{
		name:   'bluetooth-agent'
		ok:     probe.agent_registered
		detail: if probe.agent_registered {
			'a pairing agent is registered (confirmations are user-prompted, never auto-accepted)'
		} else {
			'no pairing agent detected; pairing passkey/PIN prompts will not be shown'
		} + bt_fix(probe.agent_registered,
			'open Hornero Control Center Bluetooth (it registers the pairing agent) or start hornero-bt-agent; pairing is never auto-accepted and a NoInputNoOutput agent must not be used')
	}
	return checks
}

pub fn bluetooth_doctor_result_from_probe(probe BluetoothProbe) CommandResult {
	checks := bluetooth_doctor_checks(probe)
	mut lines := []string{}
	mut failed := 0
	mut data := map[string]string{}
	for c in checks {
		mark := if c.ok { 'ok' } else { 'FAIL' }
		if !c.ok {
			failed++
		}
		lines << '${mark}  ${c.name}: ${redact_secrets(c.detail)}'
		data[c.name] = if c.ok { 'ok' } else { 'fail' }
	}
	if failed == 0 {
		lines << 'bluetooth doctor: all ${checks.len} checks passed'
	} else {
		lines << 'bluetooth doctor: ${failed}/${checks.len} checks failed'
	}
	data['adapter_present'] = probe.adapter_present.str()
	data['adapters'] = probe.adapters.join(',')
	data['service_active'] = probe.service_active.str()
	data['service_state'] = probe.service_state
	data['rfkill_soft_blocked'] = probe.rfkill_soft.str()
	data['rfkill_hard_blocked'] = probe.rfkill_hard.str()
	data['powered'] = probe.powered.str()
	data['pairable'] = probe.pairable.str()
	data['discoverable'] = probe.discoverable.str()
	data['bluez_version'] = probe.bluez_version
	data['wireplumber_bluez_nodes'] = probe.wp_bluez_nodes.len.str()
	data['wireplumber_bluez_monitor'] = probe.wp_bluez_monitor.str()
	data['audio_profiles'] = probe.audio_profiles.join(',')
	data['agent_registered'] = probe.agent_registered.str()
	return CommandResult{
		command: 'bluetooth doctor'
		ok:      failed == 0
		message: lines.join('\n')
		data:    data
	}
}

fn bluetooth_sysfs_dir() string {
	env := os.getenv('HORNERO_BLUETOOTH_SYSFS_DIR')
	if env.len > 0 {
		return env
	}
	return '/sys/class/bluetooth'
}

fn bluetooth_main_conf_path() string {
	env := os.getenv('HORNERO_BLUETOOTH_MAIN_CONF')
	if env.len > 0 {
		return env
	}
	return '/etc/bluetooth/main.conf'
}

fn run_probe(prog string, args []string) ExecReport {
	if prog.len == 0 {
		return ExecReport{
			command_line: command_line(prog, args)
			ok:           false
			output:       ''
			exit_code:    127
		}
	}
	return run_exec(ExecSpec{
		prog:        prog
		args:        args
		timeout_sec: 5
	})
}

// bluetooth_probe performs the live, single-shot probes. Missing tools
// degrade to empty/false fields; doctor renders the fixes.
pub fn bluetooth_probe() BluetoothProbe {
	adapters := os.ls(bluetooth_sysfs_dir()) or { []string{} }
	mut service_active := false
	mut service_state := 'unknown'
	sysctl := resolve_systemctl_bin()
	if sysctl.len > 0 {
		rep := run_probe(sysctl, ['is-active', 'bluetooth.service'])
		service_state = rep.output.trim_space()
		service_active = rep.ok && service_state == 'active'
		if service_state.len == 0 {
			service_state = 'unknown'
		}
	}
	mut rfkill := RfkillState{}
	rfkill_bin := resolve_rfkill_bin()
	if rfkill_bin.len > 0 {
		rep := run_probe(rfkill_bin, ['list', 'bluetooth'])
		if rep.ok {
			rfkill = parse_rfkill_bluetooth(rep.output)
		}
	}
	mut version := ''
	mut show := BluetoothShow{}
	btctl := resolve_bluetoothctl_bin()
	if btctl.len > 0 {
		vrep := run_probe(btctl, ['--version'])
		if vrep.ok {
			version = parse_bluetoothctl_version(vrep.output)
		}
		srep := run_probe(btctl, ['show'])
		if srep.ok {
			show = parse_bluetoothctl_show(srep.output)
		}
	}
	mut wp_nodes := []string{}
	wpctl := resolve_wpctl_bin()
	if wpctl.len > 0 {
		rep := run_probe(wpctl, ['status'])
		if rep.ok {
			wp_nodes = parse_wpctl_bluez_nodes(rep.output)
		}
	}
	mut bluez_monitor := false
	pwdump := find_on_path('pw-dump')
	if pwdump.len > 0 {
		rep := run_probe(pwdump, []string{})
		bluez_monitor = rep.ok && rep.output.contains('bluez5')
	}
	mut agent_active := false
	if sysctl.len > 0 {
		rep := run_probe(sysctl, ['--user', 'is-active', 'hornero-bt-agent.service'])
		agent_active = rep.ok && rep.output.trim_space() == 'active'
	}
	mut autoenable_false := false
	conf := os.read_file(bluetooth_main_conf_path()) or { '' }
	for line in conf.split_into_lines() {
		t := line.trim_space().replace(' ', '')
		if t == 'AutoEnable=false' {
			autoenable_false = true
		}
	}
	return BluetoothProbe{
		adapter_present:     adapters.len > 0
		adapters:            adapters
		service_active:      service_active
		service_state:       service_state
		rfkill_present:      rfkill.present
		rfkill_soft:         rfkill.soft_blocked
		rfkill_hard:         rfkill.hard_blocked
		powered:             show.powered
		pairable:            show.pairable
		discoverable:        show.discoverable
		bluez_version:       version
		wp_bluez_nodes:      wp_nodes
		wp_bluez_monitor:    bluez_monitor
		audio_profiles:      bluetooth_audio_profiles(wp_nodes)
		agent_registered:    agent_active
		pipewire_present:    find_on_path('pipewire').len > 0
		wireplumber_present: find_on_path('wireplumber').len > 0
		firmware_missing:    false
		autoenable_false:    autoenable_false
	}
}

pub fn bluetooth_doctor_result() CommandResult {
	return bluetooth_doctor_result_from_probe(bluetooth_probe())
}

pub struct BluetoothStatusOptions {
pub:
	dry_run bool
}

pub fn bluetooth_status_report(opts BluetoothStatusOptions) CommandResult {
	if opts.dry_run {
		return ok_result('bluetooth status', 'would probe: /sys/class/bluetooth, systemctl is-active bluetooth.service, rfkill list bluetooth, bluetoothctl show, wpctl status', {
			'dry_run': 'true'
		})
	}
	probe := bluetooth_probe()
	res := bluetooth_doctor_result_from_probe(probe)
	mut data := res.data.clone()
	data['command'] = 'status'
	return CommandResult{
		command: 'bluetooth status'
		ok:      probe.adapter_present && probe.service_active
		message: res.message.replace('bluetooth doctor:', 'bluetooth status:')
		data:    data
	}
}

pub struct BluetoothDevicesOptions {
pub:
	dry_run bool
}

// parse_bluetooth_devices parses `bluetoothctl devices` lines:
// "Device AA:BB:CC:DD:EE:FF Name".
pub fn parse_bluetooth_devices(output string) []string {
	mut devs := []string{}
	for line in output.split_into_lines() {
		t := line.trim_space()
		if t.starts_with('Device ') {
			devs << t['Device '.len..]
		}
	}
	return devs
}

pub fn bluetooth_devices_report(opts BluetoothDevicesOptions) CommandResult {
	btctl := resolve_bluetoothctl_bin()
	prog := if btctl.len > 0 { btctl } else { 'bluetoothctl' }
	if opts.dry_run {
		return ok_result('bluetooth devices', 'would run: ${command_line(prog, ['devices'])}', {
			'command_line': command_line(prog, ['devices'])
			'dry_run':      'true'
		})
	}
	if btctl.len == 0 {
		return fail_result('bluetooth devices', 'bluetoothctl not found on PATH; fix: install bluez-utils.\nExample: horneroctl hardware bluetooth devices --dry-run')
	}
	rep := run_probe(btctl, ['devices'])
	if !rep.ok {
		return fail_result('bluetooth devices', 'bluetoothctl devices failed (exit ${rep.exit_code}):\n${rep.output}')
	}
	devs := parse_bluetooth_devices(rep.output)
	mut lines := []string{}
	for d in devs {
		lines << 'device: ${d}'
	}
	if lines.len == 0 {
		lines << 'no paired/known Bluetooth devices reported by bluetoothctl'
	}
	return ok_result('bluetooth devices', lines.join('\n'), {
		'devices': devs.join(',')
		'count':   devs.len.str()
	})
}

pub struct BluetoothPowerOptions {
pub:
	action  string // on | off
	dry_run bool
	yes     bool
}

// bluetooth_power_report: off soft-blocks via rfkill only (persisted by
// systemd-rfkill, preserving the user preference); on unblocks and then
// powers the controller. It never touches pairing/trust state.
pub fn bluetooth_power_report(opts BluetoothPowerOptions) CommandResult {
	name := 'bluetooth power ${opts.action}'
	if opts.action !in ['on', 'off'] {
		return fail_result(name, 'unknown power action: ${opts.action}.\nExample: horneroctl hardware bluetooth power on --dry-run')
	}
	if !opts.yes && !opts.dry_run {
		return fail_result(name, 'refusing to change Bluetooth power without --yes (preview with --dry-run).\nExample: horneroctl hardware bluetooth power ${opts.action} --dry-run')
	}
	rfkill_bin := resolve_rfkill_bin()
	prog := if rfkill_bin.len > 0 { rfkill_bin } else { 'rfkill' }
	verb := if opts.action == 'off' { 'block' } else { 'unblock' }
	args := [verb, 'bluetooth']
	if opts.dry_run {
		mut msg := 'would run: ${command_line(prog, args)}'
		if opts.action == 'on' {
			msg += ', then bluetoothctl power on if still unpowered'
		}
		return ok_result(name, msg, {
			'command_line': command_line(prog, args)
			'dry_run':      'true'
			'action':       opts.action
		})
	}
	if rfkill_bin.len == 0 {
		return fail_result(name, 'rfkill not found on PATH.\nExample: horneroctl hardware bluetooth power ${opts.action} --dry-run')
	}
	rep := run_probe(rfkill_bin, args)
	if !rep.ok {
		return fail_result(name, 'rfkill ${verb} bluetooth failed (exit ${rep.exit_code}; an active seat session is required, no sudo/polkit is used):\n${rep.output}')
	}
	if opts.action == 'on' {
		btctl := resolve_bluetoothctl_bin()
		if btctl.len > 0 {
			run_probe(btctl, ['power', 'on'])
		}
	}
	return ok_result(name, 'Bluetooth power ${opts.action} applied via rfkill ${verb}', {
		'command_line': rep.command_line
		'action':       opts.action
	})
}

pub struct BluetoothRestartOptions {
pub:
	dry_run bool
	yes     bool
}

// bluetooth_restart_report restarts bluetooth.service through pkexec when
// available (interactive polkit prompt; never a passwordless rule).
pub fn bluetooth_restart_report(opts BluetoothRestartOptions) CommandResult {
	name := 'bluetooth restart'
	if !opts.yes && !opts.dry_run {
		return fail_result(name, 'refusing to restart bluetooth.service without --yes (preview with --dry-run).\nExample: horneroctl hardware bluetooth restart --dry-run')
	}
	sysctl := resolve_systemctl_bin()
	sysctl_prog := if sysctl.len > 0 { sysctl } else { 'systemctl' }
	pkexec := resolve_pkexec_bin()
	prog := pkexec
	args := [sysctl_prog, 'restart', 'bluetooth.service']
	if opts.dry_run {
		return ok_result(name, 'would run: ${command_line(prog, args)}', {
			'command_line': command_line(prog, args)
			'dry_run':      'true'
		})
	}
	if sysctl.len == 0 {
		return fail_result(name, 'systemctl not found on PATH.\nExample: horneroctl hardware bluetooth restart --dry-run')
	}
	if pkexec.len == 0 {
		return fail_result(name, 'pkexec not found: restarting a system service needs an interactive polkit prompt (never a passwordless rule). Install polkit, or restart manually with: sudo systemctl restart bluetooth.service')
	}
	// The polkit prompt is interactive: the 5s probe timeout would kill
	// it while the user is still typing a password.
	rep := run_exec(ExecSpec{
		prog:        prog
		args:        args
		timeout_sec: 120
	})
	if !rep.ok {
		return fail_result(name, 'restarting bluetooth.service failed (exit ${rep.exit_code}):\n${rep.output}')
	}
	return ok_result(name, 'bluetooth.service restarted', {
		'command_line': rep.command_line
	})
}

// --- Pairing agent bridge -------------------------------------------------
// hornero-bt-agent (BlueZ Agent1, KeyboardDisplay) writes
// request-<id>.json into the agent runtime dir and waits for
// response-<id>.json. The Shell dialog answers through this command;
// the agent defaults to Reject on timeout, so silence never pairs.

pub struct BluetoothAgentRespondOptions {
pub:
	id      string
	action  string // confirm | reject | pin
	pin     string
	dry_run bool
	yes     bool
}

pub fn bluetooth_agent_dir() string {
	env := os.getenv('HORNERO_BLUETOOTH_AGENT_DIR')
	if env.len > 0 {
		return env
	}
	runtime := os.getenv('XDG_RUNTIME_DIR')
	if runtime.len > 0 {
		return os.join_path(runtime, 'hornero', 'bluetooth-agent')
	}
	return os.join_path(os.temp_dir(), 'hornero-bluetooth-agent')
}

fn valid_agent_request_id(id string) bool {
	if id.len < 8 || id.len > 64 {
		return false
	}
	for ch in id {
		if !(ch.is_letter() || ch.is_digit() || ch == u8(`-`) || ch == u8(`_`)) {
			return false
		}
	}
	return true
}

pub fn bluetooth_agent_respond_report(opts BluetoothAgentRespondOptions) CommandResult {
	name := 'bluetooth agent-respond'
	if !valid_agent_request_id(opts.id) {
		return fail_result(name, 'invalid pairing request id.\\nExample: horneroctl hardware bluetooth agent-respond <id> confirm --yes')
	}
	if opts.action !in ['confirm', 'reject', 'pin'] {
		return fail_result(name, 'unknown agent response: ${opts.action}.\\nExample: horneroctl hardware bluetooth agent-respond ${opts.id} confirm --yes')
	}
	if opts.action == 'pin' && (opts.pin.len < 4 || opts.pin.len > 16) {
		return fail_result(name, 'PIN/passkey must be 4-16 characters.\\nExample: horneroctl hardware bluetooth agent-respond ${opts.id} pin 123456 --yes')
	}
	if !opts.yes && !opts.dry_run {
		return fail_result(name, 'refusing to answer a pairing request without --yes (preview with --dry-run)')
	}
	dir := bluetooth_agent_dir()
	request_path := os.join_path(dir, 'request-${opts.id}.json')
	response_path := os.join_path(dir, 'response-${opts.id}.json')
	if opts.dry_run {
		return ok_result(name, 'would write pairing response ${opts.action} for request ${opts.id}', {
			'request_id': opts.id
			'dry_run':    'true'
		})
	}
	if !os.is_file(request_path) {
		return fail_result(name, 'no pending pairing request ${opts.id} (it may have expired; the agent defaults to Reject)')
	}
	payload := if opts.action == 'pin' {
		'{"id":"${opts.id}","action":"pin","pin":"${opts.pin}"}'
	} else {
		'{"id":"${opts.id}","action":"${opts.action}"}'
	}
	tmp_path := '${response_path}.tmp'
	os.write_file(tmp_path, payload) or {
		return fail_result(name, 'could not write pairing response: ${err.msg()}')
	}
	os.mv(tmp_path, response_path) or {
		return fail_result(name, 'could not publish pairing response: ${err.msg()}')
	}
	return ok_result(name, 'pairing response ${opts.action} sent for request ${opts.id}', {
		'request_id': opts.id
		'action':     opts.action
	})
}
