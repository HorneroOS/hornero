module hornero_core

import os
import time

// -- Hermes gateway lifecycle (hornero#174) --------------------------------
// horneroctl owns starting/stopping the user-level Hermes gateway via a
// systemd user unit it writes under the user config dir. Never root,
// never a system unit, never auto-enabled at login: `assistant gateway
// start --yes` is the explicit opt-in, and the unit carries no
// [Install]-driven enablement until the user enables it themselves.
// Where systemd user sessions are unavailable the commands degrade to
// actionable guidance instead of spawning unmanaged processes.

pub const assistant_gateway_unit_name = 'hornero-hermes.service'

pub fn assistant_gateway_unit_file() string {
	paths := resolve_paths()
	return os.join_path(paths.config_dir, 'systemd', 'user', assistant_gateway_unit_name)
}

// assistant_gateway_unit_content is pure so tests can pin the contract:
// user-level, the resolved hermes binary, `gateway run`, restart only on
// failure. The gateway itself binds the loopback endpoint HorneroOS
// configures; the unit never widens that.
pub fn assistant_gateway_unit_content(hermes string) string {
	return '[Unit]\nDescription=Hornero Companion — Hermes gateway (user-level, loopback only)\nAfter=network.target\n\n[Service]\nType=simple\nExecStart=${hermes} gateway run\nRestart=on-failure\nRestartSec=5\n\n[Install]\nWantedBy=default.target\n'
}

// assistant_gateway_classify names the five operator states `assistant
// health` and `assistant gateway status` report (hornero#174 acceptance:
// not installed / installed-not-running / running-incompatible /
// running-compatible, plus the default disabled state).
pub fn assistant_gateway_classify(enabled bool, installed bool, reachable bool, compatible bool) string {
	if !enabled {
		return 'disabled'
	}
	if !installed {
		return 'not-installed'
	}
	if !reachable {
		return 'installed-not-running'
	}
	if !compatible {
		return 'running-incompatible'
	}
	return 'running-compatible'
}

// assistant_gateway_ensure_unit creates a missing unit or refreshes one
// whose current contents match a Hornero ownership receipt. External and
// locally modified units are preserved; the return value reports a write.
pub fn assistant_gateway_ensure_unit(hermes string) !bool {
	mut file_lock := assistant_setup_acquire_lock()!
	defer {
		file_lock.release()
	}
	return assistant_gateway_ensure_unit_locked(hermes)
}

fn assistant_gateway_ensure_unit_locked(hermes string) !bool {
	unit_file := assistant_gateway_unit_file()
	desired := assistant_gateway_unit_content(hermes)
	return assistant_setup_write_owned_file_locked('unit', unit_file, desired,
		assistant_setup_move_file, assistant_setup_noop_before_publish)
}

fn assistant_gateway_systemctl(args []string) ExecReport {
	return run_exec(ExecSpec{
		prog:        'systemctl'
		args:        ['--user', ...args]
		timeout_sec: 30
	})
}

fn assistant_gateway_unit_active() string {
	if find_on_path('systemctl').len == 0 {
		return 'no-systemd'
	}
	rep := assistant_gateway_systemctl(['is-active', assistant_gateway_unit_name])
	return rep.output.trim_space()
}

fn assistant_gateway_wait_reachable(settings AssistantSettings, attempts int) (bool, bool, string) {
	mut reachable, mut compatible, mut detail := assistant_gateway_state(settings)
	for _ in 0 .. attempts {
		if reachable {
			break
		}
		time.sleep(500 * time.millisecond)
		reachable, compatible, detail = assistant_gateway_state(settings)
	}
	return reachable, compatible, detail
}

pub fn assistant_gateway_status_report() CommandResult {
	settings := assistant_load_settings()
	hermes := find_on_path('hermes')
	reachable, compatible, detail := assistant_gateway_state(settings)
	state := assistant_gateway_classify(settings.enabled, hermes.len > 0, reachable,
		compatible)
	unit := assistant_gateway_unit_active()
	data := {
		'enabled':   settings.enabled.str()
		'endpoint':  settings.endpoint
		'hermes':    if hermes.len > 0 { hermes } else { 'not-found' }
		'state':     state
		'unit':      assistant_gateway_unit_name
		'unitState': unit
		'gateway':   if reachable { 'reachable' } else { 'unreachable' }
		'protocol':  if compatible { 'compatible' } else { 'incompatible' }
	}
	msg := 'gateway state: ${state} (unit ${unit}, endpoint ${settings.endpoint}: ${detail})'
	return CommandResult{
		command: 'assistant gateway'
		ok:      state == 'running-compatible'
		message: msg
		data:    data
	}
}

pub fn assistant_gateway_start_report(dry_run bool, yes bool) CommandResult {
	if dry_run || !yes {
		return assistant_gateway_start_report_locked(dry_run, yes)
	}
	mut file_lock := assistant_setup_acquire_lock() or {
		return fail_result('assistant gateway start', 'Cannot lock assistant ownership state: ${err.msg()}')
	}
	defer {
		file_lock.release()
	}
	return assistant_gateway_start_report_locked(dry_run, yes)
}

fn assistant_gateway_start_report_locked(dry_run bool, yes bool) CommandResult {
	settings := assistant_load_settings()
	unit_file := assistant_gateway_unit_file()
	if dry_run {
		return ok_result('assistant gateway start', 'Dry run: would ensure the user unit ${unit_file}, run systemctl --user daemon-reload if it changed, then systemctl --user start ${assistant_gateway_unit_name}. Nothing is enabled at login and nothing runs as root.', {
			'dryRun': 'true'
			'unit':   assistant_gateway_unit_name
		})
	}
	if !yes {
		return fail_result('assistant gateway start', 'Starting the Hermes gateway needs explicit consent. Preview with --dry-run, then run: horneroctl assistant gateway start --yes')
	}
	if !settings.enabled {
		return fail_result('assistant gateway start', 'The assistant is disabled (default). Enable it first: horneroctl assistant enable --yes')
	}
	hermes := find_on_path('hermes')
	if hermes.len == 0 {
		return fail_result('assistant gateway start', 'Hermes Agent was not found on PATH. Install Hermes through a pinned, auditable package (never a remote install script), then retry.')
	}
	reachable, compatible, _ := assistant_gateway_state(settings)
	if reachable {
		state := assistant_gateway_classify(true, true, true, compatible)
		return ok_result('assistant gateway start', 'Hermes gateway is already running at ${settings.endpoint} (${state}); not starting a duplicate.', {
			'state':    state
			'endpoint': settings.endpoint
		})
	}
	if find_on_path('systemctl').len == 0 {
		return fail_result('assistant gateway start', 'systemd user sessions are unavailable here, so horneroctl cannot manage the gateway. Start it manually in a terminal: hermes gateway run')
	}
	wrote := assistant_gateway_ensure_unit_locked(hermes) or {
		return fail_result('assistant gateway start', 'Cannot write the user unit ${unit_file}: ${err.msg()}')
	}
	if !wrote && !assistant_setup_file_is_owned('unit', unit_file) {
		return fail_result('assistant gateway start', 'The unit ${unit_file} already exists but has no matching Hornero ownership receipt. It was preserved and will not be started by Hornero; reconcile its ownership with dotfiles or manage it directly with systemctl --user.')
	}
	if wrote {
		assistant_gateway_systemctl(['daemon-reload'])
	}
	// A unit deleted while loaded (setup --remove) and then recreated
	// leaves systemd with a stale failed/load-error state; clearing it
	// is required before start and harmless otherwise (host-validated
	// in the #191 setup remove→start cycle).
	assistant_gateway_systemctl(['reset-failed', assistant_gateway_unit_name])
	start := assistant_gateway_systemctl(['start', assistant_gateway_unit_name])
	if !start.ok {
		return fail_result('assistant gateway start', 'systemctl --user start ${assistant_gateway_unit_name} failed: ${start.output}. Inspect: journalctl --user -u ${assistant_gateway_unit_name} -n 30')
	}
	now_reachable, now_compatible, detail := assistant_gateway_wait_reachable(settings,
		40)
	if !now_reachable {
		return fail_result('assistant gateway start', 'Gateway did not answer at ${settings.endpoint} yet (${detail}). Inspect: journalctl --user -u ${assistant_gateway_unit_name} -n 30')
	}
	state := assistant_gateway_classify(true, true, true, now_compatible)
	return ok_result('assistant gateway start', 'Hermes gateway started via ${assistant_gateway_unit_name}; state: ${state} at ${settings.endpoint}.', {
		'state':    state
		'endpoint': settings.endpoint
		'unit':     assistant_gateway_unit_name
	})
}

pub fn assistant_gateway_stop_report(dry_run bool, yes bool) CommandResult {
	if dry_run || !yes {
		return assistant_gateway_stop_report_locked(dry_run, yes)
	}
	mut file_lock := assistant_setup_acquire_lock() or {
		return fail_result('assistant gateway stop', 'Cannot lock assistant ownership state: ${err.msg()}')
	}
	defer {
		file_lock.release()
	}
	return assistant_gateway_stop_report_locked(dry_run, yes)
}

fn assistant_gateway_stop_report_locked(dry_run bool, yes bool) CommandResult {
	settings := assistant_load_settings()
	if dry_run {
		return ok_result('assistant gateway stop', 'Dry run: would run systemctl --user stop ${assistant_gateway_unit_name} if Hornero manages the running gateway. The desktop and the Hermes installation are untouched.', {
			'dryRun': 'true'
			'unit':   assistant_gateway_unit_name
		})
	}
	if !yes {
		return fail_result('assistant gateway stop', 'Stopping the gateway needs --yes (it changes assistant state). Preview with --dry-run first if unsure.')
	}
	if find_on_path('systemctl').len == 0 {
		return fail_result('assistant gateway stop', 'systemd user sessions are unavailable here, so horneroctl cannot manage the gateway. Stop the `hermes gateway run` process from the terminal that started it.')
	}
	unit := assistant_gateway_unit_active()
	reachable, _, _ := assistant_gateway_state(settings)
	if unit != 'active' {
		if reachable {
			return fail_result('assistant gateway stop', 'A Hermes gateway answers at ${settings.endpoint} but the ${assistant_gateway_unit_name} user unit is ${unit}; it was started outside horneroctl management, so Hornero will not kill a process it does not own. Stop it where it was started.')
		}
		return ok_result('assistant gateway stop', 'Hermes gateway is not running; nothing to stop. The desktop is unaffected.', {
			'state': assistant_gateway_classify(settings.enabled, find_on_path('hermes').len > 0,
				false, false)
			'unit':  assistant_gateway_unit_name
		})
	}
	if !assistant_setup_file_is_owned('unit', assistant_gateway_unit_file()) {
		return fail_result('assistant gateway stop', 'The active ${assistant_gateway_unit_name} unit has no matching Hornero ownership receipt, so Hornero will not stop it. Manage it through its owning configuration.')
	}
	stop := assistant_gateway_systemctl(['stop', assistant_gateway_unit_name])
	if !stop.ok {
		return fail_result('assistant gateway stop', 'systemctl --user stop ${assistant_gateway_unit_name} failed: ${stop.output}')
	}
	mut down := false
	for _ in 0 .. 10 {
		still, _, _ := assistant_gateway_state(settings)
		if !still {
			down = true
			break
		}
		time.sleep(300 * time.millisecond)
	}
	if !down {
		return fail_result('assistant gateway stop', 'Unit stopped but the gateway still answers at ${settings.endpoint}; another process may serve it. Check: horneroctl assistant gateway status')
	}
	return ok_result('assistant gateway stop', 'Hermes gateway stopped. The desktop works exactly as before; enable again any time with: horneroctl assistant gateway start --yes', {
		'state': assistant_gateway_classify(settings.enabled, find_on_path('hermes').len > 0,
			false, false)
		'unit':  assistant_gateway_unit_name
	})
}
