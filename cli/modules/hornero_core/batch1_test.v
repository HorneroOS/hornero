module hornero_core

import os

// Batch-1 fixtures: everything lives under /tmp, env overrides isolate
// HOME, and each test unsets what it sets (no network, no compositor).

const b1_root = '/tmp/hx-batch1-test'

fn b1_write(path string, content string) {
	os.mkdir_all(os.dir(path)) or { assert false }
	os.write_file(path, content) or { assert false }
}

fn b1_setup_snapshots() {
	b1_write('${b1_root}/snapshots/config_20260101_020000/metadata.json', '{"id":"config_20260101_020000","timestamp":"2026-01-01T02:00:00","hostname":"den"}')
	b1_write('${b1_root}/snapshots/config_20260201_020000/metadata.json', '{"id":"config_20260201_020000","timestamp":"2026-02-01T02:00:00","hostname":"den"}')
	os.mkdir_all('${b1_root}/snapshots/junkdir') or { assert false }
	os.setenv('HORNERO_SNAPSHOTS_DIR', '${b1_root}/snapshots', true)
}

fn b1_teardown_snapshots() {
	os.unsetenv('HORNERO_SNAPSHOTS_DIR')
}

fn test_snapshot_list_reads_materialized_dirs() {
	b1_setup_snapshots()
	snaps := list_snapshots() or {
		assert false
		return
	}
	assert snaps.len == 2
	assert snaps[0].id == 'config_20260101_020000'
	assert snaps[1].hostname == 'den'
	r2 := snapshot_list_report()
	assert r2.ok
	assert r2.command == 'config snapshot list'
	assert r2.data['count'] == '2'
	assert r2.message.contains('2 snapshot(s)')
	b1_teardown_snapshots()
}

fn test_snapshot_list_missing_dir_fails_cleanly() {
	os.setenv('HORNERO_SNAPSHOTS_DIR', '/nonexistent-snapshots-hornero-test', true)
	r := snapshot_list_report()
	assert !r.ok
	assert r.message.contains('HORNERO_SNAPSHOTS_DIR')
	os.unsetenv('HORNERO_SNAPSHOTS_DIR')
}

fn test_snapshot_create_needs_yes_and_previews() {
	b1_setup_snapshots()
	r := snapshot_create_report(SnapshotCreateOptions{})
	assert !r.ok
	assert r.message.contains('--yes')
	d := snapshot_create_report(SnapshotCreateOptions{
		dry_run: true
	})
	assert d.ok
	assert d.data['dry_run'] == 'true'
	assert d.message.contains('metadata.json')
	b1_teardown_snapshots()
}

fn test_snapshot_restore_validates_and_previews() {
	b1_setup_snapshots()
	bad := snapshot_restore_report(SnapshotRestoreOptions{
		id:      '../escape'
		dry_run: true
	})
	assert !bad.ok
	assert bad.message.contains('invalid snapshot id')
	missing := snapshot_restore_report(SnapshotRestoreOptions{
		id: 'config_20260101_020000'
	})
	assert !missing.ok
	assert missing.message.contains('--yes')
	d := snapshot_restore_report(SnapshotRestoreOptions{
		id:      'config_20260101_020000'
		dry_run: true
	})
	assert d.ok
	assert d.message.contains('config_20260101_020000')
	b1_teardown_snapshots()
}

fn test_snapshot_create_native_round_trip() {
	// Native port: create writes metadata + tarball + latest under a
	// redirected HOME and snapshots dir; list sees the new snapshot.
	os.rmdir_all(b1_root + '/native-snaps') or {}
	old_home := os.getenv('HOME')
	os.setenv('HOME', b1_root + '/fakehome', true)
	os.setenv('XDG_CONFIG_HOME', b1_root + '/fakehome/.config', true)
	os.mkdir_all(b1_root + '/fakehome/.config/hornero') or { assert false }
	os.write_file(b1_root + '/fakehome/.config/hornero/shell.json', 'v1') or { assert false }
	os.setenv('HORNERO_SNAPSHOTS_DIR', b1_root + '/native-snaps', true)
	r := snapshot_create_report(SnapshotCreateOptions{ yes: true })
	assert r.ok
	assert r.message.contains('Snapshot created:')
	meta := os.read_file(r.data['dir'] + '/metadata.json') or { '' }
	assert meta.contains(r.data['id'])
	assert os.is_file(r.data['dir'] + '/hornero-config.tar.gz')
	assert os.is_link(b1_root + '/native-snaps/latest')
	l := snapshot_list_report()
	assert l.ok
	assert l.message.contains(r.data['id'])
	os.setenv('HOME', old_home, true)
	os.unsetenv('XDG_CONFIG_HOME')
	os.unsetenv('HORNERO_SNAPSHOTS_DIR')
	os.rmdir_all(b1_root + '/fakehome') or {}
	os.rmdir_all(b1_root + '/native-snaps') or {}
}

fn test_snapshot_restore_native_round_trip() {
	// Native port: modify a file after create, restore brings the
	// original back; a pre-restore backup snapshot is recorded too.
	os.rmdir_all(b1_root + '/native-snaps2') or {}
	old_home := os.getenv('HOME')
	os.setenv('HOME', b1_root + '/fakehome2', true)
	os.setenv('XDG_CONFIG_HOME', b1_root + '/fakehome2/.config', true)
	os.mkdir_all(b1_root + '/fakehome2/.config/hornero') or { assert false }
	os.write_file(b1_root + '/fakehome2/.config/hornero/shell.json', 'v1') or { assert false }
	os.setenv('HORNERO_SNAPSHOTS_DIR', b1_root + '/native-snaps2', true)
	c := snapshot_create_report(SnapshotCreateOptions{ yes: true })
	assert c.ok
	id := c.data['id']
	os.write_file(b1_root + '/fakehome2/.config/hornero/shell.json', 'v2') or { assert false }
	r := snapshot_restore_report(SnapshotRestoreOptions{
		id:  id
		yes: true
	})
	assert r.ok
	assert r.message.contains('Restore completed!')
	assert os.read_file(b1_root + '/fakehome2/.config/hornero/shell.json') or { '' } == 'v1'
	l := snapshot_list_report()
	assert l.ok
	assert l.data['count'] == '2'
	os.setenv('HOME', old_home, true)
	os.unsetenv('XDG_CONFIG_HOME')
	os.unsetenv('HORNERO_SNAPSHOTS_DIR')
	os.rmdir_all(b1_root + '/fakehome2') or {}
	os.rmdir_all(b1_root + '/native-snaps2') or {}
}

fn test_snapshot_without_config_archive_is_not_reported_as_restored() {
	root := b1_root + '/snapshot-without-config'
	home := root + '/home'
	config_home := home + '/.config'
	snapshots := root + '/snapshots'
	old_home := os.getenv('HOME')
	old_config := os.getenv('XDG_CONFIG_HOME')
	old_snapshots := os.getenv('HORNERO_SNAPSHOTS_DIR')
	os.rmdir_all(root) or {}
	os.mkdir_all(home) or { assert false }
	os.setenv('HOME', home, true)
	os.setenv('XDG_CONFIG_HOME', config_home, true)
	os.setenv('HORNERO_SNAPSHOTS_DIR', snapshots, true)
	created := snapshot_create_report(SnapshotCreateOptions{ yes: true })
	assert created.ok
	assert !os.is_file(created.data['dir'] + '/hornero-config.tar.gz')
	os.mkdir_all(config_home + '/hornero') or { assert false }
	os.write_file(config_home + '/hornero/shell.json', 'new configuration') or { assert false }
	restored := snapshot_restore_report(SnapshotRestoreOptions{
		id:  created.data['id']
		yes: true
	})
	assert !restored.ok
	assert restored.message.contains('contains no Hornero configuration archive')
	assert (os.read_file(config_home + '/hornero/shell.json') or { '' }) == 'new configuration'
	os.setenv('HOME', old_home, true)
	if old_config.len > 0 {
		os.setenv('XDG_CONFIG_HOME', old_config, true)
	} else {
		os.unsetenv('XDG_CONFIG_HOME')
	}
	if old_snapshots.len > 0 {
		os.setenv('HORNERO_SNAPSHOTS_DIR', old_snapshots, true)
	} else {
		os.unsetenv('HORNERO_SNAPSHOTS_DIR')
	}
	os.rmdir_all(root) or {}
}

fn test_snapshot_config_home_empty_value_falls_back_to_home() {
	old_home := os.getenv('HOME')
	old_config := os.getenv('XDG_CONFIG_HOME')
	os.setenv('HOME', b1_root + '/empty-xdg-home', true)
	os.setenv('XDG_CONFIG_HOME', '', true)
	assert snapshot_config_home() == b1_root + '/empty-xdg-home/.config'
	os.setenv('HOME', old_home, true)
	if old_config.len > 0 {
		os.setenv('XDG_CONFIG_HOME', old_config, true)
	} else {
		os.unsetenv('XDG_CONFIG_HOME')
	}
}

fn test_snapshot_create_fails_when_tar_fails() {
	root := b1_root + '/tar-create-failure'
	home := root + '/home'
	config_home := home + '/.config'
	snapshots := root + '/snapshots'
	fake_tar := root + '/tar'
	old_home := os.getenv('HOME')
	old_config := os.getenv('XDG_CONFIG_HOME')
	old_snapshots := os.getenv('HORNERO_SNAPSHOTS_DIR')
	old_tar := os.getenv('HORNERO_TAR_BIN')
	os.rmdir_all(root) or {}
	os.mkdir_all(config_home + '/hornero') or { assert false }
	os.write_file(config_home + '/hornero/shell.json', '{}') or { assert false }
	os.write_file(fake_tar, '#!/bin/sh\necho simulated archive error >&2\nexit 7\n') or { assert false }
	os.chmod(fake_tar, 0o755) or { assert false }
	os.setenv('HOME', home, true)
	os.setenv('XDG_CONFIG_HOME', config_home, true)
	os.setenv('HORNERO_SNAPSHOTS_DIR', snapshots, true)
	os.setenv('HORNERO_TAR_BIN', fake_tar, true)
	r := snapshot_create_report(SnapshotCreateOptions{ yes: true })
	assert !r.ok
	assert r.message.contains('exit 7')
	assert r.message.contains('simulated archive error')
	assert !os.is_link(snapshots + '/latest')
	entries := os.ls(snapshots) or { []string{} }
	assert entries.len == 0
	os.setenv('HOME', old_home, true)
	if old_config.len > 0 {
		os.setenv('XDG_CONFIG_HOME', old_config, true)
	} else {
		os.unsetenv('XDG_CONFIG_HOME')
	}
	if old_snapshots.len > 0 {
		os.setenv('HORNERO_SNAPSHOTS_DIR', old_snapshots, true)
	} else {
		os.unsetenv('HORNERO_SNAPSHOTS_DIR')
	}
	if old_tar.len > 0 {
		os.setenv('HORNERO_TAR_BIN', old_tar, true)
	} else {
		os.unsetenv('HORNERO_TAR_BIN')
	}
	os.rmdir_all(root) or {}
}

fn test_snapshot_restore_reports_tar_extraction_failure() {
	root := b1_root + '/tar-restore-failure'
	home := root + '/home'
	config_home := home + '/.config'
	snapshots := root + '/snapshots'
	fake_tar := root + '/tar'
	old_home := os.getenv('HOME')
	old_config := os.getenv('XDG_CONFIG_HOME')
	old_snapshots := os.getenv('HORNERO_SNAPSHOTS_DIR')
	old_tar := os.getenv('HORNERO_TAR_BIN')
	os.rmdir_all(root) or {}
	os.mkdir_all(config_home + '/hornero') or { assert false }
	os.write_file(config_home + '/hornero/shell.json', 'before') or { assert false }
	os.setenv('HOME', home, true)
	os.setenv('XDG_CONFIG_HOME', config_home, true)
	os.setenv('HORNERO_SNAPSHOTS_DIR', snapshots, true)
	os.setenv('HORNERO_TAR_BIN', '/bin/tar', true)
	created := snapshot_create_report(SnapshotCreateOptions{ yes: true })
	assert created.ok
	os.write_file(config_home + '/hornero/shell.json', 'after') or { assert false }
	os.rmdir_all(config_home) or { assert false }
	os.write_file(fake_tar, '#!/bin/sh\nif [ "$1" = "-xzf" ]; then echo simulated extraction error >&2; exit 9; fi\nexec /bin/tar "$@"\n') or { assert false }
	os.chmod(fake_tar, 0o755) or { assert false }
	os.setenv('HORNERO_TAR_BIN', fake_tar, true)
	restored := snapshot_restore_report(SnapshotRestoreOptions{
		id:  created.data['id']
		yes: true
	})
	assert !restored.ok
	assert restored.message.contains('exit 9')
	assert restored.message.contains('simulated extraction error')
	assert os.is_dir(config_home)
	os.setenv('HOME', old_home, true)
	if old_config.len > 0 {
		os.setenv('XDG_CONFIG_HOME', old_config, true)
	} else {
		os.unsetenv('XDG_CONFIG_HOME')
	}
	if old_snapshots.len > 0 {
		os.setenv('HORNERO_SNAPSHOTS_DIR', old_snapshots, true)
	} else {
		os.unsetenv('HORNERO_SNAPSHOTS_DIR')
	}
	if old_tar.len > 0 {
		os.setenv('HORNERO_TAR_BIN', old_tar, true)
	} else {
		os.unsetenv('HORNERO_TAR_BIN')
	}
	os.rmdir_all(root) or {}
}

fn test_package_check_dry_run_needs_no_backend() {
	os.setenv('HORNERO_CHECKUPDATES_BIN', '/nonexistent-checkupdates-hornero-test', true)
	c := package_check_report(PackageCheckOptions{
		dry_run: true
	})
	assert c.ok
	assert c.data['dry_run'] == 'true'
	u := package_updates_report(PackageCheckOptions{
		dry_run: true
	})
	assert u.ok
	os.unsetenv('HORNERO_CHECKUPDATES_BIN')
}

fn test_package_check_missing_backend_fails_cleanly() {
	// Hermetic: isolate HOME (no ~/.local/bin helper) and PATH (no
	// checkupdates) so resolution must fail cleanly, never panic.
	old_home := os.getenv('HOME')
	old_path := os.getenv('PATH')
	os.setenv('HOME', b1_root, true)
	os.setenv('PATH', '/nonexistent-path-hornero-test', true)
	os.unsetenv('HORNERO_CHECKUPDATES_BIN')
	r := package_check_report(PackageCheckOptions{})
	assert r.command == 'package check'
	assert !r.ok
	assert r.message.contains('HORNERO_CHECKUPDATES_BIN')
	os.setenv('HOME', old_home, true)
	os.setenv('PATH', old_path, true)
}

fn test_package_updates_counts_backend_lines() {
	bin := '${b1_root}/bin/checkupdates'
	b1_write(bin, '#!/bin/sh\nprintf "pkg-a 1.0 -> 1.1\\npkg-b 2.0 -> 2.1\\npkg-c 3.0 -> 3.1\\n"')
	os.chmod(bin, 0o755) or { assert false }
	os.setenv('HORNERO_CHECKUPDATES_BIN', bin, true)
	c := package_check_report(PackageCheckOptions{})
	assert c.ok
	assert c.data['count'] == '3'
	assert c.message.contains('pkg-a')
	u := package_updates_report(PackageCheckOptions{})
	assert u.ok
	assert u.message == '3 update(s) pending'
	assert u.data['count'] == '3'
	os.unsetenv('HORNERO_CHECKUPDATES_BIN')
}

fn test_backup_list_reads_materialized_archives() {
	os.mkdir_all('${b1_root}/backups') or { assert false }
	b1_write('${b1_root}/backups/hornero-config_01.tar.gz', 'fake-archive-a')
	b1_write('${b1_root}/backups/hornero-config_02.tar.gz', 'fake-archive-b-longer')
	b1_write('${b1_root}/backups/notes.txt', 'not a backup')
	os.setenv('HORNERO_BACKUP_DIR', '${b1_root}/backups', true)
	backups := list_backups() or {
		assert false
		return
	}
	assert backups.len == 2
	assert backups[0].name == 'hornero-config_01.tar.gz'
	r := backup_list_report()
	assert r.ok
	assert r.command == 'backup list'
	assert r.data['count'] == '2'
	assert r.message.contains('2 backup(s)')
	os.unsetenv('HORNERO_BACKUP_DIR')
}

fn test_backup_list_missing_dir_fails_cleanly() {
	os.setenv('HORNERO_BACKUP_DIR', '/nonexistent-backups-hornero-test', true)
	r := backup_list_report()
	assert !r.ok
	assert r.message.contains('HORNERO_BACKUP_DIR')
	os.unsetenv('HORNERO_BACKUP_DIR')
}

fn test_backup_schedule_is_documented_not_installed() {
	r := backup_schedule_report()
	assert r.ok
	assert r.command == 'backup schedule'
	assert r.message.contains('not installed')
	assert r.message.contains('cron')
	assert r.message.contains('systemd')
}
