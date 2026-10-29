module hornero_core

import os
import x.json2

// Gaming selection state and read-only diagnostics (HorneroOS/hornero#328).
// The canonical specialization/application model lives in
// editions/catalogue.yaml; this module validates stable IDs only and never
// duplicates package lists. `gaming doctor` reports readiness and
// capability only: it never claims game compatibility, hardware
// qualification, measured performance, or latency, and it never changes
// anything. GPU driver stacks are a hardware decision made by the
// installer and first-boot diagnostics, not by this module.

pub const gaming_schema_version = 1

pub const gaming_specialization_ids = [
	'desktop-gaming',
	'handheld',
	'streaming',
	'multi-launcher',
	'vr',
	'advanced-compat',
]

pub const gaming_application_ids = [
	'steam',
	'lutris',
	'bottles',
	'wine',
	'vkbasalt',
	'obs-studio',
	'heroic-games-launcher',
	'steamvr',
]

// Proprietary or reference-only applications that a specialization must
// never pull in silently; they need an explicit application selection.
pub const gaming_opt_in_application_ids = ['steam', 'heroic-games-launcher', 'steamvr']

pub struct GamingSelection {
pub:
	schema_version  int
	specializations []string
	applications    []string
}

pub fn gaming_selection_file() string {
	override := os.getenv('HORNERO_GAMING_SELECTION_FILE')
	if override.len > 0 {
		return override
	}
	p := resolve_paths()
	return os.join_path(p.config_dir, 'hornero', 'gaming-selection.json')
}

fn gaming_string_list(value json2.Any, key string) ![]string {
	if value !is []json2.Any {
		return error('${key} must be an array of strings')
	}
	mut items := []string{}
	for item in value.as_array() {
		if item !is string {
			return error('${key} must be an array of strings')
		}
		text := item.str().trim_space()
		if text.len == 0 {
			return error('${key} must not contain empty ids')
		}
		if text in items {
			return error('${key} contains duplicate id ${text}')
		}
		items << text
	}
	return items
}

pub fn gaming_validate_selection(sel GamingSelection) ! {
	if sel.schema_version != gaming_schema_version {
		return error('unsupported gaming selection schemaVersion ${sel.schema_version} (expected ${gaming_schema_version})')
	}
	for id in sel.specializations {
		if id !in gaming_specialization_ids {
			return error('unknown gaming specialization ${id}')
		}
	}
	for id in sel.applications {
		if id !in gaming_application_ids {
			return error('unknown gaming application ${id}')
		}
	}
}

// parse_gaming_selection decodes the canonical selection file. It fails
// closed: malformed JSON, unknown IDs, or a wrong schema never produce a
// partial selection.
pub fn parse_gaming_selection(raw string) !GamingSelection {
	decoded := json2.decode[json2.Any](raw) or { return error('invalid JSON: ${err.msg()}') }
	if decoded !is map[string]json2.Any {
		return error('gaming selection must be a JSON object')
	}
	root := decoded.as_map()
	version_any := root['schemaVersion'] or { return error('gaming selection needs schemaVersion') }
	version := version_any.i64()
	if version_any !is i64 && version_any !is int && version_any !is f64 {
		return error('schemaVersion must be an integer')
	}
	if f64(version) != version_any.f64() {
		return error('schemaVersion must be an integer')
	}
	specializations := gaming_string_list(root['specializations'] or {
		return error('gaming selection needs specializations')
	}, 'specializations')!
	applications := gaming_string_list(root['applications'] or {
		return error('gaming selection needs applications')
	}, 'applications')!
	sel := GamingSelection{
		schema_version:  int(version)
		specializations: specializations
		applications:    applications
	}
	gaming_validate_selection(sel)!
	return sel
}

pub fn gaming_encode_selection(sel GamingSelection) string {
	spec_json := sel.specializations.map('"${it}"').join(', ')
	app_json := sel.applications.map('"${it}"').join(', ')
	lines := [
		'{',
		'  "schemaVersion": ${sel.schema_version},',
		'  "specializations": [${spec_json}],',
		'  "applications": [${app_json}]',
		'}',
	]
	return lines.join('\n') + '\n'
}

// load_gaming_selection returns (selection, present). A missing file is a
// valid "nothing selected" state; a present but invalid file is an error.
pub fn load_gaming_selection() !(GamingSelection, bool) {
	path := gaming_selection_file()
	if !os.is_file(path) {
		return GamingSelection{
			schema_version: gaming_schema_version
		}, false
	}
	raw := os.read_file(path) or { return error('cannot read gaming selection: ${err.msg()}') }
	sel := parse_gaming_selection(raw)!
	return sel, true
}

fn file_check(name string, path string, present_detail string) DoctorCheck {
	if os.is_file(path) {
		return DoctorCheck{
			name:   name
			ok:     true
			detail: present_detail
		}
	}
	return DoctorCheck{
		name:   name
		ok:     false
		detail: '${path} not found'
	}
}

// gaming_selection_state never fails: it returns the selection, whether
// a file was present, and the load error (empty when readable). Doctor
// uses it so one broken state file cannot hide independent checks.
fn gaming_selection_state() (GamingSelection, bool, string) {
	sel, present := load_gaming_selection() or {
		return GamingSelection{
			schema_version: gaming_schema_version
		}, false, err.msg()
	}
	return sel, present, ''
}

// gaming_doctor_checks is read-only. Platform probes report whether the
// hardware-neutral Gaming platform is usable; application probes (Steam)
// report capability only. A missing controller never fails Desktop
// Gaming readiness; it is reported as an observation because only the
// Handheld specialization requires one, on qualified hardware.
pub fn gaming_doctor_checks() []DoctorCheck {
	mut checks := []DoctorCheck{}
	// An invalid selection fails its own check but never hides the
	// independent capability checks below: diagnostics matter most
	// precisely when state is broken. Without a readable selection,
	// Steam is treated as not selected (informational only).
	sel, present, load_error := gaming_selection_state()
	if load_error.len > 0 {
		checks << DoctorCheck{
			name:   'gaming-selection'
			ok:     false
			detail: 'invalid selection state: ${load_error}'
		}
	} else {
		checks << DoctorCheck{
			name:   'gaming-selection'
			ok:     true
			detail: if present {
				'recorded: ${sel.specializations.len} specialization(s), ${sel.applications.len} application(s)'
			} else {
				'no selection recorded (Gaming is planned; nothing is installed by default)'
			}
		}
	}
	checks << bin_check('vulkan-tools', 'vulkaninfo')
	icd_dir := '/usr/share/vulkan/icd.d'
	icd_entries := os.ls(icd_dir) or { []string{} }
	checks << DoctorCheck{
		name:   'vulkan-icd'
		ok:     icd_entries.len > 0
		detail: if icd_entries.len > 0 {
			'${icd_entries.len} Vulkan ICD(s) registered in ${icd_dir} (registration is not hardware qualification)'
		} else {
			'no Vulkan ICD registered in ${icd_dir}'
		}
	}
	checks << file_check('vulkan-32bit-loader', '/usr/lib32/libvulkan.so.1',
		'32-bit Vulkan loader present (driver qualification is a hardware decision, not checked here)')
	// Steam is proprietary opt-in: missing Steam only fails readiness
	// when the recorded selection actually selected it.
	mut steam_check := bin_check('steam', 'steam')
	if !steam_check.ok && 'steam' !in sel.applications {
		steam_check = DoctorCheck{
			name:   steam_check.name
			ok:     true
			detail: 'not selected (explicit opt-in only); ${steam_check.detail}'
		}
	}
	checks << steam_check
	checks << bin_check('gamemode', 'gamemoderun')
	checks << bin_check('gamescope', 'gamescope')
	checks << bin_check('mangohud', 'mangohud')
	checks << bin_check('pipewire', 'pipewire')
	checks << bin_check('wireplumber', 'wireplumber')
	portal := '/usr/lib/xdg-desktop-portal'
	checks << file_check('xdg-desktop-portal', portal, portal)
	mut controllers := 0
	for entry in os.ls('/dev/input') or { []string{} } {
		if entry.starts_with('js') {
			controllers++
		}
	}
	checks << DoctorCheck{
		name:   'controllers'
		ok:     true
		detail: if controllers > 0 {
			'${controllers} controller device(s) visible in /dev/input (detection is not Handheld qualification)'
		} else {
			'no controller detected (optional for Desktop Gaming; required only by the Handheld specialization on qualified hardware)'
		}
	}
	// Recovery readiness is probed, never asserted: a fallback kernel
	// image or a snapshot tool must actually be present.
	lts_kernel := os.is_file('/boot/vmlinuz-linux-lts') || os.is_file('/boot/vmlinuz-linux-lts-fallback')
	snapshot_tool := bin_check('snapper', 'snapper').ok || bin_check('timeshift', 'timeshift').ok
	checks << DoctorCheck{
		name:   'recovery-readiness'
		ok:     lts_kernel || snapshot_tool
		detail: if lts_kernel {
			'LTS fallback kernel present in /boot; graphics recovery uses the system update/snapshot path and gaming doctor changes nothing'
		} else if snapshot_tool {
			'snapshot tool present; graphics recovery uses the system update/snapshot path and gaming doctor changes nothing'
		} else {
			'no LTS fallback kernel or snapshot tool detected; install linux-lts or configure snapshots before graphics-sensitive updates'
		}
	}
	return checks
}

pub fn gaming_doctor_result() CommandResult {
	checks := gaming_doctor_checks()
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
		lines << 'gaming doctor: all ${checks.len} checks passed'
	} else {
		lines << 'gaming doctor: ${failed}/${checks.len} checks failed'
	}
	return CommandResult{
		command: 'gaming doctor'
		ok:      failed == 0
		message: lines.join('\n')
		data:    data
	}
}
