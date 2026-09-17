module hornero_cli

import os

const gtk_droot = '/tmp/hx-gtk-select-dtest'

fn gtk_dsetup() {
	os.rmdir_all(gtk_droot) or {}
	os.mkdir_all('${gtk_droot}/config') or { assert false }
	os.mkdir_all('${gtk_droot}/data/themes/Alpha/gtk-3.0') or { assert false }
	os.mkdir_all('${gtk_droot}/state') or { assert false }
	os.mkdir_all('${gtk_droot}/cache') or { assert false }
	os.setenv('XDG_CONFIG_HOME', '${gtk_droot}/config', true)
	os.setenv('XDG_DATA_HOME', '${gtk_droot}/data', true)
	os.setenv('XDG_STATE_HOME', '${gtk_droot}/state', true)
	os.setenv('XDG_CACHE_HOME', '${gtk_droot}/cache', true)
	os.setenv('HORNERO_SHELL_RUNNING', '0', true)
}

fn gtk_dteardown() {
	os.unsetenv('XDG_CONFIG_HOME')
	os.unsetenv('XDG_DATA_HOME')
	os.unsetenv('XDG_STATE_HOME')
	os.unsetenv('XDG_CACHE_HOME')
	os.unsetenv('HORNERO_SHELL_RUNNING')
	os.unsetenv('HORNERO_QS_BIN')
	os.rmdir_all(gtk_droot) or {}
}

fn test_dispatch_gtk_select() {
	gtk_dsetup()
	assert dispatch(['horneroctl', 'appearance', 'gtk', 'select', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'appearance', 'gtk', 'select']) == 1
	assert dispatch(['horneroctl', 'appearance', 'gtk', 'select', 'Alpha']) == 2
	assert dispatch(['horneroctl', 'appearance', 'gtk', 'select', '--bogus']) == 2
	assert dispatch(['horneroctl', 'appearance', 'gtk', 'bogus']) == 2
	gtk_dteardown()
}

fn test_dispatch_gtk_select_quickshell() {
	gtk_dsetup()
	os.setenv('HORNERO_SHELL_RUNNING', '1', true)
	os.setenv('HORNERO_QS_BIN', '/nonexistent-qs-hornero-test', true)
	assert dispatch(['horneroctl', 'appearance', 'gtk', 'select', '--dry-run']) == 0
	gtk_dteardown()
}
