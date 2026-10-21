module hornero_core

import os
import time

// Native night-mode control. Ports horneroctl appearance night-mode: backend detection
// (redshift/gammastep/wlsunset/xrandr stay external tools with
// HORNERO_*_BIN overrides), hybrid state detection (process table plus
// a state file for daemon ambiguity), and the toggle/enable/disable/
// status/status-icon/status-text/backends verbs.

pub const night_default_temperature = 4000
pub const night_min_temperature = 1000
pub const night_max_temperature = 6500

// night_clamp_temperature resolves an unset (0) or out-of-range
// request into the supported Kelvin window.
pub fn night_clamp_temperature(k int) int {
	if k <= 0 {
		return night_default_temperature
	}
	if k < night_min_temperature {
		return night_min_temperature
	}
	if k > night_max_temperature {
		return night_max_temperature
	}
	return k
}

// night_backend_temp_args is the per-backend one-shot temperature
// argument. xrandr takes none here; it uses night_xrandr_gamma.
pub fn night_backend_temp_args(backend string, temp int) []string {
	return match backend {
		'redshift', 'gammastep' { ['-O', '${temp}K'] }
		'wlsunset' { ['-T', '${temp}'] }
		else { []string{} }
	}
}

fn night_gamma_component(v f64) string {
	if v >= 0.995 {
		return '1'
	}
	return '${v:.2f}'.trim_right('0').trim_right('.')
}

// night_xrandr_gamma maps Kelvin to an xrandr gamma triple by
// piecewise-linear interpolation between the 6500K neutral point,
// the long-standing 4000K Hornero setting, and a deep-warm 1000K.
pub fn night_xrandr_gamma(temp int) string {
	k := night_clamp_temperature(temp)
	anchors := [[6500.0, 1.0, 1.0], [4000.0, 0.85, 0.6], [1000.0, 0.65, 0.35]]
	mut g := 1.0
	mut b := 1.0
	for i in 0 .. anchors.len - 1 {
		hi := anchors[i]
		lo := anchors[i + 1]
		if k <= hi[0] && k >= lo[0] {
			frac := (f64(k) - lo[0]) / (hi[0] - lo[0])
			g = lo[1] + frac * (hi[1] - lo[1])
			b = lo[2] + frac * (hi[2] - lo[2])
			break
		}
	}
	return '1:${night_gamma_component(g)}:${night_gamma_component(b)}'
}

// resolve_night_temperature_file sits next to the state file and
// stores the chosen Kelvin temperature (plain integer).
pub fn resolve_night_temperature_file() string {
	state := resolve_night_state_file()
	return os.join_path(os.dir(state), 'night_mode_temperature')
}

pub fn read_night_temperature() int {
	raw := (os.read_file(resolve_night_temperature_file()) or { '' }).trim_space()
	if raw.len == 0 {
		return night_default_temperature
	}
	return night_clamp_temperature(raw.int())
}

pub fn write_night_temperature(temp int) ! {
	path := resolve_night_temperature_file()
	os.mkdir_all(os.dir(path)) or {
		return error('cannot create ${os.dir(path)}: ${err.msg()}')
	}
	os.write_file(path, '${night_clamp_temperature(temp)}\n') or {
		return error('cannot write ${path}: ${err.msg()}')
	}
}

// -- Schedule (shell#225 remainder) -----------------------------------------
// The schedule is enforced by two systemd user timers horneroctl
// writes (on at --from, off at --to, Persistent=true so a boundary
// missed while logged out is caught up). No daemon, no root; where
// systemd user sessions are unavailable the schedule is stored and
// reported as not enforced instead of pretending otherwise.

pub fn night_parse_hhmm(s string) (int, bool) {
	parts := s.split(':')
	if parts.len != 2 {
		return -1, false
	}
	h := parts[0]
	m := parts[1]
	if h.len == 0 || h.len > 2 || m.len != 2 {
		return -1, false
	}
	for c in h + m {
		if c < `0` || c > `9` {
			return -1, false
		}
	}
	hours := h.int()
	mins := m.int()
	if hours > 23 || mins > 59 {
		return -1, false
	}
	return hours * 60 + mins, true
}

pub fn night_format_hhmm(minutes int) string {
	h := (minutes / 60) % 24
	m := minutes % 60
	return '${h:02d}:${m:02d}'
}

// night_schedule_active_at reports whether now falls in the
// [on, off) window; off <= on wraps past midnight, on == off is an
// empty (never active) window.
pub fn night_schedule_active_at(on_min int, off_min int, now_min int) bool {
	if on_min == off_min {
		return false
	}
	if on_min < off_min {
		return now_min >= on_min && now_min < off_min
	}
	return now_min >= on_min || now_min < off_min
}

pub fn resolve_night_schedule_file() string {
	return os.join_path(os.dir(resolve_night_state_file()), 'night_mode_schedule')
}

// read_night_schedule returns (on, off, present) in minutes.
pub fn read_night_schedule() (int, int, bool) {
	raw := (os.read_file(resolve_night_schedule_file()) or { '' }).trim_space()
	if raw.len == 0 {
		return -1, -1, false
	}
	parts := raw.split(' ')
	if parts.len != 2 {
		return -1, -1, false
	}
	on, ok_on := night_parse_hhmm(parts[0])
	off, ok_off := night_parse_hhmm(parts[1])
	if !ok_on || !ok_off {
		return -1, -1, false
	}
	return on, off, true
}

pub fn write_night_schedule(on_min int, off_min int) ! {
	path := resolve_night_schedule_file()
	os.mkdir_all(os.dir(path)) or {
		return error('cannot create ${os.dir(path)}: ${err.msg()}')
	}
	os.write_file(path, '${night_format_hhmm(on_min)} ${night_format_hhmm(off_min)}\n') or {
		return error('cannot write ${path}: ${err.msg()}')
	}
}

pub fn clear_night_schedule() {
	os.rm(resolve_night_schedule_file()) or {}
}

pub fn night_schedule_unit_name(verb string, timer bool) string {
	return 'hornero-nightlight-${verb}.${if timer { 'timer' } else { 'service' }}'
}

fn night_schedule_unit_file(verb string, timer bool) string {
	paths := resolve_paths()
	return os.join_path(paths.config_dir, 'systemd', 'user', night_schedule_unit_name(verb,
		timer))
}

pub fn night_schedule_service_content(self_path string, verb string) string {
	label := if verb == 'on' { 'on' } else { 'off' }
	return '[Unit]\nDescription=Hornero Night Light ${label} (scheduled)\n\n[Service]\nType=oneshot\nExecStart=${self_path} appearance night-mode ${verb} --yes\n'
}

pub fn night_schedule_timer_content(hhmm string, verb string) string {
	label := if verb == 'on' { 'on' } else { 'off' }
	return '[Unit]\nDescription=Hornero Night Light ${label} timer\n\n[Timer]\nOnCalendar=*-*-* ${hhmm}:00\nPersistent=true\nUnit=${night_schedule_unit_name(verb, false)}\n\n[Install]\nWantedBy=timers.target\n'
}

fn night_schedule_timers_active() bool {
	if find_on_path('systemctl').len == 0 {
		return false
	}
	rep := run_exec(ExecSpec{
		prog:        'systemctl'
		args:        ['--user', 'is-active', night_schedule_unit_name('on', true)]
		timeout_sec: 10
	})
	return rep.output.trim_space() == 'active'
}

// resolve_night_state_file is the canonical state location (WRITE
// TARGET). Override with HORNERO_NIGHT_MODE_STATE_FILE.
pub fn resolve_night_state_file() string {
	env := os.getenv('HORNERO_NIGHT_MODE_STATE_FILE')
	if env.len > 0 {
		return env
	}
	mut base := os.getenv('XDG_CACHE_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.cache')
	}
	return os.join_path(base, 'hornero', 'night_mode_state')
}

// read_night_state_file returns the state content from its canonical path.
pub fn read_night_state_file() string {
	canon := resolve_night_state_file()
	return (os.read_file(canon) or { '' }).trim_space()
}

// write_night_state_file persists enabled/disabled to the canonical file.
pub fn write_night_state_file(state string) ! {
	path := resolve_night_state_file()
	os.mkdir_all(os.dir(path)) or { return error('cannot create ${os.dir(path)}: ${err.msg()}') }
	os.write_file(path, state + '\n') or { return error('cannot write ${path}: ${err.msg()}') }
}

// classify_night_procs is the pure hybrid detector: given process command
// lines, the state-file content, and an optional xrandr gamma triple,
// decide (active, backend label). Mirrors is_night_mode_active plus
// get_active_backend priority.
pub fn classify_night_procs(cmdlines []string, state string, gamma string) (bool, string) {
	has := fn [cmdlines] (a string, b string) bool {
		for c in cmdlines {
			if c.contains(a) && c.contains(b) {
				return true
			}
		}
		return false
	}
	any_proc := fn [cmdlines] (name string) bool {
		for c in cmdlines {
			if c.contains(name) {
				return true
			}
		}
		return false
	}
	if has('redshift', '-O') {
		return true, 'redshift (manual)'
	}
	if has('gammastep', '-O') {
		return true, 'gammastep (manual)'
	}
	if has('wlsunset', '-T') {
		return true, 'wlsunset'
	}
	if has('redshift', '-l') || has('gammastep', '-l') {
		if state == 'enabled' {
			if has('redshift', '-l') {
				return true, 'redshift (daemon)'
			}
			return true, 'gammastep (daemon)'
		}
		return false, 'none'
	}
	if gamma.len > 0 {
		parts := gamma.split(':')
		if parts.len == 3 {
			blue := parts[2].f64()
			if blue > 1.2 {
				return true, 'xrandr'
			}
		}
	}
	if state == 'enabled' {
		if any_proc('redshift') {
			return true, 'redshift (daemon)'
		}
		if any_proc('gammastep') {
			return true, 'gammastep (daemon)'
		}
		if any_proc('wlsunset') {
			return true, 'wlsunset'
		}
		return true, 'none'
	}
	return false, 'none'
}

// collect_proc_cmdlines scans /proc for process command lines
// (NUL-separated cmdline joined with spaces). Empty when unavailable.
pub fn collect_proc_cmdlines() []string {
	mut out := []string{}
	entries := os.ls('/proc') or { return out }
	for e in entries {
		if e.len == 0 || e[0] < `0` || e[0] > `9` {
			continue
		}
		raw := os.read_file('/proc/' + e + '/cmdline') or { continue }
		if raw.len == 0 {
			continue
		}
		out << raw.replace('\x00', ' ').trim_space()
	}
	return out
}

// parse_xrandr_gamma extracts the first `Gamma: r:g:b` triple from
// `xrandr --verbose` output.
pub fn parse_xrandr_gamma(out string) string {
	for line in out.split_into_lines() {
		t := line.trim_space()
		if t.starts_with('Gamma:') {
			return t.all_after('Gamma:').trim_space()
		}
	}
	return ''
}

// parse_xrandr_displays lists connected display names from `xrandr`.
pub fn parse_xrandr_displays(out string) []string {
	mut displays := []string{}
	for line in out.split_into_lines() {
		if line.contains(' connected') {
			fields := line.split(' ')
			if fields.len > 0 && fields[0].len > 0 {
				displays << fields[0]
			}
		}
	}
	return displays
}

// night_backends_available lists installed backends in preference order.
pub fn night_backends_available() []string {
	mut out := []string{}
	if backend_or_empty('HORNERO_REDSHIFT_BIN', 'redshift').len > 0 {
		out << 'redshift'
	}
	if backend_or_empty('HORNERO_GAMMASSTEP_BIN', 'gammastep').len > 0 {
		out << 'gammastep'
	}
	if backend_or_empty('HORNERO_WLSUNSET_BIN', 'wlsunset').len > 0 {
		out << 'wlsunset'
	}
	if backend_or_empty('HORNERO_XRANDR_BIN', 'xrandr').len > 0 {
		out << 'xrandr'
	}
	return out
}

// night_probe_live detects live state: process table, xrandr gamma
// (when xrandr exists), state file. Pure enough to describe; the gamma
// probe executes xrandr only on real runs.
pub fn night_probe_live(dry_run bool) (bool, string) {
	cmdlines := if dry_run { []string{} } else { collect_proc_cmdlines() }
	state := read_night_state_file()
	mut gamma := ''
	if !dry_run {
		xr := backend_or_empty('HORNERO_XRANDR_BIN', 'xrandr')
		if xr.len > 0 {
			rep := strict_exec(xr, ['--verbose'], false)
			if rep.ok {
				gamma = parse_xrandr_gamma(rep.output)
			}
		}
	}
	return classify_night_procs(cmdlines, state, gamma)
}

// spawn_detached starts a backend one-shot (`redshift -O 4000K &` style)
// with output discarded, like the bash `&` launches.
fn spawn_detached(prog string, args []string, dry_run bool) ExecReport {
	line := strict_command_line(prog, args) + ' >/dev/null 2>&1 &'
	if dry_run {
		return ExecReport{
			command_line: line
			ok:           true
			output:       '(dry-run: not executed)'
			exit_code:    0
			was_dry_run:  true
		}
	}
	r := os.execute(line)
	return ExecReport{
		command_line: line
		ok:           r.exit_code == 0
		output:       r.output.trim_space()
		exit_code:    r.exit_code
		was_dry_run:  false
	}
}

// night_pkill_best_effort kills backend processes; failures ignored.
fn night_pkill_best_effort(pattern string, exact bool, dry_run bool, mut lines []string) {
	pk := resolve_pkill_bin()
	mut args := []string{}
	if exact {
		args << '-x'
	}
	args << pattern
	lines << strict_command_line(if pk.len > 0 { pk } else { 'pkill' }, args)
	if dry_run || pk.len == 0 {
		return
	}
	strict_exec(pk, args, false)
}

// night_notify_best_effort sends a desktop notice when possible.
fn night_notify_best_effort(title string, body string, icon string, dry_run bool, mut lines []string) {
	nb := resolve_notify_bin()
	args := [title, body, '-t', '3000', '-i', icon]
	lines << strict_command_line(if nb.len > 0 { nb } else { 'notify-send' }, args)
	if dry_run || nb.len == 0 {
		return
	}
	strict_exec(nb, args, false)
}

pub struct NightModeCmd {
pub:
	verb        string // toggle | on | off | set | schedule | status | status-icon | status-text | backends
	dry_run     bool
	yes         bool
	temperature int    // 0 = stored/default temperature
	schedule    string // schedule sub-action: '' | status | set | clear
	from_min    int = -1 // schedule window start (minutes), -1 unset
	to_min      int = -1 // schedule window end (minutes), -1 unset
}

// night_mode_run implements the night-mode verbs natively. Mutating
// verbs need --yes; --dry-run previews the backend lines and the state
// write without executing anything.
pub fn night_mode_run(cmd NightModeCmd) CommandResult {
	match cmd.verb {
		'status-icon' {
			active, _ := night_probe_live(cmd.dry_run)
			icon := if active { '󰖔' } else { '󰖙' }
			return ok_result('appearance night-mode status-icon', icon, {
				'active': '${active}'
			})
		}
		'status-text' {
			active, backend := night_probe_live(cmd.dry_run)
			text := if active {
				'Night Mode Active\nBackend: ${backend}\nClick to toggle\n'
			} else {
				'Day Mode\nClick to enable night mode\n'
			}
			return ok_result('appearance night-mode status-text', text, {
				'active': '${active}'
			})
		}
		'backends' {
			available := night_backends_available()
			active, backend := night_probe_live(cmd.dry_run)
			mut msg := 'Available backends: ${available.join(' ')}'
			if active {
				msg += '\nCurrently active: ${backend}'
			}
			return ok_result('appearance night-mode backends', msg, {
				'available': available.join(',')
				'active':    '${active}'
			})
		}
		'status' {
			// An explicit override short-circuits to that backend
			// (opaque passthrough, fails when broken); unset means
			// fully native.
			override := os.getenv('HORNERO_NIGHT_MODE_BIN')
			if override.len > 0 && !cmd.dry_run {
				rep := strict_exec(override, ['status'], false)
				if rep.ok {
					return ok_result('appearance night-mode status', rep.output, {
						'command_line': rep.command_line
					})
				}
				return fail_result('appearance night-mode status', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
			}
			active, backend := night_probe_live(cmd.dry_run)
			state := if cmd.dry_run { '(preview)' } else { read_night_state_file() }
			mut msg := if active {
				'Night mode is ACTIVE (backend: ${backend})'
			} else {
				'Night mode is INACTIVE (day mode)'
			}
			if !cmd.dry_run {
				msg += '\nState file: ${if state.len > 0 { state } else { 'not found' }}'
			}
			sched_on, sched_off, sched_present := read_night_schedule()
			return ok_result('appearance night-mode status', msg, {
				'active':           '${active}'
				'backend':          backend
				'temperature':      '${read_night_temperature()}'
				'schedule':         if sched_present {
					'${night_format_hhmm(sched_on)}-${night_format_hhmm(sched_off)}'
				} else {
					''
				}
				'scheduleEnforced': '${sched_present && night_schedule_timers_active()}'
			})
		}
		'toggle', 'auto', 'on', 'enable', 'off', 'disable', 'set', 'schedule' {}
		else {
			return fail_result('appearance night-mode', 'unknown action: ${cmd.verb}.\nRun: horneroctl appearance night-mode --help')
		}
	}
	if cmd.verb == 'schedule' && cmd.schedule in ['', 'status'] {
		on, off, present := read_night_schedule()
		if !present {
			return ok_result('appearance night-mode schedule', 'No night light schedule is set.', {
				'schedule': ''
			})
		}
		enforced := night_schedule_timers_active()
		return ok_result('appearance night-mode schedule', 'Schedule: night light on at ${night_format_hhmm(on)}, off at ${night_format_hhmm(off)} (enforced by user timers: ${enforced}).', {
			'schedule':         '${night_format_hhmm(on)}-${night_format_hhmm(off)}'
			'scheduleEnforced': '${enforced}'
		})
	}
	if !cmd.yes && !cmd.dry_run {
		return fail_result('appearance night-mode ${cmd.verb}', 'refusing to change night mode without --yes (preview with --dry-run).\nExample: horneroctl appearance night-mode ${cmd.verb} --dry-run')
	}
	if cmd.verb == 'schedule' {
		return night_schedule_run(cmd)
	}
	active, _ := night_probe_live(cmd.dry_run)
	mut lines := []string{}
	if cmd.verb == 'set' {
		if cmd.temperature <= 0 {
			return fail_result('appearance night-mode set', 'set needs a temperature.\nExample: horneroctl appearance night-mode set --temperature 3500 --yes')
		}
		temp := night_clamp_temperature(cmd.temperature)
		if cmd.dry_run {
			return ok_result('appearance night-mode set', 'would store ${temp}K${if active {
				' and reapply it now'
			} else {
				' for the next enable'
			}}', {
				'temperature': '${temp}'
				'dry_run':     'true'
			})
		}
		write_night_temperature(temp) or {
			return fail_result('appearance night-mode set', 'cannot persist temperature: ${err.msg()}')
		}
		if active {
			return night_enable_native(cmd.dry_run, mut lines, temp)
		}
		return ok_result('appearance night-mode set', 'Temperature set to ${temp}K; it applies on the next enable.', {
			'temperature': '${temp}'
			'active':      'false'
		})
	}
	if cmd.verb in ['on', 'enable'] {
		temp := if cmd.temperature > 0 {
			night_clamp_temperature(cmd.temperature)
		} else {
			read_night_temperature()
		}
		if active && !cmd.dry_run && cmd.temperature <= 0 {
			return ok_result('appearance night-mode on', 'Night mode is already active.',
				{
					'active':      'true'
					'temperature': '${temp}'
				})
		}
		return night_enable_native(cmd.dry_run, mut lines, temp)
	}
	if cmd.verb in ['off', 'disable'] {
		if !active && !cmd.dry_run {
			return ok_result('appearance night-mode off', 'Night mode is already inactive.',
				{
					'active': 'false'
				})
		}
		return night_disable_native(cmd.dry_run, mut lines)
	}
	if active {
		return night_disable_native(cmd.dry_run, mut lines)
	}
	return night_enable_native(cmd.dry_run, mut lines, read_night_temperature())
}

// night_schedule_run implements schedule set/clear: writes the
// two oneshot services + timers, enables them, and applies the
// current window immediately so setting a schedule at 23:00 for
// 22:00-07:00 turns night light on now, not tomorrow.
fn night_schedule_run(cmd NightModeCmd) CommandResult {
	if cmd.schedule == 'clear' {
		if cmd.dry_run {
			return ok_result('appearance night-mode schedule', 'would disable the hornero-nightlight timers, remove their units, and delete the stored schedule. Current on/off state is left as-is.', {
				'dry_run': 'true'
			})
		}
		if find_on_path('systemctl').len > 0 {
			run_exec(ExecSpec{
				prog:        'systemctl'
				args:        ['--user', 'disable', '--now', night_schedule_unit_name('on', true),
					night_schedule_unit_name('off', true)]
				timeout_sec: 30
			})
		}
		for verb in ['on', 'off'] {
			os.rm(night_schedule_unit_file(verb, true)) or {}
			os.rm(night_schedule_unit_file(verb, false)) or {}
		}
		if find_on_path('systemctl').len > 0 {
			run_exec(ExecSpec{
				prog:        'systemctl'
				args:        ['--user', 'daemon-reload']
				timeout_sec: 30
			})
		}
		clear_night_schedule()
		return ok_result('appearance night-mode schedule', 'Schedule cleared; timers disabled and units removed. Current night light state is unchanged.', {
			'schedule': ''
		})
	}
	if cmd.schedule != 'set' {
		return fail_result('appearance night-mode schedule', 'unknown schedule action: ${cmd.schedule}.\nExample: horneroctl appearance night-mode schedule set --from 22:00 --to 07:00 --yes')
	}
	if cmd.from_min < 0 || cmd.to_min < 0 {
		return fail_result('appearance night-mode schedule', 'schedule set needs --from and --to.\nExample: horneroctl appearance night-mode schedule set --from 22:00 --to 07:00 --yes')
	}
	if cmd.from_min == cmd.to_min {
		return fail_result('appearance night-mode schedule', 'schedule window is empty (--from equals --to). Pick two different times.')
	}
	from := night_format_hhmm(cmd.from_min)
	to := night_format_hhmm(cmd.to_min)
	if cmd.dry_run {
		return ok_result('appearance night-mode schedule', 'would store ${from}-${to}, write the hornero-nightlight user timers, and apply the current window now.', {
			'schedule': '${from}-${to}'
			'dry_run':  'true'
		})
	}
	write_night_schedule(cmd.from_min, cmd.to_min) or {
		return fail_result('appearance night-mode schedule', 'cannot persist schedule: ${err.msg()}')
	}
	mut enforced := false
	if find_on_path('systemctl').len > 0 {
		self := os.executable()
		mut write_err := ''
		for verb, hhmm in {
			'on':  from
			'off': to
		} {
			os.mkdir_all(os.dir(night_schedule_unit_file(verb, true))) or {
				write_err = err.msg()
			}
			os.write_file(night_schedule_unit_file(verb, false), night_schedule_service_content(self,
				verb)) or { write_err = err.msg() }
			os.write_file(night_schedule_unit_file(verb, true), night_schedule_timer_content(hhmm,
				verb)) or { write_err = err.msg() }
		}
		if write_err.len == 0 {
			run_exec(ExecSpec{
				prog:        'systemctl'
				args:        ['--user', 'daemon-reload']
				timeout_sec: 30
			})
			en := run_exec(ExecSpec{
				prog:        'systemctl'
				args:        ['--user', 'enable', '--now', night_schedule_unit_name('on', true),
					night_schedule_unit_name('off', true)]
				timeout_sec: 30
			})
			enforced = en.ok
		}
	}
	now := time.now()
	in_window := night_schedule_active_at(cmd.from_min, cmd.to_min, now.hour * 60 + now.minute)
	active, _ := night_probe_live(false)
	mut applied := 'already matches the window'
	if in_window && !active {
		mut lines := []string{}
		rep := night_enable_native(false, mut lines, read_night_temperature())
		applied = if rep.ok {
			'turned on now (inside the window)'
		} else {
			'wanted on now but: ${rep.message}'
		}
	} else if !in_window && active {
		mut lines := []string{}
		rep := night_disable_native(false, mut lines)
		applied = if rep.ok {
			'turned off now (outside the window)'
		} else {
			'wanted off now but: ${rep.message}'
		}
	}
	msg := if enforced {
		'Schedule set: on at ${from}, off at ${to}, enforced by user timers; ${applied}.'
	} else {
		'Schedule stored (${from}-${to}) but NOT enforced: systemd user timers unavailable here, so nothing will fire at the boundaries. ${applied}.'
	}
	return CommandResult{
		command: 'appearance night-mode schedule'
		ok:      enforced
		message: msg
		data:    {
			'schedule':         '${from}-${to}'
			'scheduleEnforced': '${enforced}'
		}
	}
}

// night_enable_native force-enables via the first available backend
// at the given Kelvin temperature.
fn night_enable_native(dry_run bool, mut lines []string, temp int) CommandResult {
	available := night_backends_available()
	if available.len == 0 && !dry_run {
		return fail_result('appearance night-mode on', 'No supported night mode backends found (want redshift, gammastep, wlsunset, or xrandr).')
	}
	// Dry-run previews against the first-preference placeholder so docs
	// and CI never need a backend installed.
	backend := if available.len > 0 { available[0] } else { 'redshift' }
	night_pkill_best_effort('redshift', false, dry_run, mut lines)
	night_pkill_best_effort('gammastep', false, dry_run, mut lines)
	night_pkill_best_effort('wlsunset', false, dry_run, mut lines)
	kelvin := night_clamp_temperature(temp)
	if backend == 'xrandr' {
		xr := backend_or_empty('HORNERO_XRANDR_BIN', 'xrandr')
		gamma := night_xrandr_gamma(kelvin)
		brightness := if kelvin >= night_max_temperature { '1.0' } else { '0.9' }
		if dry_run {
			lines << strict_command_line(if xr.len > 0 { xr } else { 'xrandr' }, [
				'--output',
				'<display>',
				'--gamma',
				gamma,
				'--brightness',
				brightness,
			])
		} else if xr.len > 0 {
			list := strict_exec(xr, [], false).output
			for display in parse_xrandr_displays(list) {
				strict_exec(xr, ['--output', display, '--gamma', gamma, '--brightness', brightness], false)
				lines << 'xrandr ${display} gamma ${gamma} brightness ${brightness}'
			}
		}
	} else {
		bin_name := if backend == 'wlsunset' {
			'wlsunset'
		} else if backend == 'gammastep' {
			'gammastep'
		} else {
			'redshift'
		}
		bin_env := if backend == 'wlsunset' {
			'HORNERO_WLSUNSET_BIN'
		} else if backend == 'gammastep' {
			'HORNERO_GAMMASSTEP_BIN'
		} else {
			'HORNERO_REDSHIFT_BIN'
		}
		bin := backend_or_empty(bin_env, bin_name)
		rep := spawn_detached(if bin.len > 0 { bin } else { bin_name }, night_backend_temp_args(backend,
			kelvin), dry_run)
		lines << rep.command_line
	}
	night_notify_best_effort('Night Mode', '${backend} enabled at ${kelvin}K', 'weather-clear-night-symbolic',
		dry_run, mut lines)
	lines << 'write enabled to ${resolve_night_state_file()}'
	if dry_run {
		return ok_result('appearance night-mode on', 'would run:\n' + lines.join('\n'),
			{
				'command_line': lines.join('\n')
				'dry_run':      'true'
				'backend':      backend
				'temperature':  '${kelvin}'
			})
	}
	write_night_temperature(kelvin) or {
		return fail_result('appearance night-mode on', 'backend started but temperature persist failed: ${err.msg()}')
	}
	write_night_state_file('enabled') or {
		return fail_result('appearance night-mode on', 'backend started but state persist failed: ${err.msg()}')
	}
	return ok_result('appearance night-mode on', '${backend} enabled (night mode - ${kelvin}K)',
		{
			'backend':     backend
			'temperature': '${kelvin}'
		})
}

// night_disable_native force-disables every backend.
fn night_disable_native(dry_run bool, mut lines []string) CommandResult {
	night_pkill_best_effort('redshift', false, dry_run, mut lines)
	rs := backend_or_empty('HORNERO_REDSHIFT_BIN', 'redshift')
	if rs.len > 0 || dry_run {
		rep := strict_exec(if rs.len > 0 { rs } else { 'redshift' }, ['-x'], dry_run)
		lines << rep.command_line
	}
	night_pkill_best_effort('gammastep', false, dry_run, mut lines)
	gs := backend_or_empty('HORNERO_GAMMASSTEP_BIN', 'gammastep')
	if gs.len > 0 || dry_run {
		rep := strict_exec(if gs.len > 0 { gs } else { 'gammastep' }, ['-x'], dry_run)
		lines << rep.command_line
	}
	night_pkill_best_effort('wlsunset', false, dry_run, mut lines)
	xr := backend_or_empty('HORNERO_XRANDR_BIN', 'xrandr')
	if xr.len > 0 || dry_run {
		if dry_run {
			lines << strict_command_line(if xr.len > 0 { xr } else { 'xrandr' }, [
				'--output',
				'<display>',
				'--gamma',
				'1:1:1',
				'--brightness',
				'1.0',
			])
		} else {
			list := strict_exec(xr, [], false).output
			for display in parse_xrandr_displays(list) {
				strict_exec(xr, ['--output', display, '--gamma', '1:1:1', '--brightness', '1.0'],
					false)
				lines << 'xrandr ${display} gamma reset'
			}
		}
	}
	night_notify_best_effort('Day Mode', 'Night mode force disabled', 'weather-clear-symbolic',
		dry_run, mut lines)
	lines << 'write disabled to ${resolve_night_state_file()}'
	if dry_run {
		return ok_result('appearance night-mode off', 'would run:\n' + lines.join('\n'),
			{
				'command_line': lines.join('\n')
				'dry_run':      'true'
			})
	}
	write_night_state_file('disabled') or {
		return fail_result('appearance night-mode off', 'backends reset but state persist failed: ${err.msg()}')
	}
	return ok_result('appearance night-mode off', 'Night mode disabled on all backends',
		{})
}
