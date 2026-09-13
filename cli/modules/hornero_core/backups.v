module hornero_core

import os

// Backup backend: dotfiles/config backups materialized on disk.
//
// `dots-backup` (dotfiles reference, read-only) writes `<backup-dir>/`
// `*.zip` archives (`--backup-dir`, default `~/.dotfiles/backup`) and
// lists them with `--list`. Listing here is a native reader of the same
// directory (no backend process needed, mirroring `preset list`).
// Scheduling (`schedule`) is documentation-only by design: horneroctl
// prints the cron/systemd recipe and never installs it. Create/restore
// stay out until a pinned non-interactive backend lands (the legacy
// rollback/register flows prompt, which the CLI contract forbids).

// resolve_backup_dir locates materialized backups.
// Override with HORNERO_BACKUP_DIR.
pub fn resolve_backup_dir() string {
	env := os.getenv('HORNERO_BACKUP_DIR')
	if env.len > 0 {
		return env
	}
	return os.join_path(os.home_dir(), '.dotfiles', 'backup')
}

pub struct BackupEntry {
pub:
	name string
	size string
}

// list_backups returns materialized `*.zip` backups sorted by name,
// mirroring the `dots-backup --list` enumeration.
pub fn list_backups() ![]BackupEntry {
	dir := resolve_backup_dir()
	if !os.is_dir(dir) {
		return error('no backups at ${dir}. Set HORNERO_BACKUP_DIR.\nExample: horneroctl backup list --json')
	}
	files := os.ls(dir)!
	mut names := []string{}
	for f in files {
		if !f.ends_with('.zip') {
			continue
		}
		if !os.is_file(os.join_path(dir, f)) {
			continue
		}
		names << f
	}
	names.sort()
	mut backups := []BackupEntry{}
	for n in names {
		size := os.file_size(os.join_path(dir, n))
		backups << BackupEntry{
			name: n
			size: size.str()
		}
	}
	return backups
}

// backup_list_report implements `backup list` (read-only).
pub fn backup_list_report() CommandResult {
	backups := list_backups() or { return fail_result('backup list', err.msg()) }
	mut lines := []string{}
	mut names := []string{}
	for b in backups {
		names << b.name
		lines << '${b.name} (${b.size} bytes)'
	}
	lines << '${backups.len} backup(s) in ${resolve_backup_dir()}'
	return ok_result('backup list', lines.join('\n'), {
		'count': backups.len.str()
		'names': names.join(',')
		'dir':   resolve_backup_dir()
	})
}

// backup_schedule_report implements `backup schedule` (read-only): it
// prints the cron + systemd recipes for automatic backups and never
// installs anything. Copy-paste the block that fits the host.
pub fn backup_schedule_report() CommandResult {
	dir := resolve_backup_dir()
	lines := [
		'Automatic backups are documented, not installed.',
		'Pick one recipe and install it manually:',
		'',
		'cron (daily at 02:00):',
		'  0 2 * * * bash ${os.home_dir()}/.local/bin/dots-backup --backup-dir ${dir}',
		'',
		'systemd user timer (~/.config/systemd/user/hornero-backup.timer + .service):',
		'  [Unit] Description=hornero daily backup',
		'  [Service] Type=oneshot ExecStart=${os.home_dir()}/.local/bin/dots-backup --backup-dir ${dir}',
		'  [Timer] OnCalendar=daily Persistent=true',
		'  [Install] WantedBy=timers.target',
		'',
		'Then: systemctl --user daemon-reload && systemctl --user enable --now hornero-backup.timer',
	]
	return ok_result('backup schedule', lines.join('\n'), {
		'dir': dir
	})
}
