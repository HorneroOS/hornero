module hornero_core

import os

fn with_apply_xdg(tmp string, body fn ()) {
	os.mkdir_all(tmp) or {}
	os.setenv('XDG_CONFIG_HOME', os.join_path(tmp, 'config'), true)
	os.setenv('XDG_DATA_HOME', os.join_path(tmp, 'data'), true)
	os.setenv('XDG_STATE_HOME', os.join_path(tmp, 'state'), true)
	os.setenv('XDG_CACHE_HOME', os.join_path(tmp, 'cache'), true)
	os.setenv('HORNERO_GTK2_FILE', os.join_path(tmp, 'gtkrc-2.0'), true)
	os.setenv('HORNERO_M3_PYTHON_BIN', '/nonexistent/py', true)
	os.setenv('HORNERO_M3_SCRIPT', os.join_path(tmp, 'gen-m3.py'), true)
	os.setenv('HORNERO_GSETTINGS_BIN', '/nonexistent/gsettings', true)
	body()
	os.unsetenv('XDG_CONFIG_HOME')
	os.unsetenv('XDG_DATA_HOME')
	os.unsetenv('XDG_STATE_HOME')
	os.unsetenv('XDG_CACHE_HOME')
	os.unsetenv('HORNERO_GTK2_FILE')
	os.unsetenv('HORNERO_M3_PYTHON_BIN')
	os.unsetenv('HORNERO_M3_SCRIPT')
	os.unsetenv('HORNERO_GSETTINGS_BIN')
}

fn write_pack(tmp string, id string) {
	dir := os.join_path(tmp, 'data', 'hornero', 'themes', id)
	os.mkdir_all(dir) or {}
	os.write_file(os.join_path(dir, 'theme.json'), '{"schemaVersion": 1, "id": "${id}", "name": "T", "defaultWallpaper": "w.jpg", "wallpaperDir": "t", "schemeType": "tonal-spot", "darkMode": true, "gtkTheme": "Orchis-Dark", "iconTheme": "Numix-Circle"}\n') or {}
	os.setenv('HORNERO_THEMES_DIR', os.join_path(tmp, 'data', 'hornero', 'themes'), true)
}

fn test_theme_apply_rejects_bad_id() {
	rep := theme_apply_native('../x', '', true)
	assert !rep.ok
	rep2 := theme_apply_native('', '', true)
	assert !rep2.ok
}

fn test_theme_apply_missing_pack() {
	tmp := os.join_path(os.temp_dir(), 'hornero-apply-missing')
	os.rmdir_all(tmp) or {}
	os.setenv('HORNERO_THEMES_DIR', os.join_path(tmp, 'none'), true)
	rep := theme_apply_native('ghost', '', true)
	assert !rep.ok
	assert rep.message.contains('Theme not found')
	os.unsetenv('HORNERO_THEMES_DIR')
	os.rmdir_all(tmp) or {}
}

fn test_theme_apply_dry_run_previews_pipeline() {
	tmp := os.join_path(os.temp_dir(), 'hornero-apply-dry')
	os.rmdir_all(tmp) or {}
	with_apply_xdg(tmp, fn [tmp] () {
		write_pack(tmp, 'demo')
		wall := os.join_path(tmp, 'w.jpg')
		os.write_file(wall, 'x') or {}
		rep := theme_apply_native('demo', wall, true)
		assert rep.ok, rep.message
		assert rep.data['dry_run'] == 'true'
		assert rep.message.contains('wal')
		assert rep.message.contains('gen-m3.py')
		assert rep.message.contains('Orchis-Dark')
	})
	os.unsetenv('HORNERO_THEMES_DIR')
	os.rmdir_all(tmp) or {}
}

fn test_color_only_theme_uses_current_wallpaper_when_its_default_is_missing() {
	tmp := os.join_path(os.temp_dir(), 'hornero-color-only-wallpaper')
	os.rmdir_all(tmp) or {}
	defer {
		os.unsetenv('HORNERO_WALLPAPERS_DIR')
		os.unsetenv('HORNERO_PICTURES_WALLPAPERS')
		os.unsetenv('HORNERO_WALLPAPER_POINTER_FILE')
		os.unsetenv('HORNERO_THEMES_DIR')
		os.rmdir_all(tmp) or {}
	}
	with_apply_xdg(tmp, fn [tmp] () {
		write_pack(tmp, 'color-only')
		pack_file := os.join_path(tmp, 'data', 'hornero', 'themes', 'color-only', 'theme.json')
		os.write_file(pack_file, '{"id":"color-only","name":"Color only","defaultWallpaper":"missing.jpg","wallpaperDir":"color-only","colorOnly":true}') or {}
		os.setenv('HORNERO_WALLPAPERS_DIR', os.join_path(tmp, 'walls'), true)
		os.setenv('HORNERO_PICTURES_WALLPAPERS', os.join_path(tmp, 'pictures'), true)
		os.setenv('HORNERO_WALLPAPER_POINTER_FILE', os.join_path(tmp, 'state', 'hornero', 'wallpaper', 'path'), true)
		current := os.join_path(tmp, 'current.jpg')
		os.write_file(current, 'wallpaper') or {}
		pointer := resolve_wallpaper_pointer_file()
		os.mkdir_all(os.dir(pointer)) or {}
		os.write_file(pointer, current) or {}
		resolved := resolve_theme_apply_wallpaper('color-only', 'color-only', 'missing.jpg', '', true, false) or {
			assert false, err.msg()
			''
		}
		assert resolved == current
		os.rm(pointer) or {}
		missing := resolve_theme_apply_wallpaper('color-only', 'color-only', 'missing.jpg', '', true, false) or {
			assert err.msg().contains('no current wallpaper is available')
			''
		}
		assert missing == ''
		preview := resolve_theme_apply_wallpaper('color-only', 'color-only', 'missing.jpg', '', true, true) or {
			assert false, err.msg()
			''
		}
		assert preview == '<current wallpaper>'
	})
}

fn test_sync_state_from_scheme_roundtrip() {
	tmp := os.join_path(os.temp_dir(), 'hornero-syncstate')
	os.rmdir_all(tmp) or {}
	with_apply_xdg(tmp, fn [tmp] () {
		scheme := color_scheme_file()
		os.mkdir_all(os.dir(scheme)) or {}
		os.write_file(scheme, '{"name": "dynamic", "flavour": "vibrant", "mode": "light", "gtkColorScheme": "prefer-light", "colours": {"primary": "FF0000"}}\n') or {}
		path := sync_state_from_scheme() or {
			assert false, err.msg()
			return
		}
		assert os.is_file(path)
		raw := os.read_file(path) or { '' }
		assert raw.contains('"vibrant"')
		assert raw.contains('"light"')
		assert raw.contains('"gtkColorScheme":"prefer-light"')
		cur := scheme_current_report()
		assert cur.ok
		assert cur.message.contains('vibrant')
		list := scheme_list_report()
		assert list.ok
		assert list.message.contains('"vibrant"')
		assert list.message.contains('FF0000')
	})
	os.rmdir_all(tmp) or {}
}

fn test_sync_state_from_scheme_keeps_selected_theme_id() {
	tmp := os.join_path(os.temp_dir(), 'hornero-syncstate-theme-id')
	os.rmdir_all(tmp) or {}
	with_apply_xdg(tmp, fn [tmp] () {
		write_pack(tmp, 'pampa')
		scheme := color_scheme_file()
		os.mkdir_all(os.dir(scheme)) or {}
		os.write_file(scheme, '{"name":"dynamic","flavour":"tonal-spot","mode":"dark","colours":{}}\n') or {}
		path := sync_state_from_scheme_with_theme_id('pampa') or {
			assert false, err.msg()
			return
		}
		state := os.read_file(path) or { '' }
		assert state.contains('pampa')
		assert state.contains('dark')
		assert state.contains('tonal-spot')
	})
	os.unsetenv('HORNERO_THEMES_DIR')
	os.rmdir_all(tmp) or {}
}

fn test_sync_state_missing_scheme_fails() {
	tmp := os.join_path(os.temp_dir(), 'hornero-syncmissing')
	os.rmdir_all(tmp) or {}
	with_apply_xdg(tmp, fn [tmp] () {
		if _ := sync_state_from_scheme() {
			assert false, 'must fail without scheme.json'
		} else {
			assert err.msg().contains('missing')
		}
	})
	os.rmdir_all(tmp) or {}
}

fn test_sync_state_persists_builtin_theme_and_gtk_policy() {
	tmp := os.join_path(os.temp_dir(), 'hornero-syncstate-builtin')
	os.rmdir_all(tmp) or {}
	with_apply_xdg(tmp, fn [tmp] () {
		scheme := color_scheme_file()
		os.mkdir_all(os.dir(scheme)) or {}
		os.write_file(scheme, '{"name":"hornero-light","flavour":"tonal-spot","mode":"light","gtkColorScheme":"prefer-light","colours":{}}\n') or {}
		path := sync_state_from_scheme() or {
			assert false, err.msg()
			return
		}
		state := os.read_file(path) or { '' }
		assert state.contains('"name":"hornero-light"')
		assert state.contains('"mode":"light"')
		assert state.contains('"gtkColorScheme":"prefer-light"')
	})
	os.rmdir_all(tmp) or {}
}

fn test_scheme_set_mode_vectors() {
	rep := scheme_set_mode_native('bright', true)
	assert !rep.ok
	tmp := os.join_path(os.temp_dir(), 'hornero-setmode')
	os.rmdir_all(tmp) or {}
	with_apply_xdg(tmp, fn [tmp] () {
		wall := os.join_path(tmp, 'w.jpg')
		os.write_file(wall, 'x') or {}
		os.setenv('HORNERO_WALLPAPER_POINTER_FILE', wall, true)
		rep2 := scheme_set_mode_native('dark', true)
		assert rep2.ok, rep2.message
		assert rep2.data['dry_run'] == 'true'
		assert rep2.message.contains('gen-m3.py')
		os.unsetenv('HORNERO_WALLPAPER_POINTER_FILE')
		rep3 := scheme_set_variant_native('', true)
		assert !rep3.ok
		rep4 := scheme_set_variant_native('fruitsalad', true)
		assert rep4.ok, rep4.message
		assert rep4.data['variant'] == 'fruitsalad'
		assert rep4.data['flavour'] == 'expressive'
	})
	os.rmdir_all(tmp) or {}
}

fn test_accent_vectors() {
	rep := accent_report_native('set', 'nothex', true)
	assert !rep.ok
	tmp := os.join_path(os.temp_dir(), 'hornero-accent')
	os.rmdir_all(tmp) or {}
	with_apply_xdg(tmp, fn [tmp] () {
		show := accent_report_native('show', '', true)
		assert show.ok
		set := accent_report_native('set', '#8839EF', true)
		assert set.ok
		assert set.data['override'] == '#8839ef'
		assert set.data['dry_run'] == 'true'
		clear := accent_report_native('clear', '', true)
		assert clear.ok
		bad := accent_report_native('bogus', '', true)
		assert !bad.ok
	})
	os.rmdir_all(tmp) or {}
}

fn test_appearance_status_reads() {
	tmp := os.join_path(os.temp_dir(), 'hornero-status')
	os.rmdir_all(tmp) or {}
	with_apply_xdg(tmp, fn [tmp] () {
		rep := appearance_status_report(false)
		assert rep.ok
		assert rep.message.contains('gtkColorScheme : follow')
		jrep := appearance_status_report(true)
		assert jrep.ok
		assert jrep.message.contains('"gtkColorScheme":"follow"')
	})
	os.rmdir_all(tmp) or {}
}

fn test_appearance_doctor_preserves_legacy_rice_markers() {
	tmp := os.join_path(os.temp_dir(), 'hornero-doctor-legacy-rice')
	os.rmdir_all(tmp) or {}
	with_apply_xdg(tmp, fn [tmp] () {
		data_home := os.join_path(tmp, 'data')
		cache_home := os.join_path(tmp, 'cache')
		state_home := os.join_path(tmp, 'state')
		expected := [
			os.join_path(data_home, 'dots', 'rices', '.current_rice'),
			os.join_path(cache_home, 'dots', 'current_rice'),
			os.join_path(state_home, 'dots', 'rice', 'current'),
		]
		markers := legacy_rice_marker_paths()
		assert markers == expected
		for marker in markers {
			os.mkdir_all(os.dir(marker)) or {}
			os.write_file(marker, 'owner state') or {}
		}
		rep := appearance_doctor_native()
		assert rep.message.contains('legacy rice marker remains')
		for marker in markers {
			assert os.is_file(marker), 'doctor removed legacy marker ${marker}'
			assert (os.read_file(marker) or { '' }) == 'owner state'
		}
	})
	os.rmdir_all(tmp) or {}
}

fn test_hyprlock_dry_run() {
	rep := regenerate_hyprlock_native('', true)
	assert rep.ok
	assert rep.data['dry_run'] == 'true'
}

fn test_hyprlock_missing_scheme_fails() {
	tmp := os.join_path(os.temp_dir(), 'hornero-hlmissing')
	os.rmdir_all(tmp) or {}
	with_apply_xdg(tmp, fn [tmp] () {
		rep := regenerate_hyprlock_native('', false)
		assert !rep.ok
		assert rep.message.contains('scheme.json not found')
	})
	os.rmdir_all(tmp) or {}
}

fn test_colors_generate_dry_run() {
	tmp := os.join_path(os.temp_dir(), 'hornero-colorsgen')
	os.rmdir_all(tmp) or {}
	with_apply_xdg(tmp, fn [tmp] () {
		os.setenv('HORNERO_XRDB_BIN', '/nonexistent/xrdb', true)
		rep := colors_generate_native(false, true)
		assert rep.ok, rep.message
		assert rep.message.contains('xrdb')
		rep2 := colors_generate_native(true, true)
		assert rep2.ok, rep2.message
		assert rep2.message.contains('gen-m3.py')
		os.unsetenv('HORNERO_XRDB_BIN')
	})
	os.rmdir_all(tmp) or {}
}

fn test_wallpaper_reload_dry_run() {
	tmp := os.join_path(os.temp_dir(), 'hornero-walreload')
	os.rmdir_all(tmp) or {}
	with_apply_xdg(tmp, fn [tmp] () {
		wall := os.join_path(tmp, 'w.jpg')
		os.write_file(wall, 'x') or {}
		os.setenv('HORNERO_WALLPAPER_POINTER_FILE', wall, true)
		rep := wallpaper_reload_native(true)
		assert rep.ok, rep.message
		assert rep.message.contains('wal')
		os.unsetenv('HORNERO_WALLPAPER_POINTER_FILE')
	})
	os.rmdir_all(tmp) or {}
}

fn test_smart_file_outputs_count() {
	m := smart_file_outputs('/d')
	assert m.len == 12
	assert m['current.env'] == '/d/current.env'
}

// Regression (experience baseline §5.4): the shell-IPC fast path of
// `appearance theme apply` returned without persisting the pack, so
// `appearance status` (state-file backed) kept reporting the old mode
// while the live shell had already switched.
fn test_theme_apply_via_shell_syncs_scheme_state() {
	tmp := os.join_path(os.temp_dir(), 'hornero-apply-state-sync')
	os.rmdir_all(tmp) or {}
	with_apply_xdg(tmp, fn [tmp] () {
		// Stub quickshell: applyTheme/isBusy/lastError succeed instantly.
		stub := os.join_path(tmp, 'qs-stub.sh')
		os.write_file(stub, '#!/bin/sh\nif [ "$4" = "isBusy" ]; then echo 0; exit 0; fi\nif [ "$4" = "lastError" ]; then echo ""; exit 0; fi\necho ok\n') or {}
		os.chmod(stub, 0o755) or {}
		os.setenv('HORNERO_QUICKSHELL_BIN', stub, true)
		os.setenv('HORNERO_SHELL_RUNNING', '1', true)
		// Light pack over a dark pre-state.
		dir := os.join_path(tmp, 'data', 'hornero', 'themes', 'demo-light')
		os.mkdir_all(dir) or {}
		os.write_file(os.join_path(dir, 'theme.json'), '{"schemaVersion": 1, "id": "demo-light", "name": "T", "defaultWallpaper": "w.jpg", "wallpaperDir": "t", "schemeType": "expressive", "darkMode": false, "gtkTheme": "Orchis-Light", "iconTheme": "Numix-Circle"}\n') or {}
		os.setenv('HORNERO_THEMES_DIR', os.join_path(tmp, 'data', 'hornero', 'themes'), true)
		write_scheme_state('hornero-dark', 'tonal-spot', 'dark', 'tonalspot') or {
			assert false, err.msg()
		}
		rep := theme_apply_native_with('demo-light', '', false, default_palette_backends())
		assert rep.ok, rep.message
		assert rep.message.contains('via shell')
		st := read_scheme_state()
		assert st.mode == 'light', 'state mode must follow the applied pack, got ${st.mode}'
		assert st.flavour == 'expressive', 'state flavour must follow the pack, got ${st.flavour}'
		raw := os.read_file(scheme_state_file()) or { '' }
		assert raw.contains('"demo-light"'), 'state name must record the applied pack'
		os.unsetenv('HORNERO_QUICKSHELL_BIN')
		os.unsetenv('HORNERO_SHELL_RUNNING')
		os.unsetenv('HORNERO_THEMES_DIR')
	})
	os.rmdir_all(tmp) or {}
}
