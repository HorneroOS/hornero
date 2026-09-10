module hornero_core

import os

// resolve_qs_bin locates the Quickshell CLI. Override with HORNERO_QS_BIN.
pub fn resolve_qs_bin() string {
	env := os.getenv('HORNERO_QS_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('qs')
}

pub struct IpcOptions {
pub:
	passthrough []string
	dry_run     bool
	qs_bin      string
}

// shell_status reports whether a live shell session is reachable.
pub fn shell_status() CommandResult {
	sig := os.getenv('HYPRLAND_INSTANCE_SIGNATURE')
	qs := resolve_qs_bin()
	mut lines := []string{}
	mut data := map[string]string{}
	if sig.len > 0 {
		lines << 'compositor: Hyprland instance signature is set'
		data['compositor'] = 'hyprland'
	} else {
		lines << 'compositor: no Hyprland instance signature (not in a Hyprland session?)'
		data['compositor'] = 'unknown'
	}
	if qs.len > 0 {
		lines << 'quickshell-cli: ${qs}'
		data['qs'] = qs
	} else {
		lines << 'quickshell-cli: qs not found (set HORNERO_QS_BIN)'
		data['qs'] = 'missing'
	}
	return ok_result('shell status', lines.join('\n'), data)
}

// ipc_report runs `qs ipc <passthrough>` or previews it with --dry-run.
pub fn ipc_report(opts IpcOptions) CommandResult {
	bin := if opts.qs_bin.len > 0 { opts.qs_bin } else { resolve_qs_bin() }
	if bin.len == 0 {
		return fail_result('shell ipc', 'qs not found on PATH. Set HORNERO_QS_BIN.\nExample: horneroctl shell ipc --dry-run -- show')
	}
	mut args := ['ipc']
	args << opts.passthrough
	rep := run_exec(ExecSpec{
		prog: bin
		args: args
		dry_run: opts.dry_run
	})
	if opts.dry_run {
		return ok_result('shell ipc', 'would run: ${rep.command_line}', {
			'command_line': rep.command_line
			'dry_run':      'true'
		})
	}
	if rep.ok {
		return ok_result('shell ipc', rep.output, {
			'command_line': rep.command_line
		})
	}
	return fail_result('shell ipc', 'qs ipc failed (exit ${rep.exit_code}):\n${rep.output}')
}
