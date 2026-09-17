module hornero_cli

import os

const lock_droot = '/tmp/hx-lock-dtest'

fn lock_dsetup() {
	os.setenv('HORNERO_LOCK_TEST_SAVED_HOME', os.getenv('HOME'), true)
	os.setenv('HORNERO_LOCK_TEST_SAVED_PATH', os.getenv('PATH'), true)
	os.rmdir_all(lock_droot) or {}
	os.mkdir_all('${lock_droot}/cache') or { assert false }
	os.mkdir_all('${lock_droot}/state') or { assert false }
	os.mkdir_all('${lock_droot}/data') or { assert false }
	os.mkdir_all('${lock_droot}/bin') or { assert false }
	os.write_file('${lock_droot}/wall.png', 'fake-png-bytes') or { assert false }
	os.write_file('${lock_droot}/bin/magick', '#!/bin/sh\nif [ "\$1" = "-format" ]; then echo "800 600"; exit 0; fi\nout=""\nfor a in "\$@"; do out="\$a"; done\ncp "\$1" "\$out"\n') or {
		assert false
	}
	os.write_file('${lock_droot}/bin/hyprlock', '#!/bin/sh\necho "hyprlock \$*"\nexit 0\n') or {
		assert false
	}
	os.chmod('${lock_droot}/bin/magick', 0o755) or { assert false }
	os.chmod('${lock_droot}/bin/hyprlock', 0o755) or { assert false }
	os.setenv('XDG_CACHE_HOME', '${lock_droot}/cache', true)
	os.setenv('XDG_STATE_HOME', '${lock_droot}/state', true)
	os.setenv('XDG_DATA_HOME', '${lock_droot}/data', true)
	os.setenv('HORNERO_MAGICK_BIN', '${lock_droot}/bin/magick', true)
	os.setenv('HORNERO_HYPRLOCK_BIN', '${lock_droot}/bin/hyprlock', true)
	os.setenv('HORNERO_LOCKSCREEN_RESOLUTION', '800x600', true)
	os.setenv('HORNERO_LOCKSCREEN_CACHE_DIR', '${lock_droot}/imgs', true)
	os.setenv('HOME', '${lock_droot}/home', true)
	os.setenv('PATH', '${lock_droot}/bin:/usr/bin:/bin', true)
	os.unsetenv('HORNERO_LOCKSCREEN_BIN')
}

fn lock_dteardown() {
	os.unsetenv('XDG_CACHE_HOME')
	os.unsetenv('XDG_STATE_HOME')
	os.unsetenv('XDG_DATA_HOME')
	os.unsetenv('HORNERO_MAGICK_BIN')
	os.unsetenv('HORNERO_HYPRLOCK_BIN')
	os.unsetenv('HORNERO_LOCKSCREEN_RESOLUTION')
	os.unsetenv('HORNERO_LOCKSCREEN_CACHE_DIR')
	os.setenv('HOME', os.getenv('HORNERO_LOCK_TEST_SAVED_HOME'), true)
	os.unsetenv('HORNERO_LOCK_TEST_SAVED_HOME')
	os.setenv('PATH', os.getenv('HORNERO_LOCK_TEST_SAVED_PATH'), true)
	os.unsetenv('HORNERO_LOCK_TEST_SAVED_PATH')
	os.rmdir_all(lock_droot) or {}
}

fn test_dispatch_lock_update() {
	lock_dsetup()
	assert dispatch(['horneroctl', 'lock', 'update', '${lock_droot}/wall.png', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'lock', 'update', '${lock_droot}/wall.png']) == 1
	assert dispatch(['horneroctl', 'lock', 'update', '${lock_droot}/wall.png', '--dim', '30',
		'--blur', '3', '--pixel', '4', '--yes']) == 0
	assert os.is_file('${lock_droot}/imgs/current/lock_pixel.png')
	assert dispatch(['horneroctl', 'lock', 'update', '${lock_droot}/missing.png', '--yes']) == 1
	assert dispatch(['horneroctl', 'lock', 'update', '--dim', '200', '--dry-run']) == 2
	assert dispatch(['horneroctl', 'lock', 'update', '--dim', 'x', '--dry-run']) == 2
	assert dispatch(['horneroctl', 'lock', 'update', '--pixel', '0', '--dry-run']) == 2
	assert dispatch(['horneroctl', 'lock', 'update', 'a', 'b', '--dry-run']) == 2
	assert dispatch(['horneroctl', 'lock', 'update', '--bogus']) == 2
	lock_dteardown()
}

fn test_dispatch_lock_now_effect() {
	lock_dsetup()
	// No images yet: native dry-run fails with the update hint.
	assert dispatch(['horneroctl', 'lock', 'now', '--effect', 'pixel', '--dry-run']) == 1
	// Legacy plan (no override, no images): bare fixture hyprlock previews.
	assert dispatch(['horneroctl', 'lock', 'now', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'lock', 'now', '--effect', 'bogus', '--dry-run']) == 2
	assert dispatch(['horneroctl', 'lock', 'now', '--dim', '1', '--dry-run']) == 2
	assert dispatch(['horneroctl', 'lock', 'status', '--effect', 'blur']) == 2
	// Prime the cache, then the native flow runs live and dry.
	assert dispatch(['horneroctl', 'lock', 'update', '${lock_droot}/wall.png', '--yes']) == 0
	assert dispatch(['horneroctl', 'lock', 'now', '--effect', 'pixel', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'lock', 'now', '--effect', 'pixel', '--yes']) == 0
	assert dispatch(['horneroctl', 'lock', 'now', '--yes']) == 0
	lock_dteardown()
}
