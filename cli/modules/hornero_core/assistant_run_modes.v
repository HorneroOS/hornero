module hornero_core

import os
import time

#include <fcntl.h>
#include <unistd.h>

// ---- per-run mode registry ----------------------------------------
// The mode a run was created with is recorded by run id so a later
// `events`/`approve` (a restart, a follow) enforces the RUN's mode,
// not a default. Unknown run = 'ask' (non-escalating, no tools): fail
// closed.
//
// Layout: one file per run, `<dir>/<run_id>`, content exactly
// "<mode>\n", 0600, inside a 0700 directory owned by the user. Each
// record is written to an O_EXCL|O_NOFOLLOW temp file and renamed into
// place, so there is no shared read-modify-write, no lock to time out
// and no stale lock to take over: concurrent writers cannot drop each
// other's records. A record that cannot be written is an error the
// caller must surface (the run is stopped), never a silent drop that
// would later read back as 'ask' and auto-deny an Agent run.
//
// Integrity: reads validate the directory (real dir, owner = uid,
// no group/other bits) and the file (regular, not a symlink, owner =
// uid, no group/other bits, exact content). Anything else reads as
// 'ask'. Trust boundary: processes running as the same uid can still
// rewrite these files — they are inside the user's trust envelope
// (docs/javi-secure-harness.md); the checks stop other users, symlink
// tricks and corrupt or half-written records, not same-uid code.
//
// Bounded to the newest assistant_run_modes_keep records (by mtime).

pub const assistant_run_modes_keep = 200

const assistant_run_mode_values = ['ask', 'agent', 'chat']

// assistant_run_modes_file is the legacy TSV registry (pre-K3). It is
// only read as a fallback for runs recorded before the upgrade.
pub fn assistant_run_modes_file() string {
	env := os.getenv('HORNERO_ASSISTANT_RUN_MODES_FILE')
	if env.len > 0 {
		return env
	}
	return os.join_path(assistant_dir(), 'assistant-run-modes.tsv')
}

pub fn assistant_run_modes_dir() string {
	env := os.getenv('HORNERO_ASSISTANT_RUN_MODES_DIR')
	if env.len > 0 {
		return env
	}
	if os.getenv('HORNERO_ASSISTANT_RUN_MODES_FILE').len > 0 {
		return assistant_run_modes_file() + '.d'
	}
	return os.join_path(assistant_dir(), 'assistant-run-modes.d')
}

// assistant_private_owned reports whether st is owned by this user and
// carries no group/other permission bits.
fn assistant_private_owned(st os.Stat) bool {
	return int(st.uid) == os.getuid() && st.mode & 0o077 == 0
}

// assistant_run_modes_dir_ok validates the registry directory without
// following a symlink at its final component.
fn assistant_run_modes_dir_ok(dir string) bool {
	st := os.lstat(dir) or { return false }
	return st.get_filetype() == .directory && assistant_private_owned(st)
}

// assistant_run_modes_ensure_dir creates the registry directory 0700,
// tightens a pre-existing one this user owns, and refuses a symlink or
// a directory owned by someone else.
fn assistant_run_modes_ensure_dir(dir string) ! {
	if !os.exists(dir) {
		os.mkdir_all(os.dir(dir)) or { return error('cannot create ${os.dir(dir)}: ${err.msg()}') }
		os.mkdir(dir, mode: 0o700) or {
			if !os.is_dir(dir) {
				return error('cannot create ${dir}: ${err.msg()}')
			}
		}
	}
	st := os.lstat(dir) or { return error('cannot inspect ${dir}: ${err.msg()}') }
	if st.get_filetype() != .directory {
		return error('${dir} is not a directory (refusing a symlink or file)')
	}
	if int(st.uid) != os.getuid() {
		return error('${dir} is not owned by the current user')
	}
	if st.mode & 0o077 != 0 {
		os.chmod(dir, 0o700) or { return error('cannot make ${dir} private: ${err.msg()}') }
	}
}

// assistant_write_exclusive writes content to a NEW file (O_EXCL,
// O_NOFOLLOW, 0600) and fsyncs it.
fn assistant_write_exclusive(path string, content string) ! {
	fd := C.open(&char(path.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC,
		0o600)
	if fd < 0 {
		return error('cannot create ${path}: ${os.posix_get_error_msg(C.errno)}')
	}
	written := C.write(fd, content.str, uint(content.len))
	synced := C.fsync(fd)
	C.close(fd)
	if written != content.len || synced != 0 {
		os.rm(path) or {}
		return error('cannot write ${path}')
	}
}

// assistant_run_mode_record records the mode a run was created with.
// It retries transient failures and returns an error when the record
// could not be made durable; callers must not continue the run then.
pub fn assistant_run_mode_record(run_id string, mode string) ! {
	if !assistant_run_id_valid(run_id) {
		return error('invalid run id')
	}
	dir := assistant_run_modes_dir()
	effective := assistant_session_effective_mode(mode)
	mut last := ''
	for attempt in 0 .. 3 {
		if attempt > 0 {
			time.sleep(50 * time.millisecond)
		}
		assistant_run_modes_ensure_dir(dir) or {
			last = err.msg()
			continue
		}
		tmp := os.join_path(dir, '.${run_id}.${os.getpid()}.${time.now().unix_nano()}.tmp')
		assistant_write_exclusive(tmp, '${effective}\n') or {
			last = err.msg()
			continue
		}
		os.rename(tmp, os.join_path(dir, run_id)) or {
			os.rm(tmp) or {}
			last = 'cannot store the run mode: ${err.msg()}'
			continue
		}
		assistant_run_modes_prune(dir)
		if assistant_run_mode(run_id) != effective {
			last = 'the recorded run mode did not read back'
			continue
		}
		return
	}
	return error('could not record the mode of run ${run_id}: ${last}')
}

// assistant_run_modes_prune keeps the newest records. Best-effort and
// race-tolerant: two pruners removing the same old record is harmless.
fn assistant_run_modes_prune(dir string) {
	names := os.ls(dir) or { return }
	mut runs := []string{}
	for n in names {
		if assistant_run_id_valid(n) {
			runs << n
		}
	}
	if runs.len <= assistant_run_modes_keep {
		return
	}
	mut stamped := map[string]i64{}
	for n in runs {
		st := os.lstat(os.join_path(dir, n)) or { continue }
		stamped[n] = st.mtime
	}
	runs.sort_with_compare(fn [stamped] (a &string, b &string) int {
		ma := stamped[*a] or { 0 }
		mb := stamped[*b] or { 0 }
		if ma != mb {
			return if ma < mb { -1 } else { 1 }
		}
		return compare_strings(a, b)
	})
	for n in runs[..runs.len - assistant_run_modes_keep] {
		os.rm(os.join_path(dir, n)) or {}
	}
}

// assistant_run_mode returns the recorded mode of a run, or 'ask' when
// the run is unknown or its record fails validation.
pub fn assistant_run_mode(run_id string) string {
	if !assistant_run_id_valid(run_id) {
		return 'ask'
	}
	dir := assistant_run_modes_dir()
	path := os.join_path(dir, run_id)
	if os.exists(path) || os.is_link(path) {
		return assistant_run_mode_read_record(dir, path)
	}
	return assistant_run_mode_legacy(run_id)
}

fn assistant_run_mode_read_record(dir string, path string) string {
	if !assistant_run_modes_dir_ok(dir) {
		return 'ask'
	}
	st := os.lstat(path) or { return 'ask' }
	if st.get_filetype() != .regular || !assistant_private_owned(st) || st.size > 16 {
		return 'ask'
	}
	content := os.read_file(path) or { return 'ask' }
	if !content.ends_with('\n') {
		return 'ask'
	}
	mode := content[..content.len - 1]
	return if mode in assistant_run_mode_values { mode } else { 'ask' }
}

// assistant_run_mode_legacy reads the pre-K3 TSV registry (read-only),
// with the same ownership/permission and shape checks.
fn assistant_run_mode_legacy(run_id string) string {
	path := assistant_run_modes_file()
	st := os.lstat(path) or { return 'ask' }
	if st.get_filetype() != .regular || !assistant_private_owned(st) {
		return 'ask'
	}
	content := os.read_file(path) or { return 'ask' }
	mut found := ''
	for line in content.split('\n') {
		parts := line.split('\t')
		if parts.len == 2 && parts[0] == run_id && parts[1] in assistant_run_mode_values {
			found = parts[1]
		}
	}
	return if found.len > 0 { found } else { 'ask' }
}
