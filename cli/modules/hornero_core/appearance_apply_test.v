module hornero_core

import os
import x.json2

// Appearance pipeline tests: guards, dry-run previews, derived-file
// regeneration from the live Signal scheme, status and smart files.
// XDG overrides isolate every write under /tmp.

fn with_apply_xdg(tmp string, body fn ()) {
	os.mkdir_all(tmp) or {}
	os.setenv('XDG_CONFIG_HOME', os.join_path(tmp, 'config'), true)
	os.setenv('XDG_DATA_HOME', os.join_path(tmp, 'data'), true)
	os.setenv('XDG_STATE_HOME', os.join_path(tmp, 'state'), true)
	os.setenv('XDG_CACHE_HOME', os.join_path(tmp, 'cache'), true)
	os.setenv('HORNERO_GTK2_FILE', os.join_path(tmp, 'gtkrc-2.0'), true)
	os.setenv('HORNERO_GTK3_FILE', os.join_path(tmp, 'gtk3.ini'), true)
	os.setenv('HORNERO_GSETTINGS_BIN', '/nonexistent/gsettings', true)
	os.setenv('HORNERO_THEMES_DIR', apply_fixture_dir(), true)
	body()
	for name in ['XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_CACHE_HOME',
		'HORNERO_GTK2_FILE', 'HORNERO_GTK3_FILE', 'HORNERO_GSETTINGS_BIN', 'HORNERO_THEMES_DIR'] {
		os.unsetenv(name)
	}
}

fn apply_fixture_dir() string {
	return os.join_path(os.dir(@FILE), '..', '..', 'testdata', 'signal-themes')
}

fn apply_live_night() {
	raw := os.read_file(os.join_path(apply_fixture_dir(), 'hornero-signal-night', 'theme.json')) or {
		panic(err)
	}
	m := json2.decode[map[string]json2.Any](raw) or { panic(err) }
	t := parse_signal_theme('hornero-signal-night', m) or { panic(err) }
	write_signal_scheme(t) or { panic(err) }
}

fn test_theme_apply_rejects_bad_id() {
	rep := theme_apply_native('../x', '', true)
	assert !rep.ok
	assert rep.message.contains('invalid theme id')
}

fn test_theme_apply_missing_pack() {
	tmp := os.join_path(os.temp_dir(), 'hornero-apply-missing')
	os.rmdir_all(tmp) or {}
	with_apply_xdg(tmp, fn () {
		rep := theme_apply_native('nope', '', true)
		assert !rep.ok
		assert rep.message.contains('Theme not found')
	})
	os.rmdir_all(tmp) or {}
}

fn test_theme_apply_rejects_schema_v1_pack() {
	tmp := os.join_path(os.temp_dir(), 'hornero-apply-v1')
	os.rmdir_all(tmp) or {}
	with_apply_xdg(tmp, fn [tmp] () {
		dir := os.join_path(tmp, 'themes', 'legacy-pack')
		os.mkdir_all(dir) or { panic(err) }
		os.write_file(os.join_path(dir, 'theme.json'), '{"schemaVersion":1,"id":"legacy-pack","name":"L","schemeType":"vibrant","darkMode":true}') or {
			panic(err)
		}
		os.setenv('HORNERO_THEMES_DIR', os.join_path(tmp, 'themes'), true)
		rep := theme_apply_native('legacy-pack', '', true)
		assert !rep.ok
		assert rep.message.contains('not a Hornero Signal theme')
	})
	os.rmdir_all(tmp) or {}
}

fn test_appearance_status_reads() {
	tmp := os.join_path(os.temp_dir(), 'hornero-status')
	os.rmdir_all(tmp) or {}
	with_apply_xdg(tmp, fn () {
		rep := appearance_status_report(false)
		assert rep.ok
		assert rep.message.contains('gtkColorScheme : follow')
		assert rep.message.contains('theme          : hornero-signal-night')
		apply_live_night()
		jrep := appearance_status_report(true)
		assert jrep.ok
		doc := json2.decode[map[string]json2.Any](jrep.message) or { panic(err) }
		assert doc['gtk_color_scheme'].str() == 'follow'
		assert doc['mode'].str() == 'dark'
		assert 'flavour' !in doc
	})
	os.rmdir_all(tmp) or {}
}

fn test_scheme_status_and_current() {
	tmp := os.join_path(os.temp_dir(), 'hornero-scheme-status')
	os.rmdir_all(tmp) or {}
	with_apply_xdg(tmp, fn () {
		missing := scheme_status_report()
		assert missing.ok
		assert missing.data['scheme_valid'] == 'false'
		apply_live_night()
		st := scheme_status_report()
		assert st.data['scheme_valid'] == 'true'
		assert st.data['theme'] == 'hornero-signal-night'
		assert st.data['theme_source'] == 'scheme'
		cur := scheme_current_report()
		assert cur.message == 'hornero-signal-night\ndark'
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
	with_apply_xdg(tmp, fn () {
		rep := regenerate_hyprlock_native('', false)
		assert !rep.ok
		assert rep.message.contains('live scheme missing')
	})
	os.rmdir_all(tmp) or {}
}

fn test_regenerate_hyprland_and_hyprlock_from_scheme() {
	tmp := os.join_path(os.temp_dir(), 'hornero-hypr-regen')
	os.rmdir_all(tmp) or {}
	with_apply_xdg(tmp, fn [tmp] () {
		apply_live_night()
		hl := regenerate_hyprland_native(false)
		assert hl.ok, hl.message
		lua := os.read_file(os.join_path(tmp, 'cache', 'hornero', 'smart-colors', 'colors-hyprland.lua')) or {
			''
		}
		assert lua.contains('active_border = "rgba(f2a33aee)"')
		lock_rep := regenerate_hyprlock_native('', false)
		assert lock_rep.ok, lock_rep.message
		conf := os.read_file(os.join_path(tmp, 'cache', 'hornero', 'smart-colors', 'colors-hyprlock.conf')) or {
			''
		}
		assert conf.contains('$' + 'hs_signal = rgba(f2a33aff)')
	})
	os.rmdir_all(tmp) or {}
}

fn test_regenerate_hyprland_fails_without_scheme() {
	tmp := os.join_path(os.temp_dir(), 'hornero-hypr-noscheme')
	os.rmdir_all(tmp) or {}
	with_apply_xdg(tmp, fn () {
		rep := regenerate_hyprland_native(false)
		assert !rep.ok
		assert rep.message.contains('appearance sync --yes')
	})
	os.rmdir_all(tmp) or {}
}

fn test_colors_generate_writes_smart_files_from_scheme() {
	tmp := os.join_path(os.temp_dir(), 'hornero-colors-gen')
	os.rmdir_all(tmp) or {}
	with_apply_xdg(tmp, fn [tmp] () {
		dry := colors_generate_native(true)
		assert dry.ok
		assert dry.data['dry_run'] == 'true'
		assert !os.exists(os.join_path(tmp, 'cache', 'hornero', 'smart-colors', 'colors.css'))
		apply_live_night()
		rep := colors_generate_native(false)
		assert rep.ok, rep.message
		dir := os.join_path(tmp, 'cache', 'hornero', 'smart-colors')
		for name, _ in smart_file_outputs(dir) {
			assert os.is_file(os.join_path(dir, name)), name
		}
		css := os.read_file(os.join_path(dir, 'colors.css')) or { '' }
		assert css.contains('--smart-error: #F0705A;')
	})
	os.rmdir_all(tmp) or {}
}

fn test_smart_file_outputs_count() {
	m := smart_file_outputs('/d')
	assert m.len == 13
	assert m['current.env'] == '/d/current.env'
	assert m['colors-hyprland.lua'] == '/d/colors-hyprland.lua'
}

fn test_sync_kitty_include_points_at_pack_conf() {
	tmp := os.join_path(os.temp_dir(), 'hornero-kitty-include')
	os.rmdir_all(tmp) or {}
	with_apply_xdg(tmp, fn [tmp] () {
		kitty := os.join_path(tmp, 'config', 'kitty')
		os.mkdir_all(kitty) or { panic(err) }
		os.write_file(os.join_path(kitty, 'kitty.conf'), 'font_size 11\ninclude hornero-signal-night.conf\ninclude fonts.conf\n') or {
			panic(err)
		}
		os.write_file(os.join_path(kitty, 'hornero-signal-day.conf'), 'background #F2EEE5\n') or {
			panic(err)
		}
		sync_kitty_include('hornero-signal-day')
		conf := os.read_file(os.join_path(kitty, 'kitty.conf')) or { '' }
		assert conf == 'font_size 11\ninclude hornero-signal-day.conf\ninclude fonts.conf\n'
	})
	os.rmdir_all(tmp) or {}
}

fn test_ghostty_reload_falls_back_when_user_service_reload_fails() {
	tmp := '/tmp/hx-ghostty-reload-test'
	os.rmdir_all(tmp) or {}
	bin := os.join_path(tmp, 'bin')
	os.mkdir_all(bin) or { assert false }
	systemctl_log := os.join_path(tmp, 'systemctl.log')
	pkill_log := os.join_path(tmp, 'pkill.log')
	os.write_file(os.join_path(bin, 'systemctl'), '#!/bin/sh\nprintf "%s\\n" "$*" >> "$HORNERO_TEST_SYSTEMCTL_LOG"\ncase "$2" in\n  is-active) exit 0 ;;\n  reload) exit 1 ;;\nesac\nexit 2\n') or {
		assert false
	}
	os.write_file(os.join_path(bin, 'pkill'), '#!/bin/sh\nprintf "%s\\n" "$*" >> "$HORNERO_TEST_PKILL_LOG"\n') or {
		assert false
	}
	os.chmod(os.join_path(bin, 'systemctl'), 0o755) or { assert false }
	os.chmod(os.join_path(bin, 'pkill'), 0o755) or { assert false }
	old_path := os.getenv('PATH')
	os.setenv('PATH', bin, true)
	os.setenv('HORNERO_TEST_SYSTEMCTL_LOG', systemctl_log, true)
	os.setenv('HORNERO_TEST_PKILL_LOG', pkill_log, true)
	reload_ghostty_theme()
	systemctl_calls := os.read_file(systemctl_log) or { '' }
	pkill_calls := os.read_file(pkill_log) or { '' }
	assert systemctl_calls == '--user is-active --quiet app-com.mitchellh.ghostty.service\n--user reload app-com.mitchellh.ghostty.service\n'
	assert pkill_calls == '-USR2 -x ghostty\n'
	os.setenv('PATH', old_path, true)
	os.unsetenv('HORNERO_TEST_SYSTEMCTL_LOG')
	os.unsetenv('HORNERO_TEST_PKILL_LOG')
	os.rmdir_all(tmp) or {}
}
