module hornero_cli

import os

// Wallpaper dispatch fixtures reuse the /tmp tree the core tests build;
// each test sets the overrides it needs and unsets them afterwards.
fn wp_dispatch_setup() {
	base := '/tmp/hx-wallpaper-dtest'
	os.rmdir_all(base) or {}
	os.mkdir_all(base + '/state/hornero/wallpaper') or { assert false }
	os.mkdir_all(base + '/cache') or { assert false }
	os.write_file(base + '/wall.jpg', 'fake-image') or { assert false }
	os.write_file(base + '/state/hornero/wallpaper/path', base + '/wall.jpg\n') or { assert false }
	os.setenv('HORNERO_WALLPAPER_POINTER_FILE', base + '/state/hornero/wallpaper/path',
		true)
	os.setenv('XDG_STATE_HOME', base + '/state', true)
	os.setenv('XDG_CACHE_HOME', base + '/cache', true)
	os.setenv('HORNERO_WAL_RELOAD_BIN', '/nonexistent-wal-reload-hornero-test', true)
}

fn wp_dispatch_teardown() {
	os.unsetenv('HORNERO_WALLPAPER_POINTER_FILE')
	os.unsetenv('XDG_STATE_HOME')
	os.unsetenv('XDG_CACHE_HOME')
	os.unsetenv('HORNERO_WAL_RELOAD_BIN')
}

fn test_dispatch_wallpaper_current() {
	wp_dispatch_setup()
	assert dispatch(['horneroctl', 'wallpaper', 'current']) == 0
	assert dispatch(['horneroctl', 'wallpaper', 'current', '--json']) == 0
	assert dispatch(['horneroctl', '--json', 'wallpaper', 'current']) == 0
	assert dispatch(['horneroctl', '--quiet', 'wallpaper', 'current']) == 0
	assert dispatch(['horneroctl', 'wallpaper', 'current', '--dry-run']) == 2
	assert dispatch(['horneroctl', 'wallpaper', 'current', 'extra', 'args']) == 2
	wp_dispatch_teardown()
}

fn test_dispatch_wallpaper_set() {
	wp_dispatch_setup()
	assert dispatch(['horneroctl', 'wallpaper', 'set', '/tmp/hx-wallpaper-dtest/wall.jpg', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'wallpaper', 'set', '/tmp/hx-wallpaper-dtest/wall.jpg']) == 1
	assert dispatch(['horneroctl', 'wallpaper', 'set', '/tmp/hx-wallpaper-dtest/missing.jpg',
		'--dry-run']) == 1
	assert dispatch(['horneroctl', 'wallpaper', 'set']) == 2
	assert dispatch(['horneroctl', 'wallpaper', 'set', '/tmp/hx-wallpaper-dtest/wall.jpg', '--bogus']) == 2
	wp_dispatch_teardown()
}

fn test_dispatch_wallpaper_reload() {
	wp_dispatch_setup()
	assert dispatch(['horneroctl', 'wallpaper', 'reload', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'wallpaper', 'reload']) == 1
	assert dispatch(['horneroctl', 'wallpaper', 'reload', '--yes']) == 1
	assert dispatch(['horneroctl', 'wallpaper', 'reload', '--bogus']) == 2
	assert dispatch(['horneroctl', 'wallpaper', 'reload', 'extra']) == 2
	wp_dispatch_teardown()
}

fn test_dispatch_wallpaper_usage() {
	wp_dispatch_setup()
	assert dispatch(['horneroctl', 'wallpaper']) == 2
	assert dispatch(['horneroctl', 'wallpaper', 'bogus']) == 2
	assert dispatch(['horneroctl', 'wallpaper', '--help']) == 0
	assert dispatch(['horneroctl', 'help', 'wallpaper']) == 0
	wp_dispatch_teardown()
}

fn test_wallpaper_help_has_examples() {
	h := command_help('wallpaper')
	assert h.contains('Examples:')
}

fn test_wallpaper_dry_run_needs_no_backend() {
	// Hermetic: nonexistent backends; dry-run previews must still pass.
	wp_dispatch_setup()
	assert dispatch(['horneroctl', 'wallpaper', 'set', '/tmp/hx-wallpaper-dtest/wall.jpg', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'wallpaper', 'reload', '--dry-run']) == 0
	wp_dispatch_teardown()
}

fn test_wallpaper_json_and_quiet_modes() {
	wp_dispatch_setup()
	assert dispatch(['horneroctl', '--json', 'wallpaper', 'current']) == 0
	assert dispatch(['horneroctl', '--quiet', 'wallpaper', 'current']) == 0
	assert dispatch(['horneroctl', '--json', 'wallpaper', 'set', '/tmp/hx-wallpaper-dtest/wall.jpg',
		'--dry-run']) == 0
	assert dispatch(['horneroctl', '--json', 'wallpaper', 'reload', '--dry-run']) == 0
	wp_dispatch_teardown()
}
