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
	b2_write('${b2_root}/bin/horneroctl config default-apps', '#!/bin/sh\nif [ "\$1" = "--list" ]; then printf "web-browser: firefox.desktop\\ntext-editor: nvim.desktop\\n"; exit 0; fi\nexit 1\n')
	b2_write('${b2_root}/bin/materialize.sh', '#!/bin/sh\necho "materialized \$*"\nexit 0\n')
	os.setenv('HORNERO_DEFAULT_APPS_BIN', '${b2_root}/bin/horneroctl config default-apps', true)
	os.setenv('HORNERO_MATERIALIZE_BIN', '${b2_root}/bin/materialize.sh', true)
}

fn b2_teardown_backends() {
	os.unsetenv('HORNERO_DEFAULT_APPS_BIN')
	os.unsetenv('HORNERO_MATERIALIZE_BIN')
}

fn b2_isolate_resolution() (string, string) {
	old_home := os.getenv('HOME')
	old_path := os.getenv('PATH')
	os.setenv('HOME', b2_root, true)
	os.setenv('PATH', '/nonexistent-path-hornero-test', true)
	os.unsetenv('HORNERO_DEFAULT_APPS_BIN')
	os.unsetenv('HORNERO_MATERIALIZE_BIN')
	return old_home, old_path
}

fn b2_restore_resolution(old_home string, old_path string) {
	os.setenv('HOME', old_home, true)
	os.setenv('PATH', old_path, true)
}

fn test_default_apps_list_runs_native() {
	// Native port: list reads helpers.rc + handlr directly; the
	// horneroctl config default-apps backend is gone, so the fixture backend below
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
	// The explicit destination reaches the backend exactly as given.
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
	assert !r.data['command_line'].contains('/retired/')
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

fn test_settings_gui_previews_native_shell_ipc() {
	b2_setup_backends()
	b2_write('${b2_root}/bin/qs', '#!/bin/sh\nprintf "ipc %s\\n" "$*"\n')
	os.setenv('HORNERO_QS_BIN', '${b2_root}/bin/qs', true)
	d := settings_gui_report(SettingsGuiOptions{
		pane:    'vpn'
		dry_run: true
	})
	assert d.ok
	assert d.data['dry_run'] == 'true'
	assert d.message.contains('ipc call controlCenter open vpn')
	default_dry_run := settings_gui_report(SettingsGuiOptions{ dry_run: true })
	assert default_dry_run.ok
	assert default_dry_run.message.contains('ipc call controlCenter open network')
	r := settings_gui_report(SettingsGuiOptions{ pane: 'vpn' })
	assert r.ok
	assert r.message.contains('call controlCenter open vpn')
	os.unsetenv('HORNERO_QS_BIN')
	b2_teardown_backends()
}

fn test_settings_gui_missing_backend_fails_cleanly() {
	old_home, old_path := b2_isolate_resolution()
	r := settings_gui_report(SettingsGuiOptions{})
	assert r.command == 'config gui'
	assert !r.ok
	assert r.message.contains('Hornero Shell running') || r.message.contains('qs not found')
	b2_restore_resolution(old_home, old_path)
}

fn test_default_apps_friendly_name_searches_all_dirs() {
	// A Name-less .desktop file in the first dir must not stop the
	// search: the Name= entry in a later dir wins.
	base := '/tmp/hx-friendly-test'
	os.rmdir_all(base) or {}
	b2_write(base + '/a/app.desktop', '[Desktop Entry]\nType=Application\n')
	b2_write(base + '/b/app.desktop', '[Desktop Entry]\nName=Second Name\n')
	assert default_apps_friendly_name('app.desktop', [base + '/a', base + '/b']) == 'Second Name'
	assert default_apps_friendly_name('missing.desktop', [base + '/a']) == 'missing.desktop'
	os.rmdir_all(base) or {}
}
