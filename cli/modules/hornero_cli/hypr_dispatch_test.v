module hornero_cli

import os

// Hypr dispatch fixtures reuse the /tmp/hx-hypr-test tree (written
// idempotently here so this module's test binary is self-sufficient).
fn hypr_dispatch_setup() {
	os.mkdir_all('/tmp/hx-hypr-test/config/hypr/hyprland.conf.d') or { assert false }
	os.write_file('/tmp/hx-hypr-test/config/hypr/hyprland.conf.d/animations.conf', 'bezier = easeOut, 0.22, 1, 0.36, 1\nanimation = windows, 1, 3, easeOut\n') or {
		assert false
	}
	os.write_file('/tmp/hx-hypr-test/config/hypr/hyprland.conf.d/animations-cozy.conf',
		'bezier = cozy, 0.34, 1.3, 0.64, 1\nanimation = windows, 1, 5, cozy\n') or { assert false }
	os.mkdir_all('/tmp/hx-hypr-test/state') or { assert false }
	os.setenv('XDG_CONFIG_HOME', '/tmp/hx-hypr-test/config', true)
	os.setenv('XDG_STATE_HOME', '/tmp/hx-hypr-test/state', true)
	os.setenv('HORNERO_HYPRCTL_BIN', '/nonexistent-hyprctl-hornero-test', true)
	os.setenv('HORNERO_HYPRPM_BIN', '/nonexistent-hyprpm-hornero-test', true)
	os.setenv('HORNERO_I3_MSG_BIN', '/nonexistent-i3-msg-hornero-test', true)
}

fn hypr_dispatch_teardown() {
	os.unsetenv('XDG_CONFIG_HOME')
	os.unsetenv('XDG_STATE_HOME')
	os.unsetenv('HORNERO_HYPRCTL_BIN')
	os.unsetenv('HORNERO_HYPRPM_BIN')
	os.unsetenv('HORNERO_I3_MSG_BIN')
}

fn test_dispatch_hypr_reads() {
	hypr_dispatch_setup()
	assert dispatch(['horneroctl', 'hypr', 'animations', 'list']) == 0
	assert dispatch(['horneroctl', 'hypr', 'animations', 'current']) == 0
	assert dispatch(['horneroctl', 'hypr', 'layout', 'current']) == 0
	assert dispatch(['horneroctl', 'hypr', 'layout', 'status']) == 0
	assert dispatch(['horneroctl', 'hypr', 'monitors', 'status']) == 0
	assert dispatch(['horneroctl', 'hypr', 'plugins', 'status']) == 0
	assert dispatch(['horneroctl', 'hypr', 'plugins', 'list']) == 1
	assert dispatch(['horneroctl', 'hypr', 'monitors', 'list']) == 1
	hypr_dispatch_teardown()
}

fn test_dispatch_hypr_mutations_need_yes() {
	hypr_dispatch_setup()
	assert dispatch(['horneroctl', 'hypr', 'animations', 'set', 'cozy', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hypr', 'animations', 'next', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hypr', 'animations', 'restore', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hypr', 'layout', 'set', 'scrolling', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hypr', 'layout', 'toggle', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hypr', 'layout', 'restore', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hypr', 'monitors', 'set', 'mirror', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hypr', 'workspace', 'next', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hypr', 'workspace', 'prev', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hypr', 'plugins', 'install', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hypr', 'plugins', 'install', '--no-update', '--dry-run']) == 0
	// Mutations without --yes fail (exit 1), even as dry-runnable previews.
	assert dispatch(['horneroctl', 'hypr', 'animations', 'set', 'cozy']) == 1
	assert dispatch(['horneroctl', 'hypr', 'animations', 'next']) == 1
	assert dispatch(['horneroctl', 'hypr', 'layout', 'set', 'scrolling']) == 1
	assert dispatch(['horneroctl', 'hypr', 'layout', 'toggle']) == 1
	assert dispatch(['horneroctl', 'hypr', 'monitors', 'set', 'mirror']) == 1
	assert dispatch(['horneroctl', 'hypr', 'workspace', 'next']) == 1
	assert dispatch(['horneroctl', 'hypr', 'plugins', 'install']) == 1
	// Unknown values fail as command errors (exit 1).
	assert dispatch(['horneroctl', 'hypr', 'animations', 'set', 'neon', '--dry-run']) == 1
	assert dispatch(['horneroctl', 'hypr', 'layout', 'set', 'tiling', '--dry-run']) == 1
	assert dispatch(['horneroctl', 'hypr', 'monitors', 'set', 'sideways', '--dry-run']) == 1
	hypr_dispatch_teardown()
}

fn test_dispatch_hypr_monitors_all_modes_dry_run() {
	hypr_dispatch_setup()
	// Every arrangement the dots-hypr-monitors menu can pick must parse
	// and preview (exit 0); the menu choice itself is the confirmation,
	// so horneroctl only ever sees `set <mode> --yes`.
	for mode in ['internal-only', 'external-only', 'extend-right', 'extend-left', 'extend-above',
		'extend-below', 'mirror', 'disable-external'] {
		assert dispatch(['horneroctl', 'hypr', 'monitors', 'set', mode, '--dry-run']) == 0
	}
	hypr_dispatch_teardown()
}

fn test_dispatch_hypr_usage_errors() {
	hypr_dispatch_setup()
	assert dispatch(['horneroctl', 'hypr']) == 2
	assert dispatch(['horneroctl', 'hypr', 'bogus']) == 2
	assert dispatch(['horneroctl', 'hypr', 'animations']) == 2
	assert dispatch(['horneroctl', 'hypr', 'animations', 'bogus']) == 2
	assert dispatch(['horneroctl', 'hypr', 'animations', 'set']) == 2
	assert dispatch(['horneroctl', 'hypr', 'animations', 'set', 'cozy', '--bogus']) == 2
	assert dispatch(['horneroctl', 'hypr', 'animations', 'set', 'cozy', 'extra', '--dry-run']) == 2
	assert dispatch(['horneroctl', 'hypr', 'animations', 'list', '--dry-run']) == 2
	assert dispatch(['horneroctl', 'hypr', 'layout', 'bogus']) == 2
	assert dispatch(['horneroctl', 'hypr', 'layout', 'set']) == 2
	assert dispatch(['horneroctl', 'hypr', 'layout', 'current', '--dry-run']) == 2
	assert dispatch(['horneroctl', 'hypr', 'monitors', 'bogus']) == 2
	assert dispatch(['horneroctl', 'hypr', 'monitors', 'set']) == 2
	assert dispatch(['horneroctl', 'hypr', 'monitors', 'list', '--dry-run']) == 2
	assert dispatch(['horneroctl', 'hypr', 'workspace']) == 2
	assert dispatch(['horneroctl', 'hypr', 'workspace', 'bogus']) == 2
	assert dispatch(['horneroctl', 'hypr', 'workspace', 'next', '--bogus']) == 2
	assert dispatch(['horneroctl', 'hypr', 'plugins']) == 2
	assert dispatch(['horneroctl', 'hypr', 'plugins', 'bogus']) == 2
	assert dispatch(['horneroctl', 'hypr', 'plugins', 'status', '--dry-run']) == 2
	assert dispatch(['horneroctl', 'hypr', 'plugins', 'install', '--force', '--no-update',
		'--dry-run']) == 2
	assert dispatch(['horneroctl', 'hypr', 'plugins', 'install', '--bogus']) == 2
	hypr_dispatch_teardown()
}

fn test_dispatch_hypr_workspace_prev_alias() {
	hypr_dispatch_setup()
	assert dispatch(['horneroctl', 'hypr', 'workspace', 'next', '--previous', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hypr', 'workspace', 'next', '--left', '--dry-run']) == 0
	hypr_dispatch_teardown()
}

fn test_dispatch_hypr_help() {
	assert dispatch(['horneroctl', 'hypr', '--help']) == 0
	assert dispatch(['horneroctl', 'hypr', 'animations', '--help']) == 0
	assert dispatch(['horneroctl', 'hypr', 'layout', '--help']) == 0
	assert dispatch(['horneroctl', 'hypr', 'monitors', '--help']) == 0
	assert dispatch(['horneroctl', 'hypr', 'workspace', '--help']) == 0
	assert dispatch(['horneroctl', 'hypr', 'plugins', '--help']) == 0
	assert dispatch(['horneroctl', 'help', 'hypr']) == 0
}

fn test_hypr_help_has_examples() {
	for cmd in ['hypr', 'hypr animations', 'hypr layout', 'hypr monitors', 'hypr workspace',
		'hypr plugins'] {
		h := command_help(cmd)
		assert h.contains('Examples:')
	}
}

fn test_hypr_json_and_quiet_modes() {
	hypr_dispatch_setup()
	assert dispatch(['horneroctl', '--json', 'hypr', 'animations', 'list']) == 0
	assert dispatch(['horneroctl', '--quiet', 'hypr', 'animations', 'current']) == 0
	assert dispatch(['horneroctl', '--json', 'hypr', 'layout', 'status']) == 0
	assert dispatch(['horneroctl', '--quiet', 'hypr', 'layout', 'set', 'scrolling', '--dry-run']) == 0
	assert dispatch(['horneroctl', '--json', 'hypr', 'monitors', 'status']) == 0
	assert dispatch(['horneroctl', '--quiet', 'hypr', 'monitors', 'set', 'mirror', '--dry-run']) == 0
	assert dispatch(['horneroctl', '--json', 'hypr', 'workspace', 'next', '--dry-run']) == 0
	assert dispatch(['horneroctl', '--quiet', 'hypr', 'plugins', 'status']) == 0
	hypr_dispatch_teardown()
}
