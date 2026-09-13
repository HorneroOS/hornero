module hornero_cli

import os

// Batch-1 dispatch fixtures reuse the core /tmp tree; each test sets the
// overrides it needs and unsets them afterwards.
fn b1_dispatch_setup() {
	os.mkdir_all('/tmp/hx-batch1-dtest/snapshots/config_20260101_020000') or { assert false }
	os.write_file('/tmp/hx-batch1-dtest/snapshots/config_20260101_020000/metadata.json',
		'{"id":"config_20260101_020000","timestamp":"2026-01-01T02:00:00","hostname":"den","dotfiles_commit":"abc123"}') or {
		assert false
	}
	os.mkdir_all('/tmp/hx-batch1-dtest/backups') or { assert false }
	os.write_file('/tmp/hx-batch1-dtest/backups/dotfiles_backup_01.zip', 'fake-zip') or {
		assert false
	}
	os.mkdir_all('/tmp/hx-batch1-dtest/bin') or { assert false }
	os.write_file('/tmp/hx-batch1-dtest/bin/dots-checkupdates', '#!/bin/sh\nprintf "pkg-a 1.0 -> 1.1\\n"') or {
		assert false
	}
	os.chmod('/tmp/hx-batch1-dtest/bin/dots-checkupdates', 0o755) or { assert false }
	os.setenv('HORNERO_SNAPSHOTS_DIR', '/tmp/hx-batch1-dtest/snapshots', true)
	os.setenv('HORNERO_CONFIG_MANAGER_BIN', '/nonexistent-config-manager-hornero-test',
		true)
	os.setenv('HORNERO_CHECKUPDATES_BIN', '/tmp/hx-batch1-dtest/bin/dots-checkupdates',
		true)
	os.setenv('HORNERO_BACKUP_DIR', '/tmp/hx-batch1-dtest/backups', true)
}

fn b1_dispatch_teardown() {
	os.unsetenv('HORNERO_SNAPSHOTS_DIR')
	os.unsetenv('HORNERO_CONFIG_MANAGER_BIN')
	os.unsetenv('HORNERO_CHECKUPDATES_BIN')
	os.unsetenv('HORNERO_BACKUP_DIR')
}

fn test_dispatch_config_snapshot() {
	b1_dispatch_setup()
	assert dispatch(['horneroctl', 'config', 'snapshot', 'list']) == 0
	assert dispatch(['horneroctl', 'config', 'snapshot', 'create', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'config', 'snapshot', 'create']) == 1
	assert dispatch(['horneroctl', 'config', 'snapshot', 'restore', 'config_20260101_020000',
		'--dry-run']) == 0
	assert dispatch(['horneroctl', 'config', 'snapshot', 'restore', 'config_20260101_020000']) == 1
	assert dispatch(['horneroctl', 'config', 'snapshot', 'restore']) == 2
	assert dispatch(['horneroctl', 'config', 'snapshot', 'bogus']) == 2
	assert dispatch(['horneroctl', 'config', 'snapshot', '--help']) == 0
	b1_dispatch_teardown()
}

fn test_dispatch_package() {
	b1_dispatch_setup()
	assert dispatch(['horneroctl', 'package', 'check']) == 0
	assert dispatch(['horneroctl', 'package', 'check', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'package', 'updates']) == 0
	assert dispatch(['horneroctl', 'package', '--help']) == 0
	// Privileged/unpinned siblings stay explicit deferrals, never invented.
	assert dispatch(['horneroctl', 'package', 'upgrade']) == 2
	assert dispatch(['horneroctl', 'package', 'deps']) == 2
	assert dispatch(['horneroctl', 'package', 'bogus']) == 2
	assert dispatch(['horneroctl', 'package', 'check', '--bogus']) == 2
	b1_dispatch_teardown()
}

fn test_dispatch_backup() {
	b1_dispatch_setup()
	assert dispatch(['horneroctl', 'backup', 'list']) == 0
	assert dispatch(['horneroctl', 'backup', 'schedule']) == 0
	assert dispatch(['horneroctl', 'backup', '--help']) == 0
	// Unpinned siblings stay explicit deferrals, never invented.
	assert dispatch(['horneroctl', 'backup', 'create']) == 2
	assert dispatch(['horneroctl', 'backup', 'restore']) == 2
	assert dispatch(['horneroctl', 'backup', 'bogus']) == 2
	assert dispatch(['horneroctl', 'backup', 'list', '--bogus']) == 2
	b1_dispatch_teardown()
}

fn test_batch1_dry_run_needs_no_backend() {
	// Hermetic: nonexistent backends; dry-run previews must still pass.
	os.setenv('HORNERO_CONFIG_MANAGER_BIN', '/nonexistent-config-manager-hornero-test',
		true)
	assert dispatch(['horneroctl', 'config', 'snapshot', 'create', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'config', 'snapshot', 'restore', 'config_20260101_020000',
		'--dry-run']) == 0
	os.unsetenv('HORNERO_CONFIG_MANAGER_BIN')
	os.setenv('HORNERO_CHECKUPDATES_BIN', '/nonexistent-checkupdates-hornero-test', true)
	assert dispatch(['horneroctl', 'package', 'check', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'package', 'updates', '--dry-run']) == 0
	os.unsetenv('HORNERO_CHECKUPDATES_BIN')
}

fn test_batch1_help_has_examples() {
	for cmd in ['config snapshot', 'package', 'backup'] {
		h := command_help(cmd)
		assert h.contains('Examples:')
	}
}

fn test_batch1_json_and_quiet_modes() {
	b1_dispatch_setup()
	assert dispatch(['horneroctl', '--json', 'backup', 'list']) == 0
	assert dispatch(['horneroctl', '--quiet', 'backup', 'list']) == 0
	assert dispatch(['horneroctl', '--json', 'backup', 'schedule']) == 0
	assert dispatch(['horneroctl', '--json', 'package', 'updates']) == 0
	assert dispatch(['horneroctl', '--quiet', 'config', 'snapshot', 'list']) == 0
	b1_dispatch_teardown()
}
