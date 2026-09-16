module hornero_core

import os

// Network backend: single-shot connectivity probe mirroring
// dots-check-network --once (ping plus interface class). The polling loop
// streams per-poll status-bar icons, which core cannot emit (core never
// prints), so it stays in the dots-check-network shim.

// resolve_ping_bin locates ping. Override with HORNERO_PING_BIN.
pub fn resolve_ping_bin() string {
	env := os.getenv('HORNERO_PING_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('ping')
}

// resolve_ip_bin locates ip. Override with HORNERO_IP_BIN.
pub fn resolve_ip_bin() string {
	env := os.getenv('HORNERO_IP_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('ip')
}

// ping_host returns the probe target: DOTS_PING_HOST, else 1.1.1.1 (the
// dots-check-network default).
pub fn ping_host() string {
	env := os.getenv('DOTS_PING_HOST')
	if env.len > 0 {
		return env
	}
	return '1.1.1.1'
}

// first_up_interface returns the first `state UP` interface name, or ''
// when ip is missing or nothing is up.
fn first_up_interface() string {
	bin := resolve_ip_bin()
	if bin.len == 0 {
		return ''
	}
	rep := run_exec(ExecSpec{
		prog: bin
		args: ['link']
	})
	if !rep.ok {
		return ''
	}
	for line in rep.output.split_into_lines() {
		if line.contains('state UP') {
			mut fields := []string{}
			for f in line.split(' ') {
				if f.len > 0 {
					fields << f
				}
			}
			if fields.len >= 2 {
				return fields[1].trim_right(':')
			}
		}
	}
	return ''
}

pub struct NetworkStatusOptions {
pub:
	timeout int
	dry_run bool
}

// network_status_report implements `hardware network status`
// (read-only): ping the probe host once and classify the first UP
// interface as wired (eth* like the script) or wireless. timeout is the
// ping deadline in seconds (default 5).
pub fn network_status_report(opts NetworkStatusOptions) CommandResult {
	host := ping_host()
	mut timeout := opts.timeout
	if timeout <= 0 {
		timeout = 5
	}
	bin := resolve_ping_bin()
	if opts.dry_run {
		prog := if bin.len > 0 { bin } else { 'ping' }
		return ok_result('hardware network status', 'would run: ${command_line(prog, [
			'-c',
			'1',
			'-W',
			'${timeout}',
			host,
		])}', {
			'command_line': command_line(prog, ['-c', '1', '-W', '${timeout}', host])
			'dry_run':      'true'
		})
	}
	if bin.len == 0 {
		return fail_result('hardware network status', 'ping not found on PATH. Set HORNERO_PING_BIN.\nExample: horneroctl hardware network status --dry-run')
	}
	if bin.contains('/') && !os.is_file(bin) {
		return fail_result('hardware network status', 'ping backend not found (${bin} is not a file). Set HORNERO_PING_BIN.\nExample: horneroctl hardware network status --dry-run')
	}
	rep := run_exec(ExecSpec{
		prog: bin
		args: ['-c', '1', '-W', '${timeout}', host]
	})
	up := rep.ok
	iface := first_up_interface()
	class := if iface.starts_with('e') { 'wired' } else { 'wireless' }
	icon := if up {
		if class == 'wired' { '\uf817' } else { '\uf2a8' }
	} else {
		if class == 'wired' { '\uf818' } else { '\uf2a9' }
	}
	state := if up { 'connected' } else { 'disconnected' }
	via := if iface.len > 0 { ' via ${iface} (${class})' } else { ' (${class}, interface unknown)' }
	return ok_result('hardware network status', '${icon} ${state}${via} (host ${host})',
		{
		'state':     state
		'interface': if iface.len > 0 { iface } else { 'unknown' }
		'class':     class
		'host':      host
	})
}
