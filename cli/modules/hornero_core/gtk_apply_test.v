module hornero_core

import os

fn with_xdg(tmp string, body fn ()) {
	os.mkdir_all(tmp) or {}
	os.setenv('XDG_CONFIG_HOME', os.join_path(tmp, 'config'), true)
	os.setenv('XDG_DATA_HOME', os.join_path(tmp, 'data'), true)
	os.setenv('XDG_STATE_HOME', os.join_path(tmp, 'state'), true)
	os.setenv('XDG_CACHE_HOME', os.join_path(tmp, 'cache'), true)
	os.setenv('HORNERO_GTK2_FILE', os.join_path(tmp, 'gtkrc-2.0'), true)
	body()
	os.unsetenv('XDG_CONFIG_HOME')
	os.unsetenv('XDG_DATA_HOME')
	os.unsetenv('XDG_STATE_HOME')
	os.unsetenv('XDG_CACHE_HOME')
	os.unsetenv('HORNERO_GTK2_FILE')
}

fn test_gtk_ini_set_roundtrip() {
	tmp := os.join_path(os.temp_dir(), 'hornero-gtk-test')
	os.rmdir_all(tmp) or {}
	with_xdg(tmp, fn [tmp] () {
		path := resolve_gtk3_file()
		gtk_ini_set(path, 'gtk-theme-name', 'Orchis-Dark') or { assert false, err.msg() }
		assert gtk_ini_get(path, 'gtk-theme-name') == 'Orchis-Dark'
		gtk_ini_set(path, 'gtk-theme-name', 'Orchis-Light') or { assert false, err.msg() }
		assert gtk_ini_get(path, 'gtk-theme-name') == 'Orchis-Light'
		raw := os.read_file(path) or { '' }
		assert raw.contains('[Settings]')
		assert gtk_ini_get(path, 'missing') == ''
	})
	os.rmdir_all(tmp) or {}
}

fn test_detect_gtk_theme_vectors() {
	installed := ['Orchis-Dark-Compact', 'Arc-Dark', 'Orchis-Light', 'Arc']
	theme, dark := detect_gtk_theme('1a1b26', installed)
	assert theme == 'Orchis-Dark-Compact'
	assert dark == 'true'
	theme2, dark2 := detect_gtk_theme('eff1f5', installed)
	assert theme2 == 'Orchis-Light'
	assert dark2 == 'false'
	// Brightness boundary: r+g+b = 384 is light.
	theme3, _ := detect_gtk_theme('808080', installed)
	assert theme3 == 'Orchis-Light'
	theme4, dark4 := detect_gtk_theme('7f7f7f', installed)
	assert theme4 == 'Orchis-Dark-Compact'
	assert dark4 == 'true'
	// Nothing installed: safe defaults.
	theme5, dark5 := detect_gtk_theme('000000', [])
	assert theme5 == 'Orchis-Light'
	assert dark5 == 'false'
}

fn test_resolve_gtk_fallbacks() {
	installed := ['Arc-Dark', 'Numix-Circle']
	assert resolve_gtk_theme_with_fallbacks('Arc-Dark', installed)! == 'Arc-Dark'
	assert resolve_gtk_theme_with_fallbacks('Missing', installed)! == 'Arc-Dark'
	assert resolve_icon_with_fallbacks('Missing', installed) == 'Numix-Circle'
	assert resolve_icon_with_fallbacks('Weird', []) == 'Weird'
	if _ := resolve_gtk_theme_with_fallbacks('Missing', []) {
		assert false, 'must fail with no themes'
	} else {
		assert err.msg().contains('no fallback')
	}
}

fn test_list_names_in_dirs() {
	tmp := os.join_path(os.temp_dir(), 'hornero-list-test')
	os.rmdir_all(tmp) or {}
	gtk_dir := os.join_path(tmp, 'themes')
	os.mkdir_all(os.join_path(gtk_dir, 'Fake-GTK', 'gtk-3.0')) or {}
	os.mkdir_all(os.join_path(gtk_dir, 'Not-A-Theme')) or {}
	icon_dir := os.join_path(tmp, 'icons')
	os.mkdir_all(icon_dir) or {}
	os.write_file(os.join_path(icon_dir, 'Fake-Icons', 'index.theme'), '[x]\n') or {}
	os.mkdir_all(os.join_path(icon_dir, 'Fake-Icons')) or {}
	os.write_file(os.join_path(icon_dir, 'Fake-Icons', 'index.theme'), '[x]\n') or {}
	os.mkdir_all(os.join_path(icon_dir, 'hicolor')) or {}
	os.write_file(os.join_path(icon_dir, 'hicolor', 'index.theme'), '[x]\n') or {}
	assert list_names_in_dirs([gtk_dir], false) == ['Fake-GTK']
	assert list_names_in_dirs([icon_dir], true) == ['Fake-Icons']
	os.rmdir_all(tmp) or {}
}

fn test_apply_color_scheme_dry_run_proves_no_execution() {
	tmp := os.join_path(os.temp_dir(), 'hornero-policy-test')
	os.rmdir_all(tmp) or {}
	with_xdg(tmp, fn [tmp] () {
		os.setenv('HORNERO_GSETTINGS_BIN', '/nonexistent/gsettings', true)
		rep := apply_gtk_color_scheme_native('prefer-light', true)
		assert rep.ok
		assert rep.data['dry_run'] == 'true'
		assert rep.data['policy'] == 'prefer-light'
		assert rep.message.contains('would run:')
		assert !os.is_file(scheme_state_file())
		os.unsetenv('HORNERO_GSETTINGS_BIN')
	})
	os.rmdir_all(tmp) or {}
}

fn test_apply_color_scheme_invalid() {
	rep := apply_gtk_color_scheme_native('bogus', true)
	assert !rep.ok
	assert rep.message.contains('Policy must be')
}

fn test_apply_color_scheme_real_writes() {
	tmp := os.join_path(os.temp_dir(), 'hornero-policy-real')
	os.rmdir_all(tmp) or {}
	old_path := os.getenv('PATH')
	os.setenv('PATH', tmp, true)
	with_xdg(tmp, fn [tmp] () {
		rep := apply_gtk_color_scheme_native('prefer-light', false)
		assert rep.ok, rep.message
		assert gtk_ini_get(resolve_gtk3_file(), 'gtk-application-prefer-dark-theme') == 'false'
		assert gtk_ini_get(resolve_gtk4_file(), 'gtk-application-prefer-dark-theme') == 'false'
		raw := os.read_file(scheme_state_file()) or { '' }
		assert raw.contains('"gtkColorScheme"')
		assert raw.contains('prefer-light')
	})
	os.setenv('PATH', old_path, true)
	os.rmdir_all(tmp) or {}
}

fn test_patch_gtk2_config_vectors() {
	made := patch_gtk2_config('', 'Orchis-Dark', 'Numix-Circle')
	assert made.contains('gtk-theme-name="Orchis-Dark"')
	assert made.contains('gtk-icon-theme-name="Numix-Circle"')
	assert made.contains('/home/\$USER/.gtkrc-2.0.mine')
	edited := patch_gtk2_config('gtk-theme-name="Old"\ngtk-icon-theme-name="OldIcons"\n',
		'New', 'NewIcons')
	assert edited.contains('gtk-theme-name="New"')
	assert edited.contains('gtk-icon-theme-name="NewIcons"')
	assert !edited.contains('Old')
}

fn test_select_theme_by_index_vectors() {
	names := ['Alpha', 'Beta']
	assert select_theme_by_index(names, '1') or { -1 } == 0
	assert select_theme_by_index(names, '2') or { -1 } == 1
	assert select_theme_by_index(names, ' 2 ') or { -1 } == 1
	assert select_theme_by_index(names, '02') or { -1 } == 1
	if _ := select_theme_by_index(names, '') {
		assert false, 'empty must fail'
	} else {
		assert err.msg().contains('invalid selection')
	}
	if _ := select_theme_by_index(names, '0') {
		assert false, 'zero must fail'
	} else {
		assert true
	}
	if _ := select_theme_by_index(names, '3') {
		assert false, 'overflow must fail'
	} else {
		assert true
	}
	if _ := select_theme_by_index(names, 'x') {
		assert false, 'nondigits must fail'
	} else {
		assert true
	}
}

fn test_gtk_select_menu_renders() {
	menu := gtk_select_menu(['Alpha', 'Beta'])
	assert menu.contains('GTK themes:')
	assert menu.contains('1) Alpha')
	assert menu.contains('2) Beta')
	assert menu.contains('[1-2, empty to cancel]')
}

fn gtk_select_fixture(tmp string) {
	os.mkdir_all(os.join_path(tmp, 'data', 'themes', 'Alpha', 'gtk-3.0')) or { assert false }
	os.mkdir_all(os.join_path(tmp, 'data', 'themes', 'Beta', 'gtk-3.0')) or { assert false }
	os.setenv('HORNERO_SHELL_RUNNING', '0', true)
	// Never touch live gsettings: the override fails soft inside apply.
	os.setenv('HORNERO_GSETTINGS_BIN', '/nonexistent-gsettings-hornero-test', true)
}

fn test_gtk_select_report_flows() {
	tmp := os.join_path(os.temp_dir(), 'hornero-gtk-select-test')
	os.rmdir_all(tmp) or {}
	names := ['Alpha', 'Beta']
	with_xdg(tmp, fn [tmp, names] () {
		gtk_select_fixture(tmp)
		empty := gtk_select_report_with(GtkSelectOptions{}, []string{}, fn [names] () string {
			return '1'
		})
		assert !empty.ok
		assert empty.message.contains('No GTK themes')
		dry := gtk_select_report_with(GtkSelectOptions{
			dry_run: true
		}, names, fn [names] () string {
			return '1'
		})
		assert dry.ok
		assert dry.data['dry_run'] == 'true'
		assert dry.message.contains('1) Alpha')
		refused := gtk_select_report_with(GtkSelectOptions{}, names, fn [names] () string {
			return '1'
		})
		assert !refused.ok
		assert refused.message.contains('--yes')
		cancelled := gtk_select_report_with(GtkSelectOptions{
			yes: true
		}, names, fn [names] () string {
			return ''
		})
		assert cancelled.ok
		assert cancelled.data['cancelled'] == 'true'
		bad := gtk_select_report_with(GtkSelectOptions{
			yes: true
		}, names, fn [names] () string {
			return '9'
		})
		assert !bad.ok
		assert bad.message.contains('invalid selection')
		applied := gtk_select_report_with(GtkSelectOptions{
			yes: true
		}, names, fn [names] () string {
			return '2'
		})
		assert applied.ok, applied.message
		assert gtk_ini_get(resolve_gtk3_file(), 'gtk-theme-name') == 'Beta'
	})
	os.unsetenv('HORNERO_SHELL_RUNNING')
	os.unsetenv('HORNERO_GSETTINGS_BIN')
	os.rmdir_all(tmp) or {}
}

fn test_gtk_select_quickshell_path_previews() {
	tmp := os.join_path(os.temp_dir(), 'hornero-gtk-select-qs-test')
	os.rmdir_all(tmp) or {}
	names := ['Alpha', 'Beta']
	with_xdg(tmp, fn [tmp, names] () {
		gtk_select_fixture(tmp)
		os.setenv('HORNERO_SHELL_RUNNING', '1', true)
		os.setenv('HORNERO_QS_BIN', '/nonexistent-qs-hornero-test', true)
		dry := gtk_select_report_with(GtkSelectOptions{
			dry_run: true
		}, names, fn [names] () string {
			return '1'
		})
		assert dry.ok
		assert dry.message.contains('would run')
		live := gtk_select_report_with(GtkSelectOptions{
			yes: true
		}, names, fn [names] () string {
			return '1'
		})
		assert !live.ok
		os.unsetenv('HORNERO_QS_BIN')
	})
	os.unsetenv('HORNERO_SHELL_RUNNING')
	os.unsetenv('HORNERO_GSETTINGS_BIN')
	os.rmdir_all(tmp) or {}
}
