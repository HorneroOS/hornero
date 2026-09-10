module hornero_core

import os

fn test_exit_codes() {
	assert ErrorClass.ok.exit_code() == 0
	assert ErrorClass.usage_flags.exit_code() == 2
	assert ErrorClass.user.exit_code() == 1
	assert ErrorClass.config.exit_code() == 1
	assert ErrorClass.env.exit_code() == 1
	assert ErrorClass.external.exit_code() == 1
	assert ErrorClass.internal.exit_code() == 1
	assert err_usage('flag.unknown', 'x').exit_code() == 2
	assert err_user('command.failed', 'x').msg() == 'x'
}

fn test_paths_honor_xdg_overrides() {
	os.setenv('XDG_CONFIG_HOME', '/tmp/hx-xdg-test-config', true)
	os.setenv('XDG_DATA_HOME', '/tmp/hx-xdg-test-data', true)
	p := resolve_paths()
	assert p.config_dir == '/tmp/hx-xdg-test-config'
	assert p.data_dir == '/tmp/hx-xdg-test-data'
	assert shell_config_file(p) == '/tmp/hx-xdg-test-config/hornero/shell.json'
	os.unsetenv('XDG_CONFIG_HOME')
	os.unsetenv('XDG_DATA_HOME')
}

fn test_dry_run_never_executes() {
	// /nonexistent-prog would fail if executed; dry-run must still report ok.
	rep := run_exec(ExecSpec{
		prog:    '/nonexistent-prog-hornero-test'
		args:    ['--do-something-dangerous']
		dry_run: true
	})
	assert rep.ok
	assert rep.was_dry_run
	assert rep.command_line == '/nonexistent-prog-hornero-test --do-something-dangerous'
}

fn test_version_result_shape() {
	r := version_result()
	assert r.ok
	assert r.command == 'version'
	assert r.data['version'] == cli_version()
	assert r.message.contains('horneroctl')
}

fn test_doctor_returns_checks() {
	checks := run_doctor()
	assert checks.len >= 5
	names := checks.map(it.name)
	assert 'wayland-session' in names
	assert 'shell-config' in names
	r := doctor_result(checks)
	assert r.command == 'doctor'
	// exit-worthiness follows the worst check, deterministically
	failed := checks.filter(!it.ok).len
	assert r.ok == (failed == 0)
}

fn test_ipc_missing_binary_fails_cleanly() {
	r := ipc_report(IpcOptions{
		passthrough: ['show']
		qs_bin:      '/nonexistent-qs-hornero-test'
	})
	// binary missing but explicitly given: execution fails, no panic
	assert r.command == 'shell ipc'
	assert !r.ok || r.message.contains('qs ipc failed')
}

fn test_ipc_dry_run_ok_without_binary() {
	r := ipc_report(IpcOptions{
		passthrough: ['show']
		dry_run:     true
		qs_bin:      '/nonexistent-qs-hornero-test'
	})
	assert r.ok
	assert r.data['dry_run'] == 'true'
}

fn test_appearance_requires_yes_for_sync() {
	r := appearance_report(AppearanceOptions{
		action:  'sync'
		helper:  '/nonexistent-helper-hornero-test'
		dry_run: false
		yes:     false
	})
	assert !r.ok
	assert r.message.contains('--yes')
}

fn test_config_paths_report() {
	r := config_paths_report()
	assert r.ok
	assert r.message.contains('shell config:')
}

// --- phase-2 fixtures: everything lives under /tmp, XDG overrides isolate
// HOME, and each test unsets what it sets (no network, no compositor). ---

const p2_root = '/tmp/hx-phase2-test'

fn p2_write(path string, content string) {
	os.mkdir_all(os.dir(path)) or { assert false }
	os.write_file(path, content) or { assert false }
}

fn p2_setup_themes() {
	p2_write('${p2_root}/themes/alpha/theme.json', '{"schemaVersion":1,"id":"alpha","name":"Alpha","description":"First pack","gtkTheme":"Orchis-Dark","iconTheme":"Papirus","defaultWallpaper":"a.jpg","wallpaperDir":"alpha"}')
	p2_write('${p2_root}/themes/beta/theme.json', '{"schemaVersion":1,"id":"beta","name":"Beta","defaultWallpaper":"b.jpg","wallpaperDir":"beta","gtkTheme":"Orchis-Light","iconTheme":"Numix"}')
	p2_write('${p2_root}/themes/broken/theme.json', '{not json')
	os.setenv('HORNERO_THEMES_DIR', '${p2_root}/themes', true)
}

fn p2_setup_scheme() {
	p2_write('${p2_root}/state/dots/scheme/state.json', '{"name":"dynamic","flavour":"tonal-spot","mode":"dark","variant":"tonalspot","gtkColorScheme":"follow"}')
	p2_write('${p2_root}/cache/dots/smart-colors/scheme.json', '{"flavour":"expressive","mode":"light"}')
	os.setenv('XDG_STATE_HOME', '${p2_root}/state', true)
	os.setenv('XDG_CACHE_HOME', '${p2_root}/cache', true)
}

fn p2_setup_shell_config() {
	p2_write('${p2_root}/config/hornero/shell.json', '{"bar":{"position":"left","entries":[]},"theme":"vapor","debug":false,"count":3}')
	os.setenv('XDG_CONFIG_HOME', '${p2_root}/config', true)
}

fn p2_setup_presets() {
	p2_write('${p2_root}/presets/hornero-left.json', '{"_name":"Hornero Left","_description":"Left bar","bar":{"position":"left"}}')
	p2_write('${p2_root}/presets/minimal-top.json', '{"_name":"Minimal Top","bar":{"position":"top"}}')
	p2_write('${p2_root}/presets/broken.json', '{oops')
	os.setenv('HORNERO_PRESETS_DIR', '${p2_root}/presets', true)
	os.setenv('HORNERO_PRESET_STATE_FILE', '${p2_root}/preset-current', true)
	os.write_file('${p2_root}/preset-current', 'minimal-top\n') or { assert false }
}

fn test_themes_list_reads_installed_packs() {
	p2_setup_themes()
	packs := list_theme_packs() or {
		assert false
		return
	}
	assert packs.len == 2
	assert packs[0].id == 'alpha'
	assert packs[1].id == 'beta'
	assert packs[0].description == 'First pack'
	r := themes_list_report()
	assert r.ok
	assert r.data['count'] == '2'
	assert r.data['ids'] == 'alpha,beta'
	os.unsetenv('HORNERO_THEMES_DIR')
}

fn test_themes_list_missing_dir_fails_cleanly() {
	os.setenv('HORNERO_THEMES_DIR', '/nonexistent-themes-hornero-test', true)
	r := themes_list_report()
	assert !r.ok
	assert r.message.contains('HORNERO_THEMES_DIR')
	os.unsetenv('HORNERO_THEMES_DIR')
}

fn test_theme_show_detail_and_rejections() {
	p2_setup_themes()
	r := theme_show_report('beta')
	assert r.ok
	assert r.data['name'] == 'Beta'
	assert r.data['gtk_theme'] == 'Orchis-Light'
	assert r.data['wallpaper'] == 'beta/b.jpg'
	assert r.message.contains('wallpaper: beta/b.jpg')
	missing := theme_show_report('no-such-theme')
	assert !missing.ok
	assert missing.message.contains('Theme not found')
	traversal := theme_show_report('../escape')
	assert !traversal.ok
	empty := theme_show_report('')
	assert !empty.ok
	os.unsetenv('HORNERO_THEMES_DIR')
}

fn test_theme_apply_needs_yes_and_previews() {
	dry := theme_apply_report(ThemeApplyOptions{
		id:      'alpha'
		helper:  '/nonexistent-helper-hornero-test'
		dry_run: true
	})
	assert dry.ok
	assert dry.data['dry_run'] == 'true'
	assert dry.message.contains('theme apply alpha')
	refused := theme_apply_report(ThemeApplyOptions{
		id:     'alpha'
		helper: '/nonexistent-helper-hornero-test'
	})
	assert !refused.ok
	assert refused.message.contains('--yes')
	bad := theme_apply_report(ThemeApplyOptions{
		id:      '../escape'
		dry_run: true
	})
	assert !bad.ok
}

fn test_scheme_status_prefers_state_file() {
	p2_setup_scheme()
	s := read_scheme_state()
	assert s.mode == 'dark'
	assert s.flavour == 'tonal-spot'
	assert s.variant == 'tonalspot'
	assert s.gtk_color_scheme == 'follow'
	r := scheme_status_report()
	assert r.ok
	assert r.data['mode'] == 'dark'
	assert r.data['gtk_color_scheme'] == 'follow'
	assert r.message.contains('mode: dark')
	os.unsetenv('XDG_STATE_HOME')
	os.unsetenv('XDG_CACHE_HOME')
}

fn test_scheme_status_without_files_is_unknown_but_ok() {
	os.setenv('XDG_STATE_HOME', '/nonexistent-state-hornero-test', true)
	os.setenv('XDG_CACHE_HOME', '/nonexistent-cache-hornero-test', true)
	r := scheme_status_report()
	assert r.ok
	assert r.message.contains('(unknown)')
	// Missing policy key still defaults to follow (legacy-boot rule).
	assert r.data['gtk_color_scheme'] == 'follow'
	os.unsetenv('XDG_STATE_HOME')
	os.unsetenv('XDG_CACHE_HOME')
}

fn test_scheme_set_validates_and_previews() {
	bad := scheme_set_report(SchemeSetOptions{
		kind:  'mode'
		value: 'dim'
	})
	assert !bad.ok
	assert bad.message.contains('dark|light')
	dry := scheme_set_report(SchemeSetOptions{
		kind:    'mode'
		value:   'dark'
		dry_run: true
		helper:  '/nonexistent-helper-hornero-test'
	})
	assert dry.ok
	assert dry.message.contains('set-mode dark')
	refused := scheme_set_report(SchemeSetOptions{
		kind:   'variant'
		value:  'tonalspot'
		helper: '/nonexistent-helper-hornero-test'
	})
	assert !refused.ok
	assert refused.message.contains('--yes')
}

fn test_config_show_values_and_lookups() {
	p2_setup_shell_config()
	all := config_show_report('')
	assert all.ok
	assert all.data['count'] == '4'
	assert all.message.contains('theme: vapor')
	assert all.message.contains('bar: (object, 2 keys)')
	one := config_show_report('bar.position')
	assert one.ok
	assert one.message == 'left'
	assert one.data['value'] == 'left'
	obj := config_show_report('bar')
	assert obj.ok
	assert obj.message.contains('"position"')
	missing := config_show_report('bar.nope')
	assert !missing.ok
	assert missing.message.contains('Key not found')
	through_scalar := config_show_report('theme.deeper')
	assert !through_scalar.ok
	os.unsetenv('XDG_CONFIG_HOME')
}

fn test_preset_list_and_current() {
	p2_setup_presets()
	presets := list_presets() or {
		assert false
		return
	}
	// Broken preset file is skipped, survivors sorted by name.
	assert presets.len == 2
	assert presets[0].name == 'hornero-left'
	assert presets[1].name == 'minimal-top'
	assert presets[1].active
	assert !presets[0].active
	assert presets[0].position == 'left'
	r := preset_list_report()
	assert r.ok
	assert r.data['count'] == '2'
	assert r.data['active'] == 'minimal-top'
	assert r.message.contains('(active)')
	c := preset_current_report()
	assert c.ok
	assert c.message == 'minimal-top'
	os.unsetenv('HORNERO_PRESETS_DIR')
	os.unsetenv('HORNERO_PRESET_STATE_FILE')
}

fn test_preset_missing_dir_and_pointer() {
	os.setenv('HORNERO_PRESETS_DIR', '/nonexistent-presets-hornero-test', true)
	r := preset_list_report()
	assert !r.ok
	assert r.message.contains('HORNERO_PRESETS_DIR')
	os.unsetenv('HORNERO_PRESETS_DIR')
	os.setenv('HORNERO_PRESET_STATE_FILE', '/nonexistent-preset-state-hornero-test', true)
	c := preset_current_report()
	assert c.ok
	assert c.message == 'none'
	os.unsetenv('HORNERO_PRESET_STATE_FILE')
}
