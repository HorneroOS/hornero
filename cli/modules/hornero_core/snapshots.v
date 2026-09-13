module hornero_core

import os
import x.json2

// Snapshot backend: configuration snapshots materialized on disk.
//
// `dots-config-manager` (dotfiles reference, read-only) owns the verbs:
// `--create` writes `$SNAPSHOTS_DIR/config_<timestamp>/` with a
// `metadata.json` (`id`, `timestamp`, `hostname`, `dotfiles_commit`),
// `--list` tabulates those directories, `--restore <id>` restores one.
// Listing here is a native reader of the same directories (no backend
// process needed, mirroring `preset list` / `theme list`); create/restore
// delegate to the backend (mirroring `theme apply` -> `dots-appearance`).
// Later phase: native snapshot/restore stays out until a pinned in-repo
// backend lands (TRACK 2a).

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

// resolve_config_manager locates the `dots-config-manager` backend CLI.
// Override with HORNERO_CONFIG_MANAGER_BIN.
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

fn snapshot_str_field(m map[string]json2.Any, key string) string {
	if key !in m {
		return 'unknown'
	}
	v := m[key].str()
	if v.len == 0 {
		return 'unknown'
	}
	return v
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
	parsed := json2.decode[json2.Any](raw)!
	if parsed is map[string]json2.Any {
		return SnapshotEntry{
			id:        id
			timestamp: snapshot_str_field(parsed, 'timestamp')
			hostname:  snapshot_str_field(parsed, 'hostname')
			commit:    snapshot_str_field(parsed, 'dotfiles_commit')
		}
	}
	return error('snapshot is corrupt: ${id} (metadata.json is not an object)')
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

// snapshot_create_report implements `config snapshot create` by delegating
// to `dots-config-manager --create` (verified backend verb). Mutating:
// needs --yes; --dry-run only previews.
pub fn snapshot_create_report(opts SnapshotCreateOptions) CommandResult {
	if !opts.yes && !opts.dry_run {
		return fail_result('config snapshot create', 'refusing to snapshot without --yes (preview with --dry-run).\nExample: horneroctl config snapshot create --dry-run')
	}
	bin := config_manager_or_fail(opts.helper, opts.dry_run) or {
		return fail_result('config snapshot create', err.msg())
	}
	rep := run_exec(ExecSpec{
		prog:    bin
		args:    ['--create']
		dry_run: opts.dry_run
	})
	if opts.dry_run {
		return ok_result('config snapshot create', 'would run: ${rep.command_line}', {
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

pub struct SnapshotRestoreOptions {
pub:
	id      string
	dry_run bool
	yes     bool
	helper  string
}

// snapshot_restore_report implements `config snapshot restore <id>` by
// delegating to `dots-config-manager --restore <id>` (verified backend
// verb). Mutating: needs --yes; --dry-run only previews.
pub fn snapshot_restore_report(opts SnapshotRestoreOptions) CommandResult {
	if !valid_snapshot_id(opts.id) {
		return fail_result('config snapshot restore', 'invalid snapshot id: ${opts.id}.\nRun: horneroctl config snapshot list')
	}
	if !opts.yes && !opts.dry_run {
		return fail_result('config snapshot restore', 'refusing to restore without --yes (preview with --dry-run).\nExample: horneroctl config snapshot restore ${opts.id} --dry-run')
	}
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
