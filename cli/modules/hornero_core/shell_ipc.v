module hornero_core

import os

// resolve_qs_bin locates the Quickshell CLI. Override with HORNERO_QS_BIN.
pub fn resolve_qs_bin() string {
	ensure_quickshell_ipc_config()
	env := os.getenv('HORNERO_QS_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('qs')
}

// Quickshell's IPC CLI selects an instance by its config path. Desktop
// compositors launch horneroctl as a sibling process, so they do not inherit
// QS_CONFIG_PATH from the Shell process that horneroctl shell start set.
// Resolve the same packaged/user config before every CLI-originated IPC call.
pub fn ensure_quickshell_ipc_config() {
	if os.getenv('QS_CONFIG_PATH').len > 0 {
		return
	}
	config_path := os.join_path(resolve_quickshell_config_dir(), 'shell.qml')
	if os.is_file(config_path) {
		os.setenv('QS_CONFIG_PATH', config_path, true)
	}
}

pub struct IpcOptions {
pub:
	passthrough []string
	dry_run     bool
	qs_bin      string
}

// shell_ipc_bypassed provides a deterministic opt-out for headless callers.
pub fn shell_ipc_bypassed() bool {
	return os.getenv('HORNERO_BYPASS_QUICKSHELL') == '1'
}

// shell_status reports whether a live shell session is reachable.
pub fn shell_status() CommandResult {
	compositor := active_compositor()
	qs := resolve_qs_bin()
	mut lines := []string{}
	mut data := map[string]string{}
	lines << 'compositor: ${compositor}'
	data['compositor'] = compositor
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
// Dry-run never needs the backend installed: it previews the planned call.
pub fn ipc_report(opts IpcOptions) CommandResult {
	ensure_quickshell_ipc_config()
	mut bin := if opts.qs_bin.len > 0 { opts.qs_bin } else { resolve_qs_bin() }
	if bin.len == 0 && !opts.dry_run {
		return fail_result('shell ipc', 'qs not found on PATH. Set HORNERO_QS_BIN.\nExample: horneroctl shell ipc --dry-run -- show')
	}
	bin = if bin.len > 0 { bin } else { 'qs' }
	mut args := ['ipc']
	args << opts.passthrough
	rep := run_exec(ExecSpec{
		prog:    bin
		args:    args
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
