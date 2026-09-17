module hornero_core

import os

// Native night-mode control. Ports dots-night-mode: backend detection
// (redshift/gammastep/wlsunset/xrandr stay external tools with
// HORNERO_*_BIN overrides), hybrid state detection (process table plus
// a state file for daemon ambiguity), and the toggle/enable/disable/
// status/status-icon/status-text/backends verbs.

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

// night_state_file_fallback is the legacy `dots/*` location (reads only).
pub fn night_state_file_fallback() string {
	env := os.getenv('NIGHT_MODE_STATE_FILE')
	if env.len > 0 {
		return env
	}
	mut base := os.getenv('XDG_CACHE_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.cache')
	}
	return os.join_path(base, 'dots', 'night_mode_state')
}

// read_night_state_file returns the state content canonical-first.
pub fn read_night_state_file() string {
	canon := resolve_night_state_file()
	if os.is_file(canon) {
		return (os.read_file(canon) or { '' }).trim_space()
	}
	fb := night_state_file_fallback()
	if os.is_file(fb) {
		return (os.read_file(fb) or { '' }).trim_space()
	}
	return ''
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
	verb    string // toggle | on | off | status | status-icon | status-text | backends
	dry_run bool
	yes     bool
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
			// fully native with zero dots-* calls.
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
			return ok_result('appearance night-mode status', msg, {
				'active':  '${active}'
				'backend': backend
			})
		}
		'toggle', 'auto', 'on', 'enable', 'off', 'disable' {}
		else {
			return fail_result('appearance night-mode', 'unknown action: ${cmd.verb}.\nRun: horneroctl appearance night-mode --help')
		}
	}
	if !cmd.yes && !cmd.dry_run {
		return fail_result('appearance night-mode ${cmd.verb}', 'refusing to change night mode without --yes (preview with --dry-run).\nExample: horneroctl appearance night-mode ${cmd.verb} --dry-run')
	}
	active, _ := night_probe_live(cmd.dry_run)
	mut lines := []string{}
	if cmd.verb in ['on', 'enable'] {
		if active && !cmd.dry_run {
			return ok_result('appearance night-mode on', 'Night mode is already active.', {
				'active': 'true'
			})
		}
		return night_enable_native(cmd.dry_run, mut lines)
	}
	if cmd.verb in ['off', 'disable'] {
		if !active && !cmd.dry_run {
			return ok_result('appearance night-mode off', 'Night mode is already inactive.', {
				'active': 'false'
			})
		}
		return night_disable_native(cmd.dry_run, mut lines)
	}
	if active {
		return night_disable_native(cmd.dry_run, mut lines)
	}
	return night_enable_native(cmd.dry_run, mut lines)
}

// night_enable_native force-enables via the first available backend.
fn night_enable_native(dry_run bool, mut lines []string) CommandResult {
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
	if backend == 'xrandr' {
		xr := backend_or_empty('HORNERO_XRANDR_BIN', 'xrandr')
		if dry_run {
			lines << strict_command_line(if xr.len > 0 { xr } else { 'xrandr' }, [
				'--output',
				'<display>',
				'--gamma',
				'1:0.85:0.6',
				'--brightness',
				'0.9',
			])
		} else if xr.len > 0 {
			list := os.execute(strict_command_line(xr, [])).output
			for display in parse_xrandr_displays(list) {
				strict_exec(xr, ['--output', display, '--gamma', '1:0.85:0.6', '--brightness', '0.9'], false)
				lines << 'xrandr ${display} gamma 1:0.85:0.6 brightness 0.9'
			}
		}
	} else if backend == 'wlsunset' {
		wl := backend_or_empty('HORNERO_WLSUNSET_BIN', 'wlsunset')
		rep := spawn_detached(if wl.len > 0 { wl } else { 'wlsunset' }, ['-T', '4000'], dry_run)
		lines << rep.command_line
	} else if backend == 'gammastep' {
		gs := backend_or_empty('HORNERO_GAMMASSTEP_BIN', 'gammastep')
		rep := spawn_detached(if gs.len > 0 { gs } else { 'gammastep' }, ['-O', '4000K'], dry_run)
		lines << rep.command_line
	} else {
		rs := backend_or_empty('HORNERO_REDSHIFT_BIN', 'redshift')
		rep := spawn_detached(if rs.len > 0 { rs } else { 'redshift' }, ['-O', '4000K'], dry_run)
		lines << rep.command_line
	}
	night_notify_best_effort('Night Mode', '${backend} enabled at 4000K', 'weather-clear-night-symbolic', dry_run, mut lines)
	lines << 'write enabled to ${resolve_night_state_file()}'
	if dry_run {
		return ok_result('appearance night-mode on', 'would run:\n' + lines.join('\n'), {
			'command_line': lines.join('\n')
			'dry_run':      'true'
			'backend':      backend
		})
	}
	write_night_state_file('enabled') or {
		return fail_result('appearance night-mode on', 'backend started but state persist failed: ${err.msg()}')
	}
	return ok_result('appearance night-mode on', '${backend} enabled (night mode - 4000K)', {
		'backend': backend
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
			list := os.execute(strict_command_line(xr, [])).output
			for display in parse_xrandr_displays(list) {
				strict_exec(xr, ['--output', display, '--gamma', '1:1:1', '--brightness', '1.0'], false)
				lines << 'xrandr ${display} gamma reset'
			}
		}
	}
	night_notify_best_effort('Day Mode', 'Night mode force disabled', 'weather-clear-symbolic', dry_run, mut lines)
	lines << 'write disabled to ${resolve_night_state_file()}'
	if dry_run {
		return ok_result('appearance night-mode off', 'would run:\n' + lines.join('\n'), {
			'command_line': lines.join('\n')
			'dry_run':      'true'
		})
	}
	write_night_state_file('disabled') or {
		return fail_result('appearance night-mode off', 'backends reset but state persist failed: ${err.msg()}')
	}
	return ok_result('appearance night-mode off', 'Night mode disabled on all backends', {})
}
