module hornero_core

import crypto.sha256
import os
import time
import x.json2

// Low-level helpers for Hornero Chromatic: appearance lock, fsynced atomic
// writes, hashes and small JSON builders. No policy lives here.

#include <sys/file.h>
#include <unistd.h>

fn C.flock(fd int, operation int) int
fn C.fsync(fd int) int

const lock_ex = 2
const lock_nb = 4

// chromatic_sha256 is the `sha256:<hex>` form used in snapshots.
fn chromatic_sha256(content string) string {
	return 'sha256:' + sha256.hexhash(content)
}

// chromatic_now_iso is the UTC timestamp format of the state files.
fn chromatic_now_iso() string {
	t := time.utc()
	return '${t.year:04}-${t.month:02}-${t.day:02}T${t.hour:02}:${t.minute:02}:${t.second:02}Z'
}

// write_file_synced writes content to path and fsyncs it before returning.
fn write_file_synced(path string, content string) ! {
	mut f := os.create(path) or { return error('cannot create ${path}: ${err.msg()}') }
	f.write_string(content) or {
		f.close()
		return error('cannot write ${path}: ${err.msg()}')
	}
	f.flush()
	if C.fsync(f.fd) != 0 {
		f.close()
		return error('cannot fsync ${path}')
	}
	f.close()
}

// write_atomic_synced is write_file_atomic plus fsync of the temp file.
fn write_atomic_synced(path string, content string) ! {
	os.mkdir_all(os.dir(path)) or { return error('cannot create ${os.dir(path)}: ${err.msg()}') }
	tmp := os.join_path(os.dir(path), '.${os.file_name(path)}.chromatic.${os.getpid()}.tmp')
	write_file_synced(tmp, content) or {
		os.rm(tmp) or {}
		return err
	}
	os.rename(tmp, path) or {
		os.rm(tmp) or {}
		return error('cannot replace ${path}: ${err.msg()}')
	}
}

// AppearanceLock is the exclusive flock on the appearance lock file.
pub struct AppearanceLock {
mut:
	file os.File
}

// appearance_lock_file lives under $XDG_RUNTIME_DIR/hornero (tmpfs, so a
// stale lock cannot survive a reboot); without a runtime dir it falls back
// to the state directory.
pub fn appearance_lock_file() string {
	runtime := os.getenv('XDG_RUNTIME_DIR')
	if runtime.len > 0 {
		return os.join_path(runtime, 'hornero', 'appearance.lock')
	}
	return os.join_path(resolve_paths().state_dir, 'hornero', 'appearance.lock')
}

// acquire_appearance_lock takes the lock without blocking; a busy lock is
// an error so a second apply fails fast instead of queueing.
fn acquire_appearance_lock() !AppearanceLock {
	path := appearance_lock_file()
	os.mkdir_all(os.dir(path)) or { return error('cannot create ${os.dir(path)}: ${err.msg()}') }
	f := os.open_file(path, 'a+', 0o600) or { return error('cannot open ${path}: ${err.msg()}') }
	if C.flock(f.fd, lock_ex | lock_nb) != 0 {
		mut busy := f
		busy.close()
		return error('another appearance change holds ${path}')
	}
	return AppearanceLock{
		file: f
	}
}

fn (mut l AppearanceLock) release() {
	l.file.close()
}

// --- json builders ---------------------------------------------------------------

fn jstr(s string) json2.Any {
	return json2.Any(s)
}

fn jbool(b bool) json2.Any {
	return json2.Any(b)
}

fn jint(i int) json2.Any {
	return json2.Any(i)
}

fn jstrs(items []string) json2.Any {
	mut arr := []json2.Any{}
	for s in items {
		arr << json2.Any(s)
	}
	return json2.Any(arr)
}

fn jencode(m map[string]json2.Any) string {
	return json2.encode(m, escape_unicode: true)
}

// jmap returns a nested object or an empty map.
fn jmap(m map[string]json2.Any, key string) map[string]json2.Any {
	v := m[key] or { return map[string]json2.Any{} }
	if v is map[string]json2.Any {
		return v.as_map()
	}
	return map[string]json2.Any{}
}

fn jget(m map[string]json2.Any, key string) string {
	v := m[key] or { return '' }
	if v is json2.Null {
		return ''
	}
	return v.str()
}

fn parse_json_object(raw string) !map[string]json2.Any {
	parsed := json2.decode[json2.Any](raw) or { return error('not valid JSON') }
	if parsed is map[string]json2.Any {
		return parsed.as_map()
	}
	return error('not a JSON object')
}
