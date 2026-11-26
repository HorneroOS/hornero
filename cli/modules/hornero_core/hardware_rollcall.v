module hornero_core

import json2
import os
import runtime
import strings

// rollcall_categories is the canonical ordered list of hardware diagnostic
// categories inspected by `horneroctl hardware rollcall`.
pub const rollcall_categories = [
	'wifi',
	'bluetooth',
	'audio-output',
	'audio-input',
	'panel',
	'backlight',
	'touchpad',
	'graphics',
	'battery',
	'services',
]

// RollcallOptions configures `hardware_rollcall`.
pub struct RollcallOptions {
pub:
	categories []string
	list_only  bool
	markdown   bool
	json_mode  bool
	root       string
}

// RollcallEntry captures a single category's read-only diagnostic result.
pub struct RollcallEntry {
pub:
	category string
	status   string // ok | warn | missing
	summary  string
	details  []string
}

// RollcallReport is the full redacted hardware rollcall snapshot.
pub struct RollcallReport {
pub:
	kernel  string
	arch    string
	entries []RollcallEntry
}

fn is_hex_char(c u8) bool {
	return (c >= `0` && c <= `9`) || (c >= `a` && c <= `f`) || (c >= `A` && c <= `F`)
}

// redact_macs masks 6-octet MAC addresses (colon or hyphen separated).
fn redact_macs(s string) string {
	if s.len < 17 {
		return s
	}
	mut sb := strings.new_builder(s.len)
	mut i := 0
	for i < s.len {
		if i + 17 <= s.len {
			sep := s[i + 2]
			if (sep == `:` || sep == `-`)
				&& is_hex_char(s[i]) && is_hex_char(s[i + 1])
				&& is_hex_char(s[i + 3]) && is_hex_char(s[i + 4]) && s[i + 5] == sep
				&& is_hex_char(s[i + 6]) && is_hex_char(s[i + 7]) && s[i + 8] == sep
				&& is_hex_char(s[i + 9]) && is_hex_char(s[i + 10]) && s[i + 11] == sep
				&& is_hex_char(s[i + 12]) && is_hex_char(s[i + 13]) && s[i + 14] == sep
				&& is_hex_char(s[i + 15]) && is_hex_char(s[i + 16]) {
				sb.write_string('[redacted-mac]')
				i += 17
				continue
			}
		}
		sb.write_u8(s[i])
		i++
	}
	return sb.str()
}

fn redact_labeled_field(s string, label string, replacement string) string {
	mut out := s
	lower := out.to_lower()
	for sep in [':', '='] {
		needle := label + sep
		mut idx := lower.index(needle) or { -1 }
		if idx < 0 {
			continue
		}
		mut pos := idx + needle.len
		for pos < out.len && (out[pos] == ` ` || out[pos] == `\t`) {
			pos++
		}
		mut end := pos
		for end < out.len && out[end] != `\n` && out[end] != `,` && out[end] != `;` {
			end++
		}
		if end > pos {
			out = out[..pos] + replacement + out[end..]
		}
	}
	return out
}

// redact_rollcall_value strips privacy-sensitive identifiers (MAC addresses,
// SSIDs, serial numbers, hostname, username, and credentials) from rollcall
// output so reports can be safely pasted into public GitHub issues.
pub fn redact_rollcall_value(s string) string {
	if s.len == 0 {
		return s
	}
	mut out := redact_secrets(s)
	out = redact_macs(out)
	out = redact_labeled_field(out, 'ssid', '[redacted-ssid]')
	out = redact_labeled_field(out, 'serial', '[redacted-serial]')
	out = redact_labeled_field(out, 'serial_number', '[redacted-serial]')
	host := os.hostname() or { '' }
	if host.len >= 3 {
		out = out.replace(host, '[redacted-host]')
	}
	for env_key in ['USER', 'LOGNAME'] {
		u := os.getenv(env_key).trim_space()
		if u.len >= 3 {
			out = out.replace(u, '[redacted-user]')
		}
	}
	return out
}

fn rollcall_resolve_root(override string) string {
	if override.len > 0 {
		return override
	}
	env_root := os.getenv('HORNERO_ROLLCALL_ROOT').trim_space()
	if env_root.len > 0 {
		return env_root
	}
	return '/'
}

fn rc_join(root string, rel string) string {
	clean_rel := rel.trim_left('/')
	if root == '/' {
		return '/' + clean_rel
	}
	return os.join_path(root, clean_rel)
}

fn rc_read_trimmed(path string) string {
	raw := os.read_file(path) or { return '' }
	return raw.trim_space()
}

fn rc_uevent_field(path string, key string) string {
	raw := os.read_file(path) or { return '' }
	prefix := key + '='
	for line in raw.split_into_lines() {
		if line.starts_with(prefix) {
			return line[prefix.len..].trim_space()
		}
	}
	return ''
}

fn probe_wifi(root string) RollcallEntry {
	net_dir := rc_join(root, 'sys/class/net')
	entries := os.ls(net_dir) or {
		return RollcallEntry{
			category: 'wifi'
			status:   'missing'
			summary:  'no network sysfs directory'
		}
	}
	mut found := []string{}
	for name in entries {
		iface_dir := os.join_path(net_dir, name)
		has_wireless := os.is_dir(os.join_path(iface_dir, 'wireless'))
			|| os.exists(os.join_path(iface_dir, 'phy80211'))
		if !has_wireless {
			continue
		}
		state := rc_read_trimmed(os.join_path(iface_dir, 'operstate'))
		driver := rc_uevent_field(os.join_path(iface_dir, 'device/uevent'), 'DRIVER')
		mut desc := name
		if driver.len > 0 {
			desc += ' (driver=${driver})'
		}
		if state.len > 0 {
			desc += ' [${state}]'
		}
		found << redact_rollcall_value(desc)
	}
	if found.len == 0 {
		return RollcallEntry{
			category: 'wifi'
			status:   'missing'
			summary:  'no wireless interfaces detected'
		}
	}
	return RollcallEntry{
		category: 'wifi'
		status:   'ok'
		summary:  '${found.len} wireless interface(s) detected'
		details:  found
	}
}

fn probe_bluetooth(root string) RollcallEntry {
	bt_dir := rc_join(root, 'sys/class/bluetooth')
	entries := os.ls(bt_dir) or {
		return RollcallEntry{
			category: 'bluetooth'
			status:   'missing'
			summary:  'no bluetooth adapters detected'
		}
	}
	mut adapters := []string{}
	for name in entries {
		if !name.starts_with('hci') {
			continue
		}
		hci_dir := os.join_path(bt_dir, name)
		btype := rc_read_trimmed(os.join_path(hci_dir, 'type'))
		driver := rc_uevent_field(os.join_path(hci_dir, 'device/uevent'), 'DRIVER')
		mut desc := name
		if btype.len > 0 {
			desc += ' (${btype})'
		}
		if driver.len > 0 {
			desc += ' driver=${driver}'
		}
		adapters << redact_rollcall_value(desc)
	}
	if adapters.len == 0 {
		return RollcallEntry{
			category: 'bluetooth'
			status:   'missing'
			summary:  'no bluetooth hci adapters detected'
		}
	}
	return RollcallEntry{
		category: 'bluetooth'
		status:   'ok'
		summary:  '${adapters.len} bluetooth adapter(s) detected'
		details:  adapters
	}
}

fn probe_audio(root string, category string, direction string) RollcallEntry {
	asound_dir := rc_join(root, 'proc/asound')
	entries := os.ls(asound_dir) or {
		return RollcallEntry{
			category: category
			status:   'missing'
			summary:  'no ALSA sound cards detected'
		}
	}
	mut devices := []string{}
	for name in entries {
		if !name.starts_with('card') || name == 'cards' {
			continue
		}
		card_dir := os.join_path(asound_dir, name)
		if !os.is_dir(card_dir) {
			continue
		}
		card_id := rc_read_trimmed(os.join_path(card_dir, 'id'))
		pcm_entries := os.ls(card_dir) or { []string{} }
		for pcm in pcm_entries {
			if !pcm.starts_with('pcm') {
				continue
			}
			matches := if direction == 'playback' { pcm.ends_with('p') } else { pcm.ends_with('c') }
			if !matches {
				continue
			}
			label := if card_id.len > 0 { '${name} (${card_id}) ${pcm}' } else { '${name} ${pcm}' }
			devices << redact_rollcall_value(label)
		}
	}
	if devices.len == 0 {
		return RollcallEntry{
			category: category
			status:   'missing'
			summary:  'no ${direction} audio devices detected'
		}
	}
	return RollcallEntry{
		category: category
		status:   'ok'
		summary:  '${devices.len} ${direction} device(s) detected'
		details:  devices
	}
}

fn probe_panel(root string) RollcallEntry {
	drm_dir := rc_join(root, 'sys/class/drm')
	entries := os.ls(drm_dir) or {
		return RollcallEntry{
			category: 'panel'
			status:   'missing'
			summary:  'no DRM display connectors detected'
		}
	}
	mut connected := []string{}
	for name in entries {
		if !name.contains('-') {
			continue
		}
		conn_dir := os.join_path(drm_dir, name)
		status := rc_read_trimmed(os.join_path(conn_dir, 'status'))
		if status != 'connected' {
			continue
		}
		modes_raw := rc_read_trimmed(os.join_path(conn_dir, 'modes'))
		mode_line := if modes_raw.len > 0 {
			modes_raw.split_into_lines()[0]
		} else {
			'unknown-mode'
		}
		connected << redact_rollcall_value('${name} (${mode_line})')
	}
	if connected.len == 0 {
		return RollcallEntry{
			category: 'panel'
			status:   'warn'
			summary:  'no connected display panels detected'
		}
	}
	return RollcallEntry{
		category: 'panel'
		status:   'ok'
		summary:  '${connected.len} connected display(s)'
		details:  connected
	}
}

fn probe_backlight(root string) RollcallEntry {
	bl_dir := rc_join(root, 'sys/class/backlight')
	entries := os.ls(bl_dir) or {
		return RollcallEntry{
			category: 'backlight'
			status:   'missing'
			summary:  'no backlight devices detected'
		}
	}
	mut items := []string{}
	for name in entries {
		dev_dir := os.join_path(bl_dir, name)
		cur := rc_read_trimmed(os.join_path(dev_dir, 'brightness'))
		max := rc_read_trimmed(os.join_path(dev_dir, 'max_brightness'))
		if cur.len > 0 && max.len > 0 {
			items << redact_rollcall_value('${name} (${cur}/${max})')
		} else {
			items << redact_rollcall_value(name)
		}
	}
	if items.len == 0 {
		return RollcallEntry{
			category: 'backlight'
			status:   'missing'
			summary:  'no backlight devices detected'
		}
	}
	return RollcallEntry{
		category: 'backlight'
		status:   'ok'
		summary:  '${items.len} backlight device(s) detected'
		details:  items
	}
}

fn probe_touchpad(root string) RollcallEntry {
	input_dir := rc_join(root, 'sys/class/input')
	entries := os.ls(input_dir) or {
		return RollcallEntry{
			category: 'touchpad'
			status:   'missing'
			summary:  'no input sysfs directory'
		}
	}
	mut pads := []string{}
	for name in entries {
		if !name.starts_with('input') {
			continue
		}
		dev_name := rc_read_trimmed(os.join_path(input_dir, name, 'name'))
		low := dev_name.to_lower()
		if low.contains('touchpad') || low.contains('trackpad') || low.contains('synaptics')
			|| low.contains('elan') {
			pads << redact_rollcall_value('${name}: ${dev_name}')
		}
	}
	if pads.len == 0 {
		return RollcallEntry{
			category: 'touchpad'
			status:   'missing'
			summary:  'no touchpad detected'
		}
	}
	return RollcallEntry{
		category: 'touchpad'
		status:   'ok'
		summary:  '${pads.len} touchpad(s) detected'
		details:  pads
	}
}

fn probe_graphics(root string) RollcallEntry {
	drm_dir := rc_join(root, 'sys/class/drm')
	entries := os.ls(drm_dir) or {
		return RollcallEntry{
			category: 'graphics'
			status:   'missing'
			summary:  'no DRM graphics cards detected'
		}
	}
	mut gpus := []string{}
	for name in entries {
		if !name.starts_with('card') || name.contains('-') {
			continue
		}
		uevent := os.join_path(drm_dir, name, 'device/uevent')
		driver := rc_uevent_field(uevent, 'DRIVER')
		pci_id := rc_uevent_field(uevent, 'PCI_ID')
		mut desc := name
		if driver.len > 0 {
			desc += ' driver=${driver}'
		}
		if pci_id.len > 0 {
			desc += ' pci=${pci_id}'
		}
		gpus << redact_rollcall_value(desc)
	}
	if gpus.len == 0 {
		return RollcallEntry{
			category: 'graphics'
			status:   'missing'
			summary:  'no DRM graphics cards detected'
		}
	}
	return RollcallEntry{
		category: 'graphics'
		status:   'ok'
		summary:  '${gpus.len} graphics adapter(s) detected'
		details:  gpus
	}
}

fn probe_battery(root string) RollcallEntry {
	ps_dir := rc_join(root, 'sys/class/power_supply')
	entries := os.ls(ps_dir) or {
		return RollcallEntry{
			category: 'battery'
			status:   'missing'
			summary:  'no power_supply sysfs directory'
		}
	}
	mut bats := []string{}
	for name in entries {
		if !name.starts_with('BAT') {
			continue
		}
		bat_dir := os.join_path(ps_dir, name)
		status := rc_read_trimmed(os.join_path(bat_dir, 'status'))
		cap := rc_read_trimmed(os.join_path(bat_dir, 'capacity'))
		mut desc := name
		if cap.len > 0 {
			desc += ' ${cap}%'
		}
		if status.len > 0 {
			desc += ' (${status})'
		}
		bats << redact_rollcall_value(desc)
	}
	if bats.len == 0 {
		return RollcallEntry{
			category: 'battery'
			status:   'missing'
			summary:  'no battery detected'
		}
	}
	return RollcallEntry{
		category: 'battery'
		status:   'ok'
		summary:  '${bats.len} battery device(s) detected'
		details:  bats
	}
}

fn probe_services(root string) RollcallEntry {
	systemd_dir := rc_join(root, 'run/systemd/system')
	if !os.is_dir(systemd_dir) {
		return RollcallEntry{
			category: 'services'
			status:   'warn'
			summary:  'systemd runtime directory not present'
		}
	}
	return RollcallEntry{
		category: 'services'
		status:   'ok'
		summary:  'systemd runtime active'
		details:  ['systemd: active']
	}
}

fn probe_category(root string, category string) RollcallEntry {
	return match category {
		'wifi' {
			probe_wifi(root)
		}
		'bluetooth' {
			probe_bluetooth(root)
		}
		'audio-output' {
			probe_audio(root, 'audio-output', 'playback')
		}
		'audio-input' {
			probe_audio(root, 'audio-input', 'capture')
		}
		'panel' {
			probe_panel(root)
		}
		'backlight' {
			probe_backlight(root)
		}
		'touchpad' {
			probe_touchpad(root)
		}
		'graphics' {
			probe_graphics(root)
		}
		'battery' {
			probe_battery(root)
		}
		'services' {
			probe_services(root)
		}
		else {
			RollcallEntry{
				category: category
				status:   'missing'
				summary:  'unknown category'
			}
		}
	}
}

// hardware_rollcall runs a read-only, rootless, privacy-safe hardware
// diagnostic across the requested categories (or all categories if empty).
pub fn hardware_rollcall(opts RollcallOptions) RollcallReport {
	root := rollcall_resolve_root(opts.root)
	cats := if opts.categories.len > 0 { opts.categories } else { rollcall_categories }
	mut entries := []RollcallEntry{}
	for c in cats {
		entries << probe_category(root, c)
	}
	kernel_raw := rc_read_trimmed(rc_join(root, 'proc/sys/kernel/osrelease'))
	kernel := if kernel_raw.len > 0 { redact_rollcall_value(kernel_raw) } else { 'unknown' }
	return RollcallReport{
		kernel:  kernel
		arch:    runtime.nr_cpus().str() + ' cpus'
		entries: entries
	}
}

// format_rollcall_markdown renders a redacted GitHub issue snippet.
pub fn format_rollcall_markdown(report RollcallReport) string {
	mut sb := strings.new_builder(512)
	sb.write_string('## Hardware Rollcall (Redacted)\n\n')
	sb.write_string('- **Kernel**: `${report.kernel}`\n')
	sb.write_string('- **CPUs**: `${report.arch}`\n\n')
	sb.write_string('| Category | Status | Summary |\n')
	sb.write_string('| --- | --- | --- |\n')
	for e in report.entries {
		sb.write_string('| `${e.category}` | `${e.status}` | ${e.summary} |\n')
	}
	sb.write_string('\n<details>\n<summary>Details</summary>\n\n```text\n')
	for e in report.entries {
		sb.write_string('[${e.category}] ${e.status}: ${e.summary}\n')
		for d in e.details {
			sb.write_string('  - ${d}\n')
		}
	}
	sb.write_string('```\n</details>\n')
	return sb.str()
}

// format_rollcall_json renders the report as compact JSON.
pub fn format_rollcall_json(report RollcallReport) string {
	return json2.encode(report)
}

// hardware_rollcall_result executes rollcall and wraps it in a CommandResult.
pub fn hardware_rollcall_result(opts RollcallOptions) CommandResult {
	if opts.list_only {
		mut data := map[string]string{}
		data['categories'] = rollcall_categories.join(',')
		return ok_result('hardware rollcall', rollcall_categories.join('\n'), data)
	}
	report := hardware_rollcall(opts)
	mut data := map[string]string{}
	data['kernel'] = report.kernel
	data['count'] = report.entries.len.str()
	for e in report.entries {
		data[e.category] = '${e.status}: ${e.summary}'
	}
	if opts.markdown {
		md := format_rollcall_markdown(report)
		data['markdown'] = md
		return ok_result('hardware rollcall', md, data)
	}
	if opts.json_mode {
		js := format_rollcall_json(report)
		data['json'] = js
		return ok_result('hardware rollcall', js, data)
	}
	mut lines := []string{}
	for e in report.entries {
		lines << '${e.category}: [${e.status}] ${e.summary}'
	}
	return ok_result('hardware rollcall', lines.join('\n'), data)
}
