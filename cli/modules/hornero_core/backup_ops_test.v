module hornero_core

import os

fn backup_ops_test_save_env(keys []string) map[string]string {
	mut saved := map[string]string{}
	for k in keys {
		saved[k] = os.getenv(k)
	}
	return saved
}

fn backup_ops_test_restore_env(saved map[string]string) {
	for k, v in saved {
		if v.len == 0 {
			os.unsetenv(k)
		} else {
			os.setenv(k, v, true)
		}
	}
}

fn backup_ops_test_setup() {
	os.mkdir_all('/tmp/hx-backupops-test/source/sub') or { assert false }
	os.write_file('/tmp/hx-backupops-test/source/file.txt', 'hello') or { assert false }
	os.write_file('/tmp/hx-backupops-test/source/sub/nested.txt', 'nested') or { assert false }
	os.mkdir_all('/tmp/hx-backupops-test/backups') or { assert false }
	os.write_file('/tmp/hx-backupops-test/backups/legacy_dotfiles_backup.zip', 'fake-zip') or {
		assert false
	}
	os.setenv('HORNERO_BACKUP_DIR', '/tmp/hx-backupops-test/backups', true)
	os.setenv('HORNERO_BACKUP_SOURCE', '/tmp/hx-backupops-test/source', true)
	os.setenv('HORNERO_TAR_BIN', '/bin/tar', true)
}

fn backup_ops_test_teardown() {
	os.unsetenv('HORNERO_BACKUP_DIR')
	os.unsetenv('HORNERO_BACKUP_SOURCE')
	os.unsetenv('HORNERO_TAR_BIN')
	os.rmdir_all('/tmp/hx-backupops-test') or {}
}

fn test_backup_create_needs_yes() {
	r := backup_create_report(BackupCreateOptions{})
	assert !r.ok
	assert r.message.contains('--yes')
}

fn test_backup_restore_needs_yes() {
	r := backup_restore_report(BackupRestoreOptions{
		id: 'whatever'
	})
	assert !r.ok
	assert r.message.contains('--yes')
}

fn test_backup_restore_missing_id() {
	r := backup_restore_report(BackupRestoreOptions{
		dry_run: true
	})
	assert !r.ok
	assert r.message.contains('missing backup id')
}

fn test_backup_restore_invalid_id() {
	backup_ops_test_setup()
	r := backup_restore_report(BackupRestoreOptions{
		id:      '../escape'
		dry_run: true
	})
	assert !r.ok
	assert r.message.contains('invalid backup id')
	backup_ops_test_teardown()
}

fn test_backup_restore_unknown_id() {
	backup_ops_test_setup()
	r := backup_restore_report(BackupRestoreOptions{
		id:      'no-such-backup'
		dry_run: true
	})
	assert !r.ok
	assert r.message.contains('not found')
	backup_ops_test_teardown()
}

fn test_backup_create_and_restore_roundtrip() {
	// Real tar round-trip inside the hermetic /tmp tree.
	backup_ops_test_setup()
	c := backup_create_report(BackupCreateOptions{
		yes: true
	})
	assert c.ok
	assert c.message.contains('Backup created at')
	archive := c.data['archive']
	assert os.is_file(archive)
	assert archive.ends_with('.tar.gz')
	// Listing sees both the new tarball and the legacy zip.
	l := backup_list_report()
	assert l.ok
	assert l.message.contains('.tar.gz')
	assert l.message.contains('.zip')
	// Corrupt the source, restore, verify contents.
	os.write_file('/tmp/hx-backupops-test/source/file.txt', 'corrupted') or { assert false }
	base := os.file_name(archive)
	r := backup_restore_report(BackupRestoreOptions{
		id:  base
		yes: true
	})
	assert r.ok
	after := os.read_file('/tmp/hx-backupops-test/source/file.txt') or { '' }
	assert after == 'hello'
	nested := os.read_file('/tmp/hx-backupops-test/source/sub/nested.txt') or { '' }
	assert nested == 'nested'
	backup_ops_test_teardown()
}

fn test_backup_create_dry_run_previews() {
	backup_ops_test_setup()
	r := backup_create_report(BackupCreateOptions{
		dry_run: true
	})
	assert r.ok
	assert r.message.contains('would run:')
	assert r.message.contains('tar')
	backup_ops_test_teardown()
}
