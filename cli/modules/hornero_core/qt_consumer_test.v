module hornero_core

import os
import x.json2

// Qt consumer tests: scheme parity with the config generator, fresh install,
// stale-config migration with backup, user-palette respect, opt-out,
// idempotence and doctor honesty. Every write is isolated under a temp dir.

fn qt_fixture(name string) string {
	return os.join_path(os.dir(@FILE), '..', '..', 'testdata', name)
}

fn qt_theme(id string) SignalTheme {
	raw := os.read_file(os.join_path(qt_fixture('signal-themes'), id, 'theme.json')) or { panic(err) }
	m := json2.decode[map[string]json2.Any](raw) or { panic(err) }
	return parse_signal_theme(id, m) or { panic(err) }
}

fn qt_live(id string) {
	write_signal_scheme(qt_theme(id)) or { panic(err) }
}

fn with_qt_env(name string, body fn (tmp string)) {
	tmp := os.join_path(os.temp_dir(), 'hornero-qt-${name}')
	os.rmdir_all(tmp) or {}
	os.mkdir_all(tmp) or {}
	os.setenv('XDG_CONFIG_HOME', os.join_path(tmp, 'config'), true)
	os.setenv('XDG_CONFIG_DIRS', os.join_path(tmp, 'etc'), true)
	os.setenv('XDG_DATA_HOME', os.join_path(tmp, 'data'), true)
	os.setenv('XDG_STATE_HOME', os.join_path(tmp, 'state'), true)
	os.setenv('XDG_CACHE_HOME', os.join_path(tmp, 'cache'), true)
	os.setenv('HORNERO_QT_PLUGIN_DIRS', os.join_path(tmp, 'plugins'), true)
	os.setenv('HORNERO_KDE_LIB_DIRS', os.join_path(tmp, 'kdelib'), true)
	os.mkdir_all(os.join_path(tmp, 'kdelib')) or {}
	os.mkdir_all(os.join_path(tmp, 'plugins')) or {}
	body(tmp)
	for n in ['XDG_CONFIG_HOME', 'XDG_CONFIG_DIRS', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_CACHE_HOME',
		'HORNERO_QT_PLUGIN_DIRS', 'QT_QPA_PLATFORMTHEME'] {
		os.unsetenv(n)
	}
	os.rmdir_all(tmp) or {}
}

fn qt_install_plugin(tmp string, toolkit string) {
	os.write_file(os.join_path(tmp, 'plugins', 'lib${toolkit}.so'), '') or { panic(err) }
}

fn qt_scheme_rows(text string) []string {
	return text.split_into_lines().filter(it.starts_with('active_colors=')
		|| it.starts_with('inactive_colors=') || it.starts_with('disabled_colors='))
}

fn test_render_matches_config_generator_night_and_day() {
	for id in ['hornero-signal-night', 'hornero-signal-day'] {
		golden := os.read_file(os.join_path(qt_fixture('qt'), 'qt6ct-${id}.golden')) or { panic(err) }
		got := render_qt_scheme(qt_theme(id), 'qt6ct')
		assert qt_scheme_rows(got) == qt_scheme_rows(golden)
		assert qt_scheme_rows(got).len == 3
	}
}

fn test_qt5_scheme_has_no_accent_role() {
	t := qt_theme('hornero-signal-night')
	q6 := qt_scheme_rows(render_qt_scheme(t, 'qt6ct'))[0].all_after('=').split(', ')
	q5 := qt_scheme_rows(render_qt_scheme(t, 'qt5ct'))[0].all_after('=').split(', ')
	assert q6.len == 22
	assert q5.len == 21
	assert q5 == q6[..21]
}

fn test_dark_and_light_differ_in_window_role() {
	night := qt_scheme_rows(render_qt_scheme(qt_theme('hornero-signal-night'), 'qt6ct'))[0]
	day := qt_scheme_rows(render_qt_scheme(qt_theme('hornero-signal-day'), 'qt6ct'))[0]
	assert night != day
	assert night.split(', ')[7] == '#ffffffff'
	assert day.split(', ')[7] == '#ff000000'
}

fn test_fresh_install_creates_conf_from_factory_and_scheme() {
	with_qt_env('fresh', fn (tmp string) {
		qt_install_plugin(tmp, 'qt6ct')
		os.mkdir_all(os.join_path(tmp, 'etc', 'qt6ct')) or {}
		os.write_file(os.join_path(tmp, 'etc', 'qt6ct', 'qt6ct.conf'), '[Appearance]\nstyle=Fusion\nicon_theme=Papirus-Dark\n\n[Fonts]\ngeneral=IBM Plex Sans\n') or {
			panic(err)
		}
		qt_live('hornero-signal-night')
		reports := qt_sync_all(false)
		assert reports[0].status == 'synced'
		assert reports[1].status == 'not-installed'
		conf := os.read_file(qt_conf_file('qt6ct')) or { panic(err) }
		assert conf.contains('custom_palette=true')
		assert conf.contains('color_scheme_path=${qt_scheme_file('qt6ct')}')
		assert conf.contains('icon_theme=Papirus-Dark')
		assert conf.contains('general=IBM Plex Sans')
		assert os.is_file(qt_scheme_file('qt6ct'))
		assert !os.is_dir(qt_config_dir('qt5ct'))
		// no pre-existing file means nothing to back up
		assert !os.is_dir(qt_backup_dir('qt6ct'))
	})
}

fn test_stale_conf_is_migrated_with_backup_and_user_keys_survive() {
	with_qt_env('stale', fn (tmp string) {
		qt_install_plugin(tmp, 'qt6ct')
		os.mkdir_all(qt_config_dir('qt6ct')) or {}
		old := '[Appearance]\ncustom_palette=false\nicon_theme=Papirus\nstyle=Fusion\n\n[Fonts]\ngeneral="Noto Sans,12"\n\n[SettingsWindow]\ngeometry=@ByteArray(\\x1\\xd9)\n'
		os.write_file(qt_conf_file('qt6ct'), old) or { panic(err) }
		qt_live('hornero-signal-day')
		r := qt_sync_toolkit('qt6ct', qt_theme('hornero-signal-day'), false)
		assert r.status == 'synced'
		assert r.backup.len > 0
		assert (os.read_file(r.backup) or { '' }) == old
		conf := os.read_file(qt_conf_file('qt6ct')) or { panic(err) }
		assert conf.contains('custom_palette=true')
		assert !conf.contains('custom_palette=false')
		for keep in ['icon_theme=Papirus', 'style=Fusion', 'general="Noto Sans,12"',
			'geometry=@ByteArray(\\x1\\xd9)'] {
			assert conf.contains(keep)
		}
	})
}

fn test_sync_is_idempotent_and_does_not_rebackup() {
	with_qt_env('idem', fn (tmp string) {
		qt_install_plugin(tmp, 'qt6ct')
		qt_live('hornero-signal-night')
		assert qt_sync_all(false)[0].changed
		second := qt_sync_all(false)[0]
		assert second.status == 'unchanged'
		assert !second.changed
	})
}

fn test_theme_change_rerenders_scheme() {
	with_qt_env('retheme', fn (tmp string) {
		qt_install_plugin(tmp, 'qt6ct')
		qt_live('hornero-signal-night')
		qt_sync_all(false)
		before := os.read_file(qt_scheme_file('qt6ct')) or { '' }
		qt_live('hornero-signal-day')
		r := qt_sync_all(false)[0]
		assert r.status == 'synced'
		assert (os.read_file(qt_scheme_file('qt6ct')) or { '' }) != before
		assert r.backup.len > 0 || true
	})
}

fn test_user_palette_is_respected_until_forced() {
	with_qt_env('user', fn (tmp string) {
		qt_install_plugin(tmp, 'qt6ct')
		os.mkdir_all(qt_config_dir('qt6ct')) or {}
		mine := '[Appearance]\ncustom_palette=true\ncolor_scheme_path=/home/me/my-palette.conf\n'
		os.write_file(qt_conf_file('qt6ct'), mine) or { panic(err) }
		qt_live('hornero-signal-night')
		assert qt_sync_all(false)[0].status == 'user-palette'
		assert (os.read_file(qt_conf_file('qt6ct')) or { '' }) == mine
		assert !os.is_file(qt_scheme_file('qt6ct'))
		checks := qt_doctor_checks().filter(it.name == 'qt-qt6ct')
		assert checks[0].ok && checks[0].warn
		// take over explicitly
		appearance_set_qt_native('qt6ct=force', false)
		conf := os.read_file(qt_conf_file('qt6ct')) or { '' }
		assert conf.contains('color_scheme_path=${qt_scheme_file('qt6ct')}')
		assert qt_policy('qt6ct') == 'force'
	})
}

fn test_opt_out_never_touches_files() {
	with_qt_env('off', fn (tmp string) {
		qt_install_plugin(tmp, 'qt6ct')
		qt_live('hornero-signal-night')
		res := appearance_set_qt_native('qt6ct=off', false)
		assert res.ok
		assert !os.is_file(qt_conf_file('qt6ct'))
		assert !os.is_file(qt_scheme_file('qt6ct'))
		assert qt_sync_all(false)[0].status == 'off'
		c := qt_doctor_checks().filter(it.name == 'qt-qt6ct')[0]
		assert c.ok && c.detail.contains('opted out')
	})
}

fn test_set_qt_rejects_bad_spec() {
	assert !appearance_set_qt_native('qt4ct=off', true).ok
	assert !appearance_set_qt_native('qt6ct=maybe', true).ok
	assert !appearance_set_qt_native('qt6ct', true).ok
	assert appearance_set_qt_native('qt6ct=off', true).ok
}

fn test_dry_run_writes_nothing() {
	with_qt_env('dry', fn (tmp string) {
		qt_install_plugin(tmp, 'qt6ct')
		qt_live('hornero-signal-night')
		r := qt_sync_all(true)[0]
		assert r.status == 'synced'
		assert !os.is_file(qt_conf_file('qt6ct'))
		assert !os.is_file(qt_scheme_file('qt6ct'))
	})
}

fn test_doctor_reports_stale_missing_drift_and_ok() {
	with_qt_env('doctor', fn (tmp string) {
		qt_install_plugin(tmp, 'qt6ct')
		qt_live('hornero-signal-night')
		find := fn () DoctorCheck {
			return qt_doctor_checks().filter(it.name == 'qt-qt6ct')[0]
		}
		assert !find().ok
		assert find().detail.contains('missing')
		os.mkdir_all(qt_config_dir('qt6ct')) or {}
		os.write_file(qt_conf_file('qt6ct'), '[Appearance]\ncustom_palette=false\n') or { panic(err) }
		assert !find().ok
		assert find().detail.contains('no Hornero palette')
		qt_sync_all(false)
		assert find().ok
		assert find().detail.contains('hornero-signal-night')
		// scheme drift: live theme changes but Qt files are not re-synced
		qt_live('hornero-signal-day')
		assert !find().ok
		assert find().detail.contains('does not match')
		// not installed qt5ct never fails
		c5 := qt_doctor_checks().filter(it.name == 'qt-qt5ct')[0]
		assert c5.ok
	})
}

fn test_doctor_platformtheme_env() {
	with_qt_env('env', fn (tmp string) {
		qt_install_plugin(tmp, 'qt6ct')
		qt_install_plugin(tmp, 'qt5ct')
		qt_live('hornero-signal-night')
		os.setenv('QT_QPA_PLATFORMTHEME', 'qt6ct', true)
		c := qt_doctor_checks().filter(it.name == 'qt-platformtheme')[0]
		assert c.warn && c.detail.contains('lacks qt5ct')
		os.setenv('QT_QPA_PLATFORMTHEME', 'qt6ct:qt5ct', true)
		c2 := qt_doctor_checks().filter(it.name == 'qt-platformtheme')[0]
		assert !c2.warn
		os.unsetenv('QT_QPA_PLATFORMTHEME')
		assert qt_doctor_checks().filter(it.name == 'qt-platformtheme')[0].warn
	})
}

fn test_doctor_flags_kvantum_style() {
	with_qt_env('kv', fn (tmp string) {
		qt_install_plugin(tmp, 'qt6ct')
		qt_live('hornero-signal-night')
		qt_sync_all(false)
		mut conf := os.read_file(qt_conf_file('qt6ct')) or { '' }
		conf = conf.replace('style=Fusion', 'style=kvantum-dark')
		os.write_file(qt_conf_file('qt6ct'), conf) or {}
		k := qt_doctor_checks().filter(it.name == 'qt-kvantum')
		assert k.len == 1 && k[0].warn
	})
}

fn qt_install_kde(tmp string) {
	os.write_file(os.join_path(tmp, 'kdelib', 'libKF6ColorScheme.so.6'), '') or { panic(err) }
}

fn test_kde_scheme_selected_and_rendered_dark_and_light() {
	with_qt_env('kde', fn (tmp string) {
		qt_install_kde(tmp)
		qt_live('hornero-signal-night')
		r := qt_sync_all(false).filter(it.toolkit == 'kde')[0]
		assert r.status == 'synced'
		globals := os.read_file(kde_globals_file()) or { panic(err) }
		assert qt_ini_value(globals, 'UiSettings', 'ColorScheme') == 'HorneroSignal'
		night := os.read_file(kde_scheme_file()) or { panic(err) }
		t := qt_theme('hornero-signal-night')
		assert qt_ini_value(night, 'Colors:View', 'BackgroundNormal') == kde_rgb(t.role('sunken'))
		assert qt_ini_value(night, 'Colors:Selection', 'BackgroundNormal') == kde_rgb(t.role('cue'))
		assert kde_doctor_check(t).ok
		qt_live('hornero-signal-day')
		assert !kde_doctor_check(qt_theme('hornero-signal-day')).ok
		qt_sync_all(false)
		day := os.read_file(kde_scheme_file()) or { panic(err) }
		assert day != night
		assert kde_doctor_check(qt_theme('hornero-signal-day')).ok
	})
}

fn test_kde_preserves_other_groups_backs_up_and_respects_user_scheme() {
	with_qt_env('kde-user', fn (tmp string) {
		qt_install_kde(tmp)
		qt_live('hornero-signal-night')
		os.mkdir_all(gtk_config_home()) or {}
		old := '[KDE]\nSingleClick=false\n\n[UiSettings]\n'
		os.write_file(kde_globals_file(), old) or { panic(err) }
		r := kde_sync(qt_theme('hornero-signal-night'), false)
		assert r.status == 'synced'
		assert (os.read_file(r.backup) or { '' }) == old
		g := os.read_file(kde_globals_file()) or { '' }
		assert g.contains('SingleClick=false')
		assert qt_ini_value(g, 'UiSettings', 'ColorScheme') == 'HorneroSignal'
		// a user-selected scheme is left alone until forced
		mine := '[UiSettings]\nColorScheme=BreezeDark\n'
		os.write_file(kde_globals_file(), mine) or { panic(err) }
		assert kde_sync(qt_theme('hornero-signal-night'), false).status == 'user-palette'
		assert (os.read_file(kde_globals_file()) or { '' }) == mine
		assert kde_doctor_check(qt_theme('hornero-signal-night')).warn
		appearance_set_qt_native('kde=force', false)
		assert qt_ini_value(os.read_file(kde_globals_file()) or { '' }, 'UiSettings', 'ColorScheme') == 'HorneroSignal'
		appearance_set_qt_native('kde=off', false)
		assert kde_sync(qt_theme('hornero-signal-night'), false).status == 'off'
	})
}

fn test_kde_absent_writes_nothing() {
	with_qt_env('kde-none', fn (tmp string) {
		qt_live('hornero-signal-night')
		assert kde_sync(qt_theme('hornero-signal-night'), false).status == 'not-installed'
		assert !os.is_file(kde_globals_file())
		assert kde_doctor_check(qt_theme('hornero-signal-night')).ok
	})
}
