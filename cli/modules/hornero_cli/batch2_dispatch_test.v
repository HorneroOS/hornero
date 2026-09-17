module hornero_cli

import os

// Batch-2 dispatch fixtures reuse the core /tmp tree; each test sets the
// overrides it needs and unsets them afterwards.
fn b2_dispatch_setup() {
	os.mkdir_all('/tmp/hx-batch2-dtest/bin') or { assert false }
	os.write_file('/tmp/hx-batch2-dtest/bin/dots-default-apps', '#!/bin/sh\nif [ "\$1" = "--list" ]; then printf "web-browser: firefox.desktop\\n"; exit 0; fi\nexit 1\n') or {
		assert false
	}
	os.write_file('/tmp/hx-batch2-dtest/bin/dots-settings-gui', '#!/bin/sh\necho "settings hub \$*"\nexit 0\n') or {
		assert false
	}
	os.write_file('/tmp/hx-batch2-dtest/bin/materialize.sh', '#!/bin/sh\necho "materialized \$*"\nexit 0\n') or {
		assert false
	}
	os.chmod('/tmp/hx-batch2-dtest/bin/dots-default-apps', 0o755) or { assert false }
	os.chmod('/tmp/hx-batch2-dtest/bin/dots-settings-gui', 0o755) or { assert false }
	os.chmod('/tmp/hx-batch2-dtest/bin/materialize.sh', 0o755) or { assert false }
	os.setenv('HORNERO_DEFAULT_APPS_BIN', '/tmp/hx-batch2-dtest/bin/dots-default-apps',
		true)
	os.setenv('HORNERO_SETTINGS_GUI_BIN', '/tmp/hx-batch2-dtest/bin/dots-settings-gui',
		true)
	os.setenv('HORNERO_MATERIALIZE_BIN', '/tmp/hx-batch2-dtest/bin/materialize.sh', true)
}

fn b2_dispatch_teardown() {
	os.unsetenv('HORNERO_DEFAULT_APPS_BIN')
	os.unsetenv('HORNERO_SETTINGS_GUI_BIN')
	os.unsetenv('HORNERO_MATERIALIZE_BIN')
}

fn test_dispatch_config_default_apps() {
	b2_dispatch_setup()
	assert dispatch(['horneroctl', 'config', 'default-apps', 'list']) == 0
	assert dispatch(['horneroctl', 'config', 'default-apps', 'list', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'config', 'default-apps']) == 2
	assert dispatch(['horneroctl', 'config', 'default-apps', 'list', '--bogus']) == 2
	assert dispatch(['horneroctl', 'config', 'default-apps', 'list', 'extra']) == 2
	// set writes via xdg-mime: refuses without --yes, previews clean.
	assert dispatch(['horneroctl', 'config', 'default-apps', 'set', 'text/plain', 'nvim.desktop']) == 1
	assert dispatch(['horneroctl', 'config', 'default-apps', 'set', 'text/plain', 'nvim.desktop',
		'--dry-run']) == 0
	assert dispatch(['horneroctl', 'config', 'default-apps', 'set', 'text/plain']) == 2
	assert dispatch(['horneroctl', 'config', 'default-apps', 'set', 'not-a-mime', 'nvim.desktop',
		'--dry-run']) == 1
	assert dispatch(['horneroctl', 'config', 'default-apps', 'bogus']) == 2
	assert dispatch(['horneroctl', 'config', 'default-apps', '--help']) == 0
	b2_dispatch_teardown()
}

fn test_dispatch_config_materialize() {
	b2_dispatch_setup()
	assert dispatch(['horneroctl', 'config', 'materialize', '--dest', '/tmp/hx-batch2-dtest/dest',
		'--dry-run']) == 0
	assert dispatch(['horneroctl', 'config', 'materialize', '--dest=/tmp/hx-batch2-dtest/dest',
		'--dry-run']) == 0
	assert dispatch(['horneroctl', 'config', 'materialize', '--dest', '/tmp/hx-batch2-dtest/dest',
		'--yes']) == 0
	assert dispatch(['horneroctl', 'config', 'materialize', '--dest', '/tmp/hx-batch2-dtest/dest']) == 1
	assert dispatch(['horneroctl', 'config', 'materialize']) == 2
	assert dispatch(['horneroctl', 'config', 'materialize', '--dry-run']) == 2
	assert dispatch(['horneroctl', 'config', 'materialize', '--dest']) == 2
	assert dispatch(['horneroctl', 'config', 'materialize', '--bogus']) == 2
	assert dispatch(['horneroctl', 'config', 'materialize', '--help']) == 0
	b2_dispatch_teardown()
}

fn test_dispatch_config_gui() {
	b2_dispatch_setup()
	assert dispatch(['horneroctl', 'config', 'gui']) == 0
	assert dispatch(['horneroctl', 'config', 'gui', '--pane', 'appearance']) == 0
	assert dispatch(['horneroctl', 'config', 'gui', '--pane=launcher']) == 0
	assert dispatch(['horneroctl', 'config', 'gui', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'config', 'gui', '--pane', 'appearance', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'config', 'gui', '--pane', 'bogus']) == 1
	assert dispatch(['horneroctl', 'config', 'gui', '--bogus']) == 2
	assert dispatch(['horneroctl', 'config', 'gui', 'extra']) == 2
	assert dispatch(['horneroctl', 'config', 'gui', '--help']) == 0
	b2_dispatch_teardown()
}

fn test_batch2_dry_run_needs_no_backend() {
	// Hermetic: nonexistent backends; dry-run previews must still pass.
	os.setenv('HORNERO_DEFAULT_APPS_BIN', '/nonexistent-default-apps-hornero-test', true)
	assert dispatch(['horneroctl', 'config', 'default-apps', 'list', '--dry-run']) == 0
	os.unsetenv('HORNERO_DEFAULT_APPS_BIN')
	os.setenv('HORNERO_SETTINGS_GUI_BIN', '/nonexistent-settings-gui-hornero-test', true)
	assert dispatch(['horneroctl', 'config', 'gui', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'config', 'gui', '--pane', 'appearance', '--dry-run']) == 0
	os.unsetenv('HORNERO_SETTINGS_GUI_BIN')
	os.setenv('HORNERO_MATERIALIZE_BIN', '/nonexistent-materialize-hornero-test', true)
	assert dispatch(['horneroctl', 'config', 'materialize', '--dest', '/tmp/hx-batch2-dtest/dest',
		'--dry-run']) == 0
	os.unsetenv('HORNERO_MATERIALIZE_BIN')
}

fn test_batch2_help_has_examples() {
	for cmd in ['config default-apps', 'config materialize', 'config gui'] {
		h := command_help(cmd)
		assert h.contains('Examples:')
	}
}

fn test_batch2_json_and_quiet_modes() {
	b2_dispatch_setup()
	assert dispatch(['horneroctl', '--json', 'config', 'default-apps', 'list']) == 0
	assert dispatch(['horneroctl', '--quiet', 'config', 'default-apps', 'list']) == 0
	assert dispatch(['horneroctl', '--json', 'config', 'gui']) == 0
	assert dispatch(['horneroctl', '--json', 'config', 'materialize', '--dest',
		'/tmp/hx-batch2-dtest/dest', '--dry-run']) == 0
	assert dispatch(['horneroctl', '--quiet', 'config', 'gui', '--pane', 'appearance']) == 0
	b2_dispatch_teardown()
}
