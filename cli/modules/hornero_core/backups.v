module hornero_core

import os

// Hornero configuration archives live in user state. Scheduling is
// documentation-only; create and restore operate on Hornero config only.

// resolve_backup_dir locates materialized backups.
// Override with HORNERO_BACKUP_DIR.
pub fn resolve_backup_dir() string {
	env := os.getenv('HORNERO_BACKUP_DIR')
	if env.len > 0 {
		return env
	}
	mut base := os.getenv('XDG_STATE_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.local', 'state')
	}
	return os.join_path(base, 'hornero', 'backups')
}

pub struct BackupEntry {
pub:
	name string
	size string
}

// list_backups returns Hornero configuration archives sorted by name.
pub fn list_backups() ![]BackupEntry {
	dir := resolve_backup_dir()
	if !os.is_dir(dir) {
		return error('no backups at ${dir}. Set HORNERO_BACKUP_DIR.\nExample: horneroctl backup list --json')
	}
	files := os.ls(dir)!
	mut names := []string{}
	for f in files {
		if !f.ends_with('.tar.gz') {
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
		'  0 2 * * * horneroctl backup create --yes',
		'',
		'systemd user timer (~/.config/systemd/user/hornero-backup.timer + .service):',
		'  [Unit] Description=hornero daily backup',
		'  [Service] Type=oneshot ExecStart=horneroctl backup create --yes',
		'  [Timer] OnCalendar=daily Persistent=true',
		'  [Install] WantedBy=timers.target',
		'',
		'Then: systemctl --user daemon-reload && systemctl --user enable --now hornero-backup.timer',
	]
	return ok_result('backup schedule', lines.join('\n'), {
		'dir': dir
	})
}
