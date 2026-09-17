module hornero_core

import os

// Batch-2 fixtures: everything lives under /tmp, env overrides isolate
// HOME/PATH, and each test unsets what it sets (no network, no
// compositor, no real backends).

const b2_root = '/tmp/hx-batch2-test'

fn b2_write(path string, content string) {
	os.mkdir_all(os.dir(path)) or { assert false }
	os.write_file(path, content) or { assert false }
	os.chmod(path, 0o755) or { assert false }
}

fn b2_setup_backends() {
	b2_write('${b2_root}/bin/dots-default-apps', '#!/bin/sh\nif [ "\$1" = "--list" ]; then printf "web-browser: firefox.desktop\\ntext-editor: nvim.desktop\\n"; exit 0; fi\nexit 1\n')
	b2_write('${b2_root}/bin/dots-settings-gui', '#!/bin/sh\necho "settings hub \$*"\nexit 0\n')
	b2_write('${b2_root}/bin/materialize.sh', '#!/bin/sh\necho "materialized \$*"\nexit 0\n')
	os.setenv('HORNERO_DEFAULT_APPS_BIN', '${b2_root}/bin/dots-default-apps', true)
	os.setenv('HORNERO_SETTINGS_GUI_BIN', '${b2_root}/bin/dots-settings-gui', true)
	os.setenv('HORNERO_MATERIALIZE_BIN', '${b2_root}/bin/materialize.sh', true)
}

fn b2_teardown_backends() {
	os.unsetenv('HORNERO_DEFAULT_APPS_BIN')
	os.unsetenv('HORNERO_SETTINGS_GUI_BIN')
	os.unsetenv('HORNERO_MATERIALIZE_BIN')
}

fn b2_isolate_resolution() (string, string) {
	old_home := os.getenv('HOME')
	old_path := os.getenv('PATH')
	os.setenv('HOME', b2_root, true)
	os.setenv('PATH', '/nonexistent-path-hornero-test', true)
	os.unsetenv('HORNERO_DEFAULT_APPS_BIN')
	os.unsetenv('HORNERO_SETTINGS_GUI_BIN')
	os.unsetenv('HORNERO_MATERIALIZE_BIN')
	return old_home, old_path
}

fn b2_restore_resolution(old_home string, old_path string) {
	os.setenv('HOME', old_home, true)
	os.setenv('PATH', old_path, true)
}

fn test_default_apps_list_runs_native() {
	// Native port: list reads helpers.rc + handlr directly; the legacy
	// dots-default-apps backend is gone, so the fixture backend below
	// must stay unused (a fake desktop id proves it: no .desktop file
	// exists for it, and the id itself is reported).
	b2_setup_backends()
	b2_write('${b2_root}/bin/handlr', '#!/bin/sh\necho "hx-test-fake-12345.desktop"\nexit 0\n')
	os.setenv('HORNERO_HANDLR_BIN', '${b2_root}/bin/handlr', true)
	b2_write('${b2_root}/config/xfce4/helpers.rc', 'TerminalEmulator=kitty\n')
	os.setenv('XDG_CONFIG_HOME', '${b2_root}/config', true)
	r := default_apps_list_report(DefaultAppsListOptions{})
	assert r.ok
	assert r.command == 'config default-apps list'
	assert r.message.contains('Current Default Applications:')
	assert r.message.contains('Kitty Terminal')
	assert r.data['terminal'] == 'Kitty Terminal'
	assert r.data['web-browser'] == 'hx-test-fake-12345.desktop'
	os.unsetenv('HORNERO_HANDLR_BIN')
	os.unsetenv('XDG_CONFIG_HOME')
	b2_teardown_backends()
}

fn test_default_apps_list_dry_run_needs_no_backend() {
	os.setenv('HORNERO_DEFAULT_APPS_BIN', '/nonexistent-default-apps-hornero-test', true)
	d := default_apps_list_report(DefaultAppsListOptions{
		dry_run: true
	})
	assert d.ok
	assert d.data['dry_run'] == 'true'
	assert d.message.contains('--list')
	os.unsetenv('HORNERO_DEFAULT_APPS_BIN')
}

fn test_default_apps_list_missing_handlr_fails_cleanly() {
	old_home, old_path := b2_isolate_resolution()
	os.unsetenv('HORNERO_HANDLR_BIN')
	r := default_apps_list_report(DefaultAppsListOptions{})
	assert r.command == 'config default-apps list'
	assert !r.ok
	assert r.message.contains('HORNERO_HANDLR_BIN')
	b2_restore_resolution(old_home, old_path)
}

fn test_materialize_needs_yes_and_previews() {
	b2_setup_backends()
	r := materialize_report(MaterializeOptions{
		dest: '${b2_root}/dest'
	})
	assert !r.ok
	assert r.message.contains('--yes')
	d := materialize_report(MaterializeOptions{
		dest:    '${b2_root}/dest'
		dry_run: true
	})
	assert d.ok
	assert d.data['dry_run'] == 'true'
	assert d.message.contains('--dest ${b2_root}/dest')
	assert d.message.contains('--dry-run')
	b2_teardown_backends()
}

fn test_materialize_passes_dest_through_verbatim() {
	// Canonical-first: the explicit destination reaches the backend
	// exactly as given, never rewritten to a legacy `dots/*` path.
	b2_setup_backends()
	dest := '${b2_root}/canon-dest'
	r := materialize_report(MaterializeOptions{
		dest: dest
		yes:  true
	})
	assert r.ok
	assert r.command == 'config materialize'
	assert r.data['dest'] == dest
	assert r.data['command_line'] == '${b2_root}/bin/materialize.sh --dest ${dest}'
	assert !r.data['command_line'].contains('/dots/')
	b2_teardown_backends()
}

fn test_materialize_missing_backend_fails_cleanly() {
	old_home, old_path := b2_isolate_resolution()
	r := materialize_report(MaterializeOptions{
		dest: '${b2_root}/dest'
		yes:  true
	})
	assert r.command == 'config materialize'
	assert !r.ok
	assert r.message.contains('HORNERO_MATERIALIZE_BIN')
	b2_restore_resolution(old_home, old_path)
}

fn test_settings_gui_validates_pane_and_previews() {
	b2_setup_backends()
	bad := settings_gui_report(SettingsGuiOptions{
		pane: 'bogus'
	})
	assert !bad.ok
	assert bad.message.contains('invalid pane')
	d := settings_gui_report(SettingsGuiOptions{
		pane:    'appearance'
		dry_run: true
	})
	assert d.ok
	assert d.data['dry_run'] == 'true'
	assert d.message.contains('--pane=appearance')
	p := settings_gui_report(SettingsGuiOptions{
		dry_run: true
	})
	assert p.ok
	assert p.message.contains('dots-settings-gui')
	b2_teardown_backends()
}

fn test_settings_gui_runs_backend() {
	b2_setup_backends()
	r := settings_gui_report(SettingsGuiOptions{})
	assert r.ok
	assert r.command == 'config gui'
	assert r.message.contains('settings hub')
	b2_teardown_backends()
}

fn test_settings_gui_missing_backend_fails_cleanly() {
	old_home, old_path := b2_isolate_resolution()
	r := settings_gui_report(SettingsGuiOptions{})
	assert r.command == 'config gui'
	assert !r.ok
	assert r.message.contains('HORNERO_SETTINGS_GUI_BIN')
	b2_restore_resolution(old_home, old_path)
}

fn test_batch2_resolvers_honor_overrides() {
	os.setenv('HORNERO_DEFAULT_APPS_BIN', '/tmp/hx-b2-ov/dots-default-apps', true)
	os.setenv('HORNERO_SETTINGS_GUI_BIN', '/tmp/hx-b2-ov/dots-settings-gui', true)
	os.setenv('HORNERO_MATERIALIZE_BIN', '/tmp/hx-b2-ov/materialize.sh', true)
	assert resolve_default_apps_bin() == '/tmp/hx-b2-ov/dots-default-apps'
	assert resolve_settings_gui_bin() == '/tmp/hx-b2-ov/dots-settings-gui'
	assert resolve_materialize_bin() == '/tmp/hx-b2-ov/materialize.sh'
	b2_teardown_backends()
}

fn test_batch2_resolvers_never_hardcode_dots_paths() {
	// Path-contract binding (docs/PATH_CONTRACT.md rows 1-5,9,11):
	// with no override and no installed helper on PATH/HOME, batch-2
	// resolvers return '' (callers fail cleanly naming the override)
	// instead of a hardcoded `dots/*` path that bypasses resolution.
	old_home, old_path := b2_isolate_resolution()
	assert resolve_default_apps_bin() == ''
	assert resolve_settings_gui_bin() == ''
	assert resolve_materialize_bin() == ''
	for bin in [resolve_default_apps_bin(), resolve_settings_gui_bin(),
		resolve_materialize_bin()] {
		assert !bin.contains('/dots/')
	}
	b2_restore_resolution(old_home, old_path)
}
