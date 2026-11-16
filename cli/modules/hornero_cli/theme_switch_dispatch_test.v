module hornero_cli

import os

// Official theme get/set dispatch: exit-code contract plus --help text.
// Backends stay absent (nonexistent binary): only --dry-run previews and
// usage/domain rejections run here; live flows live in hornero_core tests.

const sw_droot = '/tmp/hx-theme-switch-dtest'

fn sw_dsetup() {
	os.setenv('HORNERO_THEMES_DIR', os.join_path(os.dir(@FILE), '..', '..', 'testdata',
		'signal-themes'), true)
	os.setenv('XDG_STATE_HOME', '${sw_droot}/state', true)
	os.setenv('XDG_CONFIG_HOME', '${sw_droot}/config', true)
}

fn sw_dteardown() {
	for name in ['HORNERO_THEMES_DIR', 'XDG_STATE_HOME', 'XDG_CONFIG_HOME'] {
		os.unsetenv(name)
	}
	os.rmdir_all(sw_droot) or {}
}

fn test_dispatch_appearance_theme_get() {
	sw_dsetup()
	assert dispatch(['horneroctl', 'appearance', 'theme', 'get', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'appearance', 'theme', 'get']) == 0
	assert dispatch(['horneroctl', 'appearance', 'theme', 'get', 'hornero-signal-night']) == 2
	assert dispatch(['horneroctl', 'appearance', 'theme', 'get', '--yes']) == 2
	sw_dteardown()
}

fn test_dispatch_appearance_theme_set() {
	sw_dsetup()
	for id in signal_ids() {
		assert dispatch(['horneroctl', 'appearance', 'theme', 'set', id, '--dry-run']) == 0
	}
	assert dispatch(['horneroctl', 'appearance', 'theme', 'set', 'hornero-signal-night']) == 1
	assert dispatch(['horneroctl', 'appearance', 'theme', 'set', 'hornero-dark', '--dry-run']) == 1
	assert dispatch(['horneroctl', 'appearance', 'theme', 'set', 'pampa', '--dry-run']) == 1
	assert dispatch(['horneroctl', 'appearance', 'theme', 'set']) == 2
	assert dispatch(['horneroctl', 'appearance', 'theme', 'apply', 'hornero-signal-day', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'appearance', 'theme', 'apply', 'hornero-light', '--dry-run']) == 1
	assert dispatch(['horneroctl', 'appearance', 'theme', 'set', 'hornero-signal-night', '--wallpaper',
		'x', '--dry-run']) == 2
	sw_dteardown()
}

fn test_dispatch_appearance_theme_help_covers_switching() {
	h := command_help('appearance theme')
	assert h.contains('Examples:')
	assert h.contains('get')
	assert h.contains('set hornero-signal-night --dry-run')
	assert h.contains('hornero-signal-contrast')
	assert !h.contains('M3')
	assert dispatch(['horneroctl', 'appearance', 'theme', '--help']) == 0
}

fn signal_ids() []string {
	return ['hornero-signal-night', 'hornero-signal-day', 'hornero-signal-contrast']
}
