module hornero_core

import os
import time

// Studio low-latency PipeWire profile: apply, revert, status.
//
// What this does and never does:
//   - apply writes ONE user-scope drop-in
//     (~/.config/pipewire/pipewire.conf.d/50-hornero-studio-low-latency.conf,
//     identical in values to HorneroOS/config desktop/studio-audio/
//     low-latency.conf) and pushes the same three clock values into the
//     running PipeWire through its settings metadata (pw-metadata), saving
//     the exact previous values so revert can restore them.
//   - revert removes only the drop-in this module wrote (identified by its
//     marker line) and restores the saved runtime values.
//   - it never restarts services, never needs root, never touches realtime
//     privileges, IRQs, governors, GPU or I/O schedulers, and never
//     overwrites a personal file of the same name.
//   - quantum is a scheduling period, not physical round-trip latency; the
//     status report shows xruns and DSP load as PipeWire reports them and
//     says "unavailable" when they cannot be read.

pub const studio_lowlat_dropin_name = '50-hornero-studio-low-latency.conf'
pub const studio_lowlat_marker = '# HorneroOS Studio audio policy: Low Latency (applied by horneroctl studio audio apply).'

// Runtime settings keys changed by apply, in the order they are written.
// min/max first so the quantum is always inside the allowed window; revert
// writes them back in the opposite order.
const studio_runtime_keys = ['clock.min-quantum', 'clock.max-quantum', 'clock.quantum']
const studio_lowlat_values = {
	'clock.min-quantum': '64'
	'clock.max-quantum': '256'
	'clock.quantum':     '128'
}

pub fn resolve_pw_metadata_bin() string {
	return leaf_bin('HORNERO_PW_METADATA_BIN', 'pw-metadata')
}

pub fn resolve_pw_top_bin() string {
	return leaf_bin('HORNERO_PW_TOP_BIN', 'pw-top')
}

pub fn studio_pipewire_dropin_dir() string {
	override := os.getenv('HORNERO_PIPEWIRE_CONF_DIR')
	if override.len > 0 {
		return override
	}
	return os.join_path(resolve_paths().config_dir, 'pipewire', 'pipewire.conf.d')
}

pub fn studio_pipewire_dropin_path() string {
	return os.join_path(studio_pipewire_dropin_dir(), studio_lowlat_dropin_name)
}

pub fn studio_audio_applied_file() string {
	override := os.getenv('HORNERO_STUDIO_AUDIO_APPLIED_FILE')
	if override.len > 0 {
		return override
	}
	return os.join_path(resolve_paths().config_dir, 'hornero', 'studio-audio-applied.txt')
}

pub fn studio_lowlat_dropin_content() string {
	return [
		studio_lowlat_marker,
		'#',
		'# Same values as HorneroOS/config desktop/studio-audio/low-latency.conf.',
		'# PROPOSAL VALUES, not measured per-device support. Quantum is a',
		'# scheduling period, not physical round-trip latency. A device that',
		'# underruns at 128 frames should go back to Balanced:',
		'#   horneroctl studio audio revert',
		'context.properties = {',
		'    default.clock.rate = 48000',
		'    default.clock.quantum = 128',
		'    default.clock.min-quantum = 64',
		'    default.clock.max-quantum = 256',
		'}',
		'',
	].join('\n')
}

// parse_pw_settings reads `pw-metadata -n settings` output lines of the
// form `update: id:0 key:'clock.quantum' value:'1024' type:''`.
pub fn parse_pw_settings(raw string) map[string]string {
	mut out := map[string]string{}
	for line in raw.split_into_lines() {
		ki := line.index("key:'") or { continue }
		rest := line[ki + 5..]
		ke := rest.index("'") or { continue }
		key := rest[..ke]
		after := rest[ke..]
		vi := after.index("value:'") or { continue }
		vrest := after[vi + 7..]
		ve := vrest.index("'") or { continue }
		out[key] = vrest[..ve]
	}
	return out
}

// PwRuntime is the readable PipeWire runtime state; available=false carries
// the reason instead of guessing.
pub struct PwRuntime {
pub:
	available bool
	reason    string
	settings  map[string]string
}

pub fn read_pw_runtime() PwRuntime {
	bin := resolve_pw_metadata_bin()
	if bin.len == 0 {
		return PwRuntime{
			reason: 'pw-metadata not found (pipewire tools are not installed)'
		}
	}
	rep := run_exec(ExecSpec{
		prog:        bin
		args:        ['-n', 'settings']
		timeout_sec: 5
	})
	if !rep.ok {
		return PwRuntime{
			reason: 'PipeWire is not reachable (pw-metadata exited ${rep.exit_code}); is the user pipewire service running?'
		}
	}
	s := parse_pw_settings(rep.output)
	if 'clock.quantum' !in s {
		return PwRuntime{
			reason: 'pw-metadata returned no clock settings'
		}
	}
	return PwRuntime{
		available: true
		settings:  s
	}
}

fn set_pw_setting(key string, value string) bool {
	bin := resolve_pw_metadata_bin()
	if bin.len == 0 {
		return false
	}
	return run_exec(ExecSpec{
		prog:        bin
		args:        ['-n', 'settings', '0', key, value]
		timeout_sec: 5
	}).ok
}

// PwNodeStat is one row of `pw-top -b`.
pub struct PwNodeStat {
pub:
	state string
	id    string
	quant int
	rate  int
	b_q   f64
	errs  int
	name  string
}

fn pw_num(s string) f64 {
	if s.len == 0 || s[0] == `-` {
		return 0.0
	}
	return s.f64()
}

// parse_pw_top takes the LAST iteration of `pw-top -b -n 2` (the first one
// has no deltas) and returns its rows. Rows that do not parse are skipped.
pub fn parse_pw_top(raw string) []PwNodeStat {
	lines := raw.split_into_lines()
	mut start := -1
	for i, l in lines {
		if l.trim_space().starts_with('S ') && l.contains('QUANT') && l.contains('ERR') {
			start = i
		}
	}
	if start < 0 {
		return []
	}
	mut rows := []PwNodeStat{}
	for l in lines[start + 1..] {
		t := l.fields()
		if t.len < 10 {
			continue
		}
		if t[1].len == 0 || !t[1][0].is_digit() {
			continue
		}
		rows << PwNodeStat{
			state: t[0]
			id:    t[1]
			quant: int(pw_num(t[2]))
			rate:  int(pw_num(t[3]))
			b_q:   pw_num(t[7])
			errs:  int(pw_num(t[8]))
			name:  t[t.len - 1]
		}
	}
	return rows
}

// PwLoad summarises what pw-top shows for processing graphs.
pub struct PwLoad {
pub:
	available bool
	reason    string
	active    int
	max_quant int
	max_b_q   f64
	xruns     int
	xrun_node string
}

pub fn summarise_pw_top(rows []PwNodeStat) PwLoad {
	mut active := 0
	mut max_q := 0
	mut max_b := 0.0
	mut xr := 0
	mut xr_node := ''
	mut xr_max := 0
	for r in rows {
		if r.quant > 0 {
			active++
			if r.quant > max_q {
				max_q = r.quant
			}
			if r.b_q > max_b {
				max_b = r.b_q
			}
		}
		xr += r.errs
		if r.errs > xr_max {
			xr_max = r.errs
			xr_node = r.name
		}
	}
	return PwLoad{
		available: true
		active:    active
		max_quant: max_q
		max_b_q:   max_b
		xruns:     xr
		xrun_node: xr_node
	}
}

pub fn read_pw_load() PwLoad {
	bin := resolve_pw_top_bin()
	if bin.len == 0 {
		return PwLoad{
			reason: 'pw-top not found'
		}
	}
	rep := run_exec(ExecSpec{
		prog:        bin
		args:        ['-b', '-n', '2']
		timeout_sec: 8
	})
	if !rep.ok {
		return PwLoad{
			reason: 'pw-top exited ${rep.exit_code}; PipeWire is not reachable'
		}
	}
	rows := parse_pw_top(rep.output)
	if rows.len == 0 {
		return PwLoad{
			reason: 'pw-top returned no node rows'
		}
	}
	return summarise_pw_top(rows)
}

// studio_realtime_note reports, read-only, whether the RealtimeKit daemon
// that PipeWire uses to get realtime scheduling without root is installed.
// It does not claim that scheduling is working.
pub fn studio_realtime_note() string {
	for p in ['/usr/lib/rtkit/rtkit-daemon', '/usr/libexec/rtkit-daemon', '/usr/lib/rtkit-daemon'] {
		if os.is_file(p) {
			return 'rtkit installed (${p}); PipeWire requests realtime through it. Whether a given stream actually got RT scheduling is not checked here'
		}
	}
	return 'rtkit-daemon not found; PipeWire may run without realtime scheduling, which makes low quantums unreliable'
}

fn studio_dropin_is_ours(path string) bool {
	body := os.read_file(path) or { return false }
	return body.contains(studio_lowlat_marker)
}

fn applied_encode(prev map[string]string) string {
	mut lines := []string{}
	for k in studio_runtime_keys {
		if v := prev[k] {
			lines << '${k}=${v}'
		}
	}
	lines << 'applied_unix=${time.now().unix()}'
	return lines.join('\n') + '\n'
}

fn applied_decode(raw string) map[string]string {
	mut out := map[string]string{}
	for l in raw.split_into_lines() {
		i := l.index('=') or { continue }
		out[l[..i]] = l[i + 1..]
	}
	return out
}

fn studio_audio_data(drop_in string, rt PwRuntime, load PwLoad, extra map[string]string) map[string]string {
	mut d := map[string]string{}
	d['dropin_path'] = studio_pipewire_dropin_path()
	d['dropin'] = drop_in
	d['quantum_semantics'] = 'scheduling period, not physical round-trip latency'
	d['runtime'] = if rt.available { 'readable' } else { 'unavailable' }
	if rt.available {
		for k in ['clock.rate', 'clock.quantum', 'clock.min-quantum', 'clock.max-quantum',
			'clock.force-quantum'] {
			d[k] = rt.settings[k] or { '' }
		}
	} else {
		d['runtime_reason'] = rt.reason
	}
	d['xruns'] = if load.available { '${load.xruns}' } else { 'unavailable' }
	d['dsp_load_max_b_q'] = if load.available { '${load.max_b_q}' } else { 'unavailable' }
	if !load.available {
		d['load_reason'] = load.reason
	}
	for k, v in extra {
		d[k] = v
	}
	return d
}

fn studio_dropin_state() string {
	p := studio_pipewire_dropin_path()
	if !os.is_file(p) {
		return 'absent'
	}
	return if studio_dropin_is_ours(p) { 'applied' } else { 'foreign-file' }
}

pub fn studio_audio_status_result() CommandResult {
	rt := read_pw_runtime()
	load := read_pw_load()
	state := studio_dropin_state()
	mut msg := []string{}
	msg << 'Low Latency drop-in: ${state} (${studio_pipewire_dropin_path()})'
	if state == 'foreign-file' {
		msg << 'A file with that name exists that horneroctl did not write; it is left untouched.'
	}
	if rt.available {
		msg << 'PipeWire runtime: rate ${rt.settings['clock.rate'] or { '?' }}, quantum ${rt.settings['clock.quantum'] or { '?' }} (min ${rt.settings['clock.min-quantum'] or { '?' }}, max ${rt.settings['clock.max-quantum'] or { '?' }}), force-quantum ${rt.settings['clock.force-quantum'] or { '0' }}'
	} else {
		msg << 'PipeWire runtime: unavailable (${rt.reason})'
	}
	if load.available {
		msg << 'Processing now: ${load.active} active node(s), largest quantum ${load.max_quant}, highest DSP load ${load.max_b_q:.2} of the quantum (B/Q); xruns since the nodes started: ${load.xruns}${if load.xruns > 0 {
			' (most on ${load.xrun_node})'
		} else {
			''
		}}'
	} else {
		msg << 'xruns / DSP load: unavailable (${load.reason})'
	}
	msg << studio_realtime_note()
	msg << 'Quantum is a scheduling period, not physical round-trip latency. Only a loopback measurement reports real latency.'
	return ok_result('studio audio status', msg.join('\n'), studio_audio_data(state, rt, load,
		map[string]string{}))
}

fn restore_runtime(prev map[string]string) []string {
	mut failed := []string{}
	for k in studio_runtime_keys.reverse() {
		v := prev[k] or { continue }
		if !set_pw_setting(k, v) {
			failed << k
		}
	}
	return failed
}

pub fn studio_audio_apply_result(yes bool, dry_run bool) CommandResult {
	cmd := 'studio audio apply'
	if !yes && !dry_run {
		return fail_result(cmd, 'Low Latency is an explicit opt-in and requires --yes.\nPreview first: horneroctl studio audio apply --dry-run\nExample: horneroctl studio audio apply --yes')
	}
	dropin := studio_pipewire_dropin_path()
	state := studio_dropin_state()
	if state == 'foreign-file' {
		return fail_result(cmd, '${dropin} already exists and was not written by horneroctl; refusing to overwrite a personal PipeWire file. Nothing changed.')
	}
	rt := read_pw_runtime()
	if dry_run {
		return ok_result(cmd, 'Dry run: would write ${dropin} (rate 48000, quantum 128, min 64, max 256) and ${if rt.available {
			'set the same values in the running PipeWire, saving the previous ones'
		} else {
			'NOT change the running PipeWire (${rt.reason}); values apply when PipeWire next starts'
		}}. Nothing was changed.',
			studio_audio_data(state, rt, PwLoad{
				reason: 'not read in dry run'
			}, {
				'dry_run': 'true'
			}))
	}
	// Save the previous runtime values once; a second apply keeps the
	// original restore target.
	mut prev := map[string]string{}
	applied_path := studio_audio_applied_file()
	if os.is_file(applied_path) {
		prev = applied_decode(os.read_file(applied_path) or { '' })
	} else if rt.available {
		for k in studio_runtime_keys {
			prev[k] = rt.settings[k] or { '' }
		}
		prev = prev.clone()
	}
	mut runtime_applied := false
	if rt.available {
		for k in studio_runtime_keys {
			if !set_pw_setting(k, studio_lowlat_values[k]) {
				restore_runtime(prev)
				return fail_result(cmd, 'could not set ${k} through pw-metadata; runtime values restored, no drop-in written.')
			}
		}
		after := read_pw_runtime()
		for k in studio_runtime_keys {
			if !after.available || after.settings[k] or { '' } != studio_lowlat_values[k] {
				restore_runtime(prev)
				return fail_result(cmd, 'PipeWire did not accept ${k}=${studio_lowlat_values[k]} (read back ${after.settings[k] or {
					'?'
				}}); runtime values restored, no drop-in written.')
			}
		}
		runtime_applied = true
		os.mkdir_all(os.dir(applied_path)) or {
			restore_runtime(prev)
			return fail_result(cmd, 'cannot create ${os.dir(applied_path)}: ${err.msg()}')
		}
		os.write_file(applied_path, applied_encode(prev)) or {
			restore_runtime(prev)
			return fail_result(cmd, 'cannot write ${applied_path}: ${err.msg()}; runtime values restored.')
		}
	}
	os.mkdir_all(os.dir(dropin)) or {
		if runtime_applied {
			restore_runtime(prev)
		}
		return fail_result(cmd, 'cannot create ${os.dir(dropin)}: ${err.msg()}')
	}
	tmp := '${dropin}.tmp'
	os.write_file(tmp, studio_lowlat_dropin_content()) or {
		if runtime_applied {
			restore_runtime(prev)
		}
		return fail_result(cmd, 'cannot write ${tmp}: ${err.msg()}')
	}
	os.mv(tmp, dropin) or {
		if runtime_applied {
			restore_runtime(prev)
		}
		return fail_result(cmd, 'cannot move ${tmp} to ${dropin}: ${err.msg()}')
	}
	// Record the intent last, through the same path the mode command uses.
	rec := studio_audio_mode_set_result('low-latency', true)
	mut note := if runtime_applied {
		'Applied Low Latency: quantum 128 (min 64, max 256) is live in the running PipeWire and the drop-in will make it persistent.'
	} else {
		'Wrote the drop-in only: ${rt.reason}. The values apply the next time PipeWire starts.'
	}
	if !rec.ok {
		note += ' (mode intent not recorded: ${rec.message})'
	}
	note += '\nIf you hear crackles or a stream underruns, undo it with: horneroctl studio audio revert\nQuantum is a scheduling period, not physical round-trip latency.'
	return ok_result(cmd, note, studio_audio_data('applied', read_pw_runtime(), PwLoad{
		reason: 'run studio audio status after starting your audio application'
	}, {
		'runtime_applied': '${runtime_applied}'
	}))
}

pub fn studio_audio_revert_result() CommandResult {
	cmd := 'studio audio revert'
	dropin := studio_pipewire_dropin_path()
	state := studio_dropin_state()
	if state == 'foreign-file' {
		return fail_result(cmd, '${dropin} was not written by horneroctl; leaving it untouched. Remove it yourself if you want stock behaviour.')
	}
	applied_path := studio_audio_applied_file()
	has_applied := os.is_file(applied_path)
	if state == 'absent' && !has_applied {
		return ok_result(cmd, 'Nothing to revert: no Low Latency drop-in or saved runtime values.',
			studio_audio_data(state, read_pw_runtime(), PwLoad{
				reason: 'not read'
			}, map[string]string{}))
	}
	mut notes := []string{}
	if has_applied {
		prev := applied_decode(os.read_file(applied_path) or { '' })
		rt := read_pw_runtime()
		if rt.available {
			failed := restore_runtime(prev)
			if failed.len > 0 {
				return fail_result(cmd, 'could not restore ${failed.join(', ')} through pw-metadata; saved values kept so revert can be retried.')
			}
			notes << 'runtime quantum values restored (quantum ${prev['clock.quantum'] or { '?' }}, min ${prev['clock.min-quantum'] or { '?' }}, max ${prev['clock.max-quantum'] or { '?' }})'
		} else {
			notes << 'PipeWire not reachable (${rt.reason}); nothing to restore at runtime'
		}
		os.rm(applied_path) or {}
	}
	if state == 'applied' {
		os.rm(dropin) or {
			return fail_result(cmd, 'cannot remove ${dropin}: ${err.msg()}')
		}
		notes << 'removed ${dropin}'
	}
	mut st, present := load_studio_mode() or { StudioModeState{}, false }
	if present && st.audio_mode == 'low-latency' {
		st.audio_mode = if st.previous_audio_mode.len > 0 {
			st.previous_audio_mode
		} else {
			'balanced'
		}
		st.previous_audio_mode = ''
		write_studio_mode(mut st) or {}
		notes << 'audio mode back to ${st.audio_mode}'
	}
	return ok_result(cmd, 'Reverted: ${notes.join('; ')}.', studio_audio_data('absent',
		read_pw_runtime(), PwLoad{
			reason: 'not read'
		}, map[string]string{}))
}

// studio_audio_doctor_checks adds read-only audio-stack facts to
// `studio doctor`. Anything that cannot be read is a warning that says so;
// nothing here fails the doctor because the stack is merely not running.
pub fn studio_audio_doctor_checks() []DoctorCheck {
	mut checks := []DoctorCheck{}
	rt := read_pw_runtime()
	checks << DoctorCheck{
		name:   'pipewire-runtime'
		ok:     true
		warn:   !rt.available
		detail: if rt.available {
			'running: rate ${rt.settings['clock.rate'] or { '?' }}, quantum ${rt.settings['clock.quantum'] or { '?' }} (min ${rt.settings['clock.min-quantum'] or { '?' }}, max ${rt.settings['clock.max-quantum'] or { '?' }}); a scheduling period, not physical latency'
		} else {
			'unavailable: ${rt.reason}'
		}
	}
	load := read_pw_load()
	checks << DoctorCheck{
		name:   'pipewire-xruns'
		ok:     true
		warn:   !load.available || load.xruns > 0
		detail: if !load.available {
			'unavailable: ${load.reason}'
		} else if load.xruns > 0 {
			'${load.xruns} xrun(s) counted since the nodes started (most on ${load.xrun_node}); consider a larger quantum or Balanced mode'
		} else {
			'0 xruns counted across ${load.active} active node(s), highest DSP load ${load.max_b_q:.2} of the quantum'
		}
	}
	checks << DoctorCheck{
		name:   'pipewire-jack'
		ok:     true
		warn:   find_on_path('pw-jack').len == 0
		detail: if find_on_path('pw-jack').len > 0 {
			'pw-jack present: JACK clients (Ardour, Guitarix, REAPER via JACK) run on PipeWire'
		} else {
			'pw-jack not found (pipewire-jack): JACK-only applications cannot attach to PipeWire'
		}
	}
	rtk := studio_realtime_note()
	checks << DoctorCheck{
		name:   'realtime-kit'
		ok:     true
		warn:   rtk.contains('not found')
		detail: rtk
	}
	state := studio_dropin_state()
	checks << DoctorCheck{
		name:   'studio-audio-profile'
		ok:     state != 'foreign-file'
		warn:   state == 'applied'
		detail: match state {
			'applied' {
				'Low Latency drop-in active (quantum 128 proposal); revert with: horneroctl studio audio revert'
			}
			'foreign-file' {
				'${studio_pipewire_dropin_path()} exists but was not written by horneroctl; it will not be touched'
			}
			else {
				'Balanced (no Hornero drop-in); Low Latency is an opt-in: horneroctl studio audio apply --yes'
			}
		}
	}
	return checks
}
