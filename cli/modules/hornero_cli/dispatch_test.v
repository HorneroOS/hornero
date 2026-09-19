module hornero_cli

import os

fn test_dispatch_version_exit_zero() {
	assert dispatch(['horneroctl', 'version']) == 0
}

fn test_dispatch_help_exit_zero() {
	assert dispatch(['horneroctl', '--help']) == 0
	assert dispatch(['horneroctl', 'help', 'doctor']) == 0
	assert dispatch(['horneroctl', 'doctor', '--help']) == 0
}

fn test_dispatch_unknown_command_exit_one() {
	assert dispatch(['horneroctl', 'not-a-real-command']) == 1
}

fn test_dispatch_unknown_flag_exit_two() {
	assert dispatch(['horneroctl', '--bogus-flag']) == 2
	assert dispatch(['horneroctl', 'shell', 'ipc', '--bogus']) == 2
}

fn test_dispatch_leading_json_before_command() {
	assert dispatch(['horneroctl', '--json', 'version']) == 0
}

fn test_dispatch_leading_quiet_before_command() {
	assert dispatch(['horneroctl', '--quiet', 'version']) == 0
}

fn test_dispatch_shell_status_codes() {
	code := dispatch(['horneroctl', 'shell', 'status'])
	assert code == 0
}

fn test_dispatch_shell_ipc_dry_run() {
	code := dispatch(['horneroctl', 'shell', 'ipc', '--dry-run', '--', 'show'])
	assert code == 0
}

fn test_dispatch_shell_lifecycle() {
	// Hermetic: broken backends; dry-run previews must still pass and
	// never touch the process table.
	os.setenv('HORNERO_QUICKSHELL_BIN', '/nonexistent-quickshell-hornero-test', true)
	os.setenv('HORNERO_PGREP_BIN', '/nonexistent-pgrep-hornero-test', true)
	os.setenv('HORNERO_QUICKSHELL_CONFIG_DIR', '/nonexistent-conf-hornero-test', true)
	os.setenv('HORNERO_SHELL_LOG_FILE', '/nonexistent-log-hornero-test.log', true)
	assert dispatch(['horneroctl', 'shell', 'start', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'shell', 'stop', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'shell', 'restart', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'shell', 'logs', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'shell', 'logs', '--lines', '10', '--dry-run']) == 0
	// Mutations without --yes refuse (exit 1), never signal anything.
	assert dispatch(['horneroctl', 'shell', 'start']) == 1
	assert dispatch(['horneroctl', 'shell', 'stop']) == 1
	assert dispatch(['horneroctl', 'shell', 'restart']) == 1
	// Usage errors (exit 2).
	assert dispatch(['horneroctl', 'shell', 'bogus']) == 2
	assert dispatch(['horneroctl', 'shell', 'logs', '--lines']) == 2
	assert dispatch(['horneroctl', 'shell', 'logs', '--lines', 'zero']) == 2
	assert dispatch(['horneroctl', 'shell', 'status', '--dry-run']) == 2
	assert dispatch(['horneroctl', 'shell', 'start', '--lines', '10']) == 2
	os.unsetenv('HORNERO_QUICKSHELL_BIN')
	os.unsetenv('HORNERO_PGREP_BIN')
	os.unsetenv('HORNERO_QUICKSHELL_CONFIG_DIR')
	os.unsetenv('HORNERO_SHELL_LOG_FILE')
}

fn test_dispatch_shell_help_has_examples() {
	assert command_help('shell').contains('Examples:')
}

fn test_dry_run_needs_no_backend() {
	// Hermetic: point both backends at nonexistent paths; dry-run must
	// still preview successfully on any machine (CI has no qs/dots-*).
	os.setenv('HORNERO_QS_BIN', '/nonexistent-qs-hornero-test', true)
	assert dispatch(['horneroctl', 'shell', 'ipc', '--dry-run', '--', 'show']) == 0
	os.unsetenv('HORNERO_QS_BIN')
	os.setenv('HORNERO_APPEARANCE_BIN', '/nonexistent-appearance-hornero-test', true)
	assert dispatch(['horneroctl', 'appearance', 'sync', '--dry-run']) == 0
	os.unsetenv('HORNERO_APPEARANCE_BIN')
}

fn test_dispatch_appearance_sync_needs_yes() {
	// Without --yes/--dry-run this must refuse (exit 1), never apply.
	code := dispatch(['horneroctl', 'appearance', 'sync'])
	assert code == 1
}

fn test_dispatch_config_paths() {
	assert dispatch(['horneroctl', 'config', 'paths']) == 0
}

fn test_dispatch_completion() {
	assert dispatch(['horneroctl', 'completion', 'bash']) == 0
	assert dispatch(['horneroctl', 'completion', 'powershell']) == 1
}

fn test_every_help_has_examples() {
	for cmd in ['version', 'doctor', 'shell', 'shell preset', 'appearance', 'appearance theme',
		'appearance scheme', 'appearance colors', 'appearance accent', 'appearance night-mode',
		'scheme', 'config', 'completion'] {
		h := command_help(cmd)
		assert h.contains('Examples:')
	}
	assert root_help().contains('Examples:')
}

fn test_dispatch_nested_help_exit_zero() {
	assert dispatch(['horneroctl', 'appearance', 'theme', '--help']) == 0
	assert dispatch(['horneroctl', 'appearance', 'scheme', '--help']) == 0
	assert dispatch(['horneroctl', 'appearance', 'colors', '--help']) == 0
	assert dispatch(['horneroctl', 'appearance', 'accent', '--help']) == 0
	assert dispatch(['horneroctl', 'appearance', 'night-mode', '--help']) == 0
	assert dispatch(['horneroctl', 'shell', 'preset', '--help']) == 0
	assert dispatch(['horneroctl', 'scheme', '--help']) == 0
	assert dispatch(['horneroctl', 'help', 'scheme']) == 0
}

// Phase-2 dispatch fixtures reuse the /tmp tree the core tests build;
// each test sets the overrides it needs and unsets them afterwards.
fn p2_dispatch_setup() {
	os.mkdir_all('/tmp/hx-phase2-dtest/themes/alpha') or { assert false }
	os.write_file('/tmp/hx-phase2-dtest/themes/alpha/theme.json', '{"schemaVersion":1,"id":"alpha","name":"Alpha","defaultWallpaper":"a.jpg","wallpaperDir":"alpha"}') or {
		assert false
	}
	os.mkdir_all('/tmp/hx-phase2-dtest/presets') or { assert false }
	os.write_file('/tmp/hx-phase2-dtest/presets/alpha.json', '{"_name":"Alpha"}') or {
		assert false
	}
	os.mkdir_all('/tmp/hx-phase2-dtest/config/hornero') or { assert false }
	os.write_file('/tmp/hx-phase2-dtest/config/hornero/shell.json', '{"bar":{"position":"left"}}') or {
		assert false
	}
	os.setenv('HORNERO_THEMES_DIR', '/tmp/hx-phase2-dtest/themes', true)
	os.setenv('HORNERO_PRESETS_DIR', '/tmp/hx-phase2-dtest/presets', true)
	os.setenv('HORNERO_PRESET_STATE_FILE', '/tmp/hx-phase2-dtest/preset-missing', true)
	os.setenv('XDG_CONFIG_HOME', '/tmp/hx-phase2-dtest/config', true)
	os.setenv('HORNERO_DOTS_APPEARANCE_BIN', '/nonexistent-appearance-hornero-test', true)
}

fn p2_dispatch_teardown() {
	os.unsetenv('HORNERO_THEMES_DIR')
	os.unsetenv('HORNERO_PRESETS_DIR')
	os.unsetenv('HORNERO_PRESET_STATE_FILE')
	os.unsetenv('XDG_CONFIG_HOME')
	os.unsetenv('HORNERO_DOTS_APPEARANCE_BIN')
}

fn test_dispatch_appearance_theme() {
	p2_dispatch_setup()
	assert dispatch(['horneroctl', 'appearance', 'theme', 'list']) == 0
	assert dispatch(['horneroctl', 'appearance', 'theme', 'list', '--full']) == 0
	assert dispatch(['horneroctl', 'appearance', 'theme', 'list', '--dry-run']) == 2
	assert dispatch(['horneroctl', 'appearance', 'theme', 'show', 'alpha']) == 0
	assert dispatch(['horneroctl', 'appearance', 'theme', 'show', 'missing']) == 1
	assert dispatch(['horneroctl', 'appearance', 'theme', 'show']) == 2
	assert dispatch(['horneroctl', 'appearance', 'theme', 'apply', 'alpha', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'appearance', 'theme', 'apply', 'alpha']) == 1
	assert dispatch(['horneroctl', 'appearance', 'theme', 'bogus']) == 2
	p2_dispatch_teardown()
}

fn test_dispatch_appearance_scheme_and_alias() {
	p2_dispatch_setup()
	assert dispatch(['horneroctl', 'appearance', 'scheme', 'status']) == 0
	assert dispatch(['horneroctl', 'scheme', 'status']) == 0
	assert dispatch(['horneroctl', 'appearance', 'scheme', 'set-mode', 'dark', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'scheme', 'set-mode', 'dark', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'appearance', 'scheme', 'set-mode', 'dim', '--dry-run']) == 1
	assert dispatch(['horneroctl', 'appearance', 'scheme', 'set-mode', 'dark']) == 1
	assert dispatch(['horneroctl', 'appearance', 'scheme', 'bogus']) == 2
	p2_dispatch_teardown()
}

fn test_dispatch_appearance_plus() {
	// Hermetic: nonexistent backends; dry-run previews must still exit 0
	// (CI has no dots-*), real runs must fail cleanly, usage errors exit 2.
	os.setenv('HORNERO_SMART_COLORS_BIN', '/nonexistent-colors-hornero-test', true)
	os.setenv('HORNERO_M3_COLORS_BIN', '/nonexistent-m3-hornero-test', true)
	os.setenv('HORNERO_NIGHT_MODE_BIN', '/nonexistent-night-hornero-test', true)
	os.setenv('HORNERO_ACCENT_OVERRIDE_BIN', '/nonexistent-accent-hornero-test', true)
	assert dispatch(['horneroctl', 'appearance', 'colors', 'status']) == 1
	assert dispatch(['horneroctl', 'appearance', 'colors', 'status', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'appearance', 'colors', 'generate', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'appearance', 'colors', 'generate', '--m3', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'appearance', 'colors', 'generate']) == 1
	assert dispatch(['horneroctl', 'appearance', 'colors', 'm3', '--dry-run', '--', '--help']) == 0
	assert dispatch(['horneroctl', 'appearance', 'colors', 'bogus']) == 2
	assert dispatch(['horneroctl', 'appearance', 'accent', 'show', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'appearance', 'accent', 'set', '#8839ef', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'appearance', 'accent', 'set', 'bogus', '--dry-run']) == 1
	assert dispatch(['horneroctl', 'appearance', 'accent', 'set', '#8839ef']) == 1
	assert dispatch(['horneroctl', 'appearance', 'accent', 'clear', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'appearance', 'accent', 'clear']) == 1
	assert dispatch(['horneroctl', 'appearance', 'accent', 'bogus']) == 2
	assert dispatch(['horneroctl', 'appearance', 'night-mode', 'status']) == 1
	assert dispatch(['horneroctl', 'appearance', 'night-mode', 'status', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'appearance', 'night-mode', 'toggle']) == 1
	os.unsetenv('HORNERO_SMART_COLORS_BIN')
	os.unsetenv('HORNERO_M3_COLORS_BIN')
	os.unsetenv('HORNERO_NIGHT_MODE_BIN')
	os.unsetenv('HORNERO_ACCENT_OVERRIDE_BIN')
}

fn test_dispatch_shell_preset() {
	p2_dispatch_setup()
	assert dispatch(['horneroctl', 'shell', 'preset', 'list']) == 0
	assert dispatch(['horneroctl', 'shell', 'preset', 'list', '--full']) == 0
	assert dispatch(['horneroctl', 'shell', 'preset', 'current']) == 0
	assert dispatch(['horneroctl', 'shell', 'preset', 'apply', 'alpha']) == 1
	assert dispatch(['horneroctl', 'shell', 'preset', 'apply']) == 2
	assert dispatch(['horneroctl', 'shell', 'preset', 'bogus']) == 2
	assert dispatch(['horneroctl', 'shell', 'preset', 'list', '--bogus']) == 2
	p2_dispatch_teardown()
}

fn test_dispatch_config_show() {
	p2_dispatch_setup()
	assert dispatch(['horneroctl', 'config', 'show']) == 0
	assert dispatch(['horneroctl', 'config', 'show', 'bar.position']) == 0
	assert dispatch(['horneroctl', 'config', 'show', 'bar.nope']) == 1
	assert dispatch(['horneroctl', 'config', 'show', 'a', 'b']) == 2
	p2_dispatch_teardown()
}

fn test_dispatch_welcome_status_readonly() {
	assert dispatch(['horneroctl', 'welcome', 'status']) == 0
	assert dispatch(['horneroctl', 'welcome', 'status', '--bogus']) == 2
	assert dispatch(['horneroctl', 'welcome', 'status', 'extra']) == 2
	assert dispatch(['horneroctl', 'welcome']) == 2
	assert dispatch(['horneroctl', 'welcome', 'bogus']) == 2
}

fn test_dispatch_welcome_mutations_need_yes() {
	assert dispatch(['horneroctl', 'welcome', 'set-show-on-login', 'false']) == 1
	assert dispatch(['horneroctl', 'welcome', 'set-show-on-login', 'false', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'welcome', 'set-show-on-login']) == 2
	assert dispatch(['horneroctl', 'welcome', 'set-show-on-login', 'maybe', '--yes']) == 2
	assert dispatch(['horneroctl', 'welcome', 'mark-seen']) == 1
	assert dispatch(['horneroctl', 'welcome', 'mark-seen', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'welcome', 'reset']) == 1
	assert dispatch(['horneroctl', 'welcome', 'reset', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'welcome', 'open', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'welcome', 'open', 'BAD PAGE!']) == 1
}
