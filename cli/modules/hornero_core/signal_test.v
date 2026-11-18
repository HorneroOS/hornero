module hornero_core

import os
import x.json2

// Hornero Signal contract tests (HorneroOS/.github#28): schema-v2 theme
// validation, the live scheme file, derived outputs, and the one-shot
// migration of retired selections. Fixtures follow the contract
// (cli/testdata/signal-themes). Every path is under /tmp via XDG
// overrides; nothing touches HOME, the compositor or the network.

const sg_root = '/tmp/hx-signal-test'

fn sg_fixture_dir() string {
	return os.join_path(os.dir(@FILE), '..', '..', 'testdata', 'signal-themes')
}

fn sg_fixture_map(id string) map[string]json2.Any {
	raw := os.read_file(os.join_path(sg_fixture_dir(), id, 'theme.json')) or {
		panic('missing fixture ${id}')
	}
	return json2.decode[map[string]json2.Any](raw) or { panic(err) }
}

fn sg_fixture(id string) SignalTheme {
	return parse_signal_theme(id, sg_fixture_map(id)) or { panic(err) }
}

fn sg_write(path string, content string) {
	os.mkdir_all(os.dir(path)) or { panic(err) }
	os.write_file(path, content) or { panic(err) }
}

const sg_env = ['XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_CACHE_HOME', 'XDG_DATA_DIRS',
	'HORNERO_THEMES_DIR', 'HORNERO_WALLPAPERS_DIR', 'HORNERO_PICTURES_WALLPAPERS',
	'HORNERO_WALLPAPER_POINTER_FILE', 'HORNERO_SHELL_RUNNING', 'HORNERO_GSETTINGS_BIN',
	'HORNERO_GTK2_FILE', 'HORNERO_GTK3_FILE', 'HORNERO_GTK4_FILE', 'HORNERO_SMART_COLORS_DIR',
	'HORNERO_FONT_DIRS']

fn sg_setup() {
	os.rmdir_all(sg_root) or {}
	for name in sg_env {
		os.unsetenv(name)
	}
	os.setenv('XDG_CONFIG_HOME', '${sg_root}/config', true)
	os.setenv('XDG_DATA_HOME', '${sg_root}/data', true)
	os.setenv('XDG_STATE_HOME', '${sg_root}/state', true)
	os.setenv('XDG_CACHE_HOME', '${sg_root}/cache', true)
	os.setenv('XDG_DATA_DIRS', '${sg_root}/system', true)
	os.setenv('HORNERO_THEMES_DIR', sg_fixture_dir(), true)
	os.setenv('HORNERO_WALLPAPERS_DIR', '${sg_root}/walls', true)
	os.setenv('HORNERO_SHELL_RUNNING', '0', true)
	os.setenv('HORNERO_GSETTINGS_BIN', '/nonexistent-gsettings', true)
	os.setenv('HORNERO_GTK2_FILE', '${sg_root}/gtkrc-2.0', true)
	os.setenv('HORNERO_GTK3_FILE', '${sg_root}/config/gtk-3.0/settings.ini', true)
	os.setenv('HORNERO_GTK4_FILE', '${sg_root}/config/gtk-4.0/settings.ini', true)
}

fn sg_teardown() {
	for name in sg_env {
		os.unsetenv(name)
	}
	os.rmdir_all(sg_root) or {}
}

// sg_deps records every external side effect instead of running it.
fn sg_deps(log string) AppearanceBackends {
	return AppearanceBackends{
		gtk_apply:   fn [log] (theme string, icon string, policy string, dry_run bool) CommandResult {
			mut f := os.open_append(log) or { panic(err) }
			f.writeln('gtk ${theme} ${icon} ${policy}') or {}
			f.close()
			return ok_result('appearance gtk apply', 'ok', {})
		}
		pack_extras: fn [log] (id string, gtk_theme string, name string) {
			mut f := os.open_append(log) or { panic(err) }
			f.writeln('extras ${id}') or {}
			f.close()
		}
		reload:      fn [log] () {
			mut f := os.open_append(log) or { panic(err) }
			f.writeln('reload') or {}
			f.close()
		}
	}
}

fn test_builtin_ids_and_default() {
	assert signal_default_theme_id == 'hornero-signal-night'
	assert signal_builtin_theme_ids == ['hornero-signal-night', 'hornero-signal-day',
		'hornero-signal-contrast']
	assert signal_roles.len == 33
}

fn test_fixtures_parse_as_signal_themes() {
	for id in signal_builtin_theme_ids {
		t := sg_fixture(id)
		assert t.id == id
		assert t.palette.len >= signal_roles.len
		assert t.terminal.len == 16
	}
	assert sg_fixture('hornero-signal-day').mode == 'light'
	assert sg_fixture('hornero-signal-night').role('signal') == '#F2A33A'
}

fn test_parse_rejects_non_contract_documents() {
	mut m := sg_fixture_map('hornero-signal-night')
	m['schemaVersion'] = json2.Any(1)
	if _ := parse_signal_theme('hornero-signal-night', m) {
		assert false, 'schema v1 must be rejected'
	}
	mut wrong_id := sg_fixture_map('hornero-signal-night')
	if _ := parse_signal_theme('other', wrong_id) {
		assert false, 'id must match its directory'
	}
	mut missing_role := sg_fixture_map('hornero-signal-night')
	mut pal := missing_role['palette'].as_map()
	pal.delete('cue')
	missing_role['palette'] = json2.Any(pal)
	parse_signal_theme('hornero-signal-night', missing_role) or {
		assert err.msg().contains('missing role cue')
	}
	mut extra_role := sg_fixture_map('hornero-signal-night')
	mut pal2 := extra_role['palette'].as_map()
	pal2['primary'] = json2.Any('#FFFFFF')
	extra_role['palette'] = json2.Any(pal2)
	parse_signal_theme('hornero-signal-night', extra_role) or {
		assert err.msg().contains('unknown role primary')
	}
	mut bad_hex := sg_fixture_map('hornero-signal-night')
	mut pal3 := bad_hex['palette'].as_map()
	pal3['ink'] = json2.Any('#ECE6D')
	bad_hex['palette'] = json2.Any(pal3)
	if _ := parse_signal_theme('hornero-signal-night', bad_hex) {
		assert false, 'short hex must be rejected'
	}
	mut short_term := sg_fixture_map('hornero-signal-night')
	short_term['terminal'] = json2.Any([json2.Any('#000000')])
	parse_signal_theme('hornero-signal-night', short_term) or {
		assert err.msg().contains('16 colours')
	}
	mut bad_mode := sg_fixture_map('hornero-signal-night')
	bad_mode['mode'] = json2.Any('dim')
	if _ := parse_signal_theme('hornero-signal-night', bad_mode) {
		assert false, 'mode must be dark or light'
	}
}

fn test_signal_hex_normalizes_case() {
	assert (signal_hex('#ece6da') or { '' }) == '#ECE6DA'
	if _ := signal_hex('ece6da') {
		assert false, 'leading # is required'
	}
}

fn test_write_signal_scheme_follows_contract() {
	sg_setup()
	t := sg_fixture('hornero-signal-day')
	path := write_signal_scheme(t) or { panic(err) }
	assert path == '${sg_root}/state/hornero/signal/scheme.json'
	raw := os.read_file(path) or { panic(err) }
	doc := json2.decode[map[string]json2.Any](raw) or { panic(err) }
	assert doc.len == 5
	assert doc['schemaVersion'].int() == 2
	assert doc['id'].str() == 'hornero-signal-day'
	assert doc['mode'].str() == 'light'
	pal := doc['palette'].as_map()
	assert pal.len == t.palette.len
	for role in signal_roles {
		assert pal[role].str() == t.role(role)
	}
	assert doc['terminal'].as_array().len == 16
	// No temp file is left beside the scheme.
	assert (os.ls(os.dir(path)) or { []string{} }) == ['scheme.json']
	back := read_signal_scheme() or { panic(err) }
	assert back.id == t.id
	assert back.palette == t.palette
	assert back.terminal == t.terminal
	sg_teardown()
}

fn test_read_signal_scheme_rejects_invalid_file() {
	sg_setup()
	if _ := read_signal_scheme() {
		assert false, 'missing scheme must fail'
	}
	sg_write(signal_scheme_file(), '{"colours":{"primary":"#ffffff"}}')
	read_signal_scheme() or { assert err.msg().contains('invalid') }
	sg_teardown()
}

fn test_hyprland_lua_maps_signal_roles() {
	t := sg_fixture('hornero-signal-night')
	sig := t.role('signal').trim_left('#').to_lower()
	rule := t.role('rule').trim_left('#').to_lower()
	cue := t.role('cue').trim_left('#').to_lower()
	lua := render_signal_hyprland_lua(t)
	assert lua.contains('active_border = "rgba(${sig}ee)"')
	assert lua.contains('inactive_border = "rgba(${rule}cc)"')
	assert lua.contains('border_active = "rgba(${sig}ee)"')
	assert lua.contains('border_locked_active = "rgba(${cue}ee)"')
	assert lua.contains('hl.config({')
	assert lua.contains('-- luacheck: globals hl')
	conf := render_signal_hyprland_conf(t)
	assert conf.contains('col.active_border = rgba(${sig}ee)')
	assert conf.contains('col.border_locked_active = rgba(${cue}ee)')
}

fn test_hyprlock_conf_is_variables_only() {
	night := sg_fixture('hornero-signal-night')
	conf := render_signal_hyprlock_conf(night)
	lines := conf.split_into_lines().filter(!it.starts_with('#'))
	assert lines.len == 10
	for line in lines {
		assert line.starts_with('$' + 'hs_'), line
	}
	assert conf.contains('$' + 'hs_ground = rgba(0c0f13ff)')
	glow := night.palette['glow'] or { '' }
	assert conf.contains('$' + 'hs_glow = rgba(${glow.trim_left('#').to_lower()}ff)')
	assert !conf.contains('{')
	// Contrast omits glow: it falls back to signal.
	contrast := sg_fixture('hornero-signal-contrast')
	assert 'glow' !in contrast.palette
	assert render_signal_hyprlock_conf(contrast).contains('$' + 'hs_glow = rgba(ffc247ff)')
}

fn test_optional_glow_is_written_only_when_present() {
	sg_setup()
	night := sg_fixture('hornero-signal-night')
	write_signal_scheme(night) or { panic(err) }
	raw := os.read_file(signal_scheme_file()) or { '' }
	assert raw.contains('"glow":')
	contrast := sg_fixture('hornero-signal-contrast')
	write_signal_scheme(contrast) or { panic(err) }
	raw2 := os.read_file(signal_scheme_file()) or { '' }
	assert !raw2.contains('"glow":')
	assert contrast.role('glow') == contrast.role('signal')
	mut bad := sg_fixture_map('hornero-signal-night')
	mut pal := bad['palette'].as_map()
	pal['glow'] = json2.Any('nope')
	bad['palette'] = json2.Any(pal)
	if _ := parse_signal_theme('hornero-signal-night', bad) {
		assert false, 'invalid glow must be rejected'
	}
	sg_teardown()
}

fn test_terminal_outputs_use_terminal_palette() {
	t := sg_fixture('hornero-signal-night')
	kitty := render_signal_kitty(t)
	assert kitty.contains('background ${t.role('base')}')
	assert render_signal_btop(t).contains('theme[hi_fg]="${t.role('signal')}"')
	assert render_signal_cava(t).contains("gradient_color_3 = '${t.role('signal')}'")
	assert kitty.contains('color15 ${t.terminal[15]}')
	alacritty := render_signal_alacritty(t)
	assert alacritty.contains('[colors.bright]')
	assert alacritty.contains('white = "${t.terminal[15]}"')
	ghostty := render_signal_ghostty(t)
	assert ghostty.contains('palette = 0=${t.terminal[0]}')
	assert ghostty.contains('cursor-color = ${t.role('signal')}')
}

fn test_migrate_theme_id_maps_retired_ids_once() {
	assert migrate_theme_id('hornero-dark') == 'hornero-signal-night'
	assert migrate_theme_id('hornero-light') == 'hornero-signal-day'
	assert migrate_theme_id('hornero-199x') == 'hornero-signal-night'
	for id in ['neon-city', 'vapor-dreams', 'soft-morning', 'warm-sunset'] {
		assert migrate_theme_id(id) == 'hornero-signal-night'
	}
	assert migrate_theme_id('') == 'hornero-signal-night'
	assert migrate_theme_id('hornero-signal-day') == 'hornero-signal-day'
	assert migrate_theme_id('patagonia') == 'patagonia'
}

fn test_legacy_migration_rewrites_state_and_shell_config() {
	sg_setup()
	state := scheme_state_file()
	shell := shell_config_file(resolve_paths())
	sg_write(state, '{"name":"hornero-light","flavour":"vibrant","mode":"light","variant":"vibrant","gtkColorScheme":"prefer-light"}')
	sg_write(shell, '{"appearance":{"theme":"hornero-199x","highContrast":false},"bar":{"persistent":true}}')
	sel := resolve_signal_selection()
	assert sel.id == 'hornero-signal-day'
	assert sel.source == 'state'
	assert sel.migrated_from == 'hornero-light'
	plan := plan_legacy_migration()
	assert plan.changes.len == 6
	// Planning never writes.
	assert (os.read_file(state) or { '' }).contains('hornero-light')
	done := migrate_legacy_appearance() or { panic(err) }
	assert done.changes.len == 6
	st := json2.decode[map[string]json2.Any](os.read_file(state) or { '' }) or { panic(err) }
	assert st['theme'].str() == 'hornero-signal-day'
	assert st['gtkColorScheme'].str() == 'prefer-light'
	for key in ['name', 'flavour', 'variant', 'mode'] {
		assert key !in st
	}
	sh := json2.decode[map[string]json2.Any](os.read_file(shell) or { '' }) or { panic(err) }
	assert sh['appearance'].as_map()['theme'].str() == 'hornero-signal-night'
	assert sh['appearance'].as_map()['highContrast'].bool() == false
	assert sh['bar'].as_map()['persistent'].bool()
	// One-shot: a second run has nothing to do.
	assert plan_legacy_migration().changes.len == 0
	assert (migrate_legacy_appearance() or { panic(err) }).changes.len == 0
	sg_teardown()
}

fn test_migration_never_overwrites_unparseable_shell_config() {
	sg_setup()
	shell := shell_config_file(resolve_paths())
	sg_write(shell, '{not json')
	if _ := persist_shell_theme('hornero-signal-day') {
		assert false, 'invalid shell.json must not be overwritten'
	}
	assert (os.read_file(shell) or { '' }) == '{not json'
	sg_teardown()
}

fn test_selection_defaults_to_signal_night() {
	sg_setup()
	sel := resolve_signal_selection()
	assert sel.id == 'hornero-signal-night'
	assert sel.source == 'default'
	sg_teardown()
}

fn test_theme_apply_writes_scheme_and_outputs() {
	sg_setup()
	log := '${sg_root}/deps.log'
	sg_write('${sg_root}/state/hornero/scheme/state.json', '{"name":"hornero-dark","flavour":"vibrant","gtkColorScheme":"follow"}')
	r := theme_apply_native_with('hornero-signal-day', '', false, sg_deps(log))
	assert r.ok, r.message
	assert r.data['mode'] == 'light'
	live := read_signal_scheme() or { panic(err) }
	assert live.id == 'hornero-signal-day'
	out := signal_output_paths()
	assert out.hyprland_lua == '${sg_root}/cache/hornero/smart-colors/colors-hyprland.lua'
	assert out.hyprlock_conf == '${sg_root}/cache/hornero/smart-colors/colors-hyprlock.conf'
	assert out.btop_theme == '${sg_root}/config/btop/themes/Hornero Dynamic.theme'
	assert (os.read_file(out.hyprland_lua) or { '' }).contains('rgba(8f4b00ee)')
	assert (os.read_file(out.hyprlock_conf) or { '' }).contains('$' + 'hs_ground = rgba(e6e1d5ff)')
	for path in [out.alacritty_toml, out.ghostty_theme, out.btop_theme, out.cava_theme] {
		assert os.is_file(path), path
	}
	st := json2.decode[map[string]json2.Any](os.read_file(scheme_state_file()) or { '' }) or {
		panic(err)
	}
	assert st['theme'].str() == 'hornero-signal-day'
	assert 'flavour' !in st
	sh := os.read_file(shell_config_file(resolve_paths())) or { '' }
	assert sh.contains('"theme":"hornero-signal-day"')
	calls := os.read_file(log) or { '' }
	assert calls.contains('gtk Hornero-Signal-Day Papirus prefer-light')
	assert calls.contains('extras hornero-signal-day')
	assert calls.contains('reload')
	assert r.message.contains('migrated')
	sg_teardown()
}

fn test_theme_apply_dry_run_writes_nothing() {
	sg_setup()
	r := theme_apply_native_with('hornero-signal-night', '', true, sg_deps('${sg_root}/deps.log'))
	assert r.ok, r.message
	assert r.data['dry_run'] == 'true'
	assert r.message.contains('signal/scheme.json (atomic)')
	assert !os.exists(signal_scheme_file())
	assert !os.exists('${sg_root}/deps.log')
	sg_teardown()
}

fn test_theme_apply_rejects_retired_and_v1_packs() {
	sg_setup()
	retired := theme_apply_report(ThemeApplyOptions{
		id:  'hornero-dark'
		yes: true
	})
	assert !retired.ok
	assert retired.message.contains('use hornero-signal-night')
	bad := theme_apply_report(ThemeApplyOptions{
		id:  '../etc'
		yes: true
	})
	assert !bad.ok
	refused := theme_apply_report(ThemeApplyOptions{
		id: 'hornero-signal-day'
	})
	assert !refused.ok
	assert refused.message.contains('--yes')
	assert !os.exists(signal_scheme_file())
	sg_teardown()
}

fn test_theme_apply_sets_pack_wallpaper_without_recolouring() {
	sg_setup()
	r := theme_apply_native_with('hornero-signal-night', '', false, sg_deps('${sg_root}/deps.log'))
	assert r.ok, r.message
	// The pack wallpaper is not installed: the current wallpaper stays.
	assert read_wallpaper_pointer() == ''
	sg_write('${sg_root}/walls/hornero-signal-night/hornero-signal-night-01.png', 'img')
	again := theme_apply_native_with('hornero-signal-night', '', false, sg_deps('${sg_root}/deps.log'))
	assert again.ok, again.message
	assert read_wallpaper_pointer().ends_with('hornero-signal-night-01.png')
	live := read_signal_scheme() or { panic(err) }
	assert live.palette == sg_fixture('hornero-signal-night').palette
	sg_teardown()
}

fn test_set_wallpaper_never_changes_scheme() {
	sg_setup()
	t := sg_fixture('hornero-signal-night')
	write_signal_scheme(t) or { panic(err) }
	before := os.read_file(signal_scheme_file()) or { '' }
	sg_write('${sg_root}/w.jpg', 'img')
	r := set_wallpaper_only('wallpaper set', '${sg_root}/w.jpg', false)
	assert r.ok, r.message
	assert read_wallpaper_pointer() == '${sg_root}/w.jpg'
	assert (os.read_file(signal_scheme_file()) or { '' }) == before
	assert !os.exists(signal_output_paths().hyprlock_conf)
	sg_teardown()
}

fn test_appearance_sync_migrates_and_materializes_default() {
	sg_setup()
	sg_write(shell_config_file(resolve_paths()), '{"appearance":{"theme":"hornero-light"}}')
	dry := appearance_sync_native(true)
	assert dry.ok, dry.message
	assert !os.exists(signal_scheme_file())
	r := appearance_sync_native(false)
	assert r.ok, r.message
	live := read_signal_scheme() or { panic(err) }
	assert live.id == 'hornero-signal-day'
	assert (os.read_file(shell_config_file(resolve_paths())) or { '' }).contains('hornero-signal-day')
	sg_teardown()
}

fn test_missing_ibm_plex_families() {
	sg_setup()
	fonts := '${sg_root}/fonts'
	sg_write('${fonts}/TTF/IBMPlexSansCondensed-Regular.ttf', 'x')
	sg_write('${fonts}/TTF/IBMPlexMono-Regular.ttf', 'x')
	missing := missing_ibm_plex_families([fonts])
	assert missing == ['IBM Plex Sans']
	sg_write('${fonts}/TTF/IBMPlexSans-Regular.ttf', 'x')
	assert missing_ibm_plex_families([fonts]).len == 0
	assert missing_ibm_plex_families(['${sg_root}/none']).len == 3
	sg_teardown()
}

fn test_appearance_doctor_checks_scheme_and_fonts() {
	sg_setup()
	os.setenv('HORNERO_FONT_DIRS', '${sg_root}/fonts', true)
	// hermetic: no Qt platform-theme plugin is visible to the Qt checks
	os.setenv('HORNERO_QT_PLUGIN_DIRS', '${sg_root}/no-qt-plugins', true)
	checks := appearance_doctor_checks()
	// signal-scheme, signal-fonts, chromatic-helper, then the Qt consumer
	// checks (qt-qt6ct, qt-qt5ct, qt-platformtheme).
	assert checks.len == 6
	assert checks[3..].map(it.name) == ['qt-qt6ct', 'qt-qt5ct', 'qt-platformtheme']
	assert checks[0].name == 'signal-scheme'
	assert checks[2].name == 'chromatic-helper'
	assert !checks[0].ok
	assert checks[1].name == 'signal-fonts'
	assert checks[1].detail.contains('ttf-ibm-plex')
	write_signal_scheme(sg_fixture('hornero-signal-night')) or { panic(err) }
	for f in ['IBMPlexSans-Regular.ttf', 'IBMPlexMono-Regular.ttf', 'IBMPlexSansCondensed-Regular.ttf'] {
		sg_write('${sg_root}/fonts/${f}', 'x')
	}
	ok := appearance_doctor_checks()
	assert ok[0].ok
	assert ok[1].ok
	report := appearance_doctor_native()
	assert !report.message.contains('materialyoucolor')
	os.unsetenv('HORNERO_QT_PLUGIN_DIRS')
	sg_teardown()
}

fn test_theme_list_hides_non_signal_packs() {
	sg_setup()
	packs := list_theme_packs() or { panic(err) }
	ids := packs.map(it.id)
	assert ids == ['hornero-signal-contrast', 'hornero-signal-day', 'hornero-signal-night']
	sg_teardown()
}
