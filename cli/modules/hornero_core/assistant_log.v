module hornero_core

import os
import time

// Local, user-readable audit log of assistant activity (hornero#175).
//
// Append-only TSV under the assistant config dir (0600). Each line:
// timestamp, action, run id, detail, status. The detail field is
// scrubbed through redact_secrets and stripped of tabs/newlines;
// prompts, answers and response bodies are never written — only
// the action class, the run id and the outcome, so a user can
// audit what the assistant did or approved on their behalf.
//
// Writes are O_APPEND single writes under an exclusive flock(2)
// (see assistant_log_append). Rotation: once the file passes
// assistant_log_max_bytes it is rewritten, under the same lock,
// keeping the newest lines within half the cap, so the log is bounded
// without an external rotator.

pub const assistant_log_max_bytes = 256 * 1024

pub fn assistant_log_file() string {
	env := os.getenv('HORNERO_ASSISTANT_LOG_FILE')
	if env.len > 0 {
		return env
	}
	return os.join_path(assistant_dir(), 'assistant.log')
}

fn assistant_log_clean_field(s string) string {
	mut out := redact_secrets(s).replace('\t', ' ').replace('\n', ' ').replace('\r', ' ')
	if out.len > 160 {
		out = assistant_cut(out, 160)
	}
	return out
}

// assistant_log_line renders one entry; pure, for tests.
pub fn assistant_log_line(ts string, action string, run_id string, detail string, status string) string {
	return '${ts}\t${assistant_log_clean_field(action)}\t${assistant_log_clean_field(run_id)}\t${assistant_log_clean_field(detail)}\t${assistant_log_clean_field(status)}\n'
}

// assistant_log_rotate_text keeps the newest whole lines that fit
// in cap_bytes; pure, for tests.
pub fn assistant_log_rotate_text(content string, cap_bytes int) string {
	if content.len <= cap_bytes {
		return content
	}
	lines := content.split('\n')
	mut kept := []string{}
	mut total := 0
	for i := lines.len - 1; i >= 0; i-- {
		line := lines[i]
		if line.len == 0 && i == lines.len - 1 {
			continue
		}
		if total + line.len + 1 > cap_bytes && kept.len > 0 {
			break
		}
		kept << line
		total += line.len + 1
	}
	// `reverse()` returns a copy; the newest-first list must be flipped
	// in place or the rotated log comes out in reverse order.
	kept.reverse_in_place()
	return kept.join('\n') + '\n'
}

// assistant_log_append records one boundary event. Best-effort by
// design: a logging failure must never change the outcome of the
// assistant command itself.
//
// Concurrency: the line is written with ONE write(2) on an O_APPEND
// descriptor, so concurrent horneroctl processes (stream follower,
// approval click, broker) never overwrite each other's entries — the
// old read-modify-write lost lines under concurrency. An exclusive
// flock(2) on the log itself serialises writers with rotation; after
// taking it the writer checks that its descriptor still names the
// current file (a rotation may have replaced it) and reopens if not,
// so no line lands in a rotated-away inode.
pub fn assistant_log_append(action string, run_id string, detail string, status string) {
	path := assistant_log_file()
	os.mkdir_all(os.dir(path)) or { return }
	line := assistant_log_line(time.now().custom_format('YYYY-MM-DDTHH:mm:ss'), action,
		run_id, detail, status)
	for _ in 0 .. 5 {
		mut f := os.open_file(path, 'a', 0o600) or { return }
		locked := assistant_log_lock(f.fd)
		if locked && !assistant_log_fd_is_current(f.fd, path) {
			// Rotated between open and lock: append to the new file.
			f.close()
			continue
		}
		f.write_string(line) or {
			f.close()
			return
		}
		f.flush()
		os.chmod(path, 0o600) or {}
		if locked && assistant_log_fd_size(f.fd) > assistant_log_max_bytes {
			assistant_log_rotate_locked(path)
		}
		f.close() // releases the flock
		return
	}
}

// assistant_log_lock takes an exclusive flock, waiting at most ~2 s.
// On timeout the caller still appends (O_APPEND keeps the line intact)
// but skips rotation, which needs the lock.
fn assistant_log_lock(fd int) bool {
	for _ in 0 .. 100 {
		if C.flock(fd, lock_ex | lock_nb) == 0 {
			return true
		}
		time.sleep(20 * time.millisecond)
	}
	return false
}

fn C.fstat(fd int, buf &C.stat) int

fn assistant_log_fd_stat(fd int) ?C.stat {
	mut st := C.stat{}
	if C.fstat(fd, &st) != 0 {
		return none
	}
	return st
}

fn assistant_log_fd_size(fd int) i64 {
	st := assistant_log_fd_stat(fd) or { return 0 }
	return i64(st.st_size)
}

// assistant_log_fd_is_current reports whether fd still refers to the
// file at path (same device and inode).
fn assistant_log_fd_is_current(fd int, path string) bool {
	st := assistant_log_fd_stat(fd) or { return false }
	cur := os.stat(path) or { return false }
	return u64(st.st_ino) == cur.inode && u64(st.st_dev) == cur.dev
}

// assistant_log_rotate_locked rewrites the log keeping the newest
// lines within half the cap. Caller holds the flock; the new file is
// written privately (0600) and renamed over the log, so readers see
// either the old or the new file, never a partial one.
fn assistant_log_rotate_locked(path string) {
	content := os.read_file(path) or { return }
	rotated := assistant_log_rotate_text(content, assistant_log_max_bytes / 2)
	tmp := os.join_path(os.dir(path), '.${os.file_name(path)}.rotate.${os.getpid()}')
	mut t := os.open_file(tmp, 'w', 0o600) or { return }
	t.write_string(rotated) or {
		t.close()
		os.rm(tmp) or {}
		return
	}
	t.close()
	os.chmod(tmp, 0o600) or {}
	os.rename(tmp, path) or { os.rm(tmp) or {} }
}

// assistant_log_filter_lines keeps lines containing filter
// (case-insensitive); an empty filter keeps everything. Pure, for tests.
pub fn assistant_log_filter_lines(lines []string, filter string) []string {
	needle := filter.trim_space().to_lower()
	if needle.len == 0 {
		return lines
	}
	return lines.filter(it.to_lower().contains(needle))
}

// assistant_log_report renders the newest entries for
// `horneroctl assistant log`.
pub fn assistant_log_report() CommandResult {
	return assistant_log_report_filtered('')
}

pub fn assistant_log_report_filtered(filter string) CommandResult {
	path := assistant_log_file()
	raw := os.read_file(path) or {
		return ok_result('assistant log', 'No assistant activity recorded yet. The log lives at ${path} once the assistant runs.', {
			'file':    path
			'entries': '0'
		})
	}
	lines := raw.split('\n').filter(it.len > 0)
	matched := assistant_log_filter_lines(lines, filter)
	shown := if matched.len > 50 { matched[matched.len - 50..] } else { matched }
	msg := if shown.len > 0 {
		shown.join('\n')
	} else {
		'No assistant activity matches "${assistant_log_clean_field(filter)}".'
	}
	return ok_result('assistant log', msg, {
		'file':    path
		'entries': lines.len.str()
		'matched': matched.len.str()
		'shown':   shown.len.str()
	})
}
