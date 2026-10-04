module hornero_core

import os
import time
import x.json2

// Hornero configuration snapshots are native, user-owned state under XDG.
// They capture Hornero settings, package inventory and host metadata.

// resolve_snapshots_dir locates materialized configuration snapshots: the
// canonical `hornero/*` location (docs/PATH_CONTRACT.md row 7) and the
// WRITE TARGET. Override with HORNERO_SNAPSHOTS_DIR.
pub fn resolve_snapshots_dir() string {
	env := os.getenv('HORNERO_SNAPSHOTS_DIR')
	if env.len > 0 {
		return env
	}
	mut base := os.getenv('XDG_DATA_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.local', 'share')
	}
	return os.join_path(base, 'hornero', 'snapshots')
}

// Snapshots are user-owned state and never read from package directories.
pub fn resolve_snapshots_dirs_for_read() []string {
	dir := resolve_snapshots_dir()
	return if os.is_dir(dir) { [dir] } else { []string{} }
}

pub struct SnapshotEntry {
pub:
	id        string
	timestamp string
	hostname  string
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
	id          string
	timestamp   string
	hostname    string
	user        string
	system_info SnapshotSystemInfo
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
	}
}

// list_snapshots returns materialized snapshots sorted by id.
// Reads the configured Hornero snapshot catalogue.
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
		lines << '${s.id} ${s.timestamp} ${s.hostname}'
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
}

// snapshot_create_report implements `config snapshot create` natively. Mutating: needs
// --yes; --dry-run only previews.
pub fn snapshot_create_report(opts SnapshotCreateOptions) CommandResult {
	if !opts.yes && !opts.dry_run {
		return fail_result('config snapshot create', 'refusing to snapshot without --yes (preview with --dry-run).\nExample: horneroctl config snapshot create --dry-run')
	}
	return snapshot_create_native(opts.dry_run)
}

pub struct SnapshotRestoreOptions {
pub:
	id      string
	dry_run bool
	yes     bool
}

// snapshot_restore_report implements `config snapshot restore <id>`
// natively (pre-restore backup, then tarball extraction). Mutating: needs --yes; --dry-run only previews.
pub fn snapshot_restore_report(opts SnapshotRestoreOptions) CommandResult {
	if !valid_snapshot_id(opts.id) {
		return fail_result('config snapshot restore', 'invalid snapshot id: ${opts.id}.\nRun: horneroctl config snapshot list')
	}
	if !opts.yes && !opts.dry_run {
		return fail_result('config snapshot restore', 'refusing to restore without --yes (preview with --dry-run).\nExample: horneroctl config snapshot restore ${opts.id} --dry-run')
	}
	return snapshot_restore_native(opts.id, opts.dry_run)
}

// snapshot_iso_now formats local time like `date -Iseconds`.
fn snapshot_iso_now() string {
	return time.now().custom_format('YYYY-MM-DDTHH:mm:ss')
}

// snapshot_create_native captures only Hornero-owned configuration and the
// installed package inventory. It never archives the full home directory.
pub fn snapshot_create_native(dry_run bool) CommandResult {
	name := 'config snapshot create'
	base := resolve_snapshots_dir()
	if dry_run {
		return ok_result(name, 'would create ${base}/config_<timestamp> (metadata.json, hornero-config.tar.gz, package inventory)',
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
		id:          id
		timestamp:   snapshot_iso_now()
		hostname:    host
		user:        os.getenv('USER')
		system_info: SnapshotSystemInfo{
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
	// Missing optional configuration roots do not prevent collecting package
	// metadata; tar runs only when at least one Hornero config root exists.
	config_home := os.getenv_opt('XDG_CONFIG_HOME') or { os.join_path(home, '.config') }
	config_roots := ['hornero', 'quickshell'].filter(os.is_dir(os.join_path(config_home, it)))
	if config_roots.len > 0 {
		mut args := ['-czf', os.join_path(dir, 'hornero-config.tar.gz'), '-C', config_home]
		args << config_roots
		run_exec(ExecSpec{
			prog: tar
			args: args
		})
	}
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

// snapshot_restore_native restores only the Hornero configuration roots.
pub fn snapshot_restore_native(id string, dry_run bool) CommandResult {
	name := 'config snapshot restore'
	if !valid_snapshot_id(id) {
		return fail_result(name, 'invalid snapshot id: ${id}.\nRun: horneroctl config snapshot list')
	}
	if dry_run {
		return ok_result(name, 'would back up current Hornero configuration, then restore ${id}',
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
		'    Date: ${entry.timestamp}', '    Host: ${entry.hostname}',
		'  Creating backup of current state...']
	backup := snapshot_create_native(false)
	if !backup.ok {
		return fail_result(name, 'pre-restore backup failed: ${backup.message}')
	}
	tarball := os.join_path(dir, 'hornero-config.tar.gz')
	if os.is_file(tarball) {
		lines << '  Restoring Hornero configuration...'
		tar := tar_or_fail('restore', false) or { return fail_result(name, err.msg()) }
		config_home := os.getenv_opt('XDG_CONFIG_HOME') or { os.join_path(os.home_dir(), '.config') }
		run_exec(ExecSpec{
			prog: tar
			args: ['-xzf', tarball, '-C', config_home]
		})
	}
	lines << 'Restore completed!'
	lines << '   You may need to restart your shell or reload configurations'
	return ok_result(name, lines.join('\n'), {
		'id': id
	})
}
