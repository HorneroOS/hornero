module hornero_core

import os
import x.json2

// Studio selection state and read-only diagnostics (HorneroOS/hornero#286).
// The canonical specialization/application model lives in
// editions/catalogue.yaml; this module validates stable IDs only and never
// duplicates package lists. Applying a selection to packages is a separate,
// later lifecycle: `studio selection set` records user intent atomically,
// and `studio doctor` reports health without changing anything.

pub const studio_schema_version = 1

pub const studio_specialization_ids = [
	'audio-music-production',
	'video-editing-post-production',
	'streaming-content-creation',
	'graphic-design-illustration',
	'photography-raw-processing',
	'3d-animation-vfx',
	'game-development',
	'maker-cad',
	'complete-creative-workstation',
	'custom-selection',
]

pub const studio_application_ids = [
	'ardour',
	'guitarix',
	'carla',
	'audacity',
	'reaper',
	'yabridge',
	'obs-studio',
	'kdenlive',
	'blender',
	'krita',
	'gimp',
	'inkscape',
	'darktable',
	'rawtherapee',
	'graphite',
	'penpot',
	'scribus',
	'freecad',
	'godot',
]

// Proprietary or reference-only applications that a specialization must
// never pull in silently; they need an explicit application selection.
pub const studio_opt_in_application_ids = ['reaper', 'penpot']

pub struct StudioSelection {
pub:
	schema_version  int
	specializations []string
	applications    []string
}

pub fn studio_selection_file() string {
	override := os.getenv('HORNERO_STUDIO_SELECTION_FILE')
	if override.len > 0 {
		return override
	}
	p := resolve_paths()
	return os.join_path(p.config_dir, 'hornero', 'studio-selection.json')
}

fn studio_string_list(value json2.Any, key string) ![]string {
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

pub fn studio_validate_selection(sel StudioSelection) ! {
	if sel.schema_version != studio_schema_version {
		return error('unsupported studio selection schemaVersion ${sel.schema_version} (expected ${studio_schema_version})')
	}
	for id in sel.specializations {
		if id !in studio_specialization_ids {
			return error('unknown studio specialization ${id}')
		}
	}
	for id in sel.applications {
		if id !in studio_application_ids {
			return error('unknown studio application ${id}')
		}
	}
}

// parse_studio_selection decodes the canonical selection file. It fails
// closed: malformed JSON, unknown IDs, or a wrong schema never produce a
// partial selection.
pub fn parse_studio_selection(raw string) !StudioSelection {
	decoded := json2.decode[json2.Any](raw) or { return error('invalid JSON: ${err.msg()}') }
	if decoded !is map[string]json2.Any {
		return error('studio selection must be a JSON object')
	}
	root := decoded.as_map()
	version_any := root['schemaVersion'] or { return error('studio selection needs schemaVersion') }
	version := version_any.i64()
	if version_any !is i64 && version_any !is int && version_any !is f64 {
		return error('schemaVersion must be an integer')
	}
	if f64(version) != version_any.f64() {
		return error('schemaVersion must be an integer')
	}
	specializations := studio_string_list(root['specializations'] or {
		return error('studio selection needs specializations')
	}, 'specializations')!
	applications := studio_string_list(root['applications'] or {
		return error('studio selection needs applications')
	}, 'applications')!
	sel := StudioSelection{
		schema_version:  int(version)
		specializations: specializations
		applications:    applications
	}
	studio_validate_selection(sel)!
	return sel
}

pub fn studio_encode_selection(sel StudioSelection) string {
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

// load_studio_selection returns (selection, present). A missing file is a
// valid "nothing selected" state; a present but invalid file is an error.
pub fn load_studio_selection() !(StudioSelection, bool) {
	path := studio_selection_file()
	if !os.is_file(path) {
		return StudioSelection{
			schema_version: studio_schema_version
		}, false
	}
	raw := os.read_file(path) or { return error('cannot read ${path}: ${err.msg()}') }
	sel := parse_studio_selection(raw) or {
		return error('invalid studio selection at ${path}: ${err.msg()}')
	}
	return sel, true
}

// write_studio_selection stores the selection atomically (temp + rename),
// creating the config directory as needed.
pub fn write_studio_selection(sel StudioSelection) !string {
	studio_validate_selection(sel)!
	path := studio_selection_file()
	dir := os.dir(path)
	os.mkdir_all(dir) or { return error('cannot create ${dir}: ${err.msg()}') }
	tmp := os.join_path(dir, '.studio-selection.json.tmp')
	os.write_file(tmp, studio_encode_selection(sel)) or {
		return error('cannot write ${tmp}: ${err.msg()}')
	}
	os.mv(tmp, path) or { return error('cannot move ${tmp} to ${path}: ${err.msg()}') }
	return path
}

fn studio_selection_data(sel StudioSelection, present bool, path string) map[string]string {
	return {
		'state':           if present { 'recorded' } else { 'not-selected' }
		'file':            path
		'schema_version':  '${sel.schema_version}'
		'specializations': sel.specializations.join(',')
		'applications':    sel.applications.join(',')
		'package_apply':   'not-executed'
	}
}

pub fn studio_selection_result() CommandResult {
	sel, present := load_studio_selection() or {
		return fail_result('studio selection', err.msg())
	}
	path := studio_selection_file()
	if !present {
		return ok_result('studio selection',
			'No Studio selection recorded at ${path}. Use horneroctl studio selection set --specialization <id> [--application <id>] to record one; nothing is installed by recording a selection.',
			studio_selection_data(sel, present, path))
	}
	return ok_result('studio selection',
		'Studio selection recorded at ${path}: specializations=${sel.specializations.join(', ')} applications=${sel.applications.join(', ')} (package apply not executed).',
		studio_selection_data(sel, present, path))
}

pub fn studio_selection_set_result(specializations []string, applications []string, dry_run bool) CommandResult {
	sel := StudioSelection{
		schema_version:  studio_schema_version
		specializations: specializations
		applications:    applications
	}
	studio_validate_selection(sel) or { return fail_result('studio selection set', err.msg()) }
	if dry_run {
		return ok_result('studio selection set',
			'Dry run: would record specializations=${specializations.join(', ')} applications=${applications.join(', ')} at ${studio_selection_file()}; nothing written, no packages installed.',
			studio_selection_data(sel, false, studio_selection_file()))
	}
	path := write_studio_selection(sel) or { return fail_result('studio selection set', err.msg()) }
	return ok_result('studio selection set',
		'Recorded Studio selection at ${path}: specializations=${specializations.join(', ')} applications=${applications.join(', ')}. Package installation is not executed by this command.',
		studio_selection_data(sel, true, path))
}

// studio_doctor_checks is read-only: selection validity, PipeWire stack
// presence, and the safe Balanced audio default. It never writes state,
// never probes hardware it cannot see, and never claims measured latency.
pub fn studio_doctor_checks() []DoctorCheck {
	mut checks := []DoctorCheck{}
	sel, present := load_studio_selection() or {
		checks << DoctorCheck{
			name:   'studio-selection'
			ok:     false
			detail: 'invalid selection state: ${err.msg()}'
		}
		return checks
	}
	checks << DoctorCheck{
		name:   'studio-selection'
		ok:     true
		detail: if present {
			'recorded: ${sel.specializations.len} specialization(s), ${sel.applications.len} application(s)'
		} else {
			'no selection recorded (Balanced defaults apply)'
		}
	}
	checks << bin_check('pipewire', 'pipewire')
	checks << bin_check('wireplumber', 'wireplumber')
	checks << DoctorCheck{
		name:   'studio-audio-mode'
		ok:     true
		detail: 'Balanced (device default rate/quantum; Low Latency and Advanced are explicit opt-ins)'
	}
	checks << DoctorCheck{
		name:   'studio-package-apply'
		ok:     true
		detail: 'not executed by horneroctl studio yet; selections are recorded intent only'
	}
	return checks
}

pub fn studio_doctor_result() CommandResult {
	checks := studio_doctor_checks()
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
		lines << 'studio doctor: all ${checks.len} checks passed'
	} else {
		lines << 'studio doctor: ${failed}/${checks.len} checks failed'
	}
	return CommandResult{
		command: 'studio doctor'
		ok:      failed == 0
		message: lines.join('\n')
		data:    data
	}
}
