module hornero_cli

import os

// Power/lock dispatch fixtures reuse a /tmp fixture tree; each test sets
// the backend overrides it needs and unsets them afterwards.
fn power_dispatch_setup() {
	os.mkdir_all('/tmp/hx-power-dtest/bin') or { assert false }
	os.write_file('/tmp/hx-power-dtest/bin/systemctl', '#!/bin/sh\necho "systemctl \$*"\nexit 0\n') or {
		assert false
	}
	os.write_file('/tmp/hx-power-dtest/bin/loginctl', '#!/bin/sh\necho "loginctl \$*"\nexit 0\n') or {
		assert false
	}
	os.write_file('/tmp/hx-power-dtest/bin/dots-lockscreen', '#!/bin/sh\nif [ "\$1" = "--lock" ]; then echo "locked"; exit 0; fi\nexit 1\n') or {
		assert false
	}
	os.chmod('/tmp/hx-power-dtest/bin/systemctl', 0o755) or { assert false }
	os.chmod('/tmp/hx-power-dtest/bin/loginctl', 0o755) or { assert false }
	os.chmod('/tmp/hx-power-dtest/bin/dots-lockscreen', 0o755) or { assert false }
	os.setenv('HORNERO_SYSTEMCTL_BIN', '/tmp/hx-power-dtest/bin/systemctl', true)
	os.setenv('HORNERO_LOGINCTL_BIN', '/tmp/hx-power-dtest/bin/loginctl', true)
	os.setenv('HORNERO_LOCKSCREEN_BIN', '/tmp/hx-power-dtest/bin/dots-lockscreen', true)
	os.setenv('HORNERO_HYPRLOCK_BIN', '/nonexistent-hyprlock-hornero-test', true)
	os.setenv('XDG_SESSION_ID', 'test-session', true)
}

fn power_dispatch_teardown() {
	os.unsetenv('HORNERO_SYSTEMCTL_BIN')
	os.unsetenv('HORNERO_LOGINCTL_BIN')
	os.unsetenv('HORNERO_LOCKSCREEN_BIN')
	os.unsetenv('HORNERO_HYPRLOCK_BIN')
	os.unsetenv('XDG_SESSION_ID')
}

fn test_dispatch_power() {
	power_dispatch_setup()
	assert dispatch(['horneroctl', 'power', 'status']) == 0
	assert dispatch(['horneroctl', 'power', 'lock', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'power', 'lock', '--yes']) == 0
	assert dispatch(['horneroctl', 'power', 'suspend', '--yes']) == 0
	assert dispatch(['horneroctl', 'power', 'reboot', '--yes']) == 0
	assert dispatch(['horneroctl', 'power', 'shutdown', '--yes']) == 0
	assert dispatch(['horneroctl', 'power', 'logout', '--yes']) == 0
	// Mutations without --yes fail (exit 1), even with backends present.
	assert dispatch(['horneroctl', 'power', 'lock']) == 1
	assert dispatch(['horneroctl', 'power', 'suspend']) == 1
	assert dispatch(['horneroctl', 'power', 'reboot']) == 1
	assert dispatch(['horneroctl', 'power', 'shutdown']) == 1
	assert dispatch(['horneroctl', 'power', 'logout']) == 1
	// Usage errors (exit 2).
	assert dispatch(['horneroctl', 'power']) == 2
	assert dispatch(['horneroctl', 'power', 'bogus']) == 2
	assert dispatch(['horneroctl', 'power', 'status', '--dry-run']) == 2
	assert dispatch(['horneroctl', 'power', 'lock', '--bogus']) == 2
	assert dispatch(['horneroctl', 'power', 'lock', 'extra']) == 2
	assert dispatch(['horneroctl', 'power', '--help']) == 0
	power_dispatch_teardown()
}

fn test_dispatch_lock() {
	power_dispatch_setup()
	assert dispatch(['horneroctl', 'lock', 'status']) == 0
	assert dispatch(['horneroctl', 'lock', 'now', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'lock', 'now', '--yes']) == 0
	assert dispatch(['horneroctl', 'lock', 'now']) == 1
	assert dispatch(['horneroctl', 'lock']) == 2
	assert dispatch(['horneroctl', 'lock', 'bogus']) == 2
	assert dispatch(['horneroctl', 'lock', 'status', '--dry-run']) == 2
	assert dispatch(['horneroctl', 'lock', 'now', '--bogus']) == 2
	assert dispatch(['horneroctl', 'lock', 'now', 'extra']) == 2
	assert dispatch(['horneroctl', 'lock', '--help']) == 0
	power_dispatch_teardown()
}

fn test_power_dry_run_needs_no_backend() {
	// Hermetic: nonexistent backends; dry-run previews must still pass.
	old_session := os.getenv('XDG_SESSION_ID')
	os.setenv('HORNERO_SYSTEMCTL_BIN', '/nonexistent-systemctl-hornero-test', true)
	os.setenv('HORNERO_LOGINCTL_BIN', '/nonexistent-loginctl-hornero-test', true)
	os.setenv('HORNERO_LOCKSCREEN_BIN', '/nonexistent-lockscreen-hornero-test', true)
	os.setenv('HORNERO_HYPRLOCK_BIN', '/nonexistent-hyprlock-hornero-test', true)
	os.setenv('XDG_SESSION_ID', 'test-session', true)
	for action in ['lock', 'suspend', 'reboot', 'shutdown', 'logout'] {
		assert dispatch(['horneroctl', 'power', action, '--dry-run']) == 0
	}
	assert dispatch(['horneroctl', 'lock', 'now', '--dry-run']) == 0
	os.unsetenv('HORNERO_SYSTEMCTL_BIN')
	os.unsetenv('HORNERO_LOGINCTL_BIN')
	os.unsetenv('HORNERO_LOCKSCREEN_BIN')
	os.unsetenv('HORNERO_HYPRLOCK_BIN')
	if old_session.len == 0 {
		os.unsetenv('XDG_SESSION_ID')
	} else {
		os.setenv('XDG_SESSION_ID', old_session, true)
	}
}

fn test_power_logout_without_session() {
	old_session := os.getenv('XDG_SESSION_ID')
	power_dispatch_setup()
	os.unsetenv('XDG_SESSION_ID')
	assert dispatch(['horneroctl', 'power', 'logout', '--dry-run']) == 1
	assert dispatch(['horneroctl', 'power', 'logout', '--yes']) == 1
	power_dispatch_teardown()
	if old_session.len > 0 {
		os.setenv('XDG_SESSION_ID', old_session, true)
	}
}

fn test_power_help_has_examples() {
	for cmd in ['power', 'lock'] {
		h := command_help(cmd)
		assert h.contains('Examples:')
	}
}

fn test_power_json_and_quiet_modes() {
	power_dispatch_setup()
	assert dispatch(['horneroctl', '--json', 'power', 'status']) == 0
	assert dispatch(['horneroctl', '--quiet', 'power', 'status']) == 0
	assert dispatch(['horneroctl', '--json', 'power', 'lock', '--dry-run']) == 0
	assert dispatch(['horneroctl', '--quiet', 'power', 'suspend', '--dry-run']) == 0
	assert dispatch(['horneroctl', '--json', 'lock', 'status']) == 0
	assert dispatch(['horneroctl', '--quiet', 'lock', 'now', '--dry-run']) == 0
	power_dispatch_teardown()
}
