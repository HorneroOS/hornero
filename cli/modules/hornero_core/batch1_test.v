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
	b1_write('${b1_root}/snapshots/config_20260101_020000/metadata.json', '{"id":"config_20260101_020000","timestamp":"2026-01-01T02:00:00","hostname":"den","dotfiles_commit":"abc123"}')
	b1_write('${b1_root}/snapshots/config_20260201_020000/metadata.json', '{"id":"config_20260201_020000","timestamp":"2026-02-01T02:00:00","hostname":"den","dotfiles_commit":"def456"}')
	os.mkdir_all('${b1_root}/snapshots/junkdir') or { assert false }
	os.setenv('HORNERO_SNAPSHOTS_DIR', '${b1_root}/snapshots', true)
	os.setenv('HORNERO_CONFIG_MANAGER_BIN', '/nonexistent-config-manager-hornero-test',
		true)
}

fn b1_teardown_snapshots() {
	os.unsetenv('HORNERO_SNAPSHOTS_DIR')
	os.unsetenv('HORNERO_CONFIG_MANAGER_BIN')
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
	assert d.message.contains('--create')
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
	assert d.message.contains('--restore config_20260101_020000')
	b1_teardown_snapshots()
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
	bin := '${b1_root}/bin/dots-checkupdates'
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
	b1_write('${b1_root}/backups/dotfiles_backup_01.zip', 'fake-zip-a')
	b1_write('${b1_root}/backups/dotfiles_backup_02.zip', 'fake-zip-b-longer')
	b1_write('${b1_root}/backups/notes.txt', 'not a backup')
	os.setenv('HORNERO_BACKUP_DIR', '${b1_root}/backups', true)
	backups := list_backups() or {
		assert false
		return
	}
	assert backups.len == 2
	assert backups[0].name == 'dotfiles_backup_01.zip'
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
