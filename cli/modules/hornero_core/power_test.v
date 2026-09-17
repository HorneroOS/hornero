module hornero_core

import os

fn power_test_save_env(keys []string) map[string]string {
	mut saved := map[string]string{}
	for k in keys {
		saved[k] = os.getenv(k)
	}
	return saved
}

fn power_test_restore_env(saved map[string]string) {
	for k, v in saved {
		if v.len == 0 {
			os.unsetenv(k)
		} else {
			os.setenv(k, v, true)
		}
	}
}

fn power_test_break_backends() {
	os.setenv('HORNERO_SYSTEMCTL_BIN', '/nonexistent-systemctl-hornero-test', true)
	os.setenv('HORNERO_LOGINCTL_BIN', '/nonexistent-loginctl-hornero-test', true)
	os.setenv('HORNERO_LOCKSCREEN_BIN', '/nonexistent-lockscreen-hornero-test', true)
	os.setenv('HORNERO_HYPRLOCK_BIN', '/nonexistent-hyprlock-hornero-test', true)
}

fn test_power_status_is_read_only() {
	r := power_status_report()
	assert r.ok
	assert r.message.contains('systemctl:')
	assert r.message.contains('loginctl:')
	assert 'systemctl' in r.data
	assert 'loginctl' in r.data
	assert 'lockscreen' in r.data
	assert 'hyprlock' in r.data
}

fn test_power_action_needs_yes() {
	for action in ['lock', 'suspend', 'reboot', 'shutdown', 'logout'] {
		r := power_action_report(PowerActionOptions{
			action: action
		})
		assert !r.ok
		assert r.message.contains('--yes')
	}
}

fn test_power_action_unknown() {
	r := power_action_report(PowerActionOptions{
		action:  'hibernate'
		dry_run: true
	})
	assert !r.ok
	assert r.message.contains('unknown power action')
}

fn test_power_dry_run_needs_no_backend() {
	// Hermetic: nonexistent backends; dry-run previews must still pass.
	saved := power_test_save_env(['HORNERO_SYSTEMCTL_BIN', 'HORNERO_LOGINCTL_BIN',
		'HORNERO_LOCKSCREEN_BIN', 'HORNERO_HYPRLOCK_BIN', 'XDG_SESSION_ID'])
	power_test_break_backends()
	os.setenv('XDG_SESSION_ID', 'test-session', true)
	for action in ['lock', 'suspend', 'reboot', 'shutdown', 'logout'] {
		r := power_action_report(PowerActionOptions{
			action:  action
			dry_run: true
		})
		assert r.ok
		assert r.message.contains('would run:')
	}
	power_test_restore_env(saved)
}

fn test_power_logout_needs_session() {
	saved := power_test_save_env(['XDG_SESSION_ID', 'HORNERO_LOGINCTL_BIN'])
	os.unsetenv('XDG_SESSION_ID')
	os.setenv('HORNERO_LOGINCTL_BIN', '/nonexistent-loginctl-hornero-test', true)
	r := power_action_report(PowerActionOptions{
		action:  'logout'
		dry_run: true
	})
	assert !r.ok
	assert r.message.contains('XDG_SESSION_ID')
	power_test_restore_env(saved)
}

fn test_lock_plan_prefers_lockscreen() {
	saved := power_test_save_env(['HORNERO_LOCKSCREEN_BIN', 'HORNERO_HYPRLOCK_BIN',
		'HORNERO_LOGINCTL_BIN'])
	os.setenv('HORNERO_LOCKSCREEN_BIN', '/fake/dots-lockscreen', true)
	plan := lock_plan(true) or {
		assert false, err.msg()
		return
	}
	assert plan.prog == '/fake/dots-lockscreen'
	assert plan.args == ['--lock']
	power_test_restore_env(saved)
}

fn test_lock_plan_hyprlock_pin_runs_bare() {
	// The delegating dots-lockscreen shim pins HORNERO_LOCKSCREEN_BIN at
	// the real hyprlock binary; the plan must run it bare, never --lock.
	saved := power_test_save_env(['HORNERO_LOCKSCREEN_BIN', 'HORNERO_HYPRLOCK_BIN',
		'HORNERO_LOGINCTL_BIN'])
	os.setenv('HORNERO_LOCKSCREEN_BIN', '/usr/bin/hyprlock', true)
	plan := lock_plan(true) or {
		assert false, err.msg()
		return
	}
	assert plan.prog == '/usr/bin/hyprlock'
	assert plan.args.len == 0
	power_test_restore_env(saved)
}

fn test_lock_plan_prefers_hyprlock_without_pin() {
	// Native port: no wrapper auto-discovery — unpinned machines go
	// straight to bare hyprlock.
	saved := power_test_save_env(['HORNERO_LOCKSCREEN_BIN', 'HORNERO_HYPRLOCK_BIN',
		'HORNERO_LOGINCTL_BIN'])
	os.unsetenv('HORNERO_LOCKSCREEN_BIN')
	os.setenv('HORNERO_HYPRLOCK_BIN', '/fake/hyprlock', true)
	plan := lock_plan(true) or {
		assert false, err.msg()
		return
	}
	assert plan.prog == '/fake/hyprlock'
	assert plan.args.len == 0
	power_test_restore_env(saved)
}

fn test_lock_now_needs_yes() {
	r := lock_now_report(LockNowOptions{})
	assert !r.ok
	assert r.message.contains('--yes')
}

fn test_lock_now_dry_run_needs_no_backend() {
	saved := power_test_save_env(['HORNERO_LOCKSCREEN_BIN', 'HORNERO_HYPRLOCK_BIN',
		'HORNERO_LOGINCTL_BIN'])
	power_test_break_backends()
	r := lock_now_report(LockNowOptions{
		dry_run: true
	})
	assert r.ok
	assert r.message.contains('would run:')
	power_test_restore_env(saved)
}

fn test_lock_status_is_read_only() {
	r := lock_status_report()
	assert r.ok
	assert r.message.contains('would run:')
	assert 'command_line' in r.data
	assert 'lockscreen' in r.data
	assert 'hyprlock' in r.data
}
