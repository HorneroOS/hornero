module hornero_core

// Native smart-colors engine: palette analysis, semantic color selection,
// and smart-color file generation. Ports dots-smart-colors (dotfiles
// reference) so the xrdb palette math lives in V; only genuinely external
// tools stay backends (xrdb for palette input via HORNERO_XRDB_BIN, the M3
// python synthesizer via HORNERO_M3_SCRIPT, wallpaper setters).
//
// All color math here is pure: functions take hex strings / palette maps
// and return hex strings. Golden vectors live in smartcolor_test.v.

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
// the same integer formula as dots-smart-colors:
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

// blend_hex mixes color1 toward color2 by blend_percent (0-100), clamped
// to 0-255 per channel, exactly like the bash blend_colors.
pub fn blend_hex(color1 string, color2 string, blend_percent int) string {
	r1, g1, b1 := parse_hex6(color1) or { return color1 }
	r2, g2, b2 := parse_hex6(color2) or { return color1 }
	p := if blend_percent < 0 {
		0
	} else if blend_percent > 100 {
		100
	} else {
		blend_percent
	}
	q := 100 - p
	clamp := fn (v int) int {
		return if v > 255 {
			255
		} else if v < 0 {
			0
		} else {
			v
		}
	}
	return rgb_to_hex(clamp((r1 * q + r2 * p) / 100), clamp((g1 * q + g2 * p) / 100),
		clamp((b1 * q + b2 * p) / 100))
}

// enhance_contrast_for_theme darkens too-light colors on light themes
// (60%) and brightens too-dark colors on dark themes (130%, clamped),
// mirroring enhance_color_contrast.
pub fn enhance_contrast_for_theme(color string, light bool) string {
	r, g, b := parse_hex6(color) or { return color }
	lum := color_luminance(color)
	if light {
		if lum > 180 {
			return rgb_to_hex((r * 60) / 100, (g * 60) / 100, (b * 60) / 100)
		}
		return color
	}
	if lum < 80 {
		mut nr := (r * 130) / 100
		mut ng := (g * 130) / 100
		mut nb := (b * 130) / 100
		if nr > 255 {
			nr = 255
		}
		if ng > 255 {
			ng = 255
		}
		if nb > 255 {
			nb = 255
		}
		return rgb_to_hex(nr, ng, nb)
	}
	return color
}

// palette_get reads one key from an xrdb-style palette map.
fn palette_get(pal map[string]string, key string, fallback string) string {
	if v := pal[key] {
		if v.len > 0 {
			return v
		}
	}
	return fallback
}

// palette_dominant classifies the dominant hue from bright colors 9-14
// (brightest total wins), like get_palette_dominant_color. Missing
// entries are skipped; with no data it returns 'unknown'.
pub fn palette_dominant(pal map[string]string) string {
	mut best := ''
	mut best_sum := 0
	mut found := false
	for i in 9 .. 15 {
		c := palette_get(pal, 'color${i}', '')
		if c.len == 0 {
			continue
		}
		r, g, b := parse_hex6(c) or { continue }
		sum := r + g + b
		if !found || sum > best_sum {
			best_sum = sum
			best = c
			found = true
		}
	}
	if !found {
		return 'unknown'
	}
	r, g, b := parse_hex6(best) or { return 'unknown' }
	if r > g && r > b {
		if g > 100 {
			return 'orange'
		}
		if b > 100 {
			return 'purple'
		}
		return 'red'
	} else if g > r && g > b {
		if r > 100 {
			return 'yellow'
		}
		if b > 100 {
			return 'cyan'
		}
		return 'green'
	} else if b > r && b > g {
		if r > 100 {
			return 'purple'
		}
		if g > 100 {
			return 'cyan'
		}
		return 'blue'
	}
	return 'gray'
}

// palette_average averages colors 1-14, like get_palette_average.
// With no data it returns '#808080'.
pub fn palette_average(pal map[string]string) string {
	mut tr := 0
	mut tg := 0
	mut tb := 0
	mut n := 0
	for i in 1 .. 15 {
		c := palette_get(pal, 'color${i}', '')
		if c.len == 0 {
			continue
		}
		r, g, b := parse_hex6(c) or { continue }
		tr += r
		tg += g
		tb += b
		n++
	}
	if n == 0 {
		return '#808080'
	}
	return rgb_to_hex(tr / n, tg / n, tb / n)
}

// parse_xrdb_query parses `xrdb -query` output (`name: value` per line)
// into a palette map keyed by the trailing resource name (background,
// foreground, cursor, color0..color15). Only `#`-prefixed values are kept.
pub fn parse_xrdb_query(out string) map[string]string {
	mut pal := map[string]string{}
	for line in out.split_into_lines() {
		idx := line.index(':') or { continue }
		mut name := line[..idx].trim_space()
		if name.contains('*') {
			name = name.all_after_last('*')
		}
		name = name.all_after_last('.').to_lower().trim_space()
		value := line[idx + 1..].trim_space()
		if name.len == 0 || !value.starts_with('#') {
			continue
		}
		pal[name] = value
	}
	return pal
}

// optimal_foreground picks the foreground the way get_optimal_foreground
// does: on light themes the softer color5/color7 wins over pure black.
pub fn optimal_foreground(pal map[string]string, light bool) string {
	fg := palette_get(pal, 'foreground', '#ffffff')
	if !light {
		return fg
	}
	c5 := palette_get(pal, 'color5', '#52758A')
	if c5.len > 0 && c5 != '#000000' {
		return c5
	}
	c7 := palette_get(pal, 'color7', '#0f1415')
	if c7.len > 0 && c7 != '#000000' {
		return c7
	}
	return fg
}

// semantic_table is the concept|theme|dominant lookup from
// get_smart_color. The empty-dominant key is the per-concept wildcard
// (`concept|theme|*` in bash); anything unmatched falls back to #757575.
const semantic_table = {
	'error|dark|red':       '#ff6b6b'
	'error|dark|orange':    '#ff5722'
	'error|dark|purple':    '#e91e63'
	'error|dark|':          '#f44336'
	'error|light|red':      '#d32f2f'
	'error|light|orange':   '#bf360c'
	'error|light|purple':   '#ad1457'
	'error|light|':         '#c62828'
	'warning|dark|orange':  '#ff9800'
	'warning|dark|yellow':  '#ffc107'
	'warning|dark|red':     '#ff7043'
	'warning|dark|':        '#ff8f00'
	'warning|light|orange': '#ef6c00'
	'warning|light|yellow': '#f57f17'
	'warning|light|red':    '#d84315'
	'warning|light|':       '#e65100'
	'success|dark|green':   '#4caf50'
	'success|dark|cyan':    '#00bcd4'
	'success|dark|blue':    '#2196f3'
	'success|dark|':        '#8bc34a'
	'success|light|green':  '#2e7d32'
	'success|light|cyan':   '#00838f'
	'success|light|blue':   '#1565c0'
	'success|light|':       '#689f38'
	'info|dark|blue':       '#2196f3'
	'info|dark|cyan':       '#00bcd4'
	'info|dark|purple':     '#9c27b0'
	'info|dark|':           '#03a9f4'
	'info|light|blue':      '#1976d2'
	'info|light|cyan':      '#0097a7'
	'info|light|purple':    '#7b1fa2'
	'info|light|':          '#0288d1'
	'accent|dark|purple':   '#9c27b0'
	'accent|dark|pink':     '#e91e63'
	'accent|dark|orange':   '#ff5722'
	'accent|dark|':         '#673ab7'
	'accent|light|purple':  '#6a1b9a'
	'accent|light|pink':    '#c2185b'
	'accent|light|orange':  '#d84315'
	'accent|light|':        '#512da8'
	'red|dark|red':         '#f44336'
	'red|dark|orange':      '#ff5722'
	'red|dark|':            '#e53935'
	'red|light|red':        '#d32f2f'
	'red|light|orange':     '#bf360c'
	'red|light|':           '#c62828'
	'green|dark|green':     '#4caf50'
	'green|dark|cyan':      '#26a69a'
	'green|dark|':          '#66bb6a'
	'green|light|green':    '#388e3c'
	'green|light|cyan':     '#00695c'
	'green|light|':         '#2e7d32'
	'blue|dark|blue':       '#2196f3'
	'blue|dark|cyan':       '#00bcd4'
	'blue|dark|':           '#42a5f5'
	'blue|light|blue':      '#1976d2'
	'blue|light|cyan':      '#0097a7'
	'blue|light|':          '#1565c0'
	'yellow|dark|yellow':   '#ffeb3b'
	'yellow|dark|orange':   '#ffc107'
	'yellow|dark|':         '#ffca28'
	'yellow|light|yellow':  '#f57f17'
	'yellow|light|orange':  '#ef6c00'
	'yellow|light|':        '#f9a825'
	'cyan|dark|cyan':       '#00bcd4'
	'cyan|dark|blue':       '#03a9f4'
	'cyan|dark|':           '#26c6da'
	'cyan|light|cyan':      '#00838f'
	'cyan|light|blue':      '#0277bd'
	'cyan|light|':          '#00695c'
	'magenta|dark|purple':  '#9c27b0'
	'magenta|dark|pink':    '#e91e63'
	'magenta|dark|':        '#ab47bc'
	'magenta|light|purple': '#7b1fa2'
	'magenta|light|pink':   '#ad1457'
	'magenta|light|':       '#8e24aa'
	'purple|dark|purple':   '#9c27b0'
	'purple|dark|pink':     '#e91e63'
	'purple|dark|':         '#ab47bc'
	'purple|light|purple':  '#7b1fa2'
	'purple|light|pink':    '#ad1457'
	'purple|light|':        '#8e24aa'
	'orange|dark|orange':   '#ff9800'
	'orange|dark|red':      '#ff5722'
	'orange|dark|':         '#ffb74d'
	'orange|light|orange':  '#f57c00'
	'orange|light|red':     '#d84315'
	'orange|light|':        '#ef6c00'
	'pink|dark|pink':       '#e91e63'
	'pink|dark|purple':     '#9c27b0'
	'pink|dark|':           '#f06292'
	'pink|light|pink':      '#c2185b'
	'pink|light|purple':    '#7b1fa2'
	'pink|light|':          '#ad1457'
	'brown|dark|red':       '#8d6e63'
	'brown|dark|orange':    '#a1887f'
	'brown|dark|':          '#795548'
	'brown|light|red':      '#5d4037'
	'brown|light|orange':   '#6d4c41'
	'brown|light|':         '#4e342e'
}

// semantic_base returns the raw table color for concept|theme|dominant,
// with the per-concept wildcard and the #757575 default.
pub fn semantic_base(concept string, theme string, dominant string) string {
	if v := semantic_table[concept + '|' + theme + '|' + dominant] {
		return v
	}
	if v := semantic_table[concept + '|' + theme + '|'] {
		return v
	}
	return '#757575'
}

// valid_smart_concept mirrors the find_best_color_for_concept validation.
pub fn valid_smart_concept(concept string) bool {
	return concept in ['error', 'warning', 'success', 'info', 'accent', 'red', 'green', 'blue',
		'yellow', 'cyan', 'magenta', 'purple', 'orange', 'pink', 'brown', 'white', 'black', 'gray',
		'grey', 'background', 'background-alt', 'foreground', 'foreground-alt']
}

// smart_color_for resolves one concept against a palette map: neutrals
// and background/foreground variants read the palette directly, every
// other concept goes through base + contrast + 10% harmonization.
// Output is hex (the only format the file generators consume).
pub fn smart_color_for(concept string, pal map[string]string) !string {
	if !valid_smart_concept(concept) {
		return error('unknown concept: ${concept}')
	}
	match concept {
		'white' {
			return palette_get(pal, 'foreground', '#ffffff')
		}
		'black' {
			return palette_get(pal, 'background', '#000000')
		}
		'gray', 'grey' {
			return palette_get(pal, 'color8', '#808080')
		}
		'background' {
			return palette_get(pal, 'background', '#000000')
		}
		'background-alt' {
			return palette_get(pal, 'color1', '#1a1a1a')
		}
		'foreground' {
			bg := palette_get(pal, 'background', '#000000')
			return optimal_foreground(pal, is_light_hex(bg))
		}
		'foreground-alt' {
			return palette_get(pal, 'color5', '#888888')
		}
		else {}
	}
	bg := palette_get(pal, 'background', '#000000')
	light := is_light_hex(bg)
	theme := if light { 'light' } else { 'dark' }
	dominant := palette_dominant(pal)
	average := palette_average(pal)
	base := semantic_base(concept, theme, dominant)
	enhanced := enhance_contrast_for_theme(base, light)
	return blend_hex(enhanced, average, 10)
}

// normalize_scheme_type canonicalizes an M3 scheme-type name the way
// dots-color-scheme does (fruitsalad/rainbow are expressive aliases).
pub fn normalize_scheme_type(raw string) string {
	n := raw.to_lower().replace('_', '-').replace(' ', '')
	match n {
		'vibrant' { return 'vibrant' }
		'tonalspot', 'tonal-spot' { return 'tonal-spot' }
		'expressive', 'fruitsalad', 'rainbow' { return 'expressive' }
		'fidelity' { return 'fidelity' }
		'content' { return 'content' }
		'neutral' { return 'neutral' }
		'monochrome' { return 'monochrome' }
		else { return 'tonal-spot' }
	}
}

// normalize_variant canonicalizes a launcher variant name.
pub fn normalize_variant(raw string) string {
	n := raw.to_lower().replace('_', '-').replace(' ', '')
	match n {
		'tonal-spot', 'tonalspot' {
			return 'tonalspot'
		}
		'vibrant', 'expressive', 'fidelity', 'content', 'neutral', 'monochrome', 'fruitsalad',
		'rainbow' {
			return n
		}
		else {
			return 'tonalspot'
		}
	}
}

// variant_to_scheme_type maps a variant name to its M3 scheme type.
pub fn variant_to_scheme_type(variant string) string {
	v := normalize_variant(variant)
	match v {
		'tonalspot' { return 'tonal-spot' }
		'fruitsalad', 'rainbow' { return 'expressive' }
		else { return v }
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
// _dots_aa_resolve_gtk_color_scheme and the gtk-theme-manager meta read.
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

// derive_palette resolves every smart concept against a palette map,
// mirroring generate_smart_color_files (fallbacks included).
pub fn derive_palette(pal map[string]string, wallpaper string) SmartPalette {
	bg := palette_get(pal, 'background', '#000000')
	light := is_light_hex(bg)
	fg := optimal_foreground(pal, light)
	mut cursor := palette_get(pal, 'cursor', '')
	if cursor.len == 0 {
		cursor = fg
	}
	get := fn [pal] (concept string) string {
		return smart_color_for(concept, pal) or { '#757575' }
	}
	mut base := [16]string{}
	for i in 0 .. 16 {
		base[i] = palette_get(pal, 'color${i}', '#000000')
	}
	return SmartPalette{
		background:     bg
		foreground:     fg
		cursor:         cursor
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
		light:          light
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
	mut out := '# Environment variables for smart colors\n# Generated by horneroctl appearance colors generate\n'
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
	mut out := '# Mako notification colors\n# Generated by horneroctl appearance colors generate\n'
	out += '# Include this in your mako config or replace values manually\n\n'
	out += 'background-color=${p.background}\ntext-color=${p.foreground}\n'
	out += 'border-color=${p.accent}\nprogress-color=over ${p.base[8]}\n\n'
	out += '[urgency=low]\nborder-color=${p.info}\n\n[urgency=normal]\nborder-color=${p.accent}\n\n'
	out += '[urgency=critical]\nborder-color=${p.error}\ntext-color=${p.error}\n'
	return out
}

// render_hyprland renders colors-hyprland.conf.
pub fn render_hyprland(p SmartPalette) string {
	strip := fn (c string) string {
		return if c.starts_with('#') { c[1..] } else { c }
	}
	mut out := '# Hyprland colors configuration\n# Generated by horneroctl appearance colors generate\n'
	out += '# Source this in your hyprland.conf.d/colors.conf\n\ngeneral {\n'
	out += '    col.active_border = rgba(${strip(p.accent)}ee) rgba(${strip(p.info)}ee) 45deg\n'
	out += '    col.inactive_border = rgba(${strip(p.base[8])}aa)\n}\n\ngroup {\n'
	out += '    col.border_active = rgba(${strip(p.accent)}ee)\n'
	out += '    col.border_inactive = rgba(${strip(p.base[8])}aa)\n'
	out += '    col.border_locked_active = rgba(${strip(p.warning)}ee)\n'
	out += '    col.border_locked_inactive = rgba(${strip(p.base[8])}aa)\n'
	out += '\n    groupbar {\n'
	out += '        col.active = rgba(${strip(p.accent)}ee)\n'
	out += '        col.inactive = rgba(${strip(p.base[8])}aa)\n'
	out += '        col.locked_active = rgba(${strip(p.warning)}ee)\n'
	out += '        col.locked_inactive = rgba(${strip(p.base[8])}aa)\n'
	out += '    }\n}\n'
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
	mut out := '# Hyprlock colors configuration\n# Generated by horneroctl appearance colors generate\n'
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

// render_kitty renders colors-kitty.conf.
pub fn render_kitty(p SmartPalette) string {
	mut out := '# Kitty terminal colors\n# Generated by horneroctl appearance colors generate\n'
	out += '# Include this in kitty.conf: include ~/.cache/hornero/smart-colors/colors-kitty.conf\n\n# Base colors\n'
	out += 'background ${p.background}\nforeground ${p.foreground}\ncursor ${p.cursor}\n'
	out += 'selection_background ${p.accent}\nselection_foreground ${p.background}\n'
	names := ['Black', 'Red', 'Green', 'Yellow', 'Blue', 'Magenta', 'Cyan', 'White']
	los := [0, 1, 2, 3, 4, 5, 6, 7]
	his := [8, 9, 10, 11, 12, 13, 14, 15]
	for i, name in names {
		out += '\n# ${name}\ncolor${los[i]} ${p.base[los[i]]}\ncolor${his[i]} ${p.base[his[i]]}\n'
	}
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
	out += 'font="JetBrainsMono Nerd Font,10,-1,5,50,0,0,0,0,0"\n'
	out += 'edit_font="JetBrainsMono Nerd Font,11,-1,5,50,0,0,0,0,0"\n'
	out += 'find_font="JetBrainsMono Nerd Font,10,-1,5,50,0,0,0,0,0"\n'
	out += 'notes_font="JetBrainsMono Nerd Font,11,-1,5,50,0,0,0,0,0"\n'
	out += 'num_font="JetBrainsMono Nerd Font,7,-1,5,25,0,0,0,0,0"\nfont_antialiasing=true\n\n'
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
	out += '        stop: 0 \${sel_bg},\n        stop: 1 \${sel_bg} + #111\n        )"\n\n'
	out += '# Search bar styling\nsearch_bar="\n    ;background: \${edit_bg}\n    ;color: \${edit_fg}\n'
	out += '    ;border: 1px solid \${alt_bg}\n    ;margin: 2px\n    ;border-radius: 4px"\n\n'
	out += 'search_bar_focused="\n    ;border: 1px solid \${sel_bg}"\n\n'
	// pick returns the light or dark adjustment suffix.
	pick := fn [p] (light_adj string, dark_adj string) string {
		return if p.light { light_adj } else { dark_adj }
	}
	tab_adj := pick('- #1a1a1a', '+ #1a1a1a')
	out += '# Tab bar styling\ntab_bar_css="\n    ;background: \${bg} ${tab_adj}"\n\n'
	out += 'tab_bar_tab_selected_css="\n    ;padding: 0.5em\n    ;background: \${bg}\n'
	out += '    ;border: 0.05em solid \${bg}\n    ;color: \${fg}\n    ;border-bottom: 2px solid \${sel_bg}"\n\n'
	out += 'tab_bar_tab_unselected_css="\n    ;border: 0.05em solid \${bg}\n    ;padding: 0.5em\n'
	out += '    ;background: \${bg} ${tab_adj}\n'
	out += '    ;color: \${fg} ${pick('- #2a2a2a', '+ #2a2a2a')}"\n\n'
	out += 'tab_bar_item_counter="\n    ;color: \${num_fg} ${tab_adj}\n'
	out += '    ;font-size: 7pt"\n\ntab_bar_sel_item_counter="\n    ;color: \${num_fg}"\n\n'
	out += 'tab_bar_scroll_buttons_css="\n    ;background: \${bg} ${tab_adj}\n'
	out += '    ;color: \${fg}\n    ;border: 0"\n\n'
	out += 'tab_tree_css="\n    ;font-family: sans-serif\n    ;font-size: 10pt\n    ;padding: .20em\n'
	out += '    ;color: \${fg} ${pick('+ #1a1a1a', '- #1a1a1a')}\n'
	out += '    ;background-color: \${bg}"\n\n'
	out += 'tab_tree_sel_item_css="\n'
	out += '    ;color: \${fg} ${pick('+ #1a1a1a', '- #1a1a1a')}\n'
	out += '    ;background: \${bg} ${pick('- #0f0f0f', '+ #0f0f0f')}"\n\n'
	out += 'tab_tree_item_counter="\n    ;padding:.33em\n    ;color: \${num_fg} ${tab_adj}\n'
	out += '    ;font-size: 7pt"\n\ntab_tree_sel_item_counter="\n    ;color: \${num_fg}"\n\n'
	out += 'tool_bar_css="\n    ;color: \${fg}\n    ;background-color: \${bg}\n    ;border: 0"\n\n'
	out += 'tool_button_css="\n    ;background-color: transparent"\n\n'
	out += 'tool_button_selected_css="\n    ;background-color: \${bg} ${pick('- #0a0a0a',
		'+ #0a0a0a')}"\n\n'
	out += 'tool_button_pressed_css="\n    ;background-color: \${sel_bg}\n    ;color: \${sel_fg}"\n\n'
	out += 'menu_bar_css="\n    ;background: \${bg}\n'
	out += '    ;color: \${fg} ${pick('+ #2a2a2a', '- #2a2a2a')}"\n\n'
	out += 'menu_bar_disabled_css="\n'
	out += '    ;color: \${bg} ${pick('- #4a4a4a', '+ #4a4a4a')}"\n\n'
	out += 'menu_bar_selected_css="\n    ;background: \${sel_bg}\n    ;color: \${sel_fg}"\n\n'
	out += 'menu_css="\n'
	edge_a := pick('+ #2a2a2a', '- #2a2a2a')
	edge_b := pick('- #2a2a2a', '+ #2a2a2a')
	out += '    ;border-top: 0.08em solid \${bg} ${edge_a}\n'
	out += '    ;border-left: 0.08em solid \${bg} ${edge_a}\n'
	out += '    ;border-bottom: 0.08em solid \${bg} ${edge_b}\n'
	out += '    ;border-right: 0.08em solid \${bg} ${edge_b}"\n\n'
	out += 'css="\n    ClipboardBrowser::item{\n        border-bottom: 1px solid \${alt_bg}\n    }\n'
	out += '    ClipboardBrowser::item:hover{\n        background: \${bg} ${pick('- #0a0a0a',
		'+ #0a0a0a')}\n'
	out += '    }"\n\nnotes_css=\n'
	return out
}

// hyprlock_rgba converts #rrggbb + alpha into hyprlock's rrggbbaa form.
pub fn hyprlock_rgba(color string, alpha string) string {
	hex := if color.starts_with('#') { color[1..] } else { color }
	return hex + alpha
}

pub struct HyprlockScheme {
pub:
	primary            string
	surface            string
	on_surface         string
	background         string
	on_surface_variant string
	outline            string
	secondary          string
	error              string
	light              bool
	wallpaper          string
	scheme_source      string
}

// render_hyprlock_conf renders colors-hyprlock.conf from M3 scheme colors,
// mirroring dots-hyprlock-theme byte-for-byte in structure.
pub fn render_hyprlock_conf(s HyprlockScheme) string {
	def := fn (v string, fallback string) string {
		return if v.len > 0 { v } else { fallback }
	}
	bg := hyprlock_rgba(def(s.background, '191114'), 'ff')
	on_surface := hyprlock_rgba(def(s.on_surface, 'efdfe2'), 'ff')
	on_surface_variant := hyprlock_rgba(def(s.on_surface_variant, 'd5c2c6'), 'cc')
	outline := hyprlock_rgba(def(s.outline, '9e8c91'), '88')
	secondary := hyprlock_rgba(def(s.secondary, 'e2bdc7'), 'ff')
	input_inner := hyprlock_rgba(def(s.surface, '191114'), 'bb')
	err_col := def(s.error, 'ffb4ab')
	brightness := if s.light { '1.1' } else { '0.8' }
	wall_block := if s.wallpaper.len > 0 {
		'path = ${s.wallpaper}'
	} else {
		'color = 0xff${bg}'
	}
	on_surf := def(s.on_surface, 'efdfe2')
	prim := def(s.primary, 'ffb0ca')
	mut out := '# ============================================================================\n'
	out += '# hyprlock smart-color overrides\n# Auto-generated by horneroctl — do not edit manually.\n'
	out += '# Source: ${s.scheme_source}\n'
	out += '# ============================================================================\n\nbackground {\n    monitor =\n    ${wall_block}\n'
	out += '    blur_passes = 3\n    blur_size = 6\n    noise = 0.012\n    contrast = 0.9\n'
	out += '    brightness = ${brightness}\n    vibrancy = 0.15\n    vibrancy_darkness = 0.0\n}\n\n'
	out += 'input-field {\n    monitor =\n    size = 300, 60\n    outline_thickness = 2\n'
	out += '    dots_spacing = 0.35\n    dots_center = true\n    dots_rounding = -1\n'
	out += '    fade_on_empty = true\n'
	out += '    placeholder_text = <span foreground="##${on_surface_variant}">  Enter Password</span>\n'
	out += '    font_color = rgb(${on_surf})\n    inner_color = rgba(${input_inner})\n'
	out += '    outer_color = rgba(${outline})\n    check_color = rgb(${prim})\n'
	out += '    fail_color = rgba(${err_col}bb)\n'
	out += '    fail_text = <i>\$FAIL_REASON</i>\n    fail_timeout = 2000\n    rounding = 12\n'
	out += '    shadow_passes = 3\n    shadow_size = 8\n    shadow_color = rgba(00000060)\n}\n\n'
	out += 'label {\n    monitor =\n    text = \$TIME12\n    text_align = center\n'
	out += '    color = rgba(${on_surface})\n    font_size = 56\n    font_family = Rubik 300\n'
	out += '    position = 0, 160\n    halign = center\n    valign = center\n'
	out += '    shadow_passes = 3\n    shadow_size = 6\n    shadow_color = rgba(00000088)\n}\n\n'
	out += 'label {\n    monitor =\n    text =  \$USER\n    text_align = center\n'
	out += '    color = rgba(${secondary})\n    font_size = 13\n    font_family = Rubik\n'
	out += '    position = 0, -80\n    halign = center\n    valign = center\n}\n'
	return out
}
