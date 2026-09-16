module hornero_core

import os

fn wp_setup() string {
	base := '/tmp/hx-wallpaper-test'
	os.rmdir_all(base) or {}
	os.mkdir_all(base + '/state/hornero/wallpaper') or { assert false }
	os.mkdir_all(base + '/state/dots/wallpaper') or { assert false }
	os.mkdir_all(base + '/cache') or { assert false }
	os.write_file(base + '/wall.jpg', 'fake-image') or { assert false }
	os.setenv('HORNERO_WALLPAPER_POINTER_FILE', base + '/state/hornero/wallpaper/path',
		true)
	os.setenv('XDG_STATE_HOME', base + '/state', true)
	os.setenv('XDG_CACHE_HOME', base + '/cache', true)
	return base
}

fn wp_teardown() {
	os.unsetenv('HORNERO_WALLPAPER_POINTER_FILE')
	os.unsetenv('XDG_STATE_HOME')
	os.unsetenv('XDG_CACHE_HOME')
	os.unsetenv('HORNERO_WALLPAPER_SET_BIN')
	os.unsetenv('HORNERO_WAL_RELOAD_BIN')
}

fn test_wallpaper_current_from_canonical_pointer() {
	base := wp_setup()
	os.write_file(base + '/state/hornero/wallpaper/path', base + '/wall.jpg\n') or { assert false }
	assert current_wallpaper('') == base + '/wall.jpg'
	r := wallpaper_report(WallpaperOptions{
		action: 'current'
	})
	assert r.ok
	assert r.message == base + '/wall.jpg'
	wp_teardown()
}

fn test_wallpaper_current_prefers_canonical_over_dots_fallback() {
	base := wp_setup()
	os.write_file(base + '/wall2.jpg', 'fake-image-2') or { assert false }
	os.write_file(base + '/state/hornero/wallpaper/path', base + '/wall.jpg\n') or { assert false }
	os.write_file(base + '/state/dots/wallpaper/path', base + '/wall2.jpg\n') or { assert false }
	assert current_wallpaper('') == base + '/wall.jpg'
	wp_teardown()
}

fn test_wallpaper_current_falls_back_to_dots_pointer() {
	base := wp_setup()
	os.write_file(base + '/state/dots/wallpaper/path', base + '/wall.jpg\n') or { assert false }
	assert current_wallpaper('') == base + '/wall.jpg'
	wp_teardown()
}

fn test_wallpaper_current_from_symlink_pointer() {
	base := wp_setup()
	os.symlink(base + '/wall.jpg', base + '/state/hornero/wallpaper/path') or { assert false }
	assert current_wallpaper('') == base + '/wall.jpg'
	wp_teardown()
}

fn test_wallpaper_current_explicit_path_wins() {
	base := wp_setup()
	os.write_file(base + '/wall2.jpg', 'fake-image-2') or { assert false }
	os.write_file(base + '/state/dots/wallpaper/path', base + '/wall.jpg\n') or { assert false }
	assert current_wallpaper(base + '/wall2.jpg') == base + '/wall2.jpg'
	wp_teardown()
}

fn test_wallpaper_current_missing_is_failure() {
	base := wp_setup()
	assert current_wallpaper('') == ''
	r := wallpaper_report(WallpaperOptions{
		action: 'current'
	})
	assert !r.ok
	wp_teardown()
}

fn test_wallpaper_current_self_referential_pointer_ignored() {
	base := wp_setup()
	ptr := base + '/state/hornero/wallpaper/path'
	os.write_file(ptr, ptr + '\n') or { assert false }
	assert current_wallpaper('') == ''
	wp_teardown()
}

fn test_wallpaper_set_missing_file_fails() {
	wp_setup()
	r := wallpaper_report(WallpaperOptions{
		action:  'set'
		path:    '/tmp/hx-wallpaper-test/does-not-exist.jpg'
		dry_run: true
	})
	assert !r.ok
	wp_teardown()
}

fn test_wallpaper_set_needs_yes() {
	base := wp_setup()
	r := wallpaper_report(WallpaperOptions{
		action: 'set'
		path:   base + '/wall.jpg'
	})
	assert !r.ok
	assert r.message.contains('--yes')
	wp_teardown()
}

fn test_wallpaper_set_dry_run_needs_no_backend() {
	base := wp_setup()
	r := wallpaper_report(WallpaperOptions{
		action:     'set'
		path:       base + '/wall.jpg'
		dry_run:    true
		set_helper: '/nonexistent-wallpaper-set-hornero-test'
	})
	assert r.ok
	assert r.message.contains('would run:')
	assert !r.message.contains('dots-wallpaper-set')
	assert r.message.contains('/nonexistent-wallpaper-set-hornero-test')
	assert r.message.contains('HORNEROCTL_DELEGATED=1')
	assert r.data['path'] == base + '/wall.jpg'
	wp_teardown()
}

fn test_wallpaper_set_runs_backend_with_guard() {
	base := wp_setup()
	os.write_file(base + '/dots-wallpaper-set', '#!/bin/sh\n[ -n "\$HORNEROCTL_DELEGATED" ] || { echo missing delegation guard >&2; exit 3; }\necho "wallpaper applied \$*"\nexit 0\n') or {
		assert false
	}
	os.chmod(base + '/dots-wallpaper-set', 0o755) or { assert false }
	r := wallpaper_report(WallpaperOptions{
		action:     'set'
		path:       base + '/wall.jpg'
		yes:        true
		set_helper: base + '/dots-wallpaper-set'
	})
	assert r.ok
	assert r.message.contains('wallpaper applied')
	wp_teardown()
}

fn test_wallpaper_set_path_with_metacharacters_stays_one_arg() {
	base := wp_setup()
	// If the backend line were shell-split, `touch PWNED_MARKER.jpg` would
	// run in the test working directory; it must never appear there.
	marker := os.join_path(os.getwd(), 'PWNED_MARKER.jpg')
	evil := base + '/evil;touch PWNED_MARKER.jpg'
	os.write_file(evil, 'fake-image') or { assert false }
	os.rm(marker) or {}
	os.write_file(base + '/arg-echo', '#!/bin/sh\necho "n=$#"\necho "a=$1"\nexit 0\n') or {
		assert false
	}
	os.chmod(base + '/arg-echo', 0o755) or { assert false }
	r := wallpaper_report(WallpaperOptions{
		action:     'set'
		path:       evil
		yes:        true
		set_helper: base + '/arg-echo'
	})
	assert r.ok
	assert r.message.contains('n=1')
	assert r.message.contains('a=' + evil)
	assert !os.is_file(marker)
	wp_teardown()
}

fn test_wallpaper_set_missing_backend_fails() {
	base := wp_setup()
	r := wallpaper_report(WallpaperOptions{
		action:     'set'
		path:       base + '/wall.jpg'
		yes:        true
		set_helper: '/nonexistent-wallpaper-set-hornero-test'
	})
	assert !r.ok
	wp_teardown()
}

fn test_wallpaper_reload_needs_yes() {
	wp_setup()
	r := wallpaper_report(WallpaperOptions{
		action: 'reload'
	})
	assert !r.ok
	assert r.message.contains('--yes')
	wp_teardown()
}

fn test_wallpaper_reload_dry_run_needs_no_backend() {
	wp_setup()
	r := wallpaper_report(WallpaperOptions{
		action:        'reload'
		dry_run:       true
		reload_helper: '/nonexistent-wal-reload-hornero-test'
	})
	assert r.ok
	assert r.message.contains('would run:')
	assert r.message.contains('/nonexistent-wal-reload-hornero-test')
	assert r.message.contains('HORNEROCTL_DELEGATED=1')
	wp_teardown()
}

fn test_wallpaper_reload_runs_backend_with_guard() {
	base := wp_setup()
	os.write_file(base + '/dots-wal-reload', '#!/bin/sh\n[ -n "\$HORNEROCTL_DELEGATED" ] || { echo missing delegation guard >&2; exit 3; }\necho reloaded\nexit 0\n') or {
		assert false
	}
	os.chmod(base + '/dots-wal-reload', 0o755) or { assert false }
	r := wallpaper_report(WallpaperOptions{
		action:        'reload'
		yes:           true
		reload_helper: base + '/dots-wal-reload'
	})
	assert r.ok
	assert r.message.contains('reloaded')
	wp_teardown()
}

fn test_wallpaper_reload_missing_backend_fails() {
	wp_setup()
	r := wallpaper_report(WallpaperOptions{
		action:        'reload'
		yes:           true
		reload_helper: '/nonexistent-wal-reload-hornero-test'
	})
	assert !r.ok
	wp_teardown()
}

fn test_wallpaper_unknown_action_fails() {
	wp_setup()
	r := wallpaper_report(WallpaperOptions{
		action: 'bogus'
	})
	assert !r.ok
	wp_teardown()
}

fn test_resolve_wallpaper_backends_override() {
	os.setenv('HORNERO_WALLPAPER_SET_BIN', '/tmp/hx-wallpaper-test/setter', true)
	os.setenv('HORNERO_WAL_RELOAD_BIN', '/tmp/hx-wallpaper-test/reloader', true)
	assert resolve_wallpaper_set_bin() == '/tmp/hx-wallpaper-test/setter'
	assert resolve_wal_reload_bin() == '/tmp/hx-wallpaper-test/reloader'
	wp_teardown()
}
