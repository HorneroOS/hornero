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
		'appearance scheme', 'scheme', 'config', 'completion'] {
		h := command_help(cmd)
		assert h.contains('Examples:')
	}
	assert root_help().contains('Examples:')
}

fn test_dispatch_nested_help_exit_zero() {
	assert dispatch(['horneroctl', 'appearance', 'theme', '--help']) == 0
	assert dispatch(['horneroctl', 'appearance', 'scheme', '--help']) == 0
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

fn test_dispatch_shell_preset() {
	p2_dispatch_setup()
	assert dispatch(['horneroctl', 'shell', 'preset', 'list']) == 0
	assert dispatch(['horneroctl', 'shell', 'preset', 'current']) == 0
	assert dispatch(['horneroctl', 'shell', 'preset', 'apply', 'alpha']) == 2
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
