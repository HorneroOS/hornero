module hornero_core

import os

fn wp_setup() string {
	base := '/tmp/hx-wallpaper-test'
	os.rmdir_all(base) or {}
	os.mkdir_all(base + '/state/hornero/wallpaper') or { assert false }
	os.mkdir_all(base + '/cache/wal') or { assert false }
	os.write_file(base + '/wall.jpg', 'fake-image') or { assert false }
	os.setenv('HORNERO_WALLPAPER_POINTER_FILE', base + '/state/hornero/wallpaper/path', true)
	os.setenv('XDG_STATE_HOME', base + '/state', true)
	os.setenv('XDG_CACHE_HOME', base + '/cache', true)
	os.setenv('XDG_CONFIG_HOME', base + '/config', true)
	return base
}

fn wp_teardown() {
	for name in ['HORNERO_WALLPAPER_POINTER_FILE', 'XDG_STATE_HOME', 'XDG_CACHE_HOME', 'XDG_CONFIG_HOME',
		'HORNERO_SHELL_RUNNING', 'HORNERO_QUICKSHELL_BIN'] {
		os.unsetenv(name)
	}
	os.rmdir_all('/tmp/hx-wallpaper-test') or {}
}

fn test_wallpaper_current_uses_canonical_text_pointer() {
	base := wp_setup()
	os.write_file(resolve_wallpaper_pointer_file(), base + '/wall.jpg\n') or { assert false }
	assert current_wallpaper('') == base + '/wall.jpg'
	r := wallpaper_report(WallpaperOptions{ action: 'current' })
	assert r.ok
	assert r.message == base + '/wall.jpg'
	wp_teardown()
}

fn test_wallpaper_current_uses_canonical_symlink_pointer() {
	base := wp_setup()
	os.symlink(base + '/wall.jpg', resolve_wallpaper_pointer_file()) or { assert false }
	assert current_wallpaper('') == base + '/wall.jpg'
	wp_teardown()
}

fn test_wallpaper_current_ignores_retired_pywal_pointer() {
	base := wp_setup()
	os.write_file(base + '/cache/wal/wal', base + '/wall.jpg\n') or { assert false }
	assert current_wallpaper('') == ''
	wp_teardown()
}

fn test_wallpaper_current_explicit_path_wins() {
	base := wp_setup()
	os.write_file(base + '/wall2.jpg', 'fake-image-2') or { assert false }
	assert current_wallpaper(base + '/wall2.jpg') == base + '/wall2.jpg'
	wp_teardown()
}

fn test_wallpaper_set_rejects_missing_file_and_missing_confirmation() {
	base := wp_setup()
	missing := wallpaper_report(WallpaperOptions{ action: 'set', path: base + '/missing.jpg', dry_run: true })
	assert !missing.ok
	needs_confirmation := wallpaper_report(WallpaperOptions{ action: 'set', path: base + '/wall.jpg' })
	assert !needs_confirmation.ok
	assert needs_confirmation.message.contains('--yes')
	wp_teardown()
}

fn test_wallpaper_set_dry_run_previews_pointer_write() {
	base := wp_setup()
	r := wallpaper_report(WallpaperOptions{ action: 'set', path: base + '/wall.jpg', dry_run: true })
	assert r.ok, r.message
	assert r.message.contains('would atomically write')
	assert read_wallpaper_pointer() == ''
	wp_teardown()
}

fn test_wallpaper_set_writes_pointer_without_recolouring() {
	base := wp_setup()
	os.setenv('HORNERO_SHELL_RUNNING', '1', true)
	os.setenv('HORNERO_QUICKSHELL_BIN', '/nonexistent-quickshell', true)
	r := wallpaper_report(WallpaperOptions{ action: 'set', path: base + '/wall.jpg', yes: true })
	assert r.ok, r.message
	assert read_wallpaper_pointer() == base + '/wall.jpg'
	assert !os.exists(signal_scheme_file())
	wp_teardown()
}

fn test_wallpaper_reload_is_removed() {
	wp_setup()
	r := wallpaper_report(WallpaperOptions{ action: 'reload', yes: true })
	assert !r.ok
	assert r.message.contains('unknown action')
	wp_teardown()
}

fn test_wallpaper_unknown_action_fails() {
	wp_setup()
	assert !wallpaper_report(WallpaperOptions{ action: 'bogus' }).ok
	wp_teardown()
}
