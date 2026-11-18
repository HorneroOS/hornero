module hornero_core

import os
import x.json2

// ---- idempotent mode denials ---------------------------------------
// Ask/Chat runs deny every approval request. The same request is seen
// more than once: the live stream handles it, then the outcome replays
// the whole event log, and a later follow/restore replays it again.
// Denying it each time made the second deny hit a gateway with nothing
// pending, fail, and stop the run with a spurious "deny failed".
//
// Each request is therefore denied at most once, keyed by its request
// id@generation when the event carries one, else by its ordinal among
// the run's approval events ('#<n>' — the event log is append-only and
// replayed in order, so the ordinal is stable across stream, replay and
// later follows). Handled keys are kept in memory for the command and
// in a per-run ledger, `<denials dir>/<run_id>` (0600 lines, 0700 dir,
// one O_APPEND write per key), for later invocations.

pub struct AssistantApprovalRequest {
pub:
	ref    string // request_id@generation, or '#<ordinal>'
	detail string
}

// AssistantDenyTracker is heap-allocated so the stream closure and the
// final replay of one command share it.
@[heap]
pub struct AssistantDenyTracker {
pub mut:
	done           map[string]bool
	approvals_seen int
}

pub enum AssistantDenyOutcome {
	denied  // this call denied it
	already // denied before (this command or the ledger)
	stale   // deny rejected, and the gateway definitely has nothing pending
	failed  // deny not accepted and not provably resolved: run stopped
}

pub fn assistant_denials_dir() string {
	env := os.getenv('HORNERO_ASSISTANT_DENIALS_DIR')
	if env.len > 0 {
		return env
	}
	legacy := os.getenv('HORNERO_ASSISTANT_RUN_MODES_FILE')
	if legacy.len > 0 {
		return legacy + '.denials.d'
	}
	return os.join_path(assistant_dir(), 'assistant-run-denials.d')
}

fn assistant_denials_private(st os.Stat) bool {
	return int(st.uid) == os.getuid() && st.mode & 0o077 == 0
}

// assistant_denials_load returns the keys already denied for a run.
// An unreadable or untrusted ledger yields no keys: the request is then
// denied again, which can only cost a redundant deny, never an approval.
pub fn assistant_denials_load(run_id string) map[string]bool {
	mut out := map[string]bool{}
	if !assistant_run_id_valid(run_id) {
		return out
	}
	dir := assistant_denials_dir()
	dst := os.lstat(dir) or { return out }
	if dst.get_filetype() != .directory || !assistant_denials_private(dst) {
		return out
	}
	path := os.join_path(dir, run_id)
	st := os.lstat(path) or { return out }
	if st.get_filetype() != .regular || !assistant_denials_private(st) || st.size > 65536 {
		return out
	}
	content := os.read_file(path) or { return out }
	for line in content.split('\n') {
		if assistant_approval_ref_shape_ok(line) {
			out[line] = true
		}
	}
	return out
}

fn assistant_approval_ref_shape_ok(ref string) bool {
	if ref.starts_with('#') {
		return ref.len > 1 && ref.len <= 12 && ref[1..].bytes().all(it.is_digit())
	}
	return assistant_request_ref_valid(ref)
}

// assistant_denials_record appends one key (best-effort: a failure only
// means a later replay denies again).
fn assistant_denials_record(run_id string, ref string) {
	if !assistant_run_id_valid(run_id) || !assistant_approval_ref_shape_ok(ref) {
		return
	}
	dir := assistant_denials_dir()
	if !os.exists(dir) {
		os.mkdir_all(os.dir(dir)) or { return }
		os.mkdir(dir, mode: 0o700) or {}
	}
	dst := os.lstat(dir) or { return }
	if dst.get_filetype() != .directory || int(dst.uid) != os.getuid() {
		return
	}
	if dst.mode & 0o077 != 0 {
		os.chmod(dir, 0o700) or { return }
	}
	path := os.join_path(dir, run_id)
	if os.is_link(path) {
		return
	}
	mut f := os.open_file(path, 'a', 0o600) or { return }
	f.write_string('${ref}\n') or {}
	f.close()
	os.chmod(path, 0o600) or {}
}

// assistant_event_approval returns the approval request an event
// carries, with its dedupe key. ordinal is this event's 1-based index
// among the run's approval events.
pub fn assistant_event_approval(event AssistantEvent, ordinal int) ?AssistantApprovalRequest {
	pending := assistant_pending_request([event])
	if pending.kind != 'approval' {
		return none
	}
	mut ref := '#${ordinal}'
	if decoded := json2.decode[json2.Any](event.data) {
		if decoded is map[string]json2.Any {
			root := decoded.as_map()
			for key in ['request_id', 'prompt_id', 'approval_id'] {
				if key in root && root[key] is string && assistant_run_id_valid(root[key].str()) {
					mut gen := ''
					if 'execution_generation' in root {
						gv := root['execution_generation']
						g := match gv {
							i64 { gv }
							int { i64(gv) }
							f64 { i64(gv) }
							else { i64(-1) }
						}
						if g >= 0 {
							gen = '@${g}'
						}
					}
					ref = root[key].str() + gen
					break
				}
			}
		}
	}
	return AssistantApprovalRequest{
		ref:    ref
		detail: pending.detail
	}
}

// assistant_approval_requests lists every approval request in a run's
// events, in order, with stable dedupe keys.
pub fn assistant_approval_requests(events []AssistantEvent) []AssistantApprovalRequest {
	mut out := []AssistantApprovalRequest{}
	mut ordinal := 0
	for ev in events {
		if assistant_pending_request([ev]).kind != 'approval' {
			continue
		}
		ordinal++
		if req := assistant_event_approval(ev, ordinal) {
			out << req
		}
	}
	return out
}

// assistant_mode_deny_once denies one approval request of a
// non-escalating run unless it was already handled. A deny the gateway
// rejects is only "stale" (not an error, no stop) when run status
// definitely reports nothing pending; any other failure stops the run.
fn assistant_mode_deny_once(run_id string, mode string, req AssistantApprovalRequest, mut tracker AssistantDenyTracker) AssistantDenyOutcome {
	if tracker.done[req.ref] or { false } || req.ref in assistant_denials_load(run_id) {
		tracker.done[req.ref] = true
		return .already
	}
	denied := assistant_approve_report(run_id, 'deny', '')
	if denied.ok {
		tracker.done[req.ref] = true
		assistant_denials_record(run_id, req.ref)
		assistant_log_append('mode-deny', run_id, req.detail, mode)
		return .denied
	}
	settings := assistant_load_settings()
	if !assistant_approval_still_pending(settings, run_id, 1) {
		tracker.done[req.ref] = true
		assistant_denials_record(run_id, req.ref)
		assistant_log_append('mode-deny-stale', run_id, req.detail, 'already-resolved')
		return .stale
	}
	stopped := assistant_stop_report(run_id)
	assistant_log_append('mode-deny-failed', run_id, req.detail, if stopped.ok {
		'stop-requested'
	} else {
		'stop-failed'
	})
	return .failed
}
