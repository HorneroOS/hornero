module hornero_cli

import os

// Official theme get/set dispatch: exit-code contract plus --help text.
// Backends stay absent (nonexistent binary): only --dry-run previews and
// usage/domain rejections run here; live flows live in hornero_core tests.

const sw_droot = '/tmp/hx-theme-switch-dtest'

fn sw_dsetup() {
	os.mkdir_all('${sw_droot}/themes/hornero-dark') or { assert false }
	os.write_file('${sw_droot}/themes/hornero-dark/theme.json', '{"schemaVersion":1,"id":"hornero-dark","name":"Hornero Dark","gtkTheme":"Orchis-Dark-Compact","iconTheme":"Papirus-Dark","defaultWallpaper":"hornero-dark-01.jpg","wallpaperDir":"hornero-dark","mode":"dark"}') or {
		assert false
	}
	os.mkdir_all('${sw_droot}/themes/hornero-light') or { assert false }
	os.write_file('${sw_droot}/themes/hornero-light/theme.json', '{"schemaVersion":1,"id":"hornero-light","name":"Hornero Light","gtkTheme":"Orchis-Light-Compact","iconTheme":"Numix-Circle","defaultWallpaper":"hornero-light-01.jpg","wallpaperDir":"hornero-light","mode":"light"}') or {
		assert false
	}
	os.mkdir_all('${sw_droot}/themes/pampa') or { assert false }
	os.write_file('${sw_droot}/themes/pampa/theme.json', '{"schemaVersion":1,"id":"pampa","name":"Pampa","gtkTheme":"Hornero-Pampa","iconTheme":"Papirus-Dark","defaultWallpaper":"pampa-01.png","wallpaperDir":"pampa","mode":"dark"}') or {
		assert false
	}
	os.setenv('HORNERO_THEMES_DIR', '${sw_droot}/themes', true)
	os.setenv('HORNERO_DOTS_APPEARANCE_BIN', '/nonexistent-appearance-hornero-test', true)
}

fn sw_dteardown() {
	os.unsetenv('HORNERO_THEMES_DIR')
	os.unsetenv('HORNERO_DOTS_APPEARANCE_BIN')
}

fn test_dispatch_appearance_theme_get() {
	sw_dsetup()
	assert dispatch(['horneroctl', 'appearance', 'theme', 'get', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'appearance', 'theme', 'get']) == 1
	assert dispatch(['horneroctl', 'appearance', 'theme', 'get', 'hornero-dark']) == 2
	assert dispatch(['horneroctl', 'appearance', 'theme', 'get', '--yes']) == 2
	sw_dteardown()
}

fn test_dispatch_appearance_theme_set() {
	sw_dsetup()
	assert dispatch(['horneroctl', 'appearance', 'theme', 'set', 'hornero-dark', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'appearance', 'theme', 'set', 'hornero-light', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'appearance', 'theme', 'set', 'pampa', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'appearance', 'theme', 'set', 'hornero-dark']) == 1
	assert dispatch(['horneroctl', 'appearance', 'theme', 'set', 'vapor-dreams', '--dry-run']) == 1
	assert dispatch(['horneroctl', 'appearance', 'theme', 'set']) == 2
	assert dispatch(['horneroctl', 'appearance', 'theme', 'set', 'hornero-dark', '--wallpaper',
		'x', '--dry-run']) == 2
	sw_dteardown()
}

fn test_dispatch_appearance_theme_help_covers_switching() {
	h := command_help('appearance theme')
	assert h.contains('Examples:')
	assert h.contains('get')
	assert h.contains('set hornero-dark --dry-run')
	assert dispatch(['horneroctl', 'appearance', 'theme', '--help']) == 0
}
