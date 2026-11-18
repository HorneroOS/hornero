module hornero_core

import os
import time

// ---- approval user-presence proof ----------------------------------
// `assistant approve <run> approve` can be run by anything that can run
// commands as the user — including a prompt-injected tool or a
// delegated agent on the host. When `approvals.requirePresence` is on
// (assistant.json; default ON), an approve (never a deny) needs proof
// that a human acted:
//
//   - shell flow: the Shell's approval card, at click time, writes a
//     single-use nonce file `<dir>/<runId>.<promptId>@<generation>`
//     (0600, inside the 0700 dir `$XDG_RUNTIME_DIR/hornero/
//     approval-presence`) and passes the same nonce with `--presence`,
//     plus `--request <promptId>@<generation>`. horneroctl checks the
//     directory and file (real dir/regular file, owned by the user, no
//     group/other bits, younger than assistant_presence_ttl_seconds),
//     compares the nonce in constant time, binds it to exactly that run
//     and request, and consumes the file (rename) before the decision
//     is sent, so a nonce works once.
//   - CLI flow: on an interactive terminal (stdin and stdout are TTYs,
//     human output) horneroctl shows the pending request and asks the
//     user to type `approve`; the confirmation is bound to the request
//     it showed. Non-interactive callers without a nonce are refused.
//
// Residual risk, stated plainly: this raises the bar against injected
// tools and agents that only run commands (`horneroctl assistant
// approve …` alone is refused). It is NOT a boundary against arbitrary
// code running as the same user: such code can read or create files
// in a 0700 directory it owns, drive a pseudo-terminal, or edit
// assistant.json to turn the requirement off. Same-uid code is inside
// the user's trust envelope (docs/javi-secure-harness.md); the
// sandboxed Hermes unit masks $XDG_RUNTIME_DIR, so its tools cannot
// see the presence directory at all.

pub const assistant_presence_ttl_seconds = 60

pub struct AssistantApprovalPresence {
pub:
	token         string // nonce from the Shell approval card (--presence)
	tty_confirmed bool   // the CLI adapter obtained an interactive confirmation
}

pub fn assistant_presence_dir() string {
	env := os.getenv('HORNERO_ASSISTANT_PRESENCE_DIR')
	if env.len > 0 {
		return env
	}
	runtime := os.getenv('XDG_RUNTIME_DIR')
	if runtime.len == 0 {
		return ''
	}
	return os.join_path(runtime, 'hornero', 'approval-presence')
}

// assistant_presence_token_shape_ok: 32-128 chars of [A-Za-z0-9_-].
pub fn assistant_presence_token_shape_ok(token string) bool {
	if token.len < 32 || token.len > 128 {
		return false
	}
	for c in token {
		if !(c.is_letter() || c.is_digit() || c in [`_`, `-`]) {
			return false
		}
	}
	return true
}

fn assistant_presence_private(st os.Stat) bool {
	return int(st.uid) == os.getuid() && st.mode & 0o077 == 0
}

fn assistant_constant_time_eq(a string, b string) bool {
	if a.len != b.len {
		return false
	}
	mut diff := u8(0)
	for i in 0 .. a.len {
		diff |= a[i] ^ b[i]
	}
	return diff == 0
}

// assistant_presence_file is where the Shell writes the nonce for one
// request; request_ref must be the full prompt_id@generation form.
pub fn assistant_presence_file(run_id string, request_ref string) string {
	dir := assistant_presence_dir()
	if dir.len == 0 {
		return ''
	}
	return os.join_path(dir, '${run_id}.${request_ref}')
}

// assistant_presence_check validates a nonce for {run, request} without
// consuming it. Returns '' when valid, else the reason.
pub fn assistant_presence_check(run_id string, request_ref string, token string) string {
	if !assistant_presence_token_shape_ok(token) {
		return 'the presence token has an invalid shape'
	}
	if !request_ref.contains('@') || !assistant_request_ref_valid(request_ref)
		|| !assistant_run_id_valid(run_id) {
		return 'a presence token must be bound with --request <prompt-id>@<generation>'
	}
	dir := assistant_presence_dir()
	if dir.len == 0 {
		return 'no runtime directory (XDG_RUNTIME_DIR) for presence tokens'
	}
	dst := os.lstat(dir) or { return 'no presence token was issued for this request' }
	if dst.get_filetype() != .directory || !assistant_presence_private(dst) {
		return 'the presence directory is not a private directory owned by you'
	}
	path := assistant_presence_file(run_id, request_ref)
	st := os.lstat(path) or { return 'no presence token was issued for this request' }
	if st.get_filetype() != .regular || !assistant_presence_private(st) || st.size > 256 {
		return 'the presence token file is not a private file owned by you'
	}
	age := time.now().unix() - st.mtime
	if age > assistant_presence_ttl_seconds || age < -5 {
		return 'the presence token expired; click Approve again'
	}
	content := os.read_file(path) or { return 'the presence token could not be read' }
	if !assistant_constant_time_eq(content.trim_right('\n'), token) {
		return 'the presence token does not match'
	}
	return ''
}

// assistant_presence_consume makes a checked token single-use: the
// file is renamed away (atomic; a concurrent consumer loses) and
// removed. Returns false when someone else consumed it first.
fn assistant_presence_consume(run_id string, request_ref string) bool {
	path := assistant_presence_file(run_id, request_ref)
	used := '${path}.used.${os.getpid()}'
	os.rename(path, used) or { return false }
	os.rm(used) or {}
	return true
}
