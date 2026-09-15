module hornero_core

import os
import time
import x.json2

// Portable Welcome state contract (Hornero-wide, UI-agnostic).
//
// Owner: HorneroOS/hornero. The state file is the single source of truth
// for first-login/onboarding semantics; any future frontend (Quickshell
// today, another session tomorrow) reads and writes this file without
// migrating user data (docs/PATH_CONTRACT.md row 13).
//
// File: `$XDG_STATE_HOME/hornero/welcome/state.json`
// (override with HORNERO_WELCOME_STATE_FILE). There is no legacy
// `dots/*` fallback: this file never existed before, so nothing migrates.
//
// Shape (schemaVersion 1):
//
//	{
//	  "schemaVersion": 1,
//	  "showOnLogin": true,
//	  "contentRevision": "p1",
//	  "lastSeenContentRevision": "",
//	  "firstOpenedAt": "",
//	  "lastOpenedAt": ""
//	}
//
// Rules: missing file behaves as defaults (first login shows Welcome);
// malformed content recovers to defaults without deleting the file (the
// next mutation rewrites it clean); an explicit showOnLogin=false always
// wins, even when contentRevision advances (a future "What's new" must
// not override the opt-out). Timestamps are RFC3339 UTC, "" when never.
// Writes are atomic (temp file + rename in the same directory).
//
// JSON keys are mapped explicitly (no struct attributes) so the module
// compiles on the pinned toolchain and reasonably newer V alike.

// welcome_schema_version is the only state schema this binary reads/writes.
pub const welcome_schema_version = 1

// welcome_content_revision identifies the Phase-1 Welcome content set.
// Bump when shipped content changes so a future "What's new" can compare
// against lastSeenContentRevision (never to override showOnLogin=false).
pub const welcome_content_revision = 'p1'

// WelcomeState is the decoded contract. `source` is provenance metadata
// ('defaults' when no usable file existed, else 'file'); it is never
// persisted.
pub struct WelcomeState {
pub:
	schema_version             int
	show_on_login              bool
	content_revision           string
	last_seen_content_revision string
	first_opened_at            string
	last_opened_at             string
	source                     string
}

// welcome_defaults is the first-login state: Welcome shows on login.
pub fn welcome_defaults() WelcomeState {
	return WelcomeState{
		schema_version:             welcome_schema_version
		show_on_login:              true
		content_revision:           welcome_content_revision
		last_seen_content_revision: ''
		first_opened_at:            ''
		last_opened_at:             ''
		source:                     'defaults'
	}
}

// resolve_welcome_state_file locates the Welcome state file: explicit
// HORNERO_WELCOME_STATE_FILE override wins, else
// `$XDG_STATE_HOME/hornero/welcome/state.json` (`~/.local/state` default).
pub fn resolve_welcome_state_file() string {
	env := os.getenv('HORNERO_WELCOME_STATE_FILE')
	if env.len > 0 {
		return env
	}
	mut base := os.getenv('XDG_STATE_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.local', 'state')
	}
	return os.join_path(base, 'hornero', 'welcome', 'state.json')
}

// welcome_any_number_int coerces a JSON number (i64 on some toolchains,
// f64 on others) to int, or none when it is not an integer value.
fn welcome_any_number_int(v json2.Any) ?int {
	match v {
		i64 {
			return int(v)
		}
		f64 {
			if v == f64(int(v)) {
				return int(v)
			}
			return none
		}
		else {
			return none
		}
	}
}

fn welcome_any_bool(v json2.Any) ?bool {
	match v {
		bool {
			return v
		}
		i64 {
			if v == 0 {
				return false
			}
			if v == 1 {
				return true
			}
			return none
		}
		f64 {
			if v == 0.0 {
				return false
			}
			if v == 1.0 {
				return true
			}
			return none
		}
		else {
			return none
		}
	}
}

fn welcome_any_string(v json2.Any) ?string {
	match v {
		string {
			return v
		}
		else {
			return none
		}
	}
}

// welcome_parse decodes raw state bytes tolerantly: any structural problem
// (not JSON, not an object, wrong schemaVersion, wrong field types)
// recovers to defaults. Unknown extra keys are ignored so future schema
// additions never break this reader.
pub fn welcome_parse(raw string) WelcomeState {
	base := welcome_defaults()
	decoded := json2.decode[map[string]json2.Any](raw) or { return base }
	ver := decoded['schemaVersion'] or { return base }
	ver_int := welcome_any_number_int(ver) or { return base }
	if ver_int != welcome_schema_version {
		return base
	}
	show := decoded['showOnLogin'] or { return base }
	show_on_login := welcome_any_bool(show) or { return welcome_defaults() }
	content_revision := if rev := decoded['contentRevision'] {
		welcome_any_string(rev) or { welcome_content_revision }
	} else {
		welcome_content_revision
	}
	last_seen := if seen := decoded['lastSeenContentRevision'] {
		welcome_any_string(seen) or { '' }
	} else {
		''
	}
	first_opened := if first := decoded['firstOpenedAt'] {
		welcome_any_string(first) or { '' }
	} else {
		''
	}
	last_opened := if last := decoded['lastOpenedAt'] {
		welcome_any_string(last) or { '' }
	} else {
		''
	}
	return WelcomeState{
		...base
		show_on_login:              show_on_login
		content_revision:           content_revision
		last_seen_content_revision: last_seen
		first_opened_at:            first_opened
		last_opened_at:             last_opened
		source:                     'file'
	}
}

// welcome_read loads the state file, or defaults when it is missing or
// unusable. Reading never writes.
pub fn welcome_read() WelcomeState {
	path := resolve_welcome_state_file()
	raw := os.read_file(path) or { return welcome_defaults() }
	return welcome_parse(raw)
}

// welcome_encode renders the canonical file bytes (stable key order).
// `source` is provenance only and is never persisted.
pub fn welcome_encode(st WelcomeState) string {
	lines := [
		'{',
		'  "schemaVersion": ${st.schema_version},',
		'  "showOnLogin": ${st.show_on_login},',
		'  "contentRevision": "${st.content_revision}",',
		'  "lastSeenContentRevision": "${st.last_seen_content_revision}",',
		'  "firstOpenedAt": "${st.first_opened_at}",',
		'  "lastOpenedAt": "${st.last_opened_at}"',
		'}',
	]
	return lines.join('\n') + '\n'
}

// welcome_write stores the state atomically (temp file + rename). Parent
// directories are created as needed.
pub fn welcome_write(st WelcomeState) ! {
	path := resolve_welcome_state_file()
	dir := os.dir(path)
	os.mkdir_all(dir) or { return error('cannot create ${dir}: ${err.msg()}') }
	tmp := os.join_path(dir, '.state.json.tmp')
	os.write_file(tmp, welcome_encode(st)) or { return error('cannot write ${tmp}: ${err.msg()}') }
	os.mv(tmp, path) or { return error('cannot move ${tmp} to ${path}: ${err.msg()}') }
}

fn welcome_data(st WelcomeState) map[string]string {
	return {
		'show_on_login':  '${st.show_on_login}'
		'schema_version': '${st.schema_version}'
		'content':        st.content_revision
		'last_seen':      if st.last_seen_content_revision.len > 0 {
			st.last_seen_content_revision
		} else {
			'never'
		}
		'state_file':     resolve_welcome_state_file()
		'source':         st.source
	}
}

// welcome_status_report is `horneroctl welcome status` (read-only).
pub fn welcome_status_report() CommandResult {
	st := welcome_read()
	detail := if st.source == 'file' {
		'from ${resolve_welcome_state_file()}'
	} else {
		'defaults (no state file yet)'
	}
	msg := 'show on login: ${st.show_on_login} (${detail})\ncontent: ${st.content_revision} (last seen: ${if st.last_seen_content_revision.len > 0 {
		st.last_seen_content_revision
	} else {
		'never'
	}})'
	return ok_result('welcome status', msg, welcome_data(st))
}

fn welcome_parse_bool_arg(arg string) ?bool {
	match arg.to_lower() {
		'true', '1', 'yes', 'on' {
			return true
		}
		'false', '0', 'no', 'off' {
			return false
		}
		else {
			return none
		}
	}
}

// welcome_parse_cli_bool parses a user-supplied boolean for
// `set-show-on-login` (none on anything else).
pub fn welcome_parse_cli_bool(arg string) ?bool {
	return welcome_parse_bool_arg(arg)
}

pub struct WelcomeSetOptions {
pub:
	value   bool
	dry_run bool
	yes     bool
}

// welcome_set_show_report implements `welcome set-show-on-login`.
// Mutating: needs --yes; --dry-run only previews. Idempotent: setting the
// current value succeeds as a no-op without rewriting the file.
pub fn welcome_set_show_report(opts WelcomeSetOptions) CommandResult {
	name := 'welcome set-show-on-login'
	if !opts.yes && !opts.dry_run {
		return fail_result(name, 'refusing to change without --yes (preview with --dry-run).\nExample: horneroctl welcome set-show-on-login false --dry-run')
	}
	st := welcome_read()
	if st.show_on_login == opts.value {
		mut data := welcome_data(st)
		data['dry_run'] = '${opts.dry_run}'
		data['unchanged'] = 'true'
		return ok_result(name, 'already show_on_login=${opts.value} (no change)', data)
	}
	next := WelcomeState{
		...st
		show_on_login: opts.value
	}
	if opts.dry_run {
		mut data := welcome_data(next)
		data['dry_run'] = 'true'
		return ok_result(name, 'would write show_on_login=${opts.value} to ${resolve_welcome_state_file()}',
			data)
	}
	welcome_write(next) or {
		return fail_result(name, 'cannot write state: ${err.msg()}.\nExample: HORNERO_WELCOME_STATE_FILE=/tmp/w.json horneroctl welcome set-show-on-login ${opts.value} --yes')
	}
	return ok_result(name, 'show_on_login=${opts.value} (stored in ${resolve_welcome_state_file()})',
		welcome_data(next))
}

pub struct WelcomeSeenOptions {
pub:
	revision string
	dry_run  bool
	yes      bool
}

// welcome_mark_seen_report implements `welcome mark-seen`: records the
// content revision the user has seen plus open timestamps (first wins,
// last always refreshes). Mutating: needs --yes; --dry-run previews.
pub fn welcome_mark_seen_report(opts WelcomeSeenOptions) CommandResult {
	name := 'welcome mark-seen'
	if !opts.yes && !opts.dry_run {
		return fail_result(name, 'refusing to change without --yes (preview with --dry-run).\nExample: horneroctl welcome mark-seen --dry-run')
	}
	rev := if opts.revision.len > 0 { opts.revision } else { welcome_content_revision }
	st := welcome_read()
	now := time.now().format_rfc3339()
	first := if st.first_opened_at.len == 0 { now } else { st.first_opened_at }
	next := WelcomeState{
		...st
		last_seen_content_revision: rev
		first_opened_at:            first
		last_opened_at:             now
	}
	if opts.dry_run {
		mut data := welcome_data(next)
		data['dry_run'] = 'true'
		return ok_result(name, 'would mark revision ${rev} as seen', data)
	}
	welcome_write(next) or { return fail_result(name, 'cannot write state: ${err.msg()}') }
	return ok_result(name, 'marked revision ${rev} as seen', welcome_data(next))
}

// welcome_reset_report implements `welcome reset`: restores defaults
// (showOnLogin=true) while keeping the file on disk. An explicit reset is
// the only path back to auto-show; content updates never flip the flag.
pub fn welcome_reset_report(dry_run bool, yes bool) CommandResult {
	name := 'welcome reset'
	if !yes && !dry_run {
		return fail_result(name, 'refusing to reset without --yes (preview with --dry-run).\nExample: horneroctl welcome reset --dry-run')
	}
	next := WelcomeState{
		...welcome_defaults()
		source: 'file'
	}
	if dry_run {
		mut data := welcome_data(next)
		data['dry_run'] = 'true'
		return ok_result(name, 'would reset to defaults in ${resolve_welcome_state_file()}',
			data)
	}
	welcome_write(next) or { return fail_result(name, 'cannot write state: ${err.msg()}') }
	return ok_result(name, 'reset to defaults (show on login)', welcome_data(next))
}

pub struct WelcomeOpenOptions {
pub:
	page    string
	dry_run bool
	qs_bin  string
}

// welcome_open_report implements `welcome open [page]`: asks a running
// shell to open Welcome via `qs ipc call welcome open`. The shell side
// owns the window; this is a thin passthrough like `shell ipc`.
// --dry-run previews the planned call without needing qs installed.
pub fn welcome_open_report(opts WelcomeOpenOptions) CommandResult {
	name := 'welcome open'
	if opts.page.len > 0 {
		for c in opts.page {
			if !(c.is_alnum() || c == `-` || c == `_`) {
				return fail_result(name, 'invalid page id: ${opts.page} (use [a-z0-9-_]).\nExample: horneroctl welcome open --dry-run')
			}
		}
	}
	mut bin := if opts.qs_bin.len > 0 { opts.qs_bin } else { resolve_qs_bin() }
	if bin.len == 0 && !opts.dry_run {
		return fail_result(name, 'qs not found on PATH. Set HORNERO_QS_BIN.\nExample: horneroctl welcome open --dry-run')
	}
	bin = if bin.len > 0 { bin } else { 'qs' }
	mut args := ['ipc', 'call', 'welcome', 'open']
	if opts.page.len > 0 {
		args << opts.page
	}
	rep := run_exec(ExecSpec{
		prog:    bin
		args:    args
		dry_run: opts.dry_run
	})
	if opts.dry_run {
		return ok_result(name, 'would run: ${rep.command_line}', {
			'command_line': rep.command_line
			'dry_run':      'true'
		})
	}
	if !rep.ok {
		return fail_result(name, 'shell did not open Welcome: ${rep.output}.\nIs Hornero Shell running with the welcome target?')
	}
	return ok_result(name, 'asked the shell to open Welcome', {
		'command_line': rep.command_line
	})
}
