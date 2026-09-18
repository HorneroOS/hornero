module hornero_core

import os

// Hardware backends: display brightness, battery, microphone, keyboard,
// and network state. Every leaf mirrors a dots-* reference script
// (dots-brightness, dots-battery-monitor, dots-microphone,
// dots-keyboard-layout, dots-keyboard-settings, dots-keyboard-help,
// dots-check-network): reads report backend state, mutations delegate to
// the same backend CLIs with --yes gating and --dry-run previews.

// resolve_brightnessctl_bin locates brightnessctl.
// Override with HORNERO_BRIGHTNESSCTL_BIN.
pub fn resolve_brightnessctl_bin() string {
	env := os.getenv('HORNERO_BRIGHTNESSCTL_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('brightnessctl')
}

// resolve_blight_bin locates blight. Override with HORNERO_BLIGHT_BIN.
pub fn resolve_blight_bin() string {
	env := os.getenv('HORNERO_BLIGHT_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('blight')
}

// resolve_xbacklight_bin locates xbacklight.
// Override with HORNERO_XBACKLIGHT_BIN.
pub fn resolve_xbacklight_bin() string {
	env := os.getenv('HORNERO_XBACKLIGHT_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('xbacklight')
}

// resolve_xrandr_bin locates xrandr. Override with HORNERO_XRANDR_BIN.
pub fn resolve_xrandr_bin() string {
	env := os.getenv('HORNERO_XRANDR_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('xrandr')
}

// is_decimal_number reports whether s is a plain non-negative decimal
// literal (digits with at most one dot, at least one digit).
pub fn is_decimal_number(s string) bool {
	if s.len == 0 {
		return false
	}
	mut dots := 0
	mut digits := 0
	for c in s {
		if c == `.` {
			dots++
			if dots > 1 {
				return false
			}
			continue
		}
		if c < `0` || c > `9` {
			return false
		}
		digits++
	}
	return digits > 0
}

// brightness_backend picks the display-brightness backend in the same
// precedence as dots-brightness: brightnessctl, blight, xbacklight,
// then xrandr. Returns '' when none is available.
fn brightness_backend() string {
	if resolve_brightnessctl_bin().len > 0 {
		return 'brightnessctl'
	}
	if resolve_blight_bin().len > 0 {
		return 'blight'
	}
	if resolve_xbacklight_bin().len > 0 {
		return 'xbacklight'
	}
	if resolve_xrandr_bin().len > 0 {
		return 'xrandr'
	}
	return ''
}

fn brightness_bin(backend string) string {
	match backend {
		'brightnessctl' {
			return resolve_brightnessctl_bin()
		}
		'blight' {
			return resolve_blight_bin()
		}
		'xbacklight' {
			return resolve_xbacklight_bin()
		}
		'xrandr' {
			return resolve_xrandr_bin()
		}
		else {
			return ''
		}
	}
}

struct BrightProg {
	prog string
	args []string
}

// default_display returns the first connected output from xrandr, or ''
// when xrandr is missing or nothing is connected.
fn default_display() string {
	xr := resolve_xrandr_bin()
	if xr.len == 0 {
		return ''
	}
	rep := run_exec(ExecSpec{
		prog: xr
		args: []string{}
	})
	if !rep.ok {
		return ''
	}
	for line in rep.output.split_into_lines() {
		mut fields := []string{}
		for f in line.split(' ') {
			if f.len > 0 {
				fields << f
			}
		}
		if fields.len >= 2 && fields[1] == 'connected' {
			return fields[0]
		}
	}
	return ''
}

// brightness_probe_cmd builds the read probe for a backend/display pair.
// With dry_run set a missing backend previews as a brightnessctl
// placeholder instead of failing.
fn brightness_probe_cmd(backend string, display string, dry_run bool) BrightProg {
	if backend == '' {
		return BrightProg{
			prog: 'brightnessctl'
			args: ['-m']
		}
	}
	_ = dry_run
	bin := brightness_bin(backend)
	match backend {
		'brightnessctl' {
			if display.len > 0 {
				return BrightProg{
					prog: bin
					args: ['-m', '-d', display]
				}
			}
			return BrightProg{
				prog: bin
				args: ['-m']
			}
		}
		'blight' {
			return BrightProg{
				prog: bin
				args: ['get']
			}
		}
		'xbacklight' {
			return BrightProg{
				prog: bin
				args: ['-get', '-display', display]
			}
		}
		else {
			return BrightProg{
				prog: bin
				args: ['--verbose']
			}
		}
	}
}

// brightness_clamp folds a fraction into the 0.0-1.0 range, mirroring the
// dots-brightness exec_op clamp.
fn brightness_clamp(v f64) f64 {
	if v < 0.0 {
		return 0.0
	}
	if v > 1.0 {
		return 1.0
	}
	return v
}

// brightness_set_cmd builds the absolute-set invocation for a 0.0-1.0
// fraction. brightnessctl and xbacklight take percent, xrandr takes the
// fraction, blight takes raw device units (dots-brightness arithmetic).
fn brightness_set_cmd(backend string, value f64, display string, dry_run bool) !BrightProg {
	v := brightness_clamp(value)
	pct := int(v * 100.0 + 0.5)
	if backend == '' {
		if dry_run {
			return BrightProg{
				prog: 'brightnessctl'
				args: ['-q', 'set', '${pct}%']
			}
		}
		return error('no brightness backend found (needs brightnessctl, blight, xbacklight, or xrandr). Set HORNERO_BRIGHTNESSCTL_BIN.\nExample: horneroctl hardware brightness status --dry-run')
	}
	bin := brightness_bin(backend)
	match backend {
		'brightnessctl' {
			return BrightProg{
				prog: bin
				args: ['-q', 'set', '${pct}%']
			}
		}
		'blight' {
			raw := int(v * 100000.0 + 0.5)
			return BrightProg{
				prog: bin
				args: ['set', '${raw}']
			}
		}
		'xbacklight' {
			return BrightProg{
				prog: bin
				args: ['-display', display, '-set', '${pct}']
			}
		}
		else {
			return BrightProg{
				prog: bin
				args: ['--output', display, '--brightness', v.str()]
			}
		}
	}
}

// frac_from_pct parses a percent number (without the % sign) into a
// 0.0-1.0 fraction.
fn frac_from_pct(s string) !f64 {
	t := s.trim_space()
	if !is_decimal_number(t) {
		return error('could not parse brightness value: ${t}.\nExample: horneroctl hardware brightness status')
	}
	return t.f64() / 100.0
}

// xrandr_brightness extracts the Brightness value for one display from
// `xrandr --verbose` output.
fn xrandr_brightness(output string, display string) !f64 {
	mut cur := ''
	for line in output.split_into_lines() {
		mut fields := []string{}
		for f in line.split(' ') {
			if f.len > 0 {
				fields << f
			}
		}
		if fields.len >= 2 && fields[1] == 'connected' {
			cur = fields[0]
			continue
		}
		t := line.trim_space()
		if cur == display && t.starts_with('Brightness:') {
			val := t['Brightness:'.len..].trim_space()
			if !is_decimal_number(val) {
				return error('could not parse brightness value: ${val}.\nExample: horneroctl hardware brightness status')
			}
			return val.f64()
		}
	}
	return error('no brightness value for display ${display}.\nExample: horneroctl hardware brightness status')
}

// xrandr_list_brightness maps every connected display to its Brightness
// value from `xrandr --verbose` output.
fn xrandr_list_brightness(output string) map[string]string {
	mut found := map[string]string{}
	mut cur := ''
	for line in output.split_into_lines() {
		mut fields := []string{}
		for f in line.split(' ') {
			if f.len > 0 {
				fields << f
			}
		}
		if fields.len >= 2 && fields[1] == 'connected' {
			cur = fields[0]
			continue
		}
		t := line.trim_space()
		if cur.len > 0 && t.starts_with('Brightness:') {
			found[cur] = t['Brightness:'.len..].trim_space()
		}
	}
	return found
}

// brightness_read_current returns the current brightness as a 0.0-1.0
// fraction, or an error naming the failing probe.
fn brightness_read_current(backend string, display string) !f64 {
	probe := brightness_probe_cmd(backend, display, false)
	rep := run_exec(ExecSpec{
		prog: probe.prog
		args: probe.args
	})
	if !rep.ok {
		return error('brightness probe failed (exit ${rep.exit_code}):\n${rep.output}\nExample: horneroctl hardware brightness status')
	}
	match backend {
		'brightnessctl' {
			for line in rep.output.split_into_lines() {
				mut f := []string{}
				for part in line.split(',') {
					f << part.trim_space()
				}
				if f.len >= 4 {
					return frac_from_pct(f[3].trim_right('%'))!
				}
			}
			return error('could not parse brightnessctl output.\nExample: horneroctl hardware brightness status')
		}
		'blight' {
			val := rep.output.trim_space()
			if !is_decimal_number(val) {
				return error('could not parse blight output: ${val}.\nExample: horneroctl hardware brightness status')
			}
			return val.f64() / 100000.0
		}
		'xbacklight' {
			val := rep.output.trim_space()
			if !is_decimal_number(val) {
				return error('could not parse xbacklight output: ${val}.\nExample: horneroctl hardware brightness status')
			}
			return val.f64() / 100.0
		}
		else {
			return xrandr_brightness(rep.output, display)!
		}
	}
}

pub struct BrightnessStatusOptions {
pub:
	display string
	dry_run bool
}

// brightness_status_report implements `hardware brightness status`
// (read-only): current brightness via the picked backend. Without
// --display, brightnessctl/blight report the global device(s) while
// xrandr lists every connected display (dots-brightness --list).
pub fn brightness_status_report(opts BrightnessStatusOptions) CommandResult {
	backend := brightness_backend()
	if opts.dry_run {
		probe := brightness_probe_cmd(backend, opts.display, true)
		return ok_result('hardware brightness status', 'would run: ${command_line(probe.prog, probe.args)}', {
			'command_line': command_line(probe.prog, probe.args)
			'dry_run':      'true'
		})
	}
	if backend == '' {
		return fail_result('hardware brightness status', 'no brightness backend found (needs brightnessctl, blight, xbacklight, or xrandr). Set HORNERO_BRIGHTNESSCTL_BIN.\nExample: horneroctl hardware brightness status --dry-run')
	}
	mut disp := opts.display
	if disp == '' && backend == 'xbacklight' {
		d := default_display()
		if d == '' {
			return fail_result('hardware brightness status', 'no display selected (xbacklight needs one; pass --display NAME).\nExample: horneroctl hardware brightness status --display eDP-1')
		}
		disp = d
	}
	probe := brightness_probe_cmd(backend, disp, false)
	rep := run_exec(ExecSpec{
		prog: probe.prog
		args: probe.args
	})
	if !rep.ok {
		return fail_result('hardware brightness status', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
	}
	mut lines := []string{}
	mut data := map[string]string{}
	data['backend'] = backend
	match backend {
		'brightnessctl' {
			for line in rep.output.split_into_lines() {
				mut f := []string{}
				for part in line.split(',') {
					f << part.trim_space()
				}
				if f.len >= 4 {
					name := if disp.len > 0 { disp } else { f[0] }
					lines << 'display: ${name} brightness: ${f[3]}'
				}
			}
			if lines.len == 0 {
				return fail_result('hardware brightness status', 'could not parse brightnessctl output:\n${rep.output}')
			}
			data['display'] = if disp.len > 0 { disp } else { 'all' }
		}
		'blight' {
			val := rep.output.trim_space()
			lines << 'brightness: ${val} (device units via blight)'
			data['display'] = 'global'
			data['value'] = val
		}
		'xbacklight' {
			val := rep.output.trim_space()
			lines << 'display: ${disp} brightness: ${val}%'
			data['display'] = disp
			data['value'] = val
		}
		else {
			if disp.len > 0 {
				cur := xrandr_brightness(rep.output, disp) or {
					return fail_result('hardware brightness status', err.msg())
				}
				lines << 'display: ${disp} brightness: ${cur.str()}'
				data['display'] = disp
				data['value'] = cur.str()
			} else {
				found := xrandr_list_brightness(rep.output)
				if found.len == 0 {
					return fail_result('hardware brightness status', 'no connected displays with brightness values.\nExample: horneroctl hardware brightness status --display eDP-1')
				}
				for name, val in found {
					lines << 'display: ${name} brightness: ${val}'
				}
				data['display'] = 'all'
			}
		}
	}
	return ok_result('hardware brightness status', lines.join('\n'), data)
}

pub struct BrightnessSetOptions {
pub:
	value   f64
	display string
	dry_run bool
	yes     bool
}

// brightness_set_report implements `hardware brightness set <0.0-1.0>`
// by delegating to the picked backend. The fraction is clamped into
// range like dots-brightness. Mutating: needs --yes; --dry-run previews.
pub fn brightness_set_report(opts BrightnessSetOptions) CommandResult {
	if !opts.yes && !opts.dry_run {
		return fail_result('hardware brightness set', 'refusing to set brightness without --yes (preview with --dry-run).\nExample: horneroctl hardware brightness set 0.8 --dry-run')
	}
	backend := brightness_backend()
	mut disp := opts.display
	if backend in ['xbacklight', 'xrandr'] && disp == '' {
		if opts.dry_run {
			disp = 'DISPLAY'
		} else {
			d := default_display()
			if d == '' {
				return fail_result('hardware brightness set', 'no display selected (pass --display NAME).\nExample: horneroctl hardware brightness set 0.8 --display eDP-1 --dry-run')
			}
			disp = d
		}
	}
	cmd := brightness_set_cmd(backend, opts.value, disp, opts.dry_run) or {
		return fail_result('hardware brightness set', err.msg())
	}
	rep := run_exec(ExecSpec{
		prog:    cmd.prog
		args:    cmd.args
		dry_run: opts.dry_run
	})
	if opts.dry_run {
		return ok_result('hardware brightness set', 'would run: ${rep.command_line}',
			{
				'command_line': rep.command_line
				'dry_run':      'true'
			})
	}
	if rep.ok {
		v := brightness_clamp(opts.value)
		return ok_result('hardware brightness set', 'brightness set to ${v.str()} via ${backend}',
			{
				'command_line': rep.command_line
				'value':        v.str()
			})
	}
	return fail_result('hardware brightness set', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
}

pub struct BrightnessAdjustOptions {
pub:
	dir     string // up | down
	step    f64
	display string
	dry_run bool
	yes     bool
}

// brightness_adjust_report implements `hardware brightness up|down` via
// read-compute-set: read the current fraction, shift it by step, clamp
// into 0.0-1.0, and set the result. In dry-run mode nothing executes:
// the preview names the read probe plus the intended shift. Mutating:
// needs --yes.
pub fn brightness_adjust_report(opts BrightnessAdjustOptions) CommandResult {
	if opts.dir !in ['up', 'down'] {
		return fail_result('hardware brightness', 'unknown brightness action: ${opts.dir}.\nRun: horneroctl hardware brightness --help')
	}
	if !opts.yes && !opts.dry_run {
		return fail_result('hardware brightness ${opts.dir}', 'refusing to adjust brightness without --yes (preview with --dry-run).\nExample: horneroctl hardware brightness ${opts.dir} --dry-run')
	}
	backend := brightness_backend()
	mut disp := opts.display
	if backend in ['xbacklight', 'xrandr'] && disp == '' {
		if opts.dry_run {
			disp = 'DISPLAY'
		} else {
			d := default_display()
			if d == '' {
				return fail_result('hardware brightness ${opts.dir}', 'no display selected (pass --display NAME).\nExample: horneroctl hardware brightness ${opts.dir} --display eDP-1 --dry-run')
			}
			disp = d
		}
	}
	sign := if opts.dir == 'up' { '+' } else { '-' }
	if opts.dry_run {
		probe := brightness_probe_cmd(backend, disp, true)
		return ok_result('hardware brightness ${opts.dir}', 'would run: ${command_line(probe.prog, probe.args)}, then set brightness ${sign}${opts.step.str()} (clamped 0.0-1.0)',
			{
				'read_command': command_line(probe.prog, probe.args)
				'direction':    opts.dir
				'step':         opts.step.str()
				'dry_run':      'true'
			})
	}
	if backend == '' {
		return fail_result('hardware brightness ${opts.dir}', 'no brightness backend found (needs brightnessctl, blight, xbacklight, or xrandr). Set HORNERO_BRIGHTNESSCTL_BIN.\nExample: horneroctl hardware brightness status --dry-run')
	}
	cur := brightness_read_current(backend, disp) or {
		return fail_result('hardware brightness ${opts.dir}', err.msg())
	}
	target := if opts.dir == 'up' {
		brightness_clamp(cur + opts.step)
	} else {
		brightness_clamp(cur - opts.step)
	}
	cmd := brightness_set_cmd(backend, target, disp, false) or {
		return fail_result('hardware brightness ${opts.dir}', err.msg())
	}
	rep := run_exec(ExecSpec{
		prog: cmd.prog
		args: cmd.args
	})
	if rep.ok {
		return ok_result('hardware brightness ${opts.dir}', 'brightness ${cur.str()} -> ${target.str()} via ${backend}',
			{
				'command_line': rep.command_line
				'value':        target.str()
			})
	}
	return fail_result('hardware brightness ${opts.dir}', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
}

// brightness_gamma_ramps maps color temperature to xrandr gamma triplets
// (3000K to 10000K, cribbed from redshift like dots-brightness). The
// temperature scale is the ramp index over 10 (0.0-1.0 in 0.1 steps).
const brightness_gamma_ramps = ['1.0:0.7:0.4', '1.0:0.7:0.5', '1.0:0.8:0.6', '1.0:0.8:0.7',
	'1.0:0.9:0.8', '1.0:0.9:0.9', '1.0:1.0:1.0', '0.9:0.9:1.0', '0.8:0.9:1.0', '0.8:0.8:1.0',
	'0.7:0.8:1.0']

const brightness_temp_kelvin = [3000, 3500, 4000, 4500, 5000, 6000, 6500, 7000, 8000, 9000, 10000]

// brightness_temp_of_gamma maps a corrected gamma triplet to its
// temperature (ramp index over 10), or -1.0 when it matches nothing.
pub fn brightness_temp_of_gamma(gamma string) f64 {
	for i, ramp in brightness_gamma_ramps {
		if ramp == gamma {
			return f64(i) / 10.0
		}
	}
	return -1.0
}

// brightness_ramp_idx maps a temperature to its ramp index, clamped
// into range like dots-brightness.
fn brightness_ramp_idx(temp f64) int {
	mut idx := int(temp * 10.0)
	if idx < 0 {
		idx = 0
	}
	if idx > 10 {
		idx = 10
	}
	return idx
}

// brightness_gamma_of_temp maps a temperature to its gamma triplet.
pub fn brightness_gamma_of_temp(temp f64) string {
	return brightness_gamma_ramps[brightness_ramp_idx(temp)]
}

// brightness_temp_kelvin_of maps a temperature to its label in kelvin.
pub fn brightness_temp_kelvin_of(temp f64) int {
	return brightness_temp_kelvin[brightness_ramp_idx(temp)]
}

// brightness_invert_gamma corrects the xrandr --verbose Gamma readout,
// which reports inverted values (1/x per channel, one decimal).
pub fn brightness_invert_gamma(gamma string) !string {
	parts := gamma.split(':')
	if parts.len != 3 {
		return error('could not parse gamma value: ${gamma}.\nExample: horneroctl hardware brightness status --display eDP-1')
	}
	mut out := []string{}
	for p in parts {
		v := p.f64()
		if v == 0.0 {
			return error('could not parse gamma value: ${gamma}.\nExample: horneroctl hardware brightness status --display eDP-1')
		}
		out << '${1.0 / v:.1f}'
	}
	return out.join(':')
}

// brightness_read_gamma returns the corrected gamma triplet of one
// display from `xrandr --verbose`.
fn brightness_read_gamma(xr string, display string) !string {
	rep := run_exec(ExecSpec{
		prog: xr
		args: ['--verbose']
	})
	if !rep.ok {
		return error('xrandr --verbose failed (exit ${rep.exit_code}):\n${rep.output}')
	}
	mut cur := ''
	for line in rep.output.split_into_lines() {
		fields := line.fields()
		if fields.len >= 2 && fields[1] == 'connected' {
			cur = fields[0]
			continue
		}
		t := line.trim_space()
		if cur == display && t.starts_with('Gamma:') {
			return brightness_invert_gamma(t['Gamma:'.len..].trim_space())
		}
	}
	return error('no gamma value for display ${display}.\nExample: horneroctl hardware brightness status --display ${display}')
}

pub struct BrightnessTempOptions {
pub:
	op      string // set | up | down
	value   f64    // set target / up-down step
	display string
	dry_run bool
	yes     bool
}

// brightness_temp_report implements `hardware brightness set|up|down
// --temp`: color temperature on the 0.0-1.0 ramp scale via xrandr
// --gamma, mirroring dots-brightness --temp. Mutating: needs --yes;
// --dry-run previews the read plus the exact gamma command.
pub fn brightness_temp_report(opts BrightnessTempOptions) CommandResult {
	name := 'hardware brightness ${opts.op}'
	if !opts.yes && !opts.dry_run {
		return fail_result(name, 'refusing to set temperature without --yes (preview with --dry-run).\nExample: horneroctl hardware brightness ${opts.op} --temp --dry-run')
	}
	xr := resolve_xrandr_bin()
	mut disp := opts.display
	if disp == '' {
		if opts.dry_run {
			disp = 'DISPLAY'
		} else {
			d := default_display()
			if d == '' {
				return fail_result(name, 'no display selected (pass --display NAME).\nExample: horneroctl hardware brightness ${opts.op} --temp --display eDP-1 --dry-run')
			}
			disp = d
		}
	}
	mut prog := xr
	if prog.len == 0 {
		if opts.dry_run {
			prog = 'xrandr'
		} else {
			return fail_result(name, 'xrandr not found (temperature needs xrandr). Set HORNERO_XRANDR_BIN.\nExample: horneroctl hardware brightness ${opts.op} --temp --dry-run')
		}
	}
	if opts.dry_run {
		probe := command_line(prog, ['--verbose'])
		intent := if opts.op == 'set' {
			'set temperature ${opts.value.str()} (${brightness_temp_kelvin_of(opts.value)}K)'
		} else {
			sign := if opts.op == 'up' { '+' } else { '-' }
			'shift temperature ${sign}${opts.value.str()} (clamped 0.0-1.0)'
		}
		return ok_result(name, 'would run: ${probe}, then ${intent}', {
			'read_command': probe
			'direction':    opts.op
			'step':         opts.value.str()
			'dry_run':      'true'
			'display':      disp
		})
	}
	mut target := opts.value
	if opts.op in ['up', 'down'] {
		cur_gamma := brightness_read_gamma(prog, disp) or { return fail_result(name, err.msg()) }
		cur := brightness_temp_of_gamma(cur_gamma)
		if cur < 0.0 {
			return fail_result(name, 'current gamma ${cur_gamma} matches no known ramp on ${disp}.')
		}
		target = if opts.op == 'up' { cur + opts.value } else { cur - opts.value }
	}
	target = brightness_clamp(target)
	gamma := brightness_gamma_of_temp(target)
	rep := run_exec(ExecSpec{
		prog: prog
		args: ['--output', disp, '--gamma', gamma]
	})
	if !rep.ok {
		return fail_result(name, 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
	}
	k := brightness_temp_kelvin_of(target)
	return ok_result(name, 'temperature set to ${target.str()} (${k}K) on ${disp} via xrandr',
		{
			'command_line': rep.command_line
			'value':        target.str()
			'kelvin':       k.str()
			'display':      disp
		})
}
