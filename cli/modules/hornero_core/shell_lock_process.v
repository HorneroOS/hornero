module hornero_core

import os

// Standalone lock-process management (shell#257): the shell ships a
// lock-only quickshell entrypoint (`lock.qml`) supervised by the
// `hornero-lock.service` user unit, so a main-shell crash or restart
// cannot take the session lock surface down with it. This backend
// manages the opt-in pair atomically from the user's point of view:
//
// - enable: `systemctl --user enable --now hornero-lock.service`, then
//   `systemctl --user set-environment HORNERO_EXTERNAL_LOCK=1` so the
//   main shell delegates acquisition on its next start. If the second
//   step fails, the unit is disabled again (rollback) and the failure
//   reports the partial state honestly.
// - disable: reverse pair (`disable --now`, then unset-environment).
//
// Both refuse while the session is locked: enabling would race the
// engaged lock, and stopping the lock owner while locked strands the
// compositor lock (shell#255). The main shell is never restarted from
// here; it adopts the delegation on its next start, and the message
// says so. Mutations need --yes; --dry-run previews every command.

pub const lock_process_unit_name = 'hornero-lock.service'

// resolve_lock_process_unit_file locates the shipped user unit: a
// user-installed copy wins, then the packaged one. Override with
// HORNERO_LOCK_UNIT_FILE (tests).
pub fn resolve_lock_process_unit_file() string {
	env := os.getenv('HORNERO_LOCK_UNIT_FILE')
	if env.len > 0 {
		return env
	}
	mut config_home := os.getenv('XDG_CONFIG_HOME')
	if config_home.len == 0 {
		config_home = os.join_path(os.home_dir(), '.config')
	}
	user_unit := os.join_path(config_home, 'systemd', 'user', lock_process_unit_name)
	if os.is_file(user_unit) {
		return user_unit
	}
	return os.join_path('/usr', 'lib', 'systemd', 'user', lock_process_unit_name)
}

// lock_process_lock_qml returns the lock-only entrypoint inside the
// resolved quickshell config dir ('' when absent).
pub fn lock_process_lock_qml() string {
	p := os.join_path(resolve_quickshell_config_dir(), 'lock.qml')
	if os.is_file(p) {
		return p
	}
	return ''
}

fn lock_process_systemctl(args []string) ExecReport {
	return run_exec(ExecSpec{
		prog:        resolve_systemctl_bin()
		args:        args
		timeout_sec: 10
	})
}

// lock_process_probe returns an is-enabled/is-active fact or 'unknown'
// when systemctl cannot answer (fail-open reporting, never a guess).
fn lock_process_probe(verb string) string {
	if resolve_systemctl_bin().len == 0 {
		return 'unknown'
	}
	rep := lock_process_systemctl(['--user', verb, lock_process_unit_name])
	if rep.ok {
		out := rep.output.trim_space()
		return if out.len > 0 { out } else { 'unknown' }
	}
	// is-enabled/is-active exit non-zero for disabled/inactive units
	// while still printing the fact on stdout.
	out := rep.output.trim_space()
	if out.len > 0 {
		return out
	}
	return 'unknown'
}

// shell_lock_process_status implements `shell lock-process status`
// (read-only): shipped artifacts, unit state, and whether this
// process environment already carries the delegation marker. It
// cannot see the running shell's launch environment, so it says so.
pub fn shell_lock_process_status() CommandResult {
	unit_file := resolve_lock_process_unit_file()
	unit_shipped := os.is_file(unit_file)
	qml := lock_process_lock_qml()
	enabled := lock_process_probe('is-enabled')
	active := lock_process_probe('is-active')
	env_marker := os.getenv('HORNERO_EXTERNAL_LOCK')
	msg := 'unit file: ${unit_file} (${if unit_shipped {
		'present'
	} else {
		'missing — install hornero-shell'
	}})\n' +
		'lock.qml: ${if qml.len > 0 {
			qml
		} else {
			'missing in the resolved quickshell config (pre-#257 shell)'
		}}\n' +
		'unit enabled: ${enabled}\nunit active: ${active}\n' +
		'HORNERO_EXTERNAL_LOCK in this environment: ${if env_marker.len > 0 {
			env_marker
		} else {
			'unset'
		}}\n' +
		'note: the running main shell keeps the lock mode it started with; the delegation applies from its next start.'
	return ok_result('shell lock-process status', msg, {
		'unit_file':    unit_file
		'unit_shipped': unit_shipped.str()
		'lock_qml':     qml
		'enabled':      enabled
		'active':       active
		'env_marker':   env_marker
	})
}

pub struct ShellLockProcessOptions {
pub:
	leaf    string // enable | disable
	dry_run bool
	yes     bool
}

fn lock_process_require_pair(opts ShellLockProcessOptions) !string {
	qml := lock_process_lock_qml()
	if qml.len == 0 {
		return error('lock.qml not found in the resolved quickshell config dir; this needs a shell build with the standalone lock process (shell#257).')
	}
	unit_file := resolve_lock_process_unit_file()
	if !os.is_file(unit_file) {
		return error('hornero-lock.service not installed (looked in user units and /usr/lib/systemd/user); install a hornero-shell build that ships it (shell#257).')
	}
	return qml
}

// shell_lock_process_enable implements `shell lock-process enable`.
pub fn shell_lock_process_enable(opts ShellLockProcessOptions) CommandResult {
	leaf := 'shell lock-process enable'
	if !opts.yes && !opts.dry_run {
		return fail_result(leaf, 'refusing to enable the lock process without --yes (preview with --dry-run).\nExample: horneroctl shell lock-process enable --dry-run')
	}
	enable_cmd := 'systemctl --user enable --now ${lock_process_unit_name}'
	env_cmd := 'systemctl --user set-environment HORNERO_EXTERNAL_LOCK=1'
	if opts.dry_run {
		return ok_result(leaf, 'would run: ${enable_cmd}\nwould run: ${env_cmd}\nthen: the main shell delegates lock acquisition from its next start (restart it while unlocked: horneroctl shell restart --yes)',
			{
				'command_line': '${enable_cmd}; ${env_cmd}'
				'dry_run':      'true'
			})
	}
	if session_is_locked() {
		return fail_result(leaf, 'refusing to enable the lock process while ' + locked_refusal())
	}
	lock_process_require_pair(opts) or { return fail_result(leaf, err.msg()) }
	if resolve_systemctl_bin().len == 0 {
		return fail_result(leaf, 'systemctl not found on PATH. Set HORNERO_SYSTEMCTL_BIN.')
	}
	rep := lock_process_systemctl(['--user', 'enable', '--now', lock_process_unit_name])
	if !rep.ok {
		return fail_result(leaf, 'systemctl --user enable --now ${lock_process_unit_name} failed: ${rep.output.trim_space()}')
	}
	env_rep := lock_process_systemctl(['--user', 'set-environment', 'HORNERO_EXTERNAL_LOCK=1'])
	if !env_rep.ok {
		// Roll back the first half so pair stays atomic, and say so.
		lock_process_systemctl(['--user', 'disable', '--now', lock_process_unit_name])
		return fail_result(leaf, 'systemctl --user set-environment failed: ${env_rep.output.trim_space()}. The unit was disabled again to keep the pair atomic; no delegation is active.')
	}
	return ok_result(leaf, 'Lock process enabled and delegation marker set.\nThe main shell still owns the lock in this session; it delegates from its next start. When ready and unlocked: horneroctl shell restart --yes',
		{
			'command_line': '${enable_cmd}; ${env_cmd}'
			'unit':         lock_process_unit_name
		})
}

// shell_lock_process_disable implements `shell lock-process disable`.
pub fn shell_lock_process_disable(opts ShellLockProcessOptions) CommandResult {
	leaf := 'shell lock-process disable'
	if !opts.yes && !opts.dry_run {
		return fail_result(leaf, 'refusing to disable the lock process without --yes (preview with --dry-run).\nExample: horneroctl shell lock-process disable --dry-run')
	}
	disable_cmd := 'systemctl --user disable --now ${lock_process_unit_name}'
	env_cmd := 'systemctl --user unset-environment HORNERO_EXTERNAL_LOCK'
	if opts.dry_run {
		return ok_result(leaf, 'would run: ${disable_cmd}\nwould run: ${env_cmd}\nthen: the main shell owns the lock again from its next start',
			{
				'command_line': '${disable_cmd}; ${env_cmd}'
				'dry_run':      'true'
			})
	}
	if session_is_locked() {
		return fail_result(leaf, 'refusing to disable the lock process while ' + locked_refusal())
	}
	if resolve_systemctl_bin().len == 0 {
		return fail_result(leaf, 'systemctl not found on PATH. Set HORNERO_SYSTEMCTL_BIN.')
	}
	rep := lock_process_systemctl(['--user', 'disable', '--now', lock_process_unit_name])
	if !rep.ok {
		return fail_result(leaf, 'systemctl --user disable --now ${lock_process_unit_name} failed: ${rep.output.trim_space()}. The delegation marker was left untouched.')
	}
	env_rep := lock_process_systemctl(['--user', 'unset-environment', 'HORNERO_EXTERNAL_LOCK'])
	if !env_rep.ok {
		return fail_result(leaf, 'the lock unit is disabled, but unset-environment failed: ${env_rep.output.trim_space()}. The main shell may still delegate at its next start; fix with: systemctl --user unset-environment HORNERO_EXTERNAL_LOCK')
	}
	return ok_result(leaf, 'Lock process disabled and delegation marker cleared.\nThe main shell owns the lock again from its next start (restart it while unlocked if it is currently delegating).',
		{
			'command_line': '${disable_cmd}; ${env_cmd}'
			'unit':         lock_process_unit_name
		})
}
