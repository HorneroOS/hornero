module hornero_core

import os
import time

// Backup create/restore backend: tar archives of a source tree inside
// the backup directory, ported from `dots-backup` (152 lines).
//
// - `create` writes `<backup-dir>/<stamp>_<name>.tar.gz` from the
//   source tree (default `~/.dotfiles`, `HORNERO_BACKUP_SOURCE`
//   override). The legacy script wrote gzip content under a `.zip`
//   name; new archives use `.tar.gz`, and `list` reads both.
// - `restore <id>` extracts one archive back into the source tree.
//   The legacy rollback deleted the target first (`rm -rf`); here tar
//   overwrites in place, which is safer and sufficient.
// - The legacy interactive cron flows (`--register-cron`,
//   `--unregister-cron` prompt) stay out by design: `schedule` prints
//   the recipe and never installs it.
//
// Mutations need --yes; --dry-run only previews.

// resolve_backup_source locates the tree `create` archives and
// `restore` extracts into. Override with HORNERO_BACKUP_SOURCE.
pub fn resolve_backup_source() string {
	env := os.getenv('HORNERO_BACKUP_SOURCE')
	if env.len > 0 {
		return env
	}
	return os.join_path(os.home_dir(), '.dotfiles')
}

// resolve_tar_bin locates tar. Override with HORNERO_TAR_BIN.
pub fn resolve_tar_bin() string {
	env := os.getenv('HORNERO_TAR_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('tar')
}

fn tar_or_fail(leaf string, dry_run bool) !string {
	bin := resolve_tar_bin()
	if bin.len == 0 {
		if dry_run {
			return 'tar'
		}
		return error('tar not found. Install tar, then retry.\nExample: horneroctl backup ${leaf} --dry-run')
	}
	return bin
}

// valid_backup_id rejects path escapes and empty ids, mirroring the
// snapshot-id guard in snapshots.v (ids travel to tar as argv and the
// archive name is built from them).
fn valid_backup_id(id string) bool {
	if id.len == 0 || id.contains('/') || id == '.' || id == '..' || id.contains('\x00') {
		return false
	}
	return true
}

// resolve_backup_archive maps a restore id to an existing archive: the
// exact filename first, then the `<id>.tar.gz` / `<id>.zip` stems.
fn resolve_backup_archive(id string) !string {
	dir := resolve_backup_dir()
	if !valid_backup_id(id) {
		return error('invalid backup id: ${id}.\nRun: horneroctl backup list')
	}
	candidates := [id, id + '.tar.gz', id + '.zip']
	for c in candidates {
		if valid_backup_id(c) && os.is_file(os.join_path(dir, c)) {
			return os.join_path(dir, c)
		}
	}
	return error('backup not found: ${id} in ${dir}.\nRun: horneroctl backup list')
}

pub struct BackupCreateOptions {
pub:
	name    string // archive name stem (default dotfiles_backup)
	dry_run bool
	yes     bool
}

// backup_create_report implements `backup create`: tar the source tree
// into a timestamped archive. Mutating: needs --yes; --dry-run only
// previews.
pub fn backup_create_report(opts BackupCreateOptions) CommandResult {
	if !opts.yes && !opts.dry_run {
		return fail_result('backup create', 'refusing to create a backup without --yes (preview with --dry-run).\nExample: horneroctl backup create --dry-run')
	}
	name := if opts.name.len > 0 { opts.name } else { 'dotfiles_backup' }
	if !valid_backup_id(name) {
		return fail_result('backup create', 'invalid backup name: ${name}.')
	}
	tar := tar_or_fail('create', opts.dry_run) or { return fail_result('backup create', err.msg()) }
	dir := resolve_backup_dir()
	source := resolve_backup_source()
	if !os.is_dir(source) && !opts.dry_run {
		return fail_result('backup create', 'backup source not found: ${source}. Set HORNERO_BACKUP_SOURCE.')
	}
	stamp := time.now().strftime('%Y%m%d_%H%M%S')
	archive := os.join_path(dir, '${stamp}_${name}.tar.gz')
	mut args := ['-czf', archive, '-C', source]
	if archive.starts_with(source + '/') {
		args << ['--exclude', archive[source.len + 1..]]
	} else if dir.starts_with(source + '/') {
		args << ['--exclude', dir[source.len + 1..]]
	}
	args << ['.']
	if opts.dry_run {
		rep := run_exec(ExecSpec{
			prog:    tar
			args:    args
			dry_run: true
		})
		return ok_result('backup create', 'would run: ${rep.command_line}', {
			'command_line': rep.command_line
			'archive':      archive
			'dry_run':      'true'
		})
	}
	if !os.is_dir(dir) {
		os.mkdir_all(dir) or {
			return fail_result('backup create', 'cannot create backup dir ${dir}: ${err}')
		}
	}
	rep := run_exec(ExecSpec{
		prog: tar
		args: args
	})
	if rep.ok {
		return ok_result('backup create', 'Backup created at ${archive}', {
			'command_line': rep.command_line
			'archive':      archive
		})
	}
	return fail_result('backup create', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
}

pub struct BackupRestoreOptions {
pub:
	id      string
	dry_run bool
	yes     bool
}

// backup_restore_report implements `backup restore <id>`: extract one
// archive back into the source tree. Mutating: needs --yes; --dry-run
// only previews.
pub fn backup_restore_report(opts BackupRestoreOptions) CommandResult {
	if !opts.yes && !opts.dry_run {
		return fail_result('backup restore', 'refusing to restore a backup without --yes (preview with --dry-run).\nExample: horneroctl backup restore ${opts.id} --dry-run')
	}
	if opts.id.len == 0 {
		return fail_result('backup restore', 'missing backup id.\nExample: horneroctl backup restore dotfiles_backup --dry-run')
	}
	archive := resolve_backup_archive(opts.id) or {
		return fail_result('backup restore', err.msg())
	}
	tar := tar_or_fail('restore ${opts.id}', opts.dry_run) or {
		return fail_result('backup restore', err.msg())
	}
	source := resolve_backup_source()
	if opts.dry_run {
		rep := run_exec(ExecSpec{
			prog:    tar
			args:    ['-xzf', archive, '-C', source]
			dry_run: true
		})
		return ok_result('backup restore', 'would run: ${rep.command_line}', {
			'command_line': rep.command_line
			'archive':      archive
			'dry_run':      'true'
		})
	}
	if !os.is_dir(source) {
		os.mkdir_all(source) or {
			return fail_result('backup restore', 'cannot create source dir ${source}: ${err}')
		}
	}
	rep := run_exec(ExecSpec{
		prog: tar
		args: ['-xzf', archive, '-C', source]
	})
	if rep.ok {
		return ok_result('backup restore', 'Rollback complete: restored ${archive} into ${source}',
			{
				'command_line': rep.command_line
				'archive':      archive
			})
	}
	return fail_result('backup restore', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
}
