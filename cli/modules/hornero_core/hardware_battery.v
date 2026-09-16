module hornero_core

import os
import time

// Battery backend: threshold monitoring plus a single-shot readout,
// mirroring dots-battery-monitor (poweralertd fast path, else a polling
// loop with notify-send alerts).

// resolve_acpi_bin locates acpi. Override with HORNERO_ACPI_BIN.
pub fn resolve_acpi_bin() string {
	env := os.getenv('HORNERO_ACPI_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('acpi')
}

// resolve_upower_bin locates upower. Override with HORNERO_UPOWER_BIN.
pub fn resolve_upower_bin() string {
	env := os.getenv('HORNERO_UPOWER_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('upower')
}

// resolve_poweralertd_bin locates poweralertd.
// Override with HORNERO_POWERALERTD_BIN.
pub fn resolve_poweralertd_bin() string {
	env := os.getenv('HORNERO_POWERALERTD_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('poweralertd')
}

// resolve_notify_bin locates notify-send. Override with HORNERO_NOTIFY_BIN.
pub fn resolve_notify_bin() string {
	env := os.getenv('HORNERO_NOTIFY_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('notify-send')
}

struct BatteryInfo {
	present bool
	pct     int
	state   string
	backend string
}

// battery_probe_cmd names the first-shot probe for previews: acpi, else
// upower, else an acpi placeholder.
fn battery_probe_cmd() BrightProg {
	acpi := resolve_acpi_bin()
	if acpi.len > 0 {
		return BrightProg{
			prog: acpi
			args: ['-b']
		}
	}
	up := resolve_upower_bin()
	if up.len > 0 {
		return BrightProg{
			prog: up
			args: ['-e']
		}
	}
	return BrightProg{
		prog: 'acpi'
		args: ['-b']
	}
}

// battery_pct_before scans s for the first `<digits>%` occurrence.
fn battery_pct_before(s string) int {
	idx := s.index('%') or { return -1 }
	mut start := idx
	for start > 0 && s[start - 1] >= `0` && s[start - 1] <= `9` {
		start--
	}
	if start == idx {
		return -1
	}
	return s[start..idx].int()
}

// read_battery returns the current charge via acpi, else upower (the
// dots-battery-monitor precedence). present is false on machines with no
// battery instead of the script's 100% fallback.
fn read_battery() !BatteryInfo {
	acpi := resolve_acpi_bin()
	if acpi.len > 0 {
		rep := run_exec(ExecSpec{
			prog: acpi
			args: ['-b']
		})
		if rep.ok {
			mut line := ''
			for l in rep.output.split_into_lines() {
				if l.trim_space().len > 0 {
					line = l
					break
				}
			}
			if line.len == 0 {
				return BatteryInfo{
					present: false
					backend: 'acpi'
				}
			}
			pct := battery_pct_before(line)
			if pct < 0 {
				return BatteryInfo{
					present: false
					backend: 'acpi'
				}
			}
			mut state := 'unknown'
			parts := line.split(':')
			if parts.len >= 2 {
				state = parts[1].split(',')[0].trim_space().to_lower()
				if state.len == 0 {
					state = 'unknown'
				}
			}
			return BatteryInfo{
				present: true
				pct:     pct
				state:   state
				backend: 'acpi'
			}
		}
	}
	up := resolve_upower_bin()
	if up.len > 0 {
		rep := run_exec(ExecSpec{
			prog: up
			args: ['-e']
		})
		if !rep.ok {
			return error('upower probe failed (exit ${rep.exit_code}):\n${rep.output}\nExample: horneroctl hardware battery status')
		}
		mut dev := ''
		for l in rep.output.split_into_lines() {
			if l.contains('battery') {
				dev = l.trim_space()
				break
			}
		}
		if dev.len == 0 {
			return BatteryInfo{
				present: false
				backend: 'upower'
			}
		}
		rep2 := run_exec(ExecSpec{
			prog: up
			args: ['-i', dev]
		})
		if !rep2.ok {
			return error('upower probe failed (exit ${rep2.exit_code}):\n${rep2.output}\nExample: horneroctl hardware battery status')
		}
		mut pct := -1
		mut state := 'unknown'
		for l in rep2.output.split_into_lines() {
			t := l.trim_space()
			if t.starts_with('percentage:') {
				pct = battery_pct_before(t)
			} else if t.starts_with('state:') {
				state = t['state:'.len..].trim_space().to_lower()
			}
		}
		if pct < 0 {
			return BatteryInfo{
				present: false
				backend: 'upower'
			}
		}
		return BatteryInfo{
			present: true
			pct:     pct
			state:   state
			backend: 'upower'
		}
	}
	return error('no battery backend found (needs acpi or upower on PATH). Set HORNERO_ACPI_BIN or HORNERO_UPOWER_BIN.\nExample: horneroctl hardware battery status --dry-run')
}

pub struct BatteryStatusOptions {
pub:
	dry_run bool
}

// battery_status_report implements `hardware battery status` (read-only):
// one charge readout via acpi or upower.
pub fn battery_status_report(opts BatteryStatusOptions) CommandResult {
	if opts.dry_run {
		probe := battery_probe_cmd()
		return ok_result('hardware battery status', 'would run: ${command_line(probe.prog,
			probe.args)}', {
			'command_line': command_line(probe.prog, probe.args)
			'dry_run':      'true'
		})
	}
	info := read_battery() or { return fail_result('hardware battery status', err.msg()) }
	if !info.present {
		return ok_result('hardware battery status', 'battery: none detected (desktop?)',
			{
			'present': 'false'
			'backend': info.backend
		})
	}
	return ok_result('hardware battery status', 'battery: ${info.pct}% (${info.state} via ${info.backend})',
		{
		'present':    'true'
		'percentage': '${info.pct}'
		'state':      info.state
		'backend':    info.backend
	})
}

// hardware_notify sends a best-effort desktop notification, silently
// skipping when notify-send is absent (mirrors `|| true` in the script).
fn hardware_notify(title string, body string, urgency string) {
	bin := resolve_notify_bin()
	if bin.len == 0 {
		return
	}
	run_exec(ExecSpec{
		prog: bin
		args: ['-u', urgency, title, body]
	})
}

pub struct BatteryMonitorOptions {
pub:
	low      int
	crit     int
	interval i64
	daemon   bool
	dry_run  bool
	yes      bool
}

// battery_monitor_report implements `hardware battery monitor`: the
// dots-battery-monitor polling loop (poweralertd fast path, else poll
// every interval seconds with low/critical notifications). With daemon
// set it detaches a background copy of itself via nohup. Long-running:
// needs --yes; --dry-run only previews.
pub fn battery_monitor_report(opts BatteryMonitorOptions) CommandResult {
	if !opts.yes && !opts.dry_run {
		return fail_result('hardware battery monitor', 'refusing to start the battery monitor without --yes (preview with --dry-run).\nExample: horneroctl hardware battery monitor --dry-run')
	}
	self := os.executable()
	detached := 'nohup ${command_line(self, ['hardware', 'battery', 'monitor', '--low=${opts.low}',
		'--crit=${opts.crit}', '--interval=${opts.interval}'])} >/dev/null 2>&1 &'
	if opts.dry_run {
		if opts.daemon {
			return ok_result('hardware battery monitor', 'would run (detached): ${detached}',
				{
				'command_line': detached
				'dry_run':      'true'
			})
		}
		probe := battery_probe_cmd()
		return ok_result('hardware battery monitor', 'would monitor: poll ${command_line(probe.prog,
			probe.args)} every ${opts.interval}s (low<=${opts.low}%, crit<=${opts.crit}%)',
			{
			'command_line': command_line(probe.prog, probe.args)
			'dry_run':      'true'
		})
	}
	if resolve_poweralertd_bin().len > 0 {
		hardware_notify('Battery Monitor', 'poweralertd active (horneroctl monitor idle)',
			'low')
		return ok_result('hardware battery monitor', 'poweralertd active (horneroctl monitor idle)',
			{
			'backend': 'poweralertd'
		})
	}
	if opts.daemon {
		r := os.execute(detached)
		if r.exit_code == 0 {
			return ok_result('hardware battery monitor', 'battery monitor started in background (low<=${opts.low}%, crit<=${opts.crit}%, every ${opts.interval}s)',
				{
				'command_line': detached
				'daemon':       'true'
			})
		}
		return fail_result('hardware battery monitor', 'failed to detach monitor (exit ${r.exit_code}):\n${r.output}')
	}
	mut first_run := true
	for {
		info := read_battery() or { return fail_result('hardware battery monitor', err.msg()) }
		if !info.present {
			return fail_result('hardware battery monitor', 'no battery detected (nothing to monitor).')
		}
		if info.pct <= opts.crit {
			hardware_notify('Battery Critical', '${info.pct}% remaining', 'critical')
		} else if info.pct <= opts.low {
			hardware_notify('Battery Low', '${info.pct}% remaining', 'normal')
		} else if first_run {
			hardware_notify('Battery', '${info.pct}%', 'low')
		}
		first_run = false
		time.sleep(time.Duration(opts.interval) * time.second)
	}
	return fail_result('hardware battery monitor', 'monitor loop ended unexpectedly.')
}
