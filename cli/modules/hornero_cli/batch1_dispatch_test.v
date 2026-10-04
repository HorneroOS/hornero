module hornero_cli

import os

// Batch-1 dispatch fixtures reuse the core /tmp tree; each test sets the
// overrides it needs and unsets them afterwards. HOME and XDG_CONFIG_HOME
// are redirected so archive tests cannot read or write host configuration.
const b1_fake_home = '/tmp/hx-batch1-dtest/fakehome'

fn b1_dispatch_setup() {
	// A failed assert aborts the test process before teardown: start from
	// a clean tree so a previous crash can never leave real-home archives.
	os.rmdir_all('/tmp/hx-batch1-dtest') or {}
	os.mkdir_all(b1_fake_home + '/.config/app') or { assert false }
	os.mkdir_all(b1_fake_home + '/.config/hornero') or { assert false }
	os.mkdir_all(b1_fake_home + '/.local/bin') or { assert false }
	os.write_file(b1_fake_home + '/.config/app/conf', 'v1') or { assert false }
	os.write_file(b1_fake_home + '/.config/hornero/shell.json', '{}') or { assert false }
	// Remember whether HOME and XDG_CONFIG_HOME were set at all.
	if real := os.getenv_opt('HOME') {
		os.setenv('HX_B1_REAL_HOME', real, true)
		os.setenv('HX_B1_HOME_WAS_SET', '1', true)
	} else {
		os.unsetenv('HX_B1_HOME_WAS_SET')
		if os.getenv('HX_B1_XDG_CONFIG_HOME_WAS_SET') == '1' {
			os.setenv('XDG_CONFIG_HOME', os.getenv('HX_B1_REAL_XDG_CONFIG_HOME'), true)
		} else {
			os.unsetenv('XDG_CONFIG_HOME')
		}
		os.unsetenv('HX_B1_REAL_XDG_CONFIG_HOME')
		os.unsetenv('HX_B1_XDG_CONFIG_HOME_WAS_SET')
	}
	os.setenv('HOME', b1_fake_home, true)
	if real := os.getenv_opt('XDG_CONFIG_HOME') {
		os.setenv('HX_B1_REAL_XDG_CONFIG_HOME', real, true)
		os.setenv('HX_B1_XDG_CONFIG_HOME_WAS_SET', '1', true)
	} else {
		os.unsetenv('HX_B1_XDG_CONFIG_HOME_WAS_SET')
	}
	os.setenv('XDG_CONFIG_HOME', b1_fake_home + '/.config', true)
	os.mkdir_all('/tmp/hx-batch1-dtest/snapshots/config_20260101_020000') or { assert false }
	os.write_file('/tmp/hx-batch1-dtest/snapshots/config_20260101_020000/metadata.json',
		'{"id":"config_20260101_020000","timestamp":"2026-01-01T02:00:00","hostname":"den"}') or {
		assert false
	}
	os.mkdir_all('/tmp/hx-batch1-dtest/backups') or { assert false }
	os.write_file('/tmp/hx-batch1-dtest/backups/hornero-config_01.tar.gz', 'fake-archive') or { assert false }
	os.mkdir_all('/tmp/hx-batch1-dtest/bin') or { assert false }
	os.write_file('/tmp/hx-batch1-dtest/bin/checkupdates', '#!/bin/sh\nprintf "pkg-a 1.0 -> 1.1\\n"') or {
		assert false
	}
	os.chmod('/tmp/hx-batch1-dtest/bin/checkupdates', 0o755) or { assert false }
	os.setenv('HORNERO_SNAPSHOTS_DIR', '/tmp/hx-batch1-dtest/snapshots', true)
	os.setenv('HORNERO_CHECKUPDATES_BIN', '/tmp/hx-batch1-dtest/bin/checkupdates',
		true)
	os.setenv('HORNERO_BACKUP_DIR', '/tmp/hx-batch1-dtest/backups', true)
}

fn b1_dispatch_teardown() {
	if os.getenv('HX_B1_HOME_WAS_SET') == '1' {
		os.setenv('HOME', os.getenv('HX_B1_REAL_HOME'), true)
	} else {
		os.unsetenv('HOME')
	}
	os.unsetenv('HX_B1_REAL_HOME')
	os.unsetenv('HX_B1_HOME_WAS_SET')
	if os.getenv('HX_B1_XDG_CONFIG_HOME_WAS_SET') == '1' {
		os.setenv('XDG_CONFIG_HOME', os.getenv('HX_B1_REAL_XDG_CONFIG_HOME'), true)
	} else {
		os.unsetenv('XDG_CONFIG_HOME')
	}
	os.unsetenv('HX_B1_REAL_XDG_CONFIG_HOME')
	os.unsetenv('HX_B1_XDG_CONFIG_HOME_WAS_SET')
	os.rmdir_all('/tmp/hx-batch1-dtest') or {}
	os.unsetenv('HORNERO_SNAPSHOTS_DIR')
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

fn test_config_snapshot_help_is_present() {
	assert command_help('config snapshot').contains('Usage: horneroctl config snapshot')
}

fn test_dispatch_package() {
	b1_dispatch_setup()
	assert dispatch(['horneroctl', 'package', 'check']) == 0
	assert dispatch(['horneroctl', 'package', 'check', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'package', 'updates']) == 0
	assert dispatch(['horneroctl', 'package', '--help']) == 0
	// Privileged siblings: mutations refuse without --yes, preview clean.
	assert dispatch(['horneroctl', 'package', 'upgrade']) == 1
	assert dispatch(['horneroctl', 'package', 'upgrade', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'package', 'deps']) == 0
	assert dispatch(['horneroctl', 'package', 'deps', '--optional']) == 0
	assert dispatch(['horneroctl', 'package', 'deps', '--install']) == 1
	assert dispatch(['horneroctl', 'package', 'deps', '--install', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'package', 'bogus']) == 2
	assert dispatch(['horneroctl', 'package', 'check', '--bogus']) == 2
	assert dispatch(['horneroctl', 'package', 'check', '--yes']) == 2
	assert dispatch(['horneroctl', 'package', 'upgrade', '--install']) == 2
	b1_dispatch_teardown()
}

fn test_dispatch_backup() {
	b1_dispatch_setup()
	assert dispatch(['horneroctl', 'backup', 'list']) == 0
	assert dispatch(['horneroctl', 'backup', 'schedule']) == 0
	assert dispatch(['horneroctl', 'backup', '--help']) == 0
	// File-op siblings: mutations refuse without --yes, preview clean.
	assert dispatch(['horneroctl', 'backup', 'create']) == 1
	assert dispatch(['horneroctl', 'backup', 'create', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'backup', 'create', '--name', 'dtest', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'backup', 'restore']) == 2
	assert dispatch(['horneroctl', 'backup', 'restore', 'hornero-config_01.tar.gz']) == 1
	assert dispatch(['horneroctl', 'backup', 'restore', 'hornero-config_01.tar.gz', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'backup', 'restore', 'no-such-backup', '--dry-run']) == 1
	assert dispatch(['horneroctl', 'backup', 'bogus']) == 2
	assert dispatch(['horneroctl', 'backup', 'list', '--bogus']) == 2
	b1_dispatch_teardown()
}

fn test_batch1_dry_run_needs_no_backend() {
	// Hermetic: nonexistent backends; dry-run previews must still pass.
	assert dispatch(['horneroctl', 'config', 'snapshot', 'create', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'config', 'snapshot', 'restore', 'config_20260101_020000',
		'--dry-run']) == 0
	os.setenv('HORNERO_CHECKUPDATES_BIN', '/nonexistent-checkupdates-hornero-test', true)
	assert dispatch(['horneroctl', 'package', 'check', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'package', 'updates', '--dry-run']) == 0
	os.unsetenv('HORNERO_CHECKUPDATES_BIN')
	os.setenv('HORNERO_PKEXEC_BIN', '/nonexistent-pkexec-hornero-test', true)
	os.setenv('HORNERO_PACMAN_BIN', '/nonexistent-pacman-hornero-test', true)
	os.setenv('HORNERO_PARU_BIN', '/nonexistent-paru-hornero-test', true)
	assert dispatch(['horneroctl', 'package', 'upgrade', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'package', 'deps', '--install', '--dry-run']) == 0
	os.unsetenv('HORNERO_PKEXEC_BIN')
	os.unsetenv('HORNERO_PACMAN_BIN')
	os.unsetenv('HORNERO_PARU_BIN')
	os.setenv('HORNERO_TAR_BIN', '/nonexistent-tar-hornero-test', true)
	assert dispatch(['horneroctl', 'backup', 'create', '--dry-run']) == 0
	os.unsetenv('HORNERO_TAR_BIN')
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

fn test_dispatch_snapshot_never_touches_real_home() {
	b1_dispatch_setup()
	assert os.getenv('HOME') == b1_fake_home
	assert dispatch(['horneroctl', 'config', 'snapshot', 'create', '--yes']) == 0
	mut tarballs := 0
	for d in os.ls('/tmp/hx-batch1-dtest/snapshots') or { []string{} } {
		tb := '/tmp/hx-batch1-dtest/snapshots/${d}/hornero-config.tar.gz'
		if os.is_file(tb) {
			tarballs++
			// The fake home archives to a few hundred bytes, never the real home.
			assert os.file_size(tb) < 64 * 1024
		}
	}
	assert tarballs >= 1
	b1_dispatch_teardown()
	assert !os.exists('/tmp/hx-batch1-dtest')
}
