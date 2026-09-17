module hornero_core

import os
import time
import x.json2

// Snapshot backend: configuration snapshots materialized on disk.
//
// `dots-config-manager` (dotfiles reference, read-only) owns the verbs:
// `--create` writes `$SNAPSHOTS_DIR/config_<timestamp>/` with a
// `metadata.json` (`id`, `timestamp`, `hostname`, `dotfiles_commit`),
// `--list` tabulates those directories, `--restore <id>` restores one.
// Listing here is a native reader of the same directories (no backend
// process needed, mirroring `preset list` / `theme list`); create/restore
// run natively too, with an explicit helper override still delegating
// to `dots-config-manager`.

// resolve_snapshots_dir locates materialized configuration snapshots: the
// canonical `hornero/*` location (docs/PATH_CONTRACT.md row 7) and the
// WRITE TARGET. Override with HORNERO_SNAPSHOTS_DIR.
pub fn resolve_snapshots_dir() string {
	env := os.getenv('HORNERO_SNAPSHOTS_DIR')
	if env.len > 0 {
		return env
	}
	mut base := os.getenv('XDG_CACHE_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.cache')
	}
	return os.join_path(base, 'hornero', 'snapshots')
}

// resolve_snapshots_dir_fallback is the legacy `dots/*` location (row 7).
// Reads only: nothing new is ever written here.
pub fn resolve_snapshots_dir_fallback() string {
	mut base := os.getenv('XDG_CACHE_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.cache')
	}
	return os.join_path(base, 'dots', 'snapshots')
}

// resolve_snapshots_dirs_for_read lists the directories actually read,
// canonical-first. An explicit HORNERO_SNAPSHOTS_DIR override wins outright;
// otherwise every existing directory is returned so readers merge both
// locations with canonical precedence.
pub fn resolve_snapshots_dirs_for_read() []string {
	env := os.getenv('HORNERO_SNAPSHOTS_DIR')
	if env.len > 0 {
		return [env]
	}
	mut dirs := []string{}
	canonical := resolve_snapshots_dir()
	fallback := resolve_snapshots_dir_fallback()
	if os.is_dir(canonical) {
		dirs << canonical
	}
	if os.is_dir(fallback) && fallback != canonical {
		dirs << fallback
	}
	return dirs
}

// resolve_config_manager locates the `dots-config-manager` backend CLI
// for explicit helper overrides. Override with HORNERO_CONFIG_MANAGER_BIN.
pub fn resolve_config_manager() string {
	env := os.getenv('HORNERO_CONFIG_MANAGER_BIN')
	if env.len > 0 {
		return env
	}
	home_helper := os.join_path(os.home_dir(), '.local', 'bin', 'dots-config-manager')
	if os.is_file(home_helper) {
		return home_helper
	}
	return find_on_path('dots-config-manager')
}

pub struct SnapshotEntry {
pub:
	id        string
	timestamp string
	hostname  string
	commit    string
}

// snapshot_metadata_file mirrors metadata.json; read and write share it
// (decode ignores the extra write-side keys, missing keys decode to '').
pub struct SnapshotSystemInfo {
pub:
	os     string
	kernel string
	shell  string
}

pub struct SnapshotMetadataFile {
pub:
	id              string
	timestamp       string
	hostname        string
	user            string
	dotfiles_commit string
	system_info     SnapshotSystemInfo
}

fn snapshot_or_unknown(s string) string {
	if s == '' {
		return 'unknown'
	}
	return s
}

// valid_snapshot_id rejects path escapes and empty ids, mirroring the
// theme-id guard in themes.v (ids also travel to the backend as argv).
fn valid_snapshot_id(id string) bool {
	if id.len == 0 || id.contains('/') || id == '.' || id == '..' || id.contains('\x00') {
		return false
	}
	return true
}

// read_snapshot parses one snapshot directory; the backend always writes
// metadata.json, so directories without a parseable one are skipped,
// mirroring how unparseable theme packs are skipped.
fn read_snapshot(dir string, id string) !SnapshotEntry {
	raw := os.read_file(os.join_path(dir, id, 'metadata.json'))!
	meta := json2.decode[SnapshotMetadataFile](raw) or {
		return error('snapshot is corrupt: ${id} (metadata.json is not an object)')
	}
	return SnapshotEntry{
		id:        id
		timestamp: snapshot_or_unknown(meta.timestamp)
		hostname:  snapshot_or_unknown(meta.hostname)
		commit:    snapshot_or_unknown(meta.dotfiles_commit)
	}
}

// list_snapshots returns materialized snapshots sorted by id.
// Canonical-first with legacy fallback: both directories are merged and a
// snapshot present in both resolves from the canonical side.
pub fn list_snapshots() ![]SnapshotEntry {
	dirs := resolve_snapshots_dirs_for_read().filter(os.is_dir(it))
	if dirs.len == 0 {
		explicit := resolve_snapshots_dirs_for_read()
		dir := if explicit.len > 0 { explicit[0] } else { resolve_snapshots_dir() }
		return error('no snapshots at ${dir}. Set HORNERO_SNAPSHOTS_DIR.\nExample: horneroctl config snapshot list --json')
	}
	mut seen := map[string]bool{}
	mut snaps := []SnapshotEntry{}
	for dir in dirs {
		entries := os.ls(dir) or { continue }
		for id in entries {
			if id in seen {
				continue
			}
			if !id.starts_with('config_') {
				continue
			}
			if !os.is_dir(os.join_path(dir, id)) {
				continue
			}
			if snap := read_snapshot(dir, id) {
				snaps << snap
				seen[id] = true
			} else {
				continue
			}
		}
	}
	snaps.sort(a.id < b.id)
	return snaps
}

// snapshot_list_report implements `config snapshot list` (read-only).
pub fn snapshot_list_report() CommandResult {
	snaps := list_snapshots() or { return fail_result('config snapshot list', err.msg()) }
	mut lines := []string{}
	mut ids := []string{}
	for s in snaps {
		ids << s.id
		lines << '${s.id} ${s.timestamp} ${s.hostname} ${s.commit}'
	}
	lines << '${snaps.len} snapshot(s)'
	return ok_result('config snapshot list', lines.join('\n'), {
		'count': snaps.len.str()
		'ids':   ids.join(',')
	})
}

pub struct SnapshotCreateOptions {
pub:
	dry_run bool
	yes     bool
	helper  string
}

fn config_manager_or_fail(helper string, dry_run bool) !string {
	bin := if helper.len > 0 { helper } else { resolve_config_manager() }
	if bin.len == 0 {
		if dry_run {
			return 'dots-config-manager'
		}
		return error('config snapshot backend not found. Set HORNERO_CONFIG_MANAGER_BIN.\nExample: horneroctl config snapshot create --dry-run')
	}
	return bin
}

// snapshot_create_report implements `config snapshot create` natively
// (metadata, tarball, package lists, latest link); an explicit helper
// still delegates to `dots-config-manager --create`. Mutating: needs
// --yes; --dry-run only previews.
pub fn snapshot_create_report(opts SnapshotCreateOptions) CommandResult {
	if !opts.yes && !opts.dry_run {
		return fail_result('config snapshot create', 'refusing to snapshot without --yes (preview with --dry-run).\nExample: horneroctl config snapshot create --dry-run')
	}
	if opts.helper.len > 0 {
		bin := config_manager_or_fail(opts.helper, opts.dry_run) or {
			return fail_result('config snapshot create', err.msg())
		}
		rep := run_exec(ExecSpec{
			prog:    bin
			args:    ['--create']
			dry_run: opts.dry_run
		})
		if opts.dry_run {
			return ok_result('config snapshot create', 'would run: ${rep.command_line}',
				{
				'command_line': rep.command_line
				'dry_run':      'true'
			})
		}
		if rep.ok {
			return ok_result('config snapshot create', rep.output, {
				'command_line': rep.command_line
			})
		}
		return fail_result('config snapshot create', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
	}
	return snapshot_create_native(opts.dry_run)
}

pub struct SnapshotRestoreOptions {
pub:
	id      string
	dry_run bool
	yes     bool
	helper  string
}

// snapshot_restore_report implements `config snapshot restore <id>`
// natively (pre-backup, then tarball extraction); an explicit helper
// still delegates. Mutating: needs --yes; --dry-run only previews.
pub fn snapshot_restore_report(opts SnapshotRestoreOptions) CommandResult {
	if !valid_snapshot_id(opts.id) {
		return fail_result('config snapshot restore', 'invalid snapshot id: ${opts.id}.\nRun: horneroctl config snapshot list')
	}
	if !opts.yes && !opts.dry_run {
		return fail_result('config snapshot restore', 'refusing to restore without --yes (preview with --dry-run).\nExample: horneroctl config snapshot restore ${opts.id} --dry-run')
	}
	if opts.helper.len > 0 {
		bin := config_manager_or_fail(opts.helper, opts.dry_run) or {
			return fail_result('config snapshot restore', err.msg())
		}
		rep := run_exec(ExecSpec{
			prog:    bin
			args:    ['--restore', opts.id]
			dry_run: opts.dry_run
		})
		if opts.dry_run {
			return ok_result('config snapshot restore', 'would run: ${rep.command_line}',
				{
				'command_line': rep.command_line
				'dry_run':      'true'
			})
		}
		if rep.ok {
			return ok_result('config snapshot restore', rep.output, {
				'command_line': rep.command_line
			})
		}
		return fail_result('config snapshot restore', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
	}
	return snapshot_restore_native(opts.id, opts.dry_run)
}

// snapshot_iso_now formats local time like `date -Iseconds`.
fn snapshot_iso_now() string {
	return time.now().custom_format('YYYY-MM-DDTHH:mm:ss')
}

// snapshot_dotfiles_commit reads the dotfiles HEAD, 'unknown' when the
// checkout is absent (mirrors the script's git-or-unknown).
fn snapshot_dotfiles_commit() string {
	rep := run_exec(ExecSpec{
		prog: 'git'
		args: ['-C', os.join_path(os.home_dir(), '.dotfiles'), 'rev-parse', 'HEAD']
	})
	if !rep.ok {
		return 'unknown'
	}
	out := rep.output.trim_space()
	if out.len == 0 {
		return 'unknown'
	}
	return out
}

// snapshot_create_native implements `config snapshot create` without
// the dots-config-manager wrapper (retired): metadata.json,
// dotfiles.tar.gz (tar -czf over the live HOME), pacman lists, ps
// capture, and the latest symlink — the create_snapshot contract.
// Writes go to the canonical snapshots dir; HOME redirection (tests)
// scopes the tarball source.
pub fn snapshot_create_native(dry_run bool) CommandResult {
	name := 'config snapshot create'
	base := resolve_snapshots_dir()
	if dry_run {
		return ok_result(name, 'would create ${base}/config_<timestamp> (metadata.json, dotfiles.tar.gz, package lists, processes.txt)',
			{
			'dry_run': 'true'
		})
	}
	stamp := perf_stamp(time.now())
	// Same-second collisions (create + pre-restore backup in one run)
	// get a numeric suffix; the script's plain format cannot do this.
	mut id := 'config_${stamp}'
	mut dir := os.join_path(base, id)
	mut n := 1
	for os.is_dir(dir) {
		n++
		id = 'config_${stamp}_${n}'
		dir = os.join_path(base, id)
	}
	os.mkdir_all(dir) or { return fail_result(name, 'cannot create snapshot dir: ${err.msg()}') }
	host := os.hostname() or { 'unknown' }
	meta := json2.encode(SnapshotMetadataFile{
		id:              id
		timestamp:       snapshot_iso_now()
		hostname:        host
		user:            os.getenv('USER')
		dotfiles_commit: snapshot_dotfiles_commit()
		system_info:     SnapshotSystemInfo{
			os:     perf_os_pretty()
			kernel: os.uname().release
			shell:  os.getenv('SHELL')
		}
	})
	os.write_file(os.join_path(dir, 'metadata.json'), meta) or {
		return fail_result(name, 'cannot write metadata: ${err.msg()}')
	}
	home := os.home_dir()
	tar := tar_or_fail('create', false) or { return fail_result(name, err.msg()) }
	// Best-effort like the script's `|| true`: missing members must not
	// fail the snapshot.
	run_exec(ExecSpec{
		prog: tar
		args: ['-czf', os.join_path(dir, 'dotfiles.tar.gz'), '-C', home, '.config', '.local/bin',
			'.local/lib', '.zshrc', '.p10k.zsh']
	})
	pacman := backend_or_empty('HORNERO_PACMAN_BIN', 'pacman')
	if pacman.len > 0 {
		ex := run_exec(ExecSpec{
			prog: pacman
			args: ['-Qqe']
		})
		if ex.ok {
			os.write_file(os.join_path(dir, 'packages_explicit.txt'), ex.output) or {}
		}
		aur := run_exec(ExecSpec{
			prog: pacman
			args: ['-Qqm']
		})
		if aur.ok {
			os.write_file(os.join_path(dir, 'packages_aur.txt'), aur.output) or {}
		}
	}
	ps := perf_ps_bin()
	if ps.len > 0 {
		proc := run_exec(ExecSpec{
			prog: ps
			args: ['aux']
		})
		if proc.ok {
			os.write_file(os.join_path(dir, 'processes.txt'), proc.output) or {}
		}
	}
	latest := os.join_path(base, 'latest')
	os.rm(latest) or {}
	os.symlink(dir, latest) or {}
	return ok_result(name, 'Snapshot created: ${id}\nLocation: ${dir}', {
		'id':  id
		'dir': dir
	})
}

// snapshot_find_dir locates one snapshot across the readable catalogue
// (canonical-first), '' when absent.
fn snapshot_find_dir(id string) string {
	for d in resolve_snapshots_dirs_for_read() {
		cand := os.join_path(d, id)
		if os.is_dir(cand) {
			return cand
		}
	}
	return ''
}

// snapshot_restore_native implements `config snapshot restore <id>`
// without the wrapper: info lines, a pre-restore backup of the
// current state, then tarball extraction over HOME — the
// restore_snapshot contract.
pub fn snapshot_restore_native(id string, dry_run bool) CommandResult {
	name := 'config snapshot restore'
	if !valid_snapshot_id(id) {
		return fail_result(name, 'invalid snapshot id: ${id}.\nRun: horneroctl config snapshot list')
	}
	if dry_run {
		return ok_result(name, 'would back up current state, then restore ${id} over ${os.home_dir()}',
			{
			'dry_run': 'true'
			'id':      id
		})
	}
	dir := snapshot_find_dir(id)
	if dir.len == 0 {
		return fail_result(name, 'Snapshot not found: ${id}')
	}
	entry := read_snapshot(os.dir(dir), id) or { SnapshotEntry{} }
	mut lines := ['Restoring configuration from snapshot: ${id}', '  Snapshot info:',
		'    Date: ${entry.timestamp}', '    Host: ${entry.hostname}', '    Commit: ${entry.commit}',
		'  Creating backup of current state...']
	backup := snapshot_create_native(false)
	if !backup.ok {
		return fail_result(name, 'pre-restore backup failed: ${backup.message}')
	}
	tarball := os.join_path(dir, 'dotfiles.tar.gz')
	if os.is_file(tarball) {
		lines << '  Restoring dotfiles...'
		tar := tar_or_fail('restore', false) or { return fail_result(name, err.msg()) }
		// Best-effort like the script's `|| true`.
		run_exec(ExecSpec{
			prog: tar
			args: ['-xzf', tarball, '-C', os.home_dir()]
		})
	}
	lines << 'Restore completed!'
	lines << '   You may need to restart your shell or reload configurations'
	return ok_result(name, lines.join('\n'), {
		'id': id
	})
}
