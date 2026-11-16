module hornero_core

import os
import x.json2

// Smart-colors engine vectors: hex helpers, GTK policy normalization, and
// the smart-color renderers fed from a Hornero Signal fixture
// (cli/testdata/signal-themes). Every concept maps to a Signal role.

fn sc_fixture(id string) SignalTheme {
	path := os.join_path(os.dir(@FILE), '..', '..', 'testdata', 'signal-themes', id, 'theme.json')
	raw := os.read_file(path) or { panic('missing fixture ${path}') }
	m := json2.decode[map[string]json2.Any](raw) or { panic(err) }
	return parse_signal_theme(id, m) or { panic(err) }
}

fn test_color_luminance_vectors() {
	assert color_luminance('#ff0000') == 76
	assert color_luminance('#1a1b26') == 27
	assert color_luminance('#eff1f5') == 240
	assert color_luminance('#000000') == 0
	assert color_luminance('#ffffff') == 255
	assert is_light_hex('#1a1b26') == false
	assert is_light_hex('#eff1f5') == true
}

fn test_gtk_policy_vectors() {
	assert normalize_gtk_color_scheme('follow') == 'follow'
	assert normalize_gtk_color_scheme('LIGHT') == 'prefer-light'
	assert normalize_gtk_color_scheme('dark') == 'prefer-dark'
	assert normalize_gtk_color_scheme('true') == 'prefer-dark'
	assert normalize_gtk_color_scheme('false') == 'prefer-light'
	assert normalize_gtk_color_scheme('auto') == 'default'
	assert normalize_gtk_color_scheme('bogus') == 'invalid'
	assert effective_gtk_policy('follow', 'light') == 'prefer-light'
	assert effective_gtk_policy('follow', 'dark') == 'prefer-dark'
	assert effective_gtk_policy('prefer-light', 'dark') == 'prefer-light'
	assert pack_gtk_policy('prefer-light', '', 'Orchis-Dark', 'dark') == 'prefer-light'
	assert pack_gtk_policy('', 'false', 'Orchis-Dark', 'dark') == 'prefer-light'
	assert pack_gtk_policy('', '', 'Orchis-Dark-Compact', 'light') == 'prefer-dark'
	assert pack_gtk_policy('', '', 'Orchis-Light', 'dark') == 'prefer-light'
	assert pack_gtk_policy('', '', 'auto', 'light') == 'prefer-light'
	assert pack_gtk_policy('', '', 'auto', 'dark') == 'prefer-dark'
	assert pack_gtk_policy('bogus', '', 'x', 'dark') == 'prefer-dark'
	pd, cs := policy_prefer_dark_and_scheme('prefer-light')
	assert pd == 'false'
	assert cs == 'prefer-light'
	pd2, cs2 := policy_prefer_dark_and_scheme('default')
	assert pd2 == 'false'
	assert cs2 == 'default'
	pd3, cs3 := policy_prefer_dark_and_scheme('follow')
	assert pd3 == 'true'
	assert cs3 == 'prefer-dark'
	assert normalize_prefer_dark('dark') == 'true'
	assert normalize_prefer_dark('light') == 'false'
	assert normalize_prefer_dark('x') == 'auto'
}

fn test_signal_concepts_map_to_roles() {
	t := sc_fixture('hornero-signal-night')
	assert (signal_concept(t, 'background') or { '' }) == '#13171D'
	assert (signal_concept(t, 'foreground') or { '' }) == '#ECE6DA'
	assert (signal_concept(t, 'error') or { '' }) == '#F0705A'
	assert (signal_concept(t, 'accent') or { '' }) == '#F2A33A'
	assert (signal_concept(t, 'info') or { '' }) == '#7EC1EA'
	assert (signal_concept(t, 'success') or { '' }) == '#8BD49A'
	assert (signal_concept(t, 'red') or { '' }) == t.terminal[1]
	assert (signal_concept(t, 'pink') or { '' }) == t.terminal[13]
	if _ := signal_concept(t, 'bogus') {
		assert false, 'unknown concept must fail'
	}
}

fn test_render_smart_files_from_signal() {
	t := sc_fixture('hornero-signal-day')
	p := signal_smart_palette(t, '/pic/wall.jpg')
	assert p.light
	scss := render_scss(p)
	assert scss.contains('\$wallpaper: "/pic/wall.jpg";')
	assert scss.contains('\$background: #F2EEE5;')
	assert scss.contains('\$error: #A8341C;')
	assert scss.contains('\$color0: ${t.terminal[0]};')
	assert render_shell_colors(p).contains("color_accent='#8F4B00'")
	env := render_env_colors(p, '/x/colors.env')
	assert env.contains("export COLOR_ERROR='#A8341C'")
	assert env.contains('source /x/colors.env')
	assert render_waybar(p).contains('@define-color smart-info #1A5F88;')
	assert render_mako(p).contains('background-color=#F2EEE5')
	assert render_wlogout(p).contains('@define-color wlogout-fg #1B1E22;')
	henv := render_hyprlock_env(p)
	assert henv.contains('SMART_ERROR="#A8341C"')
	assert henv.contains('SMART_THEME_TYPE="light"')
	assert render_css_vars(p).contains('--smart-success: #256A3B;')
	copyq := render_copyq(p)
	assert copyq.contains('# Theme type: light')
	assert copyq.contains('IBM Plex Mono')
	assert !copyq.contains('JetBrains')
}
