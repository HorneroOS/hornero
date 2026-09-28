module hornero_core

import os
import time

// Shell lifecycle backend: quickshell process management ported from the
// `dots-quickshell` reference script (start/stop/restart/status).
//
// Semantics preserved from the script:
// - `start` refuses when a shell is already running, requires the
//   quickshell config directory, launches detached, waits ~1s, then
//   verifies the process exists.
// - `stop` is a no-op success when nothing runs, otherwise tries the
//   graceful `quickshell kill` first, waits ~1s, and escalates to
//   SIGKILL (`pkill -9 -x qs|quickshell`) when needed.
// - `restart` is stop, wait ~1s, start.
// - `logs` tails the shell log file the `start` leaf writes (the legacy
//   script discarded stdout to /dev/null; here it is kept so `logs`
//   has something to show).
//
// Mutations need --yes; --dry-run only previews (and never touches the
// process table, so dry-run tests stay CI-hermetic).

// resolve_quickshell_bin lives in appearance_apply.v (single definition:
// HORNERO_QUICKSHELL_BIN, else quickshell, else qs).

// resolve_pgrep_bin locates pgrep for process-table checks.
// Override with HORNERO_PGREP_BIN (tests point it at /bin/true|false).
pub fn resolve_pgrep_bin() string {
	env := os.getenv('HORNERO_PGREP_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('pgrep')
}

// resolve_quickshell_config_dir locates the quickshell config directory
// `start` requires. Override with HORNERO_QUICKSHELL_CONFIG_DIR.
pub fn resolve_quickshell_config_dir() string {
	env := os.getenv('HORNERO_QUICKSHELL_CONFIG_DIR')
	if env.len > 0 {
		return env
	}
	mut base := os.getenv('XDG_CONFIG_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.config')
	}
	return os.join_path(base, 'quickshell')
}

// resolve_shell_log_file locates the shell log `start` appends to and
// `logs` tails. Override with HORNERO_SHELL_LOG_FILE.
pub fn resolve_shell_log_file() string {
	env := os.getenv('HORNERO_SHELL_LOG_FILE')
	if env.len > 0 {
		return env
	}
	mut base := os.getenv('XDG_STATE_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.local', 'state')
	}
	return os.join_path(base, 'hornero', 'quickshell.log')
}

// shell_is_running reports whether a quickshell process exists,
// mirroring the script (`pgrep -x qs || pgrep -x quickshell`).
pub fn shell_is_running() bool {
	bin := resolve_pgrep_bin()
	if bin.len == 0 {
		return false
	}
	for name in ['qs', 'quickshell'] {
		rep := run_exec(ExecSpec{
			prog: bin
			args: ['-x', name]
		})
		if rep.ok {
			return true
		}
	}
	return false
}

// shell_running_pids returns the PIDs of live quickshell processes.
fn shell_running_pids() []string {
	bin := resolve_pgrep_bin()
	if bin.len == 0 {
		return []
	}
	mut pids := []string{}
	for name in ['qs', 'quickshell'] {
		rep := run_exec(ExecSpec{
			prog: bin
			args: ['-x', name]
		})
		if rep.ok {
			for line in rep.output.split_into_lines() {
				t := line.trim_space()
				if t.len > 0 && t !in pids {
					pids << t
				}
			}
		}
	}
	return pids
}

fn quickshell_or_fail(leaf string, dry_run bool) !string {
	bin := resolve_quickshell_bin()
	if bin.len == 0 {
		if dry_run {
			return 'quickshell'
		}
		return error('quickshell not found on PATH. Set HORNERO_QUICKSHELL_BIN.\nExample: horneroctl shell ${leaf} --dry-run')
	}
	return bin
}

// shell_start_env applies the launcher environment the legacy script
// exports (QML import paths, plugin path, Qt platform theme), keeping
// any caller-provided values.
fn shell_start_env() {
	if os.getenv('QML_IMPORT_PATH').len == 0 {
		home := os.home_dir()
		os.setenv('QML_IMPORT_PATH', os.join_path(home, '.local', 'lib', 'quickshell', 'qml') +
			':' + os.join_path(home, '.local', 'usr', 'lib', 'qt6', 'qml'), true)
	}
	mut xdg_config := os.getenv('XDG_CONFIG_HOME')
	if xdg_config.len == 0 {
		xdg_config = os.join_path(os.home_dir(), '.config')
	}
	qs_conf := os.join_path(xdg_config, 'quickshell')
	qml2 := os.getenv('QML2_IMPORT_PATH')
	if qml2.len == 0 {
		os.setenv('QML2_IMPORT_PATH',
			os.join_path(os.home_dir(), '.local', 'usr', 'lib', 'qt6', 'qml') + ':' + qs_conf,
			true)
	} else if !qml2.split(':').contains(qs_conf) {
		os.setenv('QML2_IMPORT_PATH', qml2 + ':' + qs_conf, true)
	}
	if os.getenv('QS_PLUGIN_PATH').len == 0 {
		os.setenv('QS_PLUGIN_PATH', os.join_path(os.home_dir(), '.local', 'lib', 'quickshell'),
			true)
	}
	if os.getenv('QT_QPA_PLATFORMTHEME').len == 0 {
		mut theme := os.getenv('QUICKSHELL_QT_PLATFORM_THEME')
		if theme.len == 0 {
			theme = 'gtk3'
		}
		os.setenv('QT_QPA_PLATFORMTHEME', theme, true)
	}
}

pub struct ShellStartOptions {
pub:
	dry_run bool
	yes     bool
	bin     string // explicit override (tests); else resolution
	force   bool   // skip the already-running guard (restart: the only
	// quickshell present is its own reload cover, same process name)
}

// shell_start_report implements `shell start`: refuse when running
// (unless force), require the config dir, launch detached, wait,
// verify. Mutating: needs --yes; --dry-run only previews.
pub fn shell_start_report(opts ShellStartOptions) CommandResult {
	if !opts.yes && !opts.dry_run {
		return fail_result('shell start', 'refusing to start the shell without --yes (preview with --dry-run).\nExample: horneroctl shell start --dry-run')
	}
	bin := if opts.bin.len > 0 {
		opts.bin
	} else {
		quickshell_or_fail('start', opts.dry_run) or {
			return fail_result('shell start', err.msg())
		}
	}
	conf := resolve_quickshell_config_dir()
	logf := resolve_shell_log_file()
	// Mirrors the legacy `nohup "$QUICKSHELL_BIN" >/dev/null 2>&1 &`,
	// keeping stdout in the shell log so `shell logs` can tail it.
	line := 'nohup ${bin} >>${logf} 2>&1 &'
	if opts.dry_run {
		return ok_result('shell start', 'would run: ${line}\nconfig dir: ${conf}\nlog file: ${logf}',
			{
				'command_line': line
				'config_dir':   conf
				'log_file':     logf
				'dry_run':      'true'
			})
	}
	if !opts.force && shell_is_running() {
		return ok_result('shell start', 'Quickshell is already running', {
			'command_line': line
		})
	}
	if !os.is_dir(conf) {
		return fail_result('shell start', 'Quickshell config directory not found: ${conf}')
	}
	shell_start_env()
	os.mkdir_all(os.dir(logf)) or {
		return fail_result('shell start', 'cannot create log dir ${os.dir(logf)}: ${err}')
	}
	os.execute(line)
	time.sleep(1 * time.second)
	if shell_is_running() {
		pids := shell_running_pids()
		return ok_result('shell start', 'Quickshell started successfully (PID: ${pids.join(',')})',
			{
				'command_line': line
				'pids':         pids.join(',')
				'log_file':     logf
			})
	}
	return fail_result('shell start', 'Failed to start Quickshell')
}

pub struct ShellStopOptions {
pub:
	dry_run bool
	yes     bool
	bin     string // explicit override (tests); else resolution
}

// shell_stop_report implements `shell stop`: no-op success when idle,
// graceful `quickshell kill` first, SIGKILL escalation on timeout.
// Mutating: needs --yes; --dry-run only previews.
pub fn shell_stop_report(opts ShellStopOptions) CommandResult {
	if !opts.yes && !opts.dry_run {
		return fail_result('shell stop', 'refusing to stop the shell without --yes (preview with --dry-run).\nExample: horneroctl shell stop --dry-run')
	}
	bin := if opts.bin.len > 0 {
		opts.bin
	} else {
		quickshell_or_fail('stop', opts.dry_run) or {
			return fail_result('shell stop', err.msg())
		}
	}
	kill_line := command_line(bin, ['kill'])
	if opts.dry_run {
		return ok_result('shell stop', 'would run: ${kill_line}\nescalation: pkill -9 -x qs; pkill -9 -x quickshell',
			{
				'command_line': kill_line
				'dry_run':      'true'
			})
	}
	if !shell_is_running() {
		return ok_result('shell stop', 'Quickshell is not running', {
			'command_line': kill_line
		})
	}
	run_exec(ExecSpec{
		prog: bin
		args: ['kill']
	})
	time.sleep(1 * time.second)
	if !shell_is_running() {
		return ok_result('shell stop', 'Quickshell stopped', {
			'command_line': kill_line
		})
	}
	run_exec(ExecSpec{
		prog: resolve_pkill_bin()
		args: ['-9', '-x', 'qs']
	})
	run_exec(ExecSpec{
		prog: resolve_pkill_bin()
		args: ['-9', '-x', 'quickshell']
	})
	if !shell_is_running() {
		return ok_result('shell stop', 'Quickshell stopped (SIGKILL)', {
			'command_line': kill_line
		})
	}
	return fail_result('shell stop', 'Quickshell did not stop')
}

pub struct ShellRestartOptions {
pub:
	dry_run bool
	yes     bool
	bin     string // explicit override (tests); else resolution
}

// shell_restart_report implements `shell restart`: stop, cover, start.
// The reload cover (`reloadcover/shell.qml` under the quickshell config
// dir) paints every screen while the main shell is down, so a restart
// never flashes a bare desktop. The cover is best-effort: a missing
// cover file or failed cover launch degrades to the old bare sequence.
// Mutating: needs --yes; --dry-run only previews.
pub fn shell_restart_report(opts ShellRestartOptions) CommandResult {
	if !opts.yes && !opts.dry_run {
		return fail_result('shell restart', 'refusing to restart the shell without --yes (preview with --dry-run).\nExample: horneroctl shell restart --dry-run')
	}
	bin := if opts.bin.len > 0 {
		opts.bin
	} else {
		quickshell_or_fail('restart', opts.dry_run) or {
			return fail_result('shell restart', err.msg())
		}
	}
	kill_line := command_line(bin, ['kill'])
	logf := resolve_shell_log_file()
	start_line := 'nohup ${bin} >>${logf} 2>&1 &'
	cover := os.join_path(resolve_quickshell_config_dir(), 'reloadcover', 'shell.qml')
	cover_line := 'nohup ${bin} --path ${cover} >>${logf} 2>&1 & echo \$!'
	if opts.dry_run {
		return ok_result('shell restart', 'would run: ${kill_line}\nwould run: sleep 1\nwould run: ${cover_line}\nwould run: ${start_line}\nwould run: kill <cover-pid>',
			{
				'command_line': '${kill_line}; sleep 1; ${cover_line}; ${start_line}'
				'dry_run':      'true'
			})
	}
	stop_rep := shell_stop_report(ShellStopOptions{
		dry_run: false
		yes:     true
		bin:     bin
	})
	if !stop_rep.ok {
		return fail_result('shell restart', 'stop phase failed: ${stop_rep.message}')
	}
	time.sleep(1 * time.second)
	// Cover up: best-effort, tracked by PID so only the cover dies.
	cover_pid := shell_cover_up(bin, cover, logf)
	time.sleep(500 * time.millisecond)
	// Forced: the cover just went up under the same process name, so
	// the already-running guard would refuse and strand the session
	// with no main shell. The pre-start stop already cleared any real
	// instance; the post-launch verification below still applies.
	start_rep := shell_start_report(ShellStartOptions{
		dry_run: false
		yes:     true
		bin:     bin
		force:   true
	})
	shell_cover_down(cover_pid)
	if !start_rep.ok {
		return fail_result('shell restart', 'start phase failed: ${start_rep.message}')
	}
	cover_note := if cover_pid.len > 0 {
		'\ncover: shown during reload'
	} else {
		'\ncover: skipped (no reloadcover/shell.qml)'
	}
	return ok_result('shell restart', 'Quickshell restarted\n${stop_rep.message}\n${start_rep.message}${cover_note}',
		{
			'command_line': '${kill_line}; sleep 1; ${start_line}'
		})
}

// shell_cover_up launches the reload cover detached and returns its PID,
// or '' when the cover file is absent or the launch fails. Best-effort:
// the caller always proceeds, with or without a cover.
fn shell_cover_up(bin string, cover string, logf string) string {
	if !os.is_file(cover) {
		return ''
	}
	rep := os.execute('nohup ${bin} --path ${cover} >>${logf} 2>&1 & echo \$!')
	pid := rep.output.trim_space()
	if rep.exit_code != 0 || pid.len == 0 {
		return ''
	}
	return pid
}

// shell_cover_down kills a cover started by shell_cover_up. '' is a
// no-op; kill failures are ignored (the cover has a 60 s watchdog).
fn shell_cover_down(cover_pid string) {
	if cover_pid.len == 0 {
		return
	}
	os.execute('kill ${cover_pid}')
}

pub struct ShellLogsOptions {
pub:
	lines   int // tail line count (default 50)
	dry_run bool
	bin     string // unused; kept for option-shape symmetry
}

// shell_logs_report implements `shell logs`: tail the shell log file
// (read-only). Missing log file fails with guidance.
pub fn shell_logs_report(opts ShellLogsOptions) CommandResult {
	n := if opts.lines > 0 { opts.lines } else { 50 }
	logf := resolve_shell_log_file()
	if opts.dry_run {
		return ok_result('shell logs', 'would read: tail -n ${n} ${logf}', {
			'command_line': 'tail -n ${n} ${logf}'
			'log_file':     logf
			'lines':        n.str()
			'dry_run':      'true'
		})
	}
	raw := os.read_file(logf) or {
		return fail_result('shell logs', 'no shell log at ${logf} (start the shell first: horneroctl shell start --yes).\nSet HORNERO_SHELL_LOG_FILE to point at another log.')
	}
	lines := raw.split_into_lines()
	mut start := lines.len - n
	if start < 0 {
		start = 0
	}
	return ok_result('shell logs', lines[start..].join('\n'), {
		'log_file': logf
		'lines':    n.str()
	})
}
