module hornero_core

import os

const lock_troot = '/tmp/hx-lock-test'

fn lock_tsetup() {
	os.rmdir_all(lock_troot) or {}
	os.mkdir_all('${lock_troot}/cache') or { assert false }
	os.mkdir_all('${lock_troot}/state') or { assert false }
	os.mkdir_all('${lock_troot}/data') or { assert false }
	os.mkdir_all('${lock_troot}/themes/pampa') or { assert false }
	os.mkdir_all('${lock_troot}/bin') or { assert false }
	os.write_file('${lock_troot}/wall.png', 'fake-png-bytes') or { assert false }
	os.write_file('${lock_troot}/themes/pampa/theme.json', '{"schemaVersion":1,"id":"pampa","name":"Pampa","defaultWallpaper":"pampa-01.png","wallpaperDir":"pampa","mode":"dark","tags":["vaporwave","retro"]}') or {
		assert false
	}
	magick := '#!/bin/sh\nlog="\$HORNERO_LOCK_FIXLOG"\nif [ -z "\$log" ]; then log=/dev/null; fi\necho "\$@" >> "\$log"\nif [ "\$1" = "-format" ]; then echo "800 600"; exit 0; fi\nout=""\nfor a in "\$@"; do out="\$a"; done\ncp "\$1" "\$out"\n'
	os.write_file('${lock_troot}/bin/magick', magick) or { assert false }
	os.write_file('${lock_troot}/bin/hyprlock', '#!/bin/sh\necho "hyprlock \$*"\nexit 0\n') or {
		assert false
	}
	os.chmod('${lock_troot}/bin/magick', 0o755) or { assert false }
	os.chmod('${lock_troot}/bin/hyprlock', 0o755) or { assert false }
	os.setenv('XDG_CACHE_HOME', '${lock_troot}/cache', true)
	os.setenv('XDG_STATE_HOME', '${lock_troot}/state', true)
	os.setenv('XDG_DATA_HOME', '${lock_troot}/data', true)
	os.setenv('HORNERO_MAGICK_BIN', '${lock_troot}/bin/magick', true)
	os.setenv('HORNERO_HYPRLOCK_BIN', '${lock_troot}/bin/hyprlock', true)
	os.setenv('HORNERO_LOCKSCREEN_RESOLUTION', '800x600', true)
	os.setenv('HORNERO_THEMES_DIR', '${lock_troot}/themes', true)
	os.setenv('HORNERO_LOCK_FIXLOG', '${lock_troot}/magick.log', true)
	os.unsetenv('HORNERO_LOCKSCREEN_BIN')
	os.unsetenv('HORNERO_LOCKSCREEN_CACHE_DIR')
}

fn lock_tteardown() {
	os.unsetenv('XDG_CACHE_HOME')
	os.unsetenv('XDG_STATE_HOME')
	os.unsetenv('XDG_DATA_HOME')
	os.unsetenv('HORNERO_MAGICK_BIN')
	os.unsetenv('HORNERO_HYPRLOCK_BIN')
	os.unsetenv('HORNERO_LOCKSCREEN_RESOLUTION')
	os.unsetenv('HORNERO_THEMES_DIR')
	os.unsetenv('HORNERO_LOCK_FIXLOG')
	os.rmdir_all(lock_troot) or {}
}

fn lock_live_images() {
	r := lock_update_report(LockUpdateOptions{
		wallpaper: '${lock_troot}/wall.png'
		dim:       40
		blur:      5
		pixel:     10
		yes:       true
	})
	assert r.ok
}

fn test_lock_update_dry_run_previews() {
	lock_tsetup()
	r := lock_update_report(LockUpdateOptions{
		wallpaper: '${lock_troot}/wall.png'
		dim:       40
		blur:      5
		pixel:     10
		dry_run:   true
	})
	assert r.ok
	assert r.command == 'lock update'
	assert r.data['dry_run'] == 'true'
	assert r.message.contains('800x600')
	assert r.message.contains('lock_resize.png')
	assert !os.is_dir('${lock_troot}/cache/hornero/lockscreen/current')
	lock_tteardown()
}

fn test_lock_update_live_creates_five_images() {
	lock_tsetup()
	lock_live_images()
	dir := '${lock_troot}/cache/hornero/lockscreen/current'
	for name in ['lock_resize.png', 'lock_dim.png', 'lock_blur.png', 'lock_dimblur.png',
		'lock_pixel.png'] {
		assert os.is_file(os.join_path(dir, name))
	}
	log := os.read_file('${lock_troot}/magick.log') or { '' }
	assert log.contains('800x600')
	assert log.contains('-colorize 40%')
	assert log.contains('-blur 0x5')
	lock_tteardown()
}

fn test_lock_update_refuses_without_yes() {
	lock_tsetup()
	r := lock_update_report(LockUpdateOptions{
		wallpaper: '${lock_troot}/wall.png'
		dim:       40
		blur:      5
		pixel:     10
	})
	assert !r.ok
	assert r.message.contains('refusing')
	assert !os.is_dir('${lock_troot}/cache/hornero/lockscreen/current')
	lock_tteardown()
}

fn test_lock_update_missing_wallpaper_fails() {
	lock_tsetup()
	r := lock_update_report(LockUpdateOptions{
		wallpaper: '${lock_troot}/nope.png'
		dim:       40
		blur:      5
		pixel:     10
		yes:       true
	})
	assert !r.ok
	assert r.message.contains('not found')
	empty := lock_update_report(LockUpdateOptions{
		dim:   40
		blur:  5
		pixel: 10
		yes:   true
	})
	assert !empty.ok
	assert empty.message.contains('no current wallpaper')
	lock_tteardown()
}

fn test_lock_update_broken_magick_fails() {
	lock_tsetup()
	os.setenv('HORNERO_MAGICK_BIN', '/nonexistent-magick-hornero-test', true)
	r := lock_update_report(LockUpdateOptions{
		wallpaper: '${lock_troot}/wall.png'
		dim:       40
		blur:      5
		pixel:     10
		yes:       true
	})
	assert !r.ok
	assert r.message.contains('exit')
	lock_tteardown()
}

fn test_lock_layout_style_vectors() {
	// Empty theme dirs: path patterns decide alone (host packs vary).
	os.mkdir_all('/tmp/hx-lock-test-empty/themes') or { assert false }
	os.setenv('HORNERO_THEMES_DIR', '/tmp/hx-lock-test-empty/themes', true)
	assert lock_layout_style('') == 'default'
	assert lock_layout_style('/pics/neon-city/wall.jpg') == 'vaporwave'
	assert lock_layout_style('/pics/soft-morning/wall.jpg') == 'cozy'
	assert lock_layout_style('/pics/monochrome/wall.jpg') == 'minimal'
	assert lock_layout_style('/pics/gruvbox/wall.jpg') == 'default'
	assert lock_layout_style('/pics/other/wall.jpg') == 'default'
	assert lock_layout_config('NEON vibes') == 'cyberpunk'
	assert lock_layout_config('soft pastel') == 'cozy'
	assert lock_layout_config('retro 80s') == 'vaporwave'
	assert lock_layout_config('clean') == 'minimal'
	assert lock_layout_config('???') == 'default'
	os.unsetenv('HORNERO_THEMES_DIR')
	os.rmdir_all('/tmp/hx-lock-test-empty') or {}
}

fn test_lock_layout_style_prefers_pack_tags() {
	lock_tsetup()
	// pampa pack carries vaporwave tags: tags win over the path default.
	assert lock_layout_style('/pics/pampa/pampa-01.png') == 'vaporwave'
	lock_tteardown()
}

fn test_lock_colors_prefers_scheme_json() {
	lock_tsetup()
	os.mkdir_all('${lock_troot}/cache/hornero/smart-colors') or { assert false }
	os.write_file('${lock_troot}/cache/hornero/smart-colors/scheme.json', '{"colours":{"background":"#112233","onBackground":"#aabbcc","primary":"#445566","error":"#778899"}}') or {
		assert false
	}
	c := lock_colors()
	assert c.bg == '112233'
	assert c.fg == 'aabbcc'
	assert c.primary == '445566'
	assert c.error == '778899'
	lock_tteardown()
}

fn test_lock_colors_falls_back_to_legacy_env_then_defaults() {
	lock_tsetup()
	os.mkdir_all('${lock_troot}/cache/dots/smart-colors') or { assert false }
	os.write_file('${lock_troot}/cache/dots/smart-colors/current.env', 'SMART_BG="#010203"\nSMART_FG="#040506"\n') or {
		assert false
	}
	c := lock_colors()
	assert c.bg == '010203'
	assert c.fg == '040506'
	assert c.primary == '6495ed'
	assert c.error == 'ff6b6b'
	plain := lock_colors()
	assert plain.bg == '010203'
	lock_tteardown()
}

fn test_lock_colors_defaults_without_any_state() {
	lock_tsetup()
	c := lock_colors()
	assert c.bg == '1e1e1e'
	assert c.fg == 'ffffff'
	assert c.primary == '6495ed'
	assert c.error == 'ff6b6b'
	lock_tteardown()
}

fn test_lock_templates_carry_image_and_colors() {
	c := LockColors{
		bg:      '112233'
		fg:      'aabbcc'
		primary: '445566'
		error:   '778899'
	}
	cyber := render_hyprlock_config('cyberpunk', '/i/blur.png', c)
	assert cyber.contains('path = /i/blur.png')
	assert cyber.contains('ACCESS DENIED [' + '$' + 'ATTEMPTS]')
	assert cyber.contains('Cyberpunk Layout')
	cozy := render_hyprlock_config('cozy', '/i/blur.png', c)
	assert cozy.contains('password...')
	assert cozy.contains('$' + 'USER')
	vapor := render_hyprlock_config('vaporwave', '/i/blur.png', c)
	assert vapor.contains('VCR OSD Mono')
	minimal := render_hyprlock_config('minimal', '/i/blur.png', c)
	assert minimal.contains('rgba(445566ff)')
	assert minimal.contains('rgba(112233cc)')
	def := render_hyprlock_config('default', '/i/blur.png', c)
	assert def.contains('rgba(778899ff)')
	assert def.contains('$' + 'FAIL')
	unknown := render_hyprlock_config('nope', '/i/blur.png', c)
	assert unknown.contains('Default Layout')
	assert unknown.contains('date +' + "'%H:%M'" + '')
}

fn test_lock_image_selection_vectors() {
	imgs := LockEffectImages{
		resize:  '/c/lock_resize.png'
		blur:    '/c/lock_blur.png'
		pixel:   '/c/lock_pixel.png'
		dimblur: '/c/lock_dimblur.png'
	}
	assert lock_image_for_effect(imgs, 'pixel') == '/c/lock_pixel.png'
	assert lock_image_for_effect(imgs, 'dim') == '/c/lock_resize.png'
	assert lock_image_for_effect(imgs, 'bogus') == '/c/lock_blur.png'
	assert lock_effect_valid('dimblur')
	assert !lock_effect_valid('bogus')
	empty := LockEffectImages{}
	assert lock_image_for_effect(empty, 'blur') == ''
}

fn test_lock_now_native_dry_run_previews() {
	lock_tsetup()
	lock_live_images()
	r := lock_now_native_report(LockNowNativeOptions{
		effect:  'pixel'
		dry_run: true
	})
	assert r.ok
	assert r.command == 'lock now'
	assert r.data['dry_run'] == 'true'
	assert r.data['image'].ends_with('lock_pixel.png')
	assert r.data['layout'] == 'default'
	assert r.message.contains('layout: default')
	lock_tteardown()
}

fn test_lock_now_native_live_locks_and_cleans_up() {
	lock_tsetup()
	lock_live_images()
	before := os.ls(os.temp_dir()) or { []string{} }
	r := lock_now_native_report(LockNowNativeOptions{})
	assert r.ok
	assert r.message.contains('layout=default')
	assert r.data['image'].ends_with('lock_blur.png')
	after := os.ls(os.temp_dir()) or { []string{} }
	for f in after {
		if f.starts_with('hornero-lock-') && f !in before {
			assert false, 'temp config leaked: ${f}'
		}
	}
	lock_tteardown()
}

fn test_lock_now_native_without_images_fails() {
	lock_tsetup()
	r := lock_now_native_report(LockNowNativeOptions{})
	assert !r.ok
	assert r.message.contains('lock update')
	bad := lock_now_native_report(LockNowNativeOptions{
		effect: 'bogus'
	})
	assert !bad.ok
	assert bad.message.contains('unknown effect')
	lock_tteardown()
}

fn test_lock_now_native_missing_hyprlock_fails() {
	lock_tsetup()
	lock_live_images()
	os.setenv('HORNERO_HYPRLOCK_BIN', '/nonexistent-hyprlock-hornero-test', true)
	r := lock_now_native_report(LockNowNativeOptions{})
	assert !r.ok
	lock_tteardown()
}
