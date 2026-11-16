module hornero_core

// Smart-colors engine: hex helpers, GTK colour-policy normalization, and
// the smart-color file renderers (eww, waybar, mako, wlogout, CopyQ, CSS,
// shell env). Every smart concept maps to a Hornero Signal role of the
// live scheme (signal.v); there is no palette synthesis.
//
// All functions here are pure: they take hex strings / palettes and return
// strings. Golden vectors live in smartcolor_test.v.

// hex_digit_value maps one ASCII hex digit to its value, or -1.
fn hex_digit_value(c u8) int {
	if c >= u8(`0`) && c <= u8(`9`) {
		return int(c) - int(u8(`0`))
	}
	if c >= u8(`a`) && c <= u8(`f`) {
		return int(c) - int(u8(`a`)) + 10
	}
	if c >= u8(`A`) && c <= u8(`F`) {
		return int(c) - int(u8(`A`)) + 10
	}
	return -1
}

// parse_hex6 parses `#rrggbb` or `rrggbb` (any case) into channels.
fn parse_hex6(s string) !(int, int, int) {
	hex := if s.starts_with('#') { s[1..] } else { s }
	if hex.len != 6 {
		return error('not a 6-digit hex color: ${s}')
	}
	mut vals := [0, 0, 0]
	for i in 0 .. 3 {
		hi := hex_digit_value(hex[i * 2])
		lo := hex_digit_value(hex[i * 2 + 1])
		if hi < 0 || lo < 0 {
			return error('not a 6-digit hex color: ${s}')
		}
		vals[i] = hi * 16 + lo
	}
	return vals[0], vals[1], vals[2]
}

fn hex2(n int) string {
	clamped := if n < 0 {
		0
	} else if n > 255 {
		255
	} else {
		n
	}
	return '0123456789abcdef'[clamped >> 4].ascii_str() +
		'0123456789abcdef'[clamped & 15].ascii_str()
}

// rgb_to_hex formats channels as a lowercase `#rrggbb` string.
pub fn rgb_to_hex(r int, g int, b int) string {
	return '#' + hex2(r) + hex2(g) + hex2(b)
}

// color_luminance returns the relative luminance on a 0-255 scale using
// the same integer formula as Hornero palette pipeline:
// (red*299 + green*587 + blue*114) / 1000.
pub fn color_luminance(color string) int {
	r, g, b := parse_hex6(color) or { return 0 }
	return (r * 299 + g * 587 + b * 114) / 1000
}

// is_light_hex reports whether a background hex reads as a light theme
// (luminance above the 128 threshold).
pub fn is_light_hex(bg string) bool {
	return color_luminance(bg) > 128
}

// valid_smart_concept mirrors the find_best_color_for_concept validation.
pub fn valid_smart_concept(concept string) bool {
	return concept in ['error', 'warning', 'success', 'info', 'accent', 'red', 'green', 'blue',
		'yellow', 'cyan', 'magenta', 'purple', 'orange', 'pink', 'brown', 'white', 'black', 'gray',
		'grey', 'background', 'background-alt', 'foreground', 'foreground-alt']
}

// signal_concept maps one smart concept onto the Signal scheme: neutrals
// and semantic concepts read roles, basic hues read the terminal palette.
pub fn signal_concept(t SignalTheme, concept string) !string {
	if !valid_smart_concept(concept) {
		return error('unknown concept: ${concept}')
	}
	return match concept {
		'background', 'black' { t.role('base') }
		'background-alt' { t.role('panel') }
		'foreground', 'white' { t.role('ink') }
		'foreground-alt' { t.role('inkMuted') }
		'gray', 'grey' { t.role('inkFaint') }
		'error' { t.role('alert') }
		'warning', 'accent', 'orange' { t.role('signal') }
		'success' { t.role('phosphor') }
		'info' { t.role('cue') }
		'brown' { t.role('signalWell') }
		'red' { t.terminal[1] }
		'green' { t.terminal[2] }
		'yellow' { t.terminal[3] }
		'blue' { t.terminal[4] }
		'magenta', 'purple' { t.terminal[5] }
		'cyan' { t.terminal[6] }
		else { t.terminal[13] } // pink: bright magenta
	}
}

// normalize_gtk_color_scheme canonicalizes a gtkColorScheme policy:
// follow | default | prefer-light | prefer-dark (light/dark/true/false
// and friends are aliases; anything else is 'invalid').
pub fn normalize_gtk_color_scheme(raw string) string {
	n := raw.to_lower().replace('_', '-')
	match n {
		'follow', 'follow-mode', 'follow-theme', 'follow-theme-mode' { return 'follow' }
		'default', 'auto', 'apps', 'apps-decide' { return 'default' }
		'prefer-light', 'light' { return 'prefer-light' }
		'prefer-dark', 'dark' { return 'prefer-dark' }
		'true', '1', 'yes' { return 'prefer-dark' }
		'false', '0', 'no' { return 'prefer-light' }
		else { return 'invalid' }
	}
}

// normalize_prefer_dark maps a prefer-dark-ish value to 'true'/'false'/'auto'.
pub fn normalize_prefer_dark(raw string) string {
	match raw.to_lower() {
		'true', '1', 'yes', 'dark' { return 'true' }
		'false', '0', 'no', 'light' { return 'false' }
		else { return 'auto' }
	}
}

// effective_gtk_policy resolves follow against the live shell mode;
// every other policy passes through.
pub fn effective_gtk_policy(policy string, shell_mode string) string {
	p := normalize_gtk_color_scheme(policy)
	if p == 'invalid' {
		return 'prefer-dark'
	}
	if p != 'follow' {
		return p
	}
	if shell_mode == 'light' {
		return 'prefer-light'
	}
	return 'prefer-dark'
}

// pack_gtk_policy derives the canonical gtkColorScheme policy for a
// theme pack: explicit gtkColorScheme wins, then gtkPreferDark, then the
// gtk theme name, then the shell dark mode. Ports both
// theme_resolve_gtk_color_scheme and the gtk-theme-manager meta read.
pub fn pack_gtk_policy(gtk_color_scheme string, gtk_prefer_dark string, gtk_theme string, dark_mode string) string {
	if gtk_color_scheme.len > 0 {
		p := normalize_gtk_color_scheme(gtk_color_scheme)
		if p == 'follow' || p == 'default' || p == 'prefer-light' || p == 'prefer-dark' {
			return p
		}
		if p == 'invalid' {
			return 'prefer-dark'
		}
		return p
	}
	if gtk_prefer_dark == 'true' || gtk_prefer_dark == 'false' {
		if gtk_prefer_dark == 'false' {
			return 'prefer-light'
		}
		return 'prefer-dark'
	}
	lc := gtk_theme.to_lower()
	if lc.contains('light') {
		return 'prefer-light'
	}
	if lc.contains('dark') {
		return 'prefer-dark'
	}
	if dark_mode == 'light' {
		return 'prefer-light'
	}
	return 'prefer-dark'
}

// policy_prefer_dark_and_scheme maps an effective policy to the INI
// prefer-dark boolean plus the gsettings color-scheme value.
pub fn policy_prefer_dark_and_scheme(effective string) (string, string) {
	match effective {
		'default' { return 'false', 'default' }
		'prefer-light' { return 'false', 'prefer-light' }
		else { return 'true', 'prefer-dark' }
	}
}

// SmartPalette is every derived color the file generators consume.
pub struct SmartPalette {
pub:
	background     string
	foreground     string
	cursor         string
	background_alt string
	foreground_alt string
	error          string
	warning        string
	success        string
	info           string
	accent         string
	red            string
	green          string
	blue           string
	yellow         string
	cyan           string
	magenta        string
	orange         string
	pink           string
	brown          string
	white          string
	black          string
	gray           string
	base           [16]string
	wallpaper      string
	light          bool
}

// signal_smart_palette resolves every smart concept against the Signal
// scheme for the file renderers.
pub fn signal_smart_palette(t SignalTheme, wallpaper string) SmartPalette {
	get := fn [t] (concept string) string {
		return signal_concept(t, concept) or { t.role('ink') }
	}
	mut base := [16]string{}
	for i in 0 .. 16 {
		base[i] = t.terminal[i]
	}
	return SmartPalette{
		background:     get('background')
		foreground:     get('foreground')
		cursor:         t.role('signal')
		background_alt: get('background-alt')
		foreground_alt: get('foreground-alt')
		error:          get('error')
		warning:        get('warning')
		success:        get('success')
		info:           get('info')
		accent:         get('accent')
		red:            get('red')
		green:          get('green')
		blue:           get('blue')
		yellow:         get('yellow')
		cyan:           get('cyan')
		magenta:        get('magenta')
		orange:         get('orange')
		pink:           get('pink')
		brown:          get('brown')
		white:          get('white')
		black:          get('black')
		gray:           get('gray')
		base:           base
		wallpaper:      wallpaper
		light:          t.mode == 'light'
	}
}

// render_scss renders colors-eww.scss.
pub fn render_scss(p SmartPalette) string {
	mut out := '// SCSS Variables\n// Generated by horneroctl appearance colors generate\n'
	out += '\$wallpaper: "${p.wallpaper}";\n\n// Special\n\$background: ${p.background};\n'
	out += '\$foreground: ${p.foreground};\n\$cursor: ${p.cursor};\n\n// Colors\n'
	for i in 0 .. 16 {
		out += '\$color${i}: ${p.base[i]};\n'
	}
	out += '\n// Background and foreground variants\n\$background-alt: ${p.background_alt};\n'
	out += '\$foreground-alt: ${p.foreground_alt};\n\n// Smart semantic colors (theme-adaptive)\n'
	out += '\$error: ${p.error};\n\$warning: ${p.warning};\n\$success: ${p.success};\n'
	out += '\$info: ${p.info};\n\$accent: ${p.accent};\n\n// Smart basic colors (theme-adaptive)\n'
	for c in ['red', 'green', 'blue', 'yellow', 'cyan', 'magenta', 'orange', 'pink'] {
		v := match c {
			'red' { p.red }
			'green' { p.green }
			'blue' { p.blue }
			'yellow' { p.yellow }
			'cyan' { p.cyan }
			'magenta' { p.magenta }
			'orange' { p.orange }
			else { p.pink }
		}
		out += '\$${c}: ${v};\n'
	}
	return out
}

// render_shell_colors renders colors.sh.
pub fn render_shell_colors(p SmartPalette) string {
	mut out := '# Shell variables\n# Generated by horneroctl appearance colors generate\n\n'
	out += '# Background and foreground variants\n'
	out += "color_background='${p.background}'\ncolor_background_alt='${p.background_alt}'\n"
	out += "color_foreground='${p.foreground}'\ncolor_foreground_alt='${p.foreground_alt}'\n"
	out += '\n# Smart semantic colors\n'
	out += "color_error='${p.error}'\ncolor_warning='${p.warning}'\ncolor_success='${p.success}'\n"
	out += "color_info='${p.info}'\ncolor_accent='${p.accent}'\n\n# Smart basic colors\n"
	for c in ['red', 'green', 'blue', 'yellow', 'cyan', 'magenta', 'orange', 'pink'] {
		v := match c {
			'red' { p.red }
			'green' { p.green }
			'blue' { p.blue }
			'yellow' { p.yellow }
			'cyan' { p.cyan }
			'magenta' { p.magenta }
			'orange' { p.orange }
			else { p.pink }
		}
		out += "color_${c}='${v}'\n"
	}
	return out
}

// render_env_colors renders colors.env.
pub fn render_env_colors(p SmartPalette, env_file string) string {
	mut out := '# Environment variables for smart colors\n# Generated by horneroctl appearance colors generate from Hornero Signal\n'
	out += '# Source this file: source ${env_file}\n\n# Background and foreground variants\n'
	out += "export COLOR_BACKGROUND='${p.background}'\nexport COLOR_BACKGROUND_ALT='${p.background_alt}'\n"
	out += "export COLOR_FOREGROUND='${p.foreground}'\nexport COLOR_FOREGROUND_ALT='${p.foreground_alt}'\n"
	out += '\n# Smart semantic colors\n'
	out += "export COLOR_ERROR='${p.error}'\nexport COLOR_WARNING='${p.warning}'\n"
	out += "export COLOR_SUCCESS='${p.success}'\nexport COLOR_INFO='${p.info}'\n"
	out += "export COLOR_ACCENT='${p.accent}'\n\n# Smart basic colors\n"
	names := ['red', 'green', 'blue', 'yellow', 'cyan', 'magenta', 'orange', 'pink', 'brown', 'white',
		'black', 'gray']
	vals := [p.red, p.green, p.blue, p.yellow, p.cyan, p.magenta, p.orange, p.pink, p.brown, p.white,
		p.black, p.gray]
	for i, c in names {
		out += "export COLOR_${c.to_upper()}='${vals[i]}'\n"
	}
	return out
}

// render_waybar renders colors-waybar.css.
pub fn render_waybar(p SmartPalette) string {
	mut out := '/* Waybar colors configuration */\n/* Generated by horneroctl appearance colors generate */\n'
	out += '/* Theme-adaptive colors for Wayland/Hyprland */\n\n'
	out += '@define-color bg-primary ${p.background};\n@define-color bg-secondary ${p.base[1]};\n'
	out += '@define-color bg-hover ${p.base[8]};\n@define-color fg-primary ${p.foreground};\n'
	out += '@define-color fg-secondary ${p.base[5]};\n\n/* Smart semantic colors */\n'
	out += '@define-color smart-error ${p.error};\n@define-color smart-warning ${p.warning};\n'
	out += '@define-color smart-success ${p.success};\n@define-color smart-info ${p.info};\n'
	out += '@define-color smart-accent ${p.accent};\n\n/* Smart basic colors */\n'
	out += '@define-color smart-red ${p.red};\n@define-color smart-green ${p.green};\n'
	out += '@define-color smart-blue ${p.blue};\n@define-color smart-yellow ${p.yellow};\n'
	out += '@define-color smart-cyan ${p.cyan};\n@define-color smart-magenta ${p.magenta};\n'
	out += '@define-color smart-orange ${p.orange};\n@define-color smart-pink ${p.pink};\n'
	out += '\n/* Accent colors (for compatibility) */\n'
	out += '@define-color accent-primary ${p.accent};\n@define-color accent-success ${p.success};\n'
	out += '@define-color accent-warning ${p.warning};\n@define-color accent-error ${p.error};\n'
	out += '@define-color accent-info ${p.info};\n\n/* Border colors */\n'
	out += '@define-color border-color ${p.base[8]};\n'
	return out
}

// render_mako renders colors-mako.conf.
pub fn render_mako(p SmartPalette) string {
	mut out := '# Mako notification colors\n# Generated by horneroctl appearance colors generate from Hornero Signal\n'
	out += '# Include this in your mako config or replace values manually\n\n'
	out += 'background-color=${p.background}\ntext-color=${p.foreground}\n'
	out += 'border-color=${p.accent}\nprogress-color=over ${p.base[8]}\n\n'
	out += '[urgency=low]\nborder-color=${p.info}\n\n[urgency=normal]\nborder-color=${p.accent}\n\n'
	out += '[urgency=critical]\nborder-color=${p.error}\ntext-color=${p.error}\n'
	return out
}

// render_wlogout renders colors-wlogout.css.
pub fn render_wlogout(p SmartPalette) string {
	mut out := '/* Wlogout colors configuration */\n/* Generated by horneroctl appearance colors generate */\n'
	out += '/* Theme-adaptive colors for power menu */\n\n'
	out += '@define-color wlogout-bg ${p.background};\n@define-color wlogout-fg ${p.foreground};\n'
	out += '@define-color wlogout-border ${p.accent};\n\n'
	out += '@define-color wlogout-bg-hover ${p.base[8]};\n@define-color wlogout-border-hover ${p.base[13]};\n\n'
	for name in ['lock', 'logout', 'suspend', 'hibernate', 'shutdown', 'reboot'] {
		out += '@define-color wlogout-${name}-bg ${p.base[8]};\n'
	}
	out += '\n@define-color smart-color-error ${p.error};\n@define-color smart-color-warning ${p.warning};\n'
	out += '@define-color smart-color-success ${p.success};\n@define-color smart-color-info ${p.info};\n'
	out += '@define-color smart-color-accent ${p.accent};\n@define-color smart-color-highlight ${p.base[13]};\n'
	out += '@define-color smart-color-muted ${p.base[6]};\n\n@define-color wlogout-focus-ring ${p.base[8]};\n'
	return out
}

// render_hyprlock_env renders colors-hyprlock.env.
pub fn render_hyprlock_env(p SmartPalette) string {
	strip := fn (c string) string {
		return if c.starts_with('#') { c[1..] } else { c }
	}
	theme := if p.light { 'light' } else { 'dark' }
	mut out := '# Hyprlock colors configuration\n# Generated by horneroctl appearance colors generate from Hornero Signal\n'
	out += '# Source this for theme-adaptive lock screens\n\n'
	out += '# Background and foreground (without # prefix for hyprlock rgba)\n'
	out += 'SMART_BG="${p.background}"\nSMART_FG="${p.foreground}"\n'
	out += 'SMART_BG_HEX="${strip(p.background)}"\nSMART_FG_HEX="${strip(p.foreground)}"\n\n'
	out += '# Primary and accent colors\n'
	out += 'SMART_PRIMARY="${p.accent}"\nSMART_PRIMARY_HEX="${strip(p.accent)}"\n'
	out += 'SMART_ACCENT="${p.accent}"\nSMART_ACCENT_HEX="${strip(p.accent)}"\n\n# Semantic colors\n'
	out += 'SMART_ERROR="${p.error}"\nSMART_ERROR_HEX="${strip(p.error)}"\n'
	out += 'SMART_WARNING="${p.warning}"\nSMART_WARNING_HEX="${strip(p.warning)}"\n'
	out += 'SMART_SUCCESS="${p.success}"\nSMART_SUCCESS_HEX="${strip(p.success)}"\n'
	out += 'SMART_INFO="${p.info}"\nSMART_INFO_HEX="${strip(p.info)}"\n\n# Basic colors\n'
	out += 'SMART_RED="${p.red}"\nSMART_GREEN="${p.green}"\nSMART_BLUE="${p.blue}"\n'
	out += 'SMART_YELLOW="${p.yellow}"\nSMART_CYAN="${p.cyan}"\nSMART_MAGENTA="${p.magenta}"\n'
	out += 'SMART_ORANGE="${p.orange}"\nSMART_PINK="${p.pink}"\n\n# Theme type\n'
	out += 'SMART_THEME_TYPE="${theme}"\n'
	return out
}

// render_css_vars renders colors.css.
pub fn render_css_vars(p SmartPalette) string {
	mut out := '/* CSS Custom Properties for Smart Colors */\n/* Generated by horneroctl appearance colors generate */\n\n:root {\n'
	out += '    /* Background and foreground */\n'
	out += '    --smart-bg: ${p.background};\n    --smart-bg-alt: ${p.background_alt};\n'
	out += '    --smart-fg: ${p.foreground};\n    --smart-fg-alt: ${p.foreground_alt};\n\n'
	out += '    /* Semantic colors */\n'
	out += '    --smart-error: ${p.error};\n    --smart-warning: ${p.warning};\n'
	out += '    --smart-success: ${p.success};\n    --smart-info: ${p.info};\n'
	out += '    --smart-accent: ${p.accent};\n\n    /* Basic colors */\n'
	out += '    --smart-red: ${p.red};\n    --smart-green: ${p.green};\n'
	out += '    --smart-blue: ${p.blue};\n    --smart-yellow: ${p.yellow};\n'
	out += '    --smart-cyan: ${p.cyan};\n    --smart-magenta: ${p.magenta};\n'
	out += '    --smart-orange: ${p.orange};\n    --smart-pink: ${p.pink};\n\n    /* Base16 colors */\n'
	for i in 0 .. 16 {
		out += '    --color${i}: ${p.base[i]};\n'
	}
	out += '}\n'
	return out
}

// render_copyq renders colors-copyq.ini (theme-adaptive CopyQ theme).
pub fn render_copyq(p SmartPalette) string {
	theme := if p.light { 'light' } else { 'dark' }
	adj := fn (base string, light bool, light_adj string, dark_adj string) string {
		return base + ' ' + if light { light_adj } else { dark_adj }
	}
	sel_fg := if p.light { p.background } else { p.foreground }
	mut out := '[General]\n# CopyQ Theme - Smart Colors Integration\n'
	out += '# Generated by horneroctl appearance colors generate\n# Theme type: ${theme}\n\n# Fonts\n'
	out += 'font="IBM Plex Mono,10,-1,5,50,0,0,0,0,0"\n'
	out += 'edit_font="IBM Plex Mono,11,-1,5,50,0,0,0,0,0"\n'
	out += 'find_font="IBM Plex Mono,10,-1,5,50,0,0,0,0,0"\n'
	out += 'notes_font="IBM Plex Mono,11,-1,5,50,0,0,0,0,0"\n'
	out += 'num_font="IBM Plex Mono,7,-1,5,25,0,0,0,0,0"\nfont_antialiasing=true\n\n'
	out += '# Main colors - balanced and readable\nbg=${p.background}\nfg=${p.foreground}\n'
	alt_bg := if p.light { 'bg - #0a0a0a' } else { 'bg + #1a1a1a' }
	out += 'alt_bg=${alt_bg}\n'
	out += 'alt_fg=' + adj('fg', p.light, '- #1a1a1a', '+ #1a1a1a') + '\n\n'
	out += '# Selection colors - use accent color with good contrast\nsel_bg=${p.accent}\nsel_fg=${sel_fg}\n\n'
	out += '# Editor colors\n'
	out += 'edit_bg=' + adj('bg', p.light, '- #0a0a0a', '+ #0a0a0a') + '\n'
	out += 'edit_fg=' + adj('fg', p.light, '- #0a0a0a', '+ #0a0a0a') + '\n\n'
	out += '# Find/search colors\nfind_bg="rgba(0,0,0,0)"\nfind_fg=${p.accent}\n\n'
	out += '# Notes colors\nnotes_bg=bg\n'
	out += 'notes_fg=' + adj('fg', p.light, '- #2a2a2a', '+ #2a2a2a') + '\n\n'
	out += '# Number colors\nnum_fg=${p.info} ' + if p.light { '+ #111' } else { '- #111' } + '\n\n'
	out += '# Show options\nshow_scrollbars=false\nshow_number=true\nstyle_main_window=true\nuse_system_icons=false\n\n'
	out += '# Item styling\nitem_css=padding:0.5em\nalt_item_css=\n\n'
	out += '# Selection item styling with gradient\nsel_item_css="\n'
	out += '    ;background: qlineargradient(\n        x1: 0, y1: 0,\n        x2: 1, y2: 0,\n'
	out += '        stop: 0 ' + '$' + '{sel_bg}' + ',\n        stop: 1 ' + '$' + '{sel_bg}' +
		' +
		#111\n        )"\n\n'
	out += '# Search bar styling\nsearch_bar="\n    ;background: ' + '$' + '{edit_bg}' +
		'\n    ;color: ' + '$' + '{edit_fg}' + '\n'
	out += '    ;border: 1px solid ' + '$' + '{alt_bg}' +
		'\n    ;margin: 2px\n    ;border-radius: 4px"\n\n'
	out += 'search_bar_focused="\n    ;border: 1px solid ' + '$' + '{sel_bg}' + '"\n\n'
	// pick returns the light or dark adjustment suffix.
	pick := fn [p] (light_adj string, dark_adj string) string {
		return if p.light { light_adj } else { dark_adj }
	}
	tab_adj := pick('- #1a1a1a', '+ #1a1a1a')
	out += '# Tab bar styling\ntab_bar_css="\n    ;background: ' + '$' + '{bg}' + ' ${tab_adj}"\n\n'
	out += 'tab_bar_tab_selected_css="\n    ;padding: 0.5em\n    ;background: ' + '$' + '{bg}' +
		'\n'
	out += '    ;border: 0.05em solid ' + '$' + '{bg}' + '\n    ;color: ' + '$' + '{fg}' +
		'\n    ;border-bottom: 2px solid ' + '$' + '{sel_bg}' + '"\n\n'
	out += 'tab_bar_tab_unselected_css="\n    ;border: 0.05em solid ' + '$' + '{bg}' +
		'\n    ;padding: 0.5em\n'
	out += '    ;background: ' + '$' + '{bg}' + ' ${tab_adj}\n'
	out += '    ;color: ' + '$' + '{fg}' + ' ${pick('- #2a2a2a', '+ #2a2a2a')}"\n\n'
	out += 'tab_bar_item_counter="\n    ;color: ' + '$' + '{num_fg}' + ' ${tab_adj}\n'
	out += '    ;font-size: 7pt"\n\ntab_bar_sel_item_counter="\n    ;color: ' + '$' + '{num_fg}' +
		'"\n\n'
	out += 'tab_bar_scroll_buttons_css="\n    ;background: ' + '$' + '{bg}' + ' ${tab_adj}\n'
	out += '    ;color: ' + '$' + '{fg}' + '\n    ;border: 0"\n\n'
	out += 'tab_tree_css="\n    ;font-family: sans-serif\n    ;font-size: 10pt\n    ;padding: .20em\n'
	out += '    ;color: ' + '$' + '{fg}' + ' ${pick('+ #1a1a1a', '- #1a1a1a')}\n'
	out += '    ;background-color: ' + '$' + '{bg}' + '"\n\n'
	out += 'tab_tree_sel_item_css="\n'
	out += '    ;color: ' + '$' + '{fg}' + ' ${pick('+ #1a1a1a', '- #1a1a1a')}\n'
	out += '    ;background: ' + '$' + '{bg}' + ' ${pick('- #0f0f0f', '+ #0f0f0f')}"\n\n'
	out += 'tab_tree_item_counter="\n    ;padding:.33em\n    ;color: ' + '$' + '{num_fg}' +
		' ${tab_adj}\n'
	out += '    ;font-size: 7pt"\n\ntab_tree_sel_item_counter="\n    ;color: ' + '$' + '{num_fg}' +
		'"\n\n'
	out += 'tool_bar_css="\n    ;color: ' + '$' + '{fg}' + '\n    ;background-color: ' + '$' +
		'{bg}' + '\n    ;border: 0"\n\n'
	out += 'tool_button_css="\n    ;background-color: transparent"\n\n'
	out += 'tool_button_selected_css="\n    ;background-color: ' + '$' + '{bg}' +
		' ${pick('- #0a0a0a', '+ #0a0a0a')}"\n\n'
	out += 'tool_button_pressed_css="\n    ;background-color: ' + '$' + '{sel_bg}' +
		'\n    ;color: ' + '$' + '{sel_fg}' + '"\n\n'
	out += 'menu_bar_css="\n    ;background: ' + '$' + '{bg}' + '\n'
	out += '    ;color: ' + '$' + '{fg}' + ' ${pick('+ #2a2a2a', '- #2a2a2a')}"\n\n'
	out += 'menu_bar_disabled_css="\n'
	out += '    ;color: ' + '$' + '{bg}' + ' ${pick('- #4a4a4a', '+ #4a4a4a')}"\n\n'
	out += 'menu_bar_selected_css="\n    ;background: ' + '$' + '{sel_bg}' + '\n    ;color: ' +
		'$' + '{sel_fg}' + '"\n\n'
	out += 'menu_css="\n'
	edge_a := pick('+ #2a2a2a', '- #2a2a2a')
	edge_b := pick('- #2a2a2a', '+ #2a2a2a')
	out += '    ;border-top: 0.08em solid ' + '$' + '{bg}' + ' ${edge_a}\n'
	out += '    ;border-left: 0.08em solid ' + '$' + '{bg}' + ' ${edge_a}\n'
	out += '    ;border-bottom: 0.08em solid ' + '$' + '{bg}' + ' ${edge_b}\n'
	out += '    ;border-right: 0.08em solid ' + '$' + '{bg}' + ' ${edge_b}"\n\n'
	out += 'css="\n    ClipboardBrowser::item{\n        border-bottom: 1px solid ' + '$' +
		'{alt_bg}' + '\n    }\n'
	out += '    ClipboardBrowser::item:hover{\n        background: ' + '$' + '{bg}' +
		' ${pick('- #0a0a0a', '+ #0a0a0a')}\n'
	out += '    }"\n\nnotes_css=\n'
	return out
}
