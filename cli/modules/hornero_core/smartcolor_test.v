module hornero_core

// Golden vectors for the smart-colors engine. Expected outputs were
// computed by an independent Python oracle implementing the bash
// formulas, then hardcoded here: the V port must match exactly.

fn golden_palette() map[string]string {
	return {
		'background': '#1a1b26'
		'foreground': '#c0caf5'
		'cursor':     '#c0caf5'
		'color0':     '#15161e'
		'color1':     '#f7768e'
		'color2':     '#9ece6a'
		'color3':     '#e0af68'
		'color4':     '#7aa2f7'
		'color5':     '#bb9af7'
		'color6':     '#7dcfff'
		'color7':     '#a9b1d6'
		'color8':     '#414868'
		'color9':     '#f7768e'
		'color10':    '#9ece6a'
		'color11':    '#e0af68'
		'color12':    '#7aa2f7'
		'color13':    '#bb9af7'
		'color14':    '#7dcfff'
		'color15':    '#c0caf5'
	}
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

fn test_blend_hex_vector() {
	assert blend_hex('#ff0000', '#0000ff', 50) == '#7f007f'
	assert blend_hex('#e91e63', '#a8a3b4', 10) == '#e22b6b'
	assert blend_hex('#ffffff', '#000000', 0) == '#ffffff'
	assert blend_hex('#ffffff', '#000000', 100) == '#000000'
}

fn test_enhance_contrast_vectors() {
	assert enhance_contrast_for_theme('#ffffff', true) == '#999999'
	assert enhance_contrast_for_theme('#d32f2f', true) == '#d32f2f'
	assert enhance_contrast_for_theme('#f44336', false) == '#f44336'
	assert enhance_contrast_for_theme('#f57f17', true) == '#f57f17'
}

fn test_palette_dominant_and_average() {
	pal := golden_palette()
	assert palette_dominant(pal) == 'purple'
	assert palette_average(pal) == '#a8a3b4'
	assert palette_dominant(map[string]string{}) == 'unknown'
	assert palette_average(map[string]string{}) == '#808080'
}

fn test_semantic_base_spots() {
	assert semantic_base('error', 'dark', 'purple') == '#e91e63'
	assert semantic_base('error', 'dark', 'red') == '#ff6b6b'
	assert semantic_base('accent', 'light', 'pink') == '#c2185b'
	assert semantic_base('magenta', 'dark', 'pink') == '#e91e63'
	assert semantic_base('purple', 'light', 'cyan') == '#8e24aa'
	assert semantic_base('brown', 'light', 'orange') == '#6d4c41'
	assert semantic_base('nope', 'dark', 'red') == '#757575'
}

fn test_smart_color_golden_finals() {
	pal := golden_palette()
	assert smart_color_for('error', pal)! == '#e22b6b'
	assert smart_color_for('warning', pal)! == '#f69112'
	assert smart_color_for('success', pal)! == '#8dbf54'
	assert smart_color_for('info', pal)! == '#9d33b0'
	assert smart_color_for('accent', pal)! == '#9d33b0'
	assert smart_color_for('red', pal)! == '#de4341'
	assert smart_color_for('green', pal)! == '#6cb871'
	assert smart_color_for('blue', pal)! == '#4ca4ee'
	assert smart_color_for('yellow', pal)! == '#f6c636'
	assert smart_color_for('cyan', pal)! == '#33c2d6'
	assert smart_color_for('magenta', pal)! == '#9d33b0'
	assert smart_color_for('purple', pal)! == '#9d33b0'
	assert smart_color_for('orange', pal)! == '#f6b557'
	assert smart_color_for('pink', pal)! == '#9d33b0'
	assert smart_color_for('brown', pal)! == '#7d5c52'
	assert smart_color_for('background', pal)! == '#1a1b26'
	assert smart_color_for('background-alt', pal)! == '#f7768e'
	assert smart_color_for('foreground', pal)! == '#c0caf5'
	assert smart_color_for('foreground-alt', pal)! == '#bb9af7'
	assert smart_color_for('white', pal)! == '#c0caf5'
	assert smart_color_for('black', pal)! == '#1a1b26'
	assert smart_color_for('gray', pal)! == '#414868'
	assert smart_color_for('grey', pal)! == '#414868'
	if _ := smart_color_for('bogus', pal) {
		assert false, 'bogus concept must fail'
	} else {
		assert err.msg().contains('unknown concept')
	}
}

fn test_normalize_scheme_type_vectors() {
	assert normalize_scheme_type('fruitsalad') == 'expressive'
	assert normalize_scheme_type('RAINBOW') == 'expressive'
	assert normalize_scheme_type('TonalSpot') == 'tonal-spot'
	assert normalize_scheme_type('tonal_spot') == 'tonal-spot'
	assert normalize_scheme_type('vibrant') == 'vibrant'
	assert normalize_scheme_type('bogus') == 'tonal-spot'
}

fn test_normalize_variant_vectors() {
	assert normalize_variant('FRUITSALAD') == 'fruitsalad'
	assert normalize_variant('TonalSpot') == 'tonalspot'
	assert normalize_variant('bogus') == 'tonalspot'
	assert variant_to_scheme_type('tonalspot') == 'tonal-spot'
	assert variant_to_scheme_type('fruitsalad') == 'expressive'
	assert variant_to_scheme_type('rainbow') == 'expressive'
	assert variant_to_scheme_type('vibrant') == 'vibrant'
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

fn test_parse_xrdb_query_vector() {
	out := '*background:\t#1a1b26\n*foreground:\t#c0caf5\nXTerm*color1: #f7768e\ncolor2: not-a-color\n'
	pal := parse_xrdb_query(out)
	assert pal['background'] == '#1a1b26'
	assert pal['foreground'] == '#c0caf5'
	assert pal['color1'] == '#f7768e'
	assert 'color2' !in pal
}

fn test_hyprlock_rgba_vector() {
	assert hyprlock_rgba('#ff6b6b', 'ff') == 'ff6b6bff'
	assert hyprlock_rgba('ff6b6b', 'aa') == 'ff6b6baa'
}

fn test_render_scss_spots() {
	p := derive_palette(golden_palette(), '/pic/wall.jpg')
	scss := render_scss(p)
	assert scss.contains('\$wallpaper: "/pic/wall.jpg";')
	assert scss.contains('\$background: #1a1b26;')
	assert scss.contains('\$error: #e22b6b;')
	assert scss.contains('\$color0: #15161e;')
	assert scss.contains('\$pink: #9d33b0;')
	sh := render_shell_colors(p)
	assert sh.contains("color_error='#e22b6b'")
	assert sh.contains("color_background='#1a1b26'")
	env := render_env_colors(p, '/x/colors.env')
	assert env.contains("export COLOR_ERROR='#e22b6b'")
	assert env.contains('source /x/colors.env')
	waybar := render_waybar(p)
	assert waybar.contains('@define-color smart-error #e22b6b;')
	mako := render_mako(p)
	assert mako.contains('background-color=#1a1b26')
	hypr := render_hyprland(p)
	assert hypr.contains('col.active_border = rgba(9d33b0ee) rgba(9d33b0ee) 45deg')
	assert hypr.contains('col.border_locked_inactive')
	wlogout := render_wlogout(p)
	assert wlogout.contains('@define-color wlogout-bg #1a1b26;')
	henv := render_hyprlock_env(p)
	assert henv.contains('SMART_ERROR="#e22b6b"')
	assert henv.contains('SMART_THEME_TYPE="dark"')
	kitty := render_kitty(p)
	assert kitty.contains('background #1a1b26')
	assert kitty.contains('color1 #f7768e')
	css := render_css_vars(p)
	assert css.contains('--smart-error: #e22b6b;')
	copyq := render_copyq(p)
	assert copyq.contains('# Theme type: dark')
	assert copyq.contains('sel_bg=#9d33b0')
}

fn test_render_hyprlock_conf_vector() {
	s := HyprlockScheme{
		primary:            '#9d33b0'
		surface:            '#1a1b26'
		on_surface:         '#c0caf5'
		background:         '#1a1b26'
		on_surface_variant: '#a9b1d6'
		outline:            '#414868'
		secondary:          '#7aa2f7'
		error:              '#e22b6b'
		light:              false
		wallpaper:          '/pic/wall.jpg'
		scheme_source:      '/scheme.json'
	}
	conf := render_hyprlock_conf(s)
	assert conf.contains('path = /pic/wall.jpg')
	assert conf.contains('brightness = 0.8')
	assert conf.contains('font_color = rgb(#c0caf5)')
	assert conf.contains('fail_color = rgba(#e22b6b')
	assert conf.contains('inner_color = rgba(1a1b26bb)')
	assert conf.contains('# Source: /scheme.json')
	light_conf := render_hyprlock_conf(HyprlockScheme{
		background: '#eff1f5'
		light:      true
	})
	assert light_conf.contains('brightness = 1.1')
	assert light_conf.contains('color = 0xffeff1f5ff')
}
