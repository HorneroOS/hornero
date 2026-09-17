module hornero_core

import os
import x.json2

// Lockscreen effect images and hyprlock layout configs, native V port of
// `dots-lockscreen`. `lock update` rebuilds the cached effect PNGs from a
// wallpaper with ImageMagick; `lock now --effect=` picks one, infers the
// layout style, renders a temporary hyprlock config, and locks.
// Only ImageMagick and hyprlock stay external backends (HORNERO_MAGICK_BIN,
// HORNERO_HYPRLOCK_BIN overrides). --dry-run only previews.

// lockscreen_cache_dir is the canonical effect-image cache
// (docs/PATH_CONTRACT.md lockscreen row). Override with
// HORNERO_LOCKSCREEN_CACHE_DIR.
pub fn lockscreen_cache_dir() string {
	env := os.getenv('HORNERO_LOCKSCREEN_CACHE_DIR')
	if env.len > 0 {
		return env
	}
	mut base := os.getenv('XDG_CACHE_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.cache')
	}
	return os.join_path(base, 'hornero', 'lockscreen')
}

// lockscreen_cache_dir_fallback is the legacy `dots-lockscreen` location,
// kept as a read-only fallback (canonical-first).
fn lockscreen_cache_dir_fallback() string {
	mut base := os.getenv('XDG_CACHE_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.cache')
	}
	return os.join_path(base, 'dots-lockscreen')
}

// lockscreen_current_dir resolves the `current/` image directory:
// the canonical one when it holds images, else the legacy fallback,
// else the canonical path (callers create it on update).
fn lockscreen_current_dir() string {
	canon := os.join_path(lockscreen_cache_dir(), 'current')
	if lockscreen_dir_has_images(canon) {
		return canon
	}
	legacy := os.join_path(lockscreen_cache_dir_fallback(), 'current')
	if lockscreen_dir_has_images(legacy) {
		return legacy
	}
	return canon
}

fn lockscreen_dir_has_images(dir string) bool {
	for name in ['lock_resize.png', 'lock_dim.png', 'lock_blur.png', 'lock_dimblur.png',
		'lock_pixel.png'] {
		if os.is_file(os.join_path(dir, name)) {
			return true
		}
	}
	return false
}

// lock_has_images reports whether any cached effect image exists
// (canonical or legacy location).
fn lock_has_images() bool {
	imgs := lock_effect_images()
	return imgs.resize.len > 0 || imgs.dim.len > 0 || imgs.blur.len > 0 || imgs.dimblur.len > 0
		|| imgs.pixel.len > 0
}

// lock_effect_image resolves one cached effect image (canonical-first
// with legacy fallback). Returns '' when the image exists nowhere.
fn lock_effect_image(name string) string {
	canon := os.join_path(lockscreen_cache_dir(), 'current', name)
	if os.is_file(canon) {
		return canon
	}
	legacy := os.join_path(lockscreen_cache_dir_fallback(), 'current', name)
	if os.is_file(legacy) {
		return legacy
	}
	return ''
}

pub struct LockEffectImages {
pub:
	resize  string
	dim     string
	blur    string
	dimblur string
	pixel   string
}

// lock_effect_images resolves all five cached images ('' per missing one).
pub fn lock_effect_images() LockEffectImages {
	return LockEffectImages{
		resize:  lock_effect_image('lock_resize.png')
		dim:     lock_effect_image('lock_dim.png')
		blur:    lock_effect_image('lock_blur.png')
		dimblur: lock_effect_image('lock_dimblur.png')
		pixel:   lock_effect_image('lock_pixel.png')
	}
}

// lock_effect_valid reports whether name is a known lock effect.
pub fn lock_effect_valid(name string) bool {
	return name in ['dim', 'blur', 'dimblur', 'pixel']
}

// lock_image_for_effect picks the cached image for an effect, falling
// back to the base resized image exactly like dots-lockscreen.
pub fn lock_image_for_effect(imgs LockEffectImages, effect string) string {
	img := match effect {
		'dim' { imgs.dim }
		'blur' { imgs.blur }
		'dimblur' { imgs.dimblur }
		'pixel' { imgs.pixel }
		else { imgs.blur }
	}
	if img.len > 0 {
		return img
	}
	return imgs.resize
}

// lock_magick_bin resolves ImageMagick: an explicit HORNERO_MAGICK_BIN
// override wins (returned as-is so callers fail loudly), else `magick`,
// else legacy `convert`. Dry-run previews against the placeholder name.
fn lock_magick_bin(dry_run bool) !string {
	env := os.getenv('HORNERO_MAGICK_BIN')
	if env.len > 0 {
		return env
	}
	if find_on_path('magick').len > 0 {
		return 'magick'
	}
	if find_on_path('convert').len > 0 {
		return 'convert'
	}
	if dry_run {
		return 'magick'
	}
	return error('ImageMagick not found (magick or convert). Set HORNERO_MAGICK_BIN.\nExample: horneroctl lock update ~/wall.jpg --dry-run')
}

// sway_current_mode mirrors one swaymsg get_outputs[].current_mode.
pub struct SwayCurrentMode {
pub:
	width  int
	height int
}

pub struct SwayOutput {
pub:
	current_mode SwayCurrentMode
}

// lock_screen_resolution detects the output resolution for the base
// resize: explicit HORNERO_LOCKSCREEN_RESOLUTION wins (deterministic),
// then swaymsg on Wayland, then xrandr, then 1920x1080.
fn lock_screen_resolution() string {
	env := os.getenv('HORNERO_LOCKSCREEN_RESOLUTION')
	if env.len > 0 {
		return env
	}
	if os.getenv('WAYLAND_DISPLAY').len > 0 && find_on_path('swaymsg').len > 0 {
		out := run_exec(ExecSpec{
			prog: 'swaymsg'
			args: ['-t', 'get_outputs']
		})
		if out.ok {
			outs := json2.decode[[]SwayOutput](out.output) or { []SwayOutput{} }
			if outs.len > 0 && outs[0].current_mode.width > 0 && outs[0].current_mode.height > 0 {
				return '${outs[0].current_mode.width}x${outs[0].current_mode.height}'
			}
			mut w := ''
			for line in out.output.split_into_lines() {
				if line.contains('"width"') {
					w = line.all_after('"width":').all_before(',').trim_space()
					continue
				}
				if w.len > 0 && line.contains('"height"') {
					h := line.all_after('"height":').all_before(',').trim_space()
					if h.len > 0 {
						return '${w}x${h}'
					}
				}
			}
		}
	}
	if find_on_path('xrandr').len > 0 {
		out := run_exec(ExecSpec{
			prog: 'xrandr'
			args: ['--current']
		})
		if out.ok {
			for line in out.output.split_into_lines() {
				if line.contains('*') {
					fields := line.fields()
					if fields.len > 0 && fields[0].contains('x') {
						return fields[0]
					}
				}
			}
		}
	}
	return '1920x1080'
}

pub struct LockUpdateOptions {
pub:
	wallpaper string // explicit path; '' resolves the current pointer
	dim       int    // 0-100
	blur      int    // >= 0
	pixel     int    // >= 1
	dry_run   bool
	yes       bool
}

// lock_update_report implements `lock update` (mutating): rebuilds the
// five cached effect PNGs from a wallpaper. Needs --yes; --dry-run
// only previews the exact magick command lines.
pub fn lock_update_report(opts LockUpdateOptions) CommandResult {
	if !opts.yes && !opts.dry_run {
		return fail_result('lock update', 'refusing to update without --yes (preview with --dry-run).\nExample: horneroctl lock update --dry-run')
	}
	wallpaper := current_wallpaper(opts.wallpaper)
	if wallpaper.len == 0 {
		if opts.wallpaper.len > 0 {
			return fail_result('lock update', 'wallpaper file not found: ${opts.wallpaper}')
		}
		return fail_result('lock update', 'no current wallpaper found.\nExample: horneroctl lock update ~/wall.jpg --dry-run')
	}
	magick := lock_magick_bin(opts.dry_run) or { return fail_result('lock update', err.msg()) }
	dir := os.join_path(lockscreen_cache_dir(), 'current')
	if !opts.dry_run {
		os.mkdir_all(dir) or {
			return fail_result('lock update', 'cannot create ${dir}: ${err.msg()}')
		}
	}
	res := lock_screen_resolution()
	resize := os.join_path(dir, 'lock_resize.png')
	dim := os.join_path(dir, 'lock_dim.png')
	blur := os.join_path(dir, 'lock_blur.png')
	dimblur := os.join_path(dir, 'lock_dimblur.png')
	pixel := os.join_path(dir, 'lock_pixel.png')
	steps := [
		[wallpaper, '-resize', '${res}^', '-gravity', 'center', '-extent', res, resize],
		[resize, '-fill', 'black', '-colorize', '${opts.dim}%', dim],
		[resize, '-blur', '0x${opts.blur}', blur],
		[resize, '-fill', 'black', '-colorize', '${opts.dim}%', '-blur', '0x${opts.blur}', dimblur],
	]
	mut lines := []string{}
	for args in steps {
		rep := strict_exec(magick, args, opts.dry_run)
		if opts.dry_run {
			lines << 'would run: ${rep.command_line}'
			continue
		}
		if !rep.ok {
			return fail_result('lock update', 'magick failed (exit ${rep.exit_code}):\n${rep.output}')
		}
	}
	// Pixelate needs the base dimensions first.
	if opts.dry_run {
		rep := strict_exec(magick, [resize, '-scale', '<w/s>x<h/s>', '-scale', '<wxh>', pixel],
			true)
		lines << 'would run: ${rep.command_line}'
		return ok_result('lock update', lines.join('\n'), {
			'command_line': lines.join('; ')
			'dry_run':      'true'
			'dir':          dir
		})
	}
	dims := strict_exec(magick, ['-format', '%w %h', resize, 'info:'], false)
	if !dims.ok {
		return fail_result('lock update', 'magick failed (exit ${dims.exit_code}):\n${dims.output}')
	}
	parts := dims.output.fields()
	if parts.len != 2 {
		return fail_result('lock update', 'cannot read dimensions of ${resize}: `${dims.output}`')
	}
	w := parts[0].int()
	h := parts[1].int()
	if w <= 0 || h <= 0 {
		return fail_result('lock update', 'cannot read dimensions of ${resize}: `${dims.output}`')
	}
	nw := w / opts.pixel
	nh := h / opts.pixel
	if nw <= 0 || nh <= 0 {
		return fail_result('lock update', 'pixel scale ${opts.pixel} too large for ${w}x${h}')
	}
	rep := strict_exec(magick, [resize, '-scale', '${nw}x${nh}', '-scale', '${w}x${h}', pixel],
		false)
	if !rep.ok {
		return fail_result('lock update', 'magick failed (exit ${rep.exit_code}):\n${rep.output}')
	}
	return ok_result('lock update', 'lockscreen images updated in ${dir}', {
		'dir': dir
	})
}

// lock_layout_style infers the hyprlock layout from a wallpaper path,
// mirroring dots-lockscreen: path-folder patterns first, then the
// theme.json tags of the pack the path maps to. Empty path → default.
pub fn lock_layout_style(wallpaper_path string) string {
	if wallpaper_path.len == 0 {
		return 'default'
	}
	lower := wallpaper_path.to_lower()
	mut style := 'default'
	if lower.contains('neon-city') || lower.contains('vapor-dreams') {
		style = 'vaporwave'
	} else if lower.contains('soft-morning') || lower.contains('catppuccin-latte') {
		style = 'cozy'
	} else if lower.contains('monochrome') {
		style = 'minimal'
	} else if lower.contains('gruvbox') {
		style = 'default'
	}
	pack := os.base(os.dir(wallpaper_path))
	if pack.len > 0 {
		tags := lock_pack_tags(pack)
		if tags.len > 0 {
			style = tags
		}
	}
	return lock_layout_config(style)
}

// lock_pack_tags reads the `tags` array of an installed theme pack
// (canonical-first lookup, same order as show_theme_pack).
fn lock_pack_tags(pack string) string {
	for dir in resolve_themes_dirs_for_read() {
		raw := os.read_file(os.join_path(dir, pack, 'theme.json')) or { continue }
		parsed := json2.decode[json2.Any](raw) or { continue }
		if parsed is map[string]json2.Any {
			if tags := parsed['tags'] {
				if tags is []json2.Any {
					mut out := []string{}
					for t in tags {
						out << t.str()
					}
					return out.join(' ')
				}
			}
		}
	}
	return ''
}

// lock_layout_config maps aesthetic keywords to one layout name,
// mirroring dots-lockscreen get_layout_config.
pub fn lock_layout_config(style string) string {
	lower := style.to_lower()
	if lower.contains('cyberpunk') || lower.contains('neon') || lower.contains('synthwave') {
		return 'cyberpunk'
	}
	if lower.contains('cozy') || lower.contains('kawaii') || lower.contains('pastel')
		|| lower.contains('soft') {
		return 'cozy'
	}
	if lower.contains('vaporwave') || lower.contains('retro') || lower.contains('80s')
		|| lower.contains('90s') {
		return 'vaporwave'
	}
	if lower.contains('minimal') || lower.contains('clean') {
		return 'minimal'
	}
	return 'default'
}

pub struct LockColors {
pub:
	bg      string // hex without leading `#`
	fg      string
	primary string
	error   string
}

// lock_colors resolves the lock palette: the native scheme.json colours
// first, then the legacy dots current.env, then the dots-lockscreen
// hardcoded fallbacks. Never fails.
pub fn lock_colors() LockColors {
	mut bg := lock_scheme_colour('background')
	mut fg := lock_scheme_colour('onBackground')
	mut primary := lock_scheme_colour('primary')
	mut error := lock_scheme_colour('error')
	if bg.len == 0 || fg.len == 0 || primary.len == 0 || error.len == 0 {
		legacy := lock_legacy_env()
		if bg.len == 0 {
			bg = lock_env_colour(legacy, 'SMART_BG')
		}
		if fg.len == 0 {
			fg = lock_env_colour(legacy, 'SMART_FG')
		}
		if primary.len == 0 {
			primary = lock_env_colour(legacy, 'SMART_PRIMARY')
		}
		if error.len == 0 {
			error = lock_env_colour(legacy, 'SMART_ERROR')
		}
	}
	if bg.len == 0 {
		bg = '1e1e1e'
	}
	if fg.len == 0 {
		fg = 'ffffff'
	}
	if primary.len == 0 {
		primary = '6495ed'
	}
	if error.len == 0 {
		error = 'ff6b6b'
	}
	return LockColors{
		bg:      lock_hex(bg)
		fg:      lock_hex(fg)
		primary: lock_hex(primary)
		error:   lock_hex(error)
	}
}

fn lock_hex(raw string) string {
	mut c := raw.trim_space()
	if c.starts_with('#') {
		c = c[1..]
	}
	return c
}

// lock_scheme_colour reads one M3 colour from the native scheme.json
// (canonical-first with legacy fallback).
fn lock_scheme_colour(key string) string {
	scheme := color_scheme_file_for_read()
	raw := os.read_file(scheme) or { return '' }
	parsed := json2.decode[json2.Any](raw) or { return '' }
	if parsed is map[string]json2.Any {
		if colours := parsed['colours'] {
			if colours is map[string]json2.Any {
				if v := colours[key] {
					return v.str()
				}
			}
		}
	}
	return ''
}

// lock_legacy_env loads the legacy dots smart-colors current.env
// (`KEY=value` lines, optional quoting) into a map.
fn lock_legacy_env() map[string]string {
	mut out := map[string]string{}
	mut base := os.getenv('XDG_CACHE_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.cache')
	}
	raw := os.read_file(os.join_path(base, 'dots', 'smart-colors', 'current.env')) or { return out }
	for line in raw.split_into_lines() {
		t := line.trim_space()
		if t.len == 0 || t.starts_with('#') || !t.contains('=') {
			continue
		}
		k := t.all_before('=').trim_space()
		mut v := t.all_after('=').trim_space()
		if v.len >= 2 && ((v.starts_with('"') && v.ends_with('"'))
			|| (v.starts_with("'") && v.ends_with("'"))) {
			v = v[1..v.len - 1]
		}
		out[k] = v
	}
	return out
}

fn lock_env_colour(env map[string]string, key string) string {
	return env[key] or { '' }
}

// render_hyprlock_config renders one temporary hyprlock config for a
// layout, image, and palette. Literal `$` (hyprlock runtime vars) is
// built with '$' chunks: no backslash-dollar escapes anywhere, so both
// supported V compilers emit them verbatim.
pub fn render_hyprlock_config(layout string, image string, c LockColors) string {
	return match layout {
		'cyberpunk' { render_lock_cyberpunk(image) }
		'cozy' { render_lock_cozy(image) }
		'vaporwave' { render_lock_vaporwave(image) }
		'minimal' { render_lock_minimal(image, c) }
		else { render_lock_default(image, c) }
	}
}

fn render_lock_cyberpunk(image string) string {
	mut lines := []string{}
	lines << '# Generated by horneroctl lock - Cyberpunk Layout'
	lines << 'background {'
	lines << '  monitor ='
	lines << '  path = ' + image
	lines << '  blur_passes = 4'
	lines << '  blur_size = 8'
	lines << '  contrast = 1.1'
	lines << '  brightness = 0.6'
	lines << '  vibrancy = 0.3'
	lines << '  vibrancy_darkness = 0.2'
	lines << '}'
	lines << ''
	lines << 'input-field {'
	lines << '  monitor ='
	lines << '  size = 350, 55'
	lines << '  outline_thickness = 3'
	lines << '  dots_size = 0.25'
	lines << '  dots_spacing = 0.4'
	lines << '  dots_center = true'
	lines << '  dots_rounding = 2'
	lines << '  outer_color = rgba(ff00ffff)'
	lines << '  inner_color = rgba(0a0a0fcc)'
	lines << '  font_color = rgba(00ffffff)'
	lines << '  fade_on_empty = true'
	lines << '  fade_timeout = 500'
	lines << '  placeholder_text = <i>// ENTER ACCESS CODE...</i>'
	lines << '  hide_input = false'
	lines << '  rounding = 5'
	lines << '  check_color = rgba(00ffffff)'
	lines << '  fail_color = rgba(ff0064ff)'
	lines << '  fail_text = <i>ACCESS DENIED [' + '$' + 'ATTEMPTS]</i>'
	lines << '  fail_transition = 200'
	lines << '  position = 0, -100'
	lines << '  halign = center'
	lines << '  valign = center'
	lines << '}'
	lines << ''
	lines << 'label {'
	lines << '  monitor ='
	lines << '  text = cmd[update:1000] echo "' + '$' + '(date +\'%H:%M:%S\')"'
	lines << '  color = rgba(00ffffff)'
	lines << '  font_size = 90'
	lines << '  font_family = JetBrainsMono Nerd Font'
	lines << '  text_align = center'
	lines << '  position = 0, 180'
	lines << '  halign = center'
	lines << '  valign = center'
	lines << '  shadow_passes = 3'
	lines << '  shadow_size = 10'
	lines << '  shadow_color = rgba(00ffff66)'
	lines << '}'
	lines << ''
	lines << 'label {'
	lines << '  monitor ='
	lines << '  text = ▌SYSTEM LOCKED▐'
	lines << '  color = rgba(ff00ffdd)'
	lines << '  font_size = 14'
	lines << '  font_family = JetBrainsMono Nerd Font'
	lines << '  position = 0, 100'
	lines << '  halign = center'
	lines << '  valign = center'
	lines << '}'
	lines << ''
	lines << 'label {'
	lines << '  monitor ='
	lines << '  text = cmd[update:1000] echo "' + '$' + '(date +\'%Y.%m.%d\')"'
	lines << '  color = rgba(9d00ffdd)'
	lines << '  font_size = 16'
	lines << '  font_family = JetBrainsMono Nerd Font'
	lines << '  position = 0, 70'
	lines << '  halign = center'
	lines << '  valign = center'
	lines << '}'
	lines << ''
	lines << 'label {'
	lines << '  monitor ='
	lines << '  text = 󰯄 ' + '$' + 'USER'
	lines << '  color = rgba(ff00ffcc)'
	lines << '  font_size = 18'
	lines << '  font_family = JetBrainsMono Nerd Font'
	lines << '  position = 0, -170'
	lines << '  halign = center'
	lines << '  valign = center'
	lines << '}'
	return lines.join('\n') + '\n'
}

fn render_lock_cozy(image string) string {
	mut lines := []string{}
	lines << '# Generated by horneroctl lock - Cozy Layout'
	lines << 'background {'
	lines << '  monitor ='
	lines << '  path = ' + image
	lines << '  blur_passes = 2'
	lines << '  blur_size = 5'
	lines << '  contrast = 0.95'
	lines << '  brightness = 0.9'
	lines << '  vibrancy = 0.1'
	lines << '  vibrancy_darkness = 0.0'
	lines << '}'
	lines << ''
	lines << 'input-field {'
	lines << '  monitor ='
	lines << '  size = 280, 50'
	lines << '  outline_thickness = 2'
	lines << '  dots_size = 0.35'
	lines << '  dots_spacing = 0.35'
	lines << '  dots_center = true'
	lines << '  dots_rounding = -1'
	lines << '  outer_color = rgba(f5c2e7aa)'
	lines << '  inner_color = rgba(1e1e2ecc)'
	lines << '  font_color = rgba(f5e0dcff)'
	lines << '  fade_on_empty = true'
	lines << '  fade_timeout = 2000'
	lines << '  placeholder_text = <i>password...</i>'
	lines << '  hide_input = false'
	lines << '  rounding = 16'
	lines << '  check_color = rgba(a6e3a1ff)'
	lines << '  fail_color = rgba(f38ba8ff)'
	lines << '  fail_text = <i>oops! try again~</i>'
	lines << '  fail_transition = 500'
	lines << '  position = 0, -100'
	lines << '  halign = center'
	lines << '  valign = center'
	lines << '}'
	lines << ''
	lines << 'label {'
	lines << '  monitor ='
	lines << '  text = cmd[update:1000] echo "' + '$' + '(date +\'%-I:%M %p\')"'
	lines << '  color = rgba(f5e0dcff)'
	lines << '  font_size = 70'
	lines << '  font_family = Quicksand'
	lines << '  position = 0, 160'
	lines << '  halign = center'
	lines << '  valign = center'
	lines << '}'
	lines << ''
	lines << 'label {'
	lines << '  monitor ='
	lines << '  text = cmd[update:1000] echo "' + '$' + '(date +\'%A\')"'
	lines << '  color = rgba(cba6f7dd)'
	lines << '  font_size = 22'
	lines << '  font_family = Quicksand'
	lines << '  position = 0, 90'
	lines << '  halign = center'
	lines << '  valign = center'
	lines << '}'
	lines << ''
	lines << 'label {'
	lines << '  monitor ='
	lines << '  text = cmd[update:1000] echo "' + '$' + '(date +\'%B %d, %Y\')"'
	lines << '  color = rgba(f5c2e7cc)'
	lines << '  font_size = 16'
	lines << '  font_family = Quicksand'
	lines << '  position = 0, 60'
	lines << '  halign = center'
	lines << '  valign = center'
	lines << '}'
	lines << ''
	lines << 'label {'
	lines << '  monitor ='
	lines << '  text = 🌸 ' + '$' + 'USER'
	lines << '  color = rgba(f5c2e7dd)'
	lines << '  font_size = 16'
	lines << '  font_family = Quicksand'
	lines << '  position = 0, -165'
	lines << '  halign = center'
	lines << '  valign = center'
	lines << '}'
	return lines.join('\n') + '\n'
}

fn render_lock_vaporwave(image string) string {
	mut lines := []string{}
	lines << '# Generated by horneroctl lock - Vaporwave Layout'
	lines << 'background {'
	lines << '  monitor ='
	lines << '  path = ' + image
	lines << '  blur_passes = 2'
	lines << '  blur_size = 6'
	lines << '  contrast = 1.0'
	lines << '  brightness = 0.75'
	lines << '  vibrancy = 0.25'
	lines << '  vibrancy_darkness = 0.1'
	lines << '}'
	lines << ''
	lines << 'input-field {'
	lines << '  monitor ='
	lines << '  size = 320, 50'
	lines << '  outline_thickness = 2'
	lines << '  dots_size = 0.3'
	lines << '  dots_spacing = 0.35'
	lines << '  dots_center = true'
	lines << '  dots_rounding = 0'
	lines << '  outer_color = rgba(ff71ceff)'
	lines << '  inner_color = rgba(1a0a2ecc)'
	lines << '  font_color = rgba(01cdfeff)'
	lines << '  fade_on_empty = true'
	lines << '  fade_timeout = 1000'
	lines << '  placeholder_text = <i>▌PASSWORD▐</i>'
	lines << '  hide_input = false'
	lines << '  rounding = 0'
	lines << '  check_color = rgba(05ffa1ff)'
	lines << '  fail_color = rgba(ff71ceff)'
	lines << '  fail_text = <i>▌ERROR▐</i>'
	lines << '  fail_transition = 300'
	lines << '  position = 0, -100'
	lines << '  halign = center'
	lines << '  valign = center'
	lines << '}'
	lines << ''
	lines << 'label {'
	lines << '  monitor ='
	lines << '  text = cmd[update:1000] echo "' + '$' + '(date +\'%H:%M:%S\')"'
	lines << '  color = rgba(01cdfeff)'
	lines << '  font_size = 75'
	lines << '  font_family = VCR OSD Mono'
	lines << '  position = 0, 170'
	lines << '  halign = center'
	lines << '  valign = center'
	lines << '}'
	lines << ''
	lines << 'label {'
	lines << '  monitor ='
	lines << '  text = ＶＡＰＯＲｗａｖｅ'
	lines << '  color = rgba(ff71cedd)'
	lines << '  font_size = 20'
	lines << '  font_family = VCR OSD Mono'
	lines << '  position = 0, 95'
	lines << '  halign = center'
	lines << '  valign = center'
	lines << '}'
	lines << ''
	lines << 'label {'
	lines << '  monitor ='
	lines << '  text = cmd[update:1000] echo "' + '$' + '(date +\'%m / %d / %y\')"'
	lines << '  color = rgba(b967ffcc)'
	lines << '  font_size = 16'
	lines << '  font_family = VCR OSD Mono'
	lines << '  position = 0, 65'
	lines << '  halign = center'
	lines << '  valign = center'
	lines << '}'
	lines << ''
	lines << 'label {'
	lines << '  monitor ='
	lines << '  text = 🌴 ' + '$' + 'USER 🌴'
	lines << '  color = rgba(05ffa1cc)'
	lines << '  font_size = 16'
	lines << '  font_family = VCR OSD Mono'
	lines << '  position = 0, -165'
	lines << '  halign = center'
	lines << '  valign = center'
	lines << '}'
	return lines.join('\n') + '\n'
}

fn render_lock_minimal(image string, c LockColors) string {
	mut lines := []string{}
	lines << '# Generated by horneroctl lock - Minimal Layout'
	lines << 'background {'
	lines << '  monitor ='
	lines << '  path = ' + image
	lines << '  blur_passes = 3'
	lines << '  blur_size = 8'
	lines << '  contrast = 0.9'
	lines << '  brightness = 0.85'
	lines << '  vibrancy = 0.0'
	lines << '  vibrancy_darkness = 0.0'
	lines << '}'
	lines << ''
	lines << 'input-field {'
	lines << '  monitor ='
	lines << '  size = 250, 45'
	lines << '  outline_thickness = 1'
	lines << '  dots_size = 0.3'
	lines << '  dots_spacing = 0.3'
	lines << '  dots_center = true'
	lines << '  dots_rounding = -1'
	lines << '  outer_color = rgba(' + c.primary + '88)'
	lines << '  inner_color = rgba(' + c.bg + 'cc)'
	lines << '  font_color = rgba(' + c.fg + 'ff)'
	lines << '  fade_on_empty = true'
	lines << '  fade_timeout = 1500'
	lines << '  placeholder_text ='
	lines << '  hide_input = false'
	lines << '  rounding = 8'
	lines << '  check_color = rgba(' + c.primary + 'ff)'
	lines << '  fail_color = rgba(' + c.error + 'ff)'
	lines << '  fail_text ='
	lines << '  fail_transition = 200'
	lines << '  position = 0, 0'
	lines << '  halign = center'
	lines << '  valign = center'
	lines << '}'
	lines << ''
	lines << 'label {'
	lines << '  monitor ='
	lines << '  text = cmd[update:1000] echo "' + '$' + '(date +\'%H:%M\')"'
	lines << '  color = rgba(' + c.fg + 'ff)'
	lines << '  font_size = 64'
	lines << '  font_family = SF Pro Display'
	lines << '  position = 0, 150'
	lines << '  halign = center'
	lines << '  valign = center'
	lines << '}'
	lines << ''
	lines << 'label {'
	lines << '  monitor ='
	lines << '  text = cmd[update:1000] echo "' + '$' + '(date +\'%a, %b %d\')"'
	lines << '  color = rgba(' + c.fg + 'aa)'
	lines << '  font_size = 16'
	lines << '  font_family = SF Pro Display'
	lines << '  position = 0, 90'
	lines << '  halign = center'
	lines << '  valign = center'
	lines << '}'
	return lines.join('\n') + '\n'
}

fn render_lock_default(image string, c LockColors) string {
	mut lines := []string{}
	lines << '# Generated by horneroctl lock - Default Layout'
	lines << 'background {'
	lines << '  monitor ='
	lines << '  path = ' + image
	lines << '  blur_passes = 3'
	lines << '  blur_size = 7'
	lines << '  contrast = 0.8916'
	lines << '  brightness = 0.8172'
	lines << '  vibrancy = 0.1696'
	lines << '  vibrancy_darkness = 0.0'
	lines << '}'
	lines << ''
	lines << 'input-field {'
	lines << '  monitor ='
	lines << '  size = 300, 60'
	lines << '  outline_thickness = 2'
	lines << '  dots_size = 0.33'
	lines << '  dots_spacing = 0.3'
	lines << '  dots_center = true'
	lines << '  dots_rounding = -1'
	lines << '  outer_color = rgba(' + c.primary + 'ff)'
	lines << '  inner_color = rgba(' + c.bg + 'cc)'
	lines << '  font_color = rgba(' + c.fg + 'ff)'
	lines << '  fade_on_empty = true'
	lines << '  fade_timeout = 1000'
	lines << '  placeholder_text = <i>Enter Password...</i>'
	lines << '  hide_input = false'
	lines << '  rounding = -1'
	lines << '  check_color = rgba(' + c.primary + 'ff)'
	lines << '  fail_color = rgba(' + c.error + 'ff)'
	lines << '  fail_text = <i>' + '$' + 'FAIL <b>(' + '$' + 'ATTEMPTS)</b></i>'
	lines << '  fail_transition = 300'
	lines << '  capslock_color = -1'
	lines << '  numlock_color = -1'
	lines << '  bothlock_color = -1'
	lines << '  invert_numlock = false'
	lines << '  swap_font_color = false'
	lines << '  position = 0, -120'
	lines << '  halign = center'
	lines << '  valign = center'
	lines << '}'
	lines << ''
	lines << 'label {'
	lines << '  monitor ='
	lines << '  text = cmd[update:1000] echo "' + '$' + '(date +\'%H:%M\')"'
	lines << '  color = rgba(' + c.fg + 'ff)'
	lines << '  font_size = 80'
	lines << '  font_family = JetBrainsMono Nerd Font'
	lines << '  position = 0, 150'
	lines << '  halign = center'
	lines << '  valign = center'
	lines << '}'
	lines << ''
	lines << 'label {'
	lines << '  monitor ='
	lines << '  text = cmd[update:1000] echo "' + '$' + '(date +\'%A, %d %B %Y\')"'
	lines << '  color = rgba(' + c.fg + 'dd)'
	lines << '  font_size = 18'
	lines << '  font_family = JetBrainsMono Nerd Font'
	lines << '  position = 0, 80'
	lines << '  halign = center'
	lines << '  valign = center'
	lines << '}'
	lines << ''
	lines << 'label {'
	lines << '  monitor ='
	lines << '  text = 󰌾 ' + '$' + 'USER'
	lines << '  color = rgba(' + c.fg + 'dd)'
	lines << '  font_size = 16'
	lines << '  font_family = JetBrainsMono Nerd Font'
	lines << '  position = 0, -180'
	lines << '  halign = center'
	lines << '  valign = center'
	lines << '}'
	return lines.join('\n') + '\n'
}

pub struct LockNowNativeOptions {
pub:
	effect  string // dim | blur | dimblur | pixel; '' means blur
	dry_run bool
}

// lock_now_native_report implements the native `lock now` flow: pick the
// cached effect image, infer the layout, render a temporary hyprlock
// config, and lock with it. Mutating: --yes is enforced by the
// lock_now_report caller; --dry-run previews.
pub fn lock_now_native_report(opts LockNowNativeOptions) CommandResult {
	effect := if opts.effect.len > 0 { opts.effect } else { 'blur' }
	if !lock_effect_valid(effect) {
		return fail_result('lock now', 'unknown effect: ${effect} (want dim, blur, dimblur, or pixel).\nExample: horneroctl lock now --effect blur --dry-run')
	}
	hl := lock_hyprlock_bin(opts.dry_run) or { return fail_result('lock now', err.msg()) }
	imgs := lock_effect_images()
	img := lock_image_for_effect(imgs, effect)
	if img.len == 0 {
		return fail_result('lock now', 'no lockscreen image available. Run:\nhorneroctl lock update --dry-run')
	}
	layout := lock_layout_style(current_wallpaper(''))
	colors := lock_colors()
	config := render_hyprlock_config(layout, img, colors)
	if opts.dry_run {
		rep := strict_exec(hl, ['--config', '<temp hyprlock.conf>'], true)
		lines := ['would run: ${rep.command_line}', 'image: ${img}', 'layout: ${layout}',
			'colors: bg=${colors.bg} fg=${colors.fg} primary=${colors.primary} error=${colors.error}']
		return ok_result('lock now', lines.join('\n'), {
			'command_line': rep.command_line
			'dry_run':      'true'
			'image':        img
			'layout':       layout
		})
	}
	tmp := os.join_path(os.temp_dir(), 'hornero-lock-${os.getpid()}.conf')
	os.write_file(tmp, config) or {
		return fail_result('lock now', 'cannot write ${tmp}: ${err.msg()}')
	}
	rep := strict_exec(hl, ['--config', tmp], false)
	os.rm(tmp) or {}
	if !rep.ok {
		return fail_result('lock now', 'hyprlock failed (exit ${rep.exit_code}):\n${rep.output}')
	}
	return ok_result('lock now', 'locked (effect=${effect}, layout=${layout}).', {
		'command_line': rep.command_line
		'image':        img
		'layout':       layout
	})
}

// lock_hyprlock_bin resolves hyprlock: an explicit HORNERO_HYPRLOCK_BIN
// override wins (returned as-is so callers fail loudly), else PATH.
// Dry-run previews against the placeholder name.
fn lock_hyprlock_bin(dry_run bool) !string {
	env := os.getenv('HORNERO_HYPRLOCK_BIN')
	if env.len > 0 {
		return env
	}
	if find_on_path('hyprlock').len > 0 {
		return 'hyprlock'
	}
	if dry_run {
		return 'hyprlock'
	}
	return error('hyprlock not found on PATH. Set HORNERO_HYPRLOCK_BIN.\nExample: horneroctl lock now --dry-run')
}
