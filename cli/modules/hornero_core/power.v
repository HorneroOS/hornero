module hornero_core

import os

// Power + screen-lock backends: session and machine power verbs.
//
// Verified backends (mirroring the dots-* reference scripts):
// - `dots-power-menu` minimal mode locks via dots-lockscreen with a
//   `loginctl lock-session` fallback, suspends with `systemctl suspend`,
//   logs out with `loginctl terminate-session $XDG_SESSION_ID`, reboots
//   with `systemctl -i reboot`, and powers off with `systemctl -i poweroff`.
// - `dots-lockscreen --lock` is the hyprlock orchestration (themed config,
//   effect images); it needs Wayland + hyprlock.
// `power lock` and `lock now` share one lock plan: dots-lockscreen
// (`--lock`), else bare hyprlock, else `loginctl lock-session`. When the
// dots-lockscreen delegating shim calls outward it pins
// HORNERO_LOCKSCREEN_BIN at the real hyprlock binary, so the hyprlock
// basename below runs it bare instead of looping back into the shim.

// resolve_systemctl_bin locates systemctl. Override with HORNERO_SYSTEMCTL_BIN.
pub fn resolve_systemctl_bin() string {
	env := os.getenv('HORNERO_SYSTEMCTL_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('systemctl')
}

// resolve_loginctl_bin locates loginctl. Override with HORNERO_LOGINCTL_BIN.
pub fn resolve_loginctl_bin() string {
	env := os.getenv('HORNERO_LOGINCTL_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('loginctl')
}

// resolve_hyprlock_bin locates hyprlock. Override with HORNERO_HYPRLOCK_BIN.
pub fn resolve_hyprlock_bin() string {
	env := os.getenv('HORNERO_HYPRLOCK_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('hyprlock')
}

// resolve_lockscreen_bin locates the dots-lockscreen locker.
// Override with HORNERO_LOCKSCREEN_BIN.
pub fn resolve_lockscreen_bin() string {
	env := os.getenv('HORNERO_LOCKSCREEN_BIN')
	if env.len > 0 {
		return env
	}
	home_helper := os.join_path(os.home_dir(), '.local', 'bin', 'dots-lockscreen')
	if os.is_file(home_helper) {
		return home_helper
	}
	return find_on_path('dots-lockscreen')
}

struct LockPlan {
	prog string
	args []string
}

// lock_plan picks the screen-lock invocation: dots-lockscreen with --lock,
// else bare hyprlock, else `loginctl lock-session`. A HORNERO_LOCKSCREEN_BIN
// pointing at a hyprlock binary (pinned by the delegating dots-lockscreen
// shim) runs bare so the call cannot loop back into the shim. With dry_run
// set a missing backend previews as a placeholder instead of failing.
fn lock_plan(dry_run bool) !LockPlan {
	ls := resolve_lockscreen_bin()
	if ls.len > 0 {
		if os.file_name(ls) == 'hyprlock' {
			return LockPlan{
				prog: ls
				args: []string{}
			}
		}
		return LockPlan{
			prog: ls
			args: ['--lock']
		}
	}
	hl := resolve_hyprlock_bin()
	if hl.len > 0 {
		return LockPlan{
			prog: hl
			args: []string{}
		}
	}
	lc := resolve_loginctl_bin()
	if lc.len > 0 {
		return LockPlan{
			prog: lc
			args: ['lock-session']
		}
	}
	if dry_run {
		return LockPlan{
			prog: 'dots-lockscreen'
			args: ['--lock']
		}
	}
	return error('no lock backend found (dots-lockscreen, hyprlock, or loginctl). Set HORNERO_LOCKSCREEN_BIN.\nExample: horneroctl lock now --dry-run')
}

fn systemctl_or_fail(action string, dry_run bool) !string {
	bin := resolve_systemctl_bin()
	if bin.len == 0 {
		if dry_run {
			return 'systemctl'
		}
		return error('systemctl not found on PATH. Set HORNERO_SYSTEMCTL_BIN.\nExample: horneroctl power ${action} --dry-run')
	}
	return bin
}

fn loginctl_or_fail(action string, dry_run bool) !string {
	bin := resolve_loginctl_bin()
	if bin.len == 0 {
		if dry_run {
			return 'loginctl'
		}
		return error('loginctl not found on PATH. Set HORNERO_LOGINCTL_BIN.\nExample: horneroctl ${action} --dry-run')
	}
	return bin
}

fn describe_bin(bin string) string {
	if bin.len == 0 {
		return 'missing'
	}
	return bin
}

// power_status_report implements `power status` (read-only): session
// context plus backend presence. It never fails.
pub fn power_status_report() CommandResult {
	session := os.getenv('XDG_SESSION_ID')
	wayland := os.getenv('WAYLAND_DISPLAY')
	sig := os.getenv('HYPRLAND_INSTANCE_SIGNATURE')
	mut lines := []string{}
	mut data := map[string]string{}
	if session.len > 0 {
		lines << 'session: ${session}'
		data['session'] = session
	} else {
		lines << 'session: no XDG_SESSION_ID (not in a login session?)'
		data['session'] = 'unknown'
	}
	if wayland.len > 0 {
		lines << 'wayland: ${wayland}'
		data['wayland'] = wayland
	} else {
		lines << 'wayland: no WAYLAND_DISPLAY (not in a Wayland session?)'
		data['wayland'] = 'unknown'
	}
	if sig.len > 0 {
		lines << 'compositor: Hyprland instance signature is set'
		data['compositor'] = 'hyprland'
	} else {
		lines << 'compositor: no Hyprland instance signature'
		data['compositor'] = 'unknown'
	}
	sys := resolve_systemctl_bin()
	lc := resolve_loginctl_bin()
	ls := resolve_lockscreen_bin()
	hl := resolve_hyprlock_bin()
	lines << 'systemctl: ${describe_bin(sys)}'
	lines << 'loginctl: ${describe_bin(lc)}'
	lines << 'lockscreen: ${describe_bin(ls)}'
	lines << 'hyprlock: ${describe_bin(hl)}'
	data['systemctl'] = describe_bin(sys)
	data['loginctl'] = describe_bin(lc)
	data['lockscreen'] = describe_bin(ls)
	data['hyprlock'] = describe_bin(hl)
	return ok_result('power status', lines.join('\n'), data)
}

pub struct PowerActionOptions {
pub:
	action  string // lock | suspend | reboot | shutdown | logout
	dry_run bool
	yes     bool
}

// power_action_report implements the mutating `power` leaves by delegating
// to systemctl/loginctl (or the shared lock plan). Mutating: needs --yes;
// --dry-run only previews.
pub fn power_action_report(opts PowerActionOptions) CommandResult {
	if opts.action !in ['lock', 'suspend', 'reboot', 'shutdown', 'logout'] {
		return fail_result('power', 'unknown power action: ${opts.action}.\nRun: horneroctl power --help')
	}
	if !opts.yes && !opts.dry_run {
		return fail_result('power ${opts.action}', 'refusing to ${opts.action} without --yes (preview with --dry-run).\nExample: horneroctl power ${opts.action} --dry-run')
	}
	mut prog := ''
	mut args := []string{}
	match opts.action {
		'lock' {
			plan := lock_plan(opts.dry_run) or { return fail_result('power lock', err.msg()) }
			prog = plan.prog
			args = plan.args.clone()
		}
		'suspend' {
			prog = systemctl_or_fail(opts.action, opts.dry_run) or {
				return fail_result('power suspend', err.msg())
			}
			args = ['suspend']
		}
		'reboot' {
			prog = systemctl_or_fail(opts.action, opts.dry_run) or {
				return fail_result('power reboot', err.msg())
			}
			args = ['-i', 'reboot']
		}
		'shutdown' {
			prog = systemctl_or_fail(opts.action, opts.dry_run) or {
				return fail_result('power shutdown', err.msg())
			}
			args = ['-i', 'poweroff']
		}
		'logout' {
			prog = loginctl_or_fail('power logout', opts.dry_run) or {
				return fail_result('power logout', err.msg())
			}
			id := os.getenv('XDG_SESSION_ID')
			if id.len == 0 {
				return fail_result('power logout', 'cannot logout: XDG_SESSION_ID is not set (not in a login session?).')
			}
			args = ['terminate-session', id]
		}
		else {
			return fail_result('power', 'unknown power action: ${opts.action}.\nRun: horneroctl power --help')
		}
	}
	rep := run_exec(ExecSpec{
		prog:    prog
		args:    args
		dry_run: opts.dry_run
	})
	if opts.dry_run {
		return ok_result('power ${opts.action}', 'would run: ${rep.command_line}', {
			'command_line': rep.command_line
			'dry_run':      'true'
		})
	}
	if rep.ok {
		return ok_result('power ${opts.action}', rep.output, {
			'command_line': rep.command_line
		})
	}
	return fail_result('power ${opts.action}', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
}

pub struct LockNowOptions {
pub:
	dry_run bool
	yes     bool
}

// lock_now_report implements `lock now` via the shared lock plan.
// Mutating: needs --yes; --dry-run only previews.
pub fn lock_now_report(opts LockNowOptions) CommandResult {
	if !opts.yes && !opts.dry_run {
		return fail_result('lock now', 'refusing to lock without --yes (preview with --dry-run).\nExample: horneroctl lock now --dry-run')
	}
	plan := lock_plan(opts.dry_run) or { return fail_result('lock now', err.msg()) }
	rep := run_exec(ExecSpec{
		prog:    plan.prog
		args:    plan.args
		dry_run: opts.dry_run
	})
	if opts.dry_run {
		return ok_result('lock now', 'would run: ${rep.command_line}', {
			'command_line': rep.command_line
			'dry_run':      'true'
		})
	}
	if rep.ok {
		return ok_result('lock now', rep.output, {
			'command_line': rep.command_line
		})
	}
	return fail_result('lock now', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
}

// lock_status_report implements `lock status` (read-only): lock backend
// presence plus the exact command `lock now` would run. It never fails.
pub fn lock_status_report() CommandResult {
	ls := resolve_lockscreen_bin()
	hl := resolve_hyprlock_bin()
	session := os.getenv('XDG_SESSION_ID')
	wayland := os.getenv('WAYLAND_DISPLAY')
	plan := lock_plan(true) or { return fail_result('lock status', err.msg()) }
	mut lines := []string{}
	mut data := map[string]string{}
	lines << 'lockscreen: ${describe_bin(ls)}'
	lines << 'hyprlock: ${describe_bin(hl)}'
	lines << 'would run: ${command_line(plan.prog, plan.args)}'
	if session.len > 0 {
		lines << 'session: ${session}'
		data['session'] = session
	} else {
		lines << 'session: no XDG_SESSION_ID (not in a login session?)'
		data['session'] = 'unknown'
	}
	if wayland.len > 0 {
		lines << 'wayland: ${wayland}'
		data['wayland'] = wayland
	} else {
		lines << 'wayland: no WAYLAND_DISPLAY (not in a Wayland session?)'
		data['wayland'] = 'unknown'
	}
	data['lockscreen'] = describe_bin(ls)
	data['hyprlock'] = describe_bin(hl)
	data['command_line'] = command_line(plan.prog, plan.args)
	return ok_result('lock status', lines.join('\n'), data)
}
