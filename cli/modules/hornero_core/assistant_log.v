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
// Rotation: once the file passes assistant_log_max_bytes it is
// rewritten keeping the newest lines within half the cap, so the
// log is bounded without an external rotator.

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
		out = out[..160]
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
	kept.reverse()
	return kept.join('\n') + '\n'
}

// assistant_log_append records one boundary event. Best-effort by
// design: a logging failure must never change the outcome of the
// assistant command itself.
pub fn assistant_log_append(action string, run_id string, detail string, status string) {
	path := assistant_log_file()
	os.mkdir_all(os.dir(path)) or { return }
	line := assistant_log_line(time.now().custom_format('YYYY-MM-DDTHH:mm:ss'), action,
		run_id, detail, status)
	mut content := os.read_file(path) or { '' }
	content += line
	if content.len > assistant_log_max_bytes {
		content = assistant_log_rotate_text(content, assistant_log_max_bytes / 2)
	}
	os.write_file(path, content) or { return }
	os.chmod(path, 0o600) or {}
}

// assistant_log_report renders the newest entries for
// `horneroctl assistant log`.
pub fn assistant_log_report() CommandResult {
	path := assistant_log_file()
	raw := os.read_file(path) or {
		return ok_result('assistant log', 'No assistant activity recorded yet. The log lives at ${path} once the assistant runs.', {
			'file':    path
			'entries': '0'
		})
	}
	lines := raw.split('\n').filter(it.len > 0)
	shown := if lines.len > 50 { lines[lines.len - 50..] } else { lines }
	return ok_result('assistant log', shown.join('\n'), {
		'file':    path
		'entries': lines.len.str()
		'shown':   shown.len.str()
	})
}
