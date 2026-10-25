module hornero_core

import os
import time
import x.json2

// Studio mode lifecycle (HorneroOS/hornero#286, consuming the mode
// contract of HorneroOS/hornero#287 in editions/catalogue.yaml).
// Audio mode is recorded user intent here; the PipeWire drop-in values
// are owned by HorneroOS/config (desktop/studio-audio) and activated by
// the user, so this module never writes PipeWire configuration, never
// restarts services, and never presents quantum as physical latency.
// Temporary Performance is the one live switch: it goes through
// power-profiles-daemon (powerprofilesctl fixed argv), records the
// exact previous profile, and restores it on demand. A mode never
// forces an RT kernel, IRQ tuning, CPU governor, GPU, I/O scheduler,
// or privilege-policy change.

pub const studio_audio_mode_ids = ['balanced', 'low-latency', 'advanced']

pub const studio_audio_opt_in_ids = ['low-latency', 'advanced']

pub struct StudioModeState {
pub mut:
	audio_mode           string = 'balanced'
	previous_audio_mode  string
	performance_active   bool
	performance_previous string
	performance_started  i64
	performance_timeout  i64
	updated_unix         i64
}

pub fn studio_mode_file() string {
	override := os.getenv('HORNERO_STUDIO_MODE_FILE')
	if override.len > 0 {
		return override
	}
	p := resolve_paths()
	return os.join_path(p.config_dir, 'hornero', 'studio-mode.json')
}

fn studio_mode_string(root map[string]json2.Any, key string, fallback string) !string {
	v := root[key] or { return fallback }
	if v !is string {
		return error('${key} must be a string')
	}
	return v.str().trim_space()
}

fn studio_mode_bool(root map[string]json2.Any, key string) !bool {
	v := root[key] or { return false }
	if v !is bool {
		return error('${key} must be a boolean')
	}
	return v.bool()
}

fn studio_mode_i64(root map[string]json2.Any, key string) !i64 {
	v := root[key] or { return i64(0) }
	if v is i64 {
		return v.i64()
	}
	if v is f64 {
		f := v.f64()
		if f64(i64(f)) != f {
			return error('${key} must be an integer')
		}
		return i64(f)
	}
	return error('${key} must be an integer')
}

// parse_studio_mode fails closed like parse_studio_selection: malformed
// JSON, wrong schema, or unknown mode IDs never yield a partial state.
pub fn parse_studio_mode(raw string) !StudioModeState {
	decoded := json2.decode[json2.Any](raw) or { return error('invalid JSON: ${err.msg()}') }
	if decoded !is map[string]json2.Any {
		return error('studio mode state must be a JSON object')
	}
	root := decoded.as_map()
	version_any := root['schemaVersion'] or { return error('studio mode state needs schemaVersion') }
	if version_any !is i64 && version_any !is int && version_any !is f64 {
		return error('schemaVersion must be an integer')
	}
	if f64(version_any.i64()) != version_any.f64() {
		return error('schemaVersion must be an integer')
	}
	if int(version_any.i64()) != studio_schema_version {
		return error('unsupported studio mode schemaVersion ${version_any.i64()} (expected ${studio_schema_version})')
	}
	audio := studio_mode_string(root, 'audioMode', 'balanced')!
	if audio !in studio_audio_mode_ids {
		return error('unknown studio audio mode ${audio}')
	}
	previous := studio_mode_string(root, 'previousAudioMode', '')!
	if previous.len > 0 && previous !in studio_audio_mode_ids {
		return error('unknown previous studio audio mode ${previous}')
	}
	return StudioModeState{
		audio_mode:           audio
		previous_audio_mode:  previous
		performance_active:   studio_mode_bool(root, 'performanceActive')!
		performance_previous: studio_mode_string(root, 'performancePrevious', '')!
		performance_started:  studio_mode_i64(root, 'performanceStartedUnix')!
		performance_timeout:  studio_mode_i64(root, 'performanceTimeoutUnix')!
		updated_unix:         studio_mode_i64(root, 'updatedUnix')!
	}
}

pub fn studio_encode_mode(st StudioModeState) string {
	lines := [
		'{',
		'  "schemaVersion": ${studio_schema_version},',
		'  "audioMode": "${st.audio_mode}",',
		'  "previousAudioMode": "${st.previous_audio_mode}",',
		'  "performanceActive": ${st.performance_active},',
		'  "performancePrevious": "${st.performance_previous}",',
		'  "performanceStartedUnix": ${st.performance_started},',
		'  "performanceTimeoutUnix": ${st.performance_timeout},',
		'  "updatedUnix": ${st.updated_unix}',
		'}',
	]
	return lines.join('\n') + '\n'
}

// load_studio_mode returns (state, present). Missing file means the
// Balanced defaults; a present but invalid file is an error.
pub fn load_studio_mode() !(StudioModeState, bool) {
	path := studio_mode_file()
	if !os.is_file(path) {
		return StudioModeState{}, false
	}
	raw := os.read_file(path) or { return error('cannot read ${path}: ${err.msg()}') }
	st := parse_studio_mode(raw) or {
		return error('invalid studio mode state at ${path}: ${err.msg()}')
	}
	return st, true
}

pub fn write_studio_mode(mut st StudioModeState) !string {
	if st.audio_mode !in studio_audio_mode_ids {
		return error('unknown studio audio mode ${st.audio_mode}')
	}
	st.updated_unix = time.now().unix()
	path := studio_mode_file()
	dir := os.dir(path)
	os.mkdir_all(dir) or { return error('cannot create ${dir}: ${err.msg()}') }
	tmp := os.join_path(dir, '.studio-mode.json.tmp')
	os.write_file(tmp, studio_encode_mode(st)) or {
		return error('cannot write ${tmp}: ${err.msg()}')
	}
	os.mv(tmp, path) or { return error('cannot move ${tmp} to ${path}: ${err.msg()}') }
	return path
}

fn studio_mode_data(st StudioModeState, present bool) map[string]string {
	return {
		'state':                if present { 'recorded' } else { 'default' }
		'file':                 studio_mode_file()
		'audio_mode':           st.audio_mode
		'previous_audio_mode':  st.previous_audio_mode
		'performance_active':   '${st.performance_active}'
		'performance_previous': st.performance_previous
		'quantum_semantics':    'scheduling period, not physical round-trip latency'
	}
}

pub fn studio_mode_show_result() CommandResult {
	st, present := load_studio_mode() or { return fail_result('studio mode', err.msg()) }
	mut msg := 'Studio audio mode: ${st.audio_mode}'
	if st.previous_audio_mode.len > 0 {
		msg += ' (previous: ${st.previous_audio_mode}, restorable with: horneroctl studio mode restore)'
	}
	if st.performance_active {
		msg += '\nTemporary Performance: active since unix ${st.performance_started} (previous profile: ${st.performance_previous}); restore with: horneroctl studio mode restore'
	} else {
		msg += '\nTemporary Performance: inactive'
	}
	msg += '\nQuantum is a scheduling period, not physical round-trip latency.'
	return ok_result('studio mode', msg, studio_mode_data(st, present))
}

// studio_audio_mode_set_result records the audio mode intent. Low
// Latency and Advanced are explicit opt-ins (#287) and require --yes.
// PipeWire activation stays with HorneroOS/config drop-ins; this never
// writes PipeWire config or restarts services.
pub fn studio_audio_mode_set_result(mode_id string, yes bool) CommandResult {
	if mode_id !in studio_audio_mode_ids {
		return fail_result('studio mode audio',
			'unknown audio mode: ${mode_id}. Available: ${studio_audio_mode_ids.join(', ')}')
	}
	if mode_id in studio_audio_opt_in_ids && !yes {
		return fail_result('studio mode audio',
			'${mode_id} is an explicit opt-in and requires --yes.\nExample: horneroctl studio mode audio ${mode_id} --yes')
	}
	mut st, _ := load_studio_mode() or { return fail_result('studio mode audio', err.msg()) }
	if st.audio_mode == mode_id {
		return ok_result('studio mode audio', 'Studio audio mode already ${mode_id}; nothing changed.',
			studio_mode_data(st, true))
	}
	st.previous_audio_mode = st.audio_mode
	st.audio_mode = mode_id
	path := write_studio_mode(mut st) or { return fail_result('studio mode audio', err.msg()) }
	return ok_result('studio mode audio',
		'Recorded Studio audio mode ${mode_id} at ${path} (previous: ${st.previous_audio_mode}). PipeWire values are owned by HorneroOS/config desktop/studio-audio drop-ins; horneroctl does not write PipeWire config or restart services. Restore with: horneroctl studio mode restore',
		studio_mode_data(st, true))
}

// studio_performance_set_result enables Temporary Performance through
// power-profiles-daemon only, recording the exact previous profile.
pub fn studio_performance_set_result(yes bool, timeout_minutes int) CommandResult {
	if !yes {
		return fail_result('studio mode performance',
			'Temporary Performance is an explicit opt-in and requires --yes.\nExample: horneroctl studio mode performance --yes')
	}
	if timeout_minutes < 0 || timeout_minutes > 1440 {
		return fail_result('studio mode performance', 'timeout must be between 0 and 1440 minutes (0 = no timeout)')
	}
	mut st, _ := load_studio_mode() or { return fail_result('studio mode performance', err.msg()) }
	if st.performance_active {
		return fail_result('studio mode performance',
			'Temporary Performance already active (previous profile: ${st.performance_previous}); restore first with: horneroctl studio mode restore')
	}
	bin := resolve_powerprofilesctl_bin()
	if bin.len == 0 {
		return fail_result('studio mode performance',
			'powerprofilesctl not found; Temporary Performance needs power-profiles-daemon. No state changed.')
	}
	get_rep := run_exec(ExecSpec{
		prog: bin
		args: ['get']
	})
	if !get_rep.ok || get_rep.output.trim_space().len == 0 {
		return fail_result('studio mode performance', 'could not read current power profile; no state changed.')
	}
	current := get_rep.output.trim_space()
	if current == 'performance' {
		return fail_result('studio mode performance',
			'current profile is already performance outside Studio Temporary Performance; refusing to record it as the restore target.')
	}
	set_rep := run_exec(ExecSpec{
		prog: bin
		args: ['set', 'performance']
	})
	if !set_rep.ok {
		return fail_result('studio mode performance',
			'powerprofilesctl set performance failed (exit ${set_rep.exit_code}); profile unchanged, no state recorded.')
	}
	st.performance_active = true
	st.performance_previous = current
	st.performance_started = time.now().unix()
	st.performance_timeout = if timeout_minutes > 0 {
		st.performance_started + i64(timeout_minutes) * 60
	} else {
		i64(0)
	}
	write_studio_mode(mut st) or { return fail_result('studio mode performance', err.msg()) }
	mut msg := 'Temporary Performance active (previous profile: ${current}). Restore with: horneroctl studio mode restore'
	if st.performance_timeout > 0 {
		msg += '\nRecorded timeout at unix ${st.performance_timeout}; check with: horneroctl studio mode'
	}
	return ok_result('studio mode performance', msg, studio_mode_data(st, true))
}

// studio_mode_restore_result restores the exact previous audio mode
// intent and, when Temporary Performance is active, the exact previous
// power profile. Restoring never needs --yes.
pub fn studio_mode_restore_result() CommandResult {
	mut st, present := load_studio_mode() or { return fail_result('studio mode restore', err.msg()) }
	if !present || (st.previous_audio_mode.len == 0 && !st.performance_active) {
		return ok_result('studio mode restore', 'Nothing to restore: no previous Studio mode recorded.',
			studio_mode_data(st, present))
	}
	mut notes := []string{}
	if st.performance_active {
		bin := resolve_powerprofilesctl_bin()
		if bin.len == 0 {
			return fail_result('studio mode restore',
				'powerprofilesctl not found; cannot restore previous profile ${st.performance_previous}. State kept so restore can be retried.')
		}
		rep := run_exec(ExecSpec{
			prog: bin
			args: ['set', st.performance_previous]
		})
		if !rep.ok {
			return fail_result('studio mode restore',
				'powerprofilesctl set ${st.performance_previous} failed (exit ${rep.exit_code}); state kept so restore can be retried.')
		}
		notes << 'power profile restored to ${st.performance_previous}'
		st.performance_active = false
		st.performance_previous = ''
		st.performance_started = 0
		st.performance_timeout = 0
	}
	if st.previous_audio_mode.len > 0 {
		notes << 'audio mode restored to ${st.previous_audio_mode} (PipeWire drop-in activation remains a HorneroOS/config user step)'
		st.audio_mode = st.previous_audio_mode
		st.previous_audio_mode = ''
	}
	write_studio_mode(mut st) or { return fail_result('studio mode restore', err.msg()) }
	return ok_result('studio mode restore', 'Restored: ${notes.join('; ')}.', studio_mode_data(st, true))
}
