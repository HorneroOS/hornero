module hornero_core

import db.sqlite
import os
import time
import x.json2

// Normalized AI-agent usage contract (hornero#407, Extensions 2.0):
// providers/collectors emit ONE provider-independent record shape and
// shell/plugins consume only that normalized shape (see
// docs/agent-usage-contract.md). The pre-existing
// `horneroctl assistant usage --json` contract is unchanged; the Hermes
// collector below reuses it verbatim instead of re-querying.
//
// Truthfulness rules, enforced by construction here:
// - No invented quota/limits/resets/costs. `quota` is 'unknown' (and
//   numeric quota fields are omitted) unless the provider's own local
//   record actually carries them (today: only a Codex rollout's latest
//   `token_count.rate_limits`). There is no cost field at all.
// - Account is 'unknown': deriving it would mean reading credential
//   files, which this module never does. Collectors read only the
//   usage stores named in `source`; credential contents are never
//   read, returned, or logged, and errors never embed file contents.
// - Errors are never zeros: a missing/unreadable/empty source yields
//   status 'unavailable'/'error' with an `errors` entry and NO numeric
//   token fields (flat keys report 'unknown').
// - Everything is local and read-only: no network, no subprocess.

pub const agent_usage_schema_version = 1

// Collector scan caps: a workstation's local history can be large, so
// JSONL collectors stop at the cap and say so in `errors` rather than
// scanning unboundedly (the record then understates, never overstates,
// and is labelled with the truncation).
const agent_usage_max_files = 5000

pub struct AgentUsageRecord {
pub:
	provider string // agent registry id: javi-hermes, codex, claude-code, muse, opencode
	account  string // always 'unknown' in this slice (see header)
	source   string // collector source kind, e.g. 'hermes-state-db'
pub mut:
	status               string // 'ok', 'unavailable', or 'error'
	period_start         string // '' = unknown/all recorded history
	period_end           string
	measured_at_unix     i64 // source mtime, 0 = unknown
	has_tokens           bool
	input_tokens         i64
	output_tokens        i64
	cache_read_tokens    i64
	cache_write_tokens   i64
	reasoning_tokens     i64
	sessions             i64    // -1 = unknown
	api_calls            i64    // -1 = unknown
	models               string // 'name:tokens' joined by ',', '' = unknown
	quota_used_percent   f64
	quota_window_minutes i64
	quota_resets_at_unix i64
	has_quota            bool
	balance              string // '' = not applicable/unknown
	errors               []string
}

fn agent_usage_base(provider string, source string) AgentUsageRecord {
	return AgentUsageRecord{
		provider:  provider
		account:   'unknown'
		source:    source
		status:    'unavailable'
		sessions:  -1
		api_calls: -1
	}
}

// freshness classifies source age: fresh <= 24h, else stale/unknown.
pub fn (r AgentUsageRecord) freshness() string {
	if r.measured_at_unix <= 0 {
		return 'unknown'
	}
	age := time.now().unix() - r.measured_at_unix
	if age < 0 {
		return 'unknown'
	}
	return if age <= 86400 { 'fresh' } else { 'stale' }
}

// total_tokens is input+output (cache/reasoning stay separate fields).
pub fn (r AgentUsageRecord) total_tokens() i64 {
	return r.input_tokens + r.output_tokens
}

// agent_usage_record_json encodes one normalized record. Unknown
// numerics are omitted (never zero-filled); quota/balance keys appear
// only when the provider's own record carried them.
pub fn agent_usage_record_json(r AgentUsageRecord) map[string]json2.Any {
	mut m := map[string]json2.Any{}
	m['schemaVersion'] = json2.Any(agent_usage_schema_version)
	m['provider'] = r.provider
	m['account'] = r.account
	m['source'] = r.source
	m['status'] = r.status
	m['freshness'] = r.freshness()
	m['periodStart'] = r.period_start
	m['periodEnd'] = r.period_end
	if r.measured_at_unix > 0 {
		m['measuredAtUnix'] = json2.Any(r.measured_at_unix)
	}
	if r.has_tokens {
		m['inputTokens'] = json2.Any(r.input_tokens)
		m['outputTokens'] = json2.Any(r.output_tokens)
		m['cacheReadTokens'] = json2.Any(r.cache_read_tokens)
		m['cacheWriteTokens'] = json2.Any(r.cache_write_tokens)
		m['reasoningTokens'] = json2.Any(r.reasoning_tokens)
		m['totalTokens'] = json2.Any(r.total_tokens())
	}
	if r.sessions >= 0 {
		m['sessions'] = json2.Any(r.sessions)
	}
	if r.api_calls >= 0 {
		m['apiCalls'] = json2.Any(r.api_calls)
	}
	if r.models.len > 0 {
		m['models'] = r.models
	}
	m['quota'] = if r.has_quota { 'available' } else { 'unknown' }
	if r.has_quota {
		m['quotaUsedPercent'] = json2.Any(r.quota_used_percent)
		m['quotaWindowMinutes'] = json2.Any(r.quota_window_minutes)
		m['quotaResetsAtUnix'] = json2.Any(r.quota_resets_at_unix)
	}
	m['balance'] = if r.balance.len > 0 { r.balance } else { 'unknown' }
	mut errs := []json2.Any{cap: r.errors.len}
	for e in r.errors {
		errs << json2.Any(e)
	}
	m['errors'] = json2.Any(errs)
	return m
}

// agent_usage_encode renders records as one normalized JSON array.
pub fn agent_usage_encode(records []AgentUsageRecord) string {
	mut arr := []json2.Any{cap: records.len}
	for r in records {
		arr << json2.Any(agent_usage_record_json(r))
	}
	return json2.encode(arr, escape_unicode: true)
}

fn agent_usage_num(has bool, v i64) string {
	return if has { v.str() } else { 'unknown' }
}

fn agent_usage_flat(mut data map[string]string, r AgentUsageRecord) {
	p := 'usage.${r.provider}'
	data['${p}.status'] = r.status
	data['${p}.account'] = r.account
	data['${p}.source'] = r.source
	data['${p}.freshness'] = r.freshness()
	data['${p}.inputTokens'] = agent_usage_num(r.has_tokens, r.input_tokens)
	data['${p}.outputTokens'] = agent_usage_num(r.has_tokens, r.output_tokens)
	data['${p}.totalTokens'] = agent_usage_num(r.has_tokens, r.total_tokens())
	data['${p}.sessions'] = agent_usage_num(r.sessions >= 0, r.sessions)
	data['${p}.quota'] = if r.has_quota { 'available' } else { 'unknown' }
	data['${p}.quotaResetsAtUnix'] = agent_usage_num(r.has_quota, r.quota_resets_at_unix)
	data['${p}.balance'] = if r.balance.len > 0 { r.balance } else { 'unknown' }
	data['${p}.errors'] = r.errors.join('; ')
}

// --- default source locations (env-overridable, fixture-friendly) ---

pub fn agent_usage_hermes_db() string {
	hermes_home := os.getenv('HERMES_HOME')
	base := if hermes_home.len > 0 {
		hermes_home
	} else {
		os.join_path(os.home_dir(), '.hermes')
	}
	return os.join_path(base, 'state.db')
}

// agent_usage_codex_sessions resolves $CODEX_HOME/sessions (or ~/.codex).
pub fn agent_usage_codex_sessions() string {
	home := os.getenv('CODEX_HOME')
	base := if home.len > 0 { home } else { os.join_path(os.home_dir(), '.codex') }
	return os.join_path(base, 'sessions')
}

// agent_usage_claude_dir resolves $CLAUDE_CONFIG_DIR (or ~/.claude).
pub fn agent_usage_claude_dir() string {
	dir := os.getenv('CLAUDE_CONFIG_DIR')
	return if dir.len > 0 { dir } else { os.join_path(os.home_dir(), '.claude') }
}

// agent_usage_muse_sessions resolves Muse's local session store.
pub fn agent_usage_muse_sessions() string {
	data := os.getenv('MUSE_DATA_DIR')
	if data.len > 0 {
		return os.join_path(data, 'sessions')
	}
	return os.join_path(resolve_paths().data_dir, 'muse', 'sessions')
}

// agent_usage_opencode_db resolves $OPENCODE_DB (or the XDG default).
pub fn agent_usage_opencode_db() string {
	db := os.getenv('OPENCODE_DB')
	if db.len > 0 {
		return db
	}
	return os.join_path(resolve_paths().data_dir, 'opencode', 'opencode.db')
}

// --- shared collector helpers ---

fn agent_usage_map(v json2.Any) map[string]json2.Any {
	if v is map[string]json2.Any {
		return v as map[string]json2.Any
	}
	return map[string]json2.Any{}
}

fn agent_usage_child(m map[string]json2.Any, key string) map[string]json2.Any {
	if key in m {
		return agent_usage_map(m[key])
	}
	return map[string]json2.Any{}
}

fn agent_usage_i64(m map[string]json2.Any, key string) i64 {
	if key in m {
		return m[key].i64()
	}
	return 0
}

fn agent_usage_mtime(path string) i64 {
	if os.exists(path) {
		return os.file_last_mod_unix(path)
	}
	return 0
}

// agent_usage_jsonl_files lists '*.jsonl' under dir (recursive),
// capped; truncated=true when the cap cut the listing.
fn agent_usage_jsonl_files(dir string) ([]string, bool) {
	mut files := os.walk_ext(dir, 'jsonl')
	files.sort()
	if files.len > agent_usage_max_files {
		return files[..agent_usage_max_files], true
	}
	return files, false
}

// --- Hermes collector: reuses the existing assistant usage contract ---

pub fn collect_hermes_usage_at(db_path string) AgentUsageRecord {
	mut r := agent_usage_base('javi-hermes', 'hermes-state-db')
	r.measured_at_unix = agent_usage_mtime(db_path)
	res := assistant_usage_report_at(db_path)
	if !res.ok {
		r.status = 'unavailable'
		r.errors << res.message
		return r
	}
	r.status = 'ok'
	r.has_tokens = true
	r.input_tokens = res.data['inputTokens'].i64()
	r.output_tokens = res.data['outputTokens'].i64()
	r.cache_read_tokens = res.data['cacheReadTokens'].i64()
	r.cache_write_tokens = res.data['cacheWriteTokens'].i64()
	r.reasoning_tokens = res.data['reasoningTokens'].i64()
	r.sessions = res.data['sessions'].i64()
	r.api_calls = res.data['apiCalls'].i64()
	r.models = res.data['models'] or { '' }
	return r
}

// --- Codex collector: rollout `token_count` events (last usage per
// event, never the cumulative totals, so nothing double-counts). The
// latest event's `rate_limits.primary` is Codex's own recorded quota
// snapshot — the only quota this contract ever reports. ---

pub fn collect_codex_usage_at(sessions_dir string) AgentUsageRecord {
	mut r := agent_usage_base('codex', 'codex-rollout-jsonl')
	if !os.is_dir(sessions_dir) {
		r.errors << 'No Codex sessions directory (Codex not used on this machine?).'
		return r
	}
	files, truncated := agent_usage_jsonl_files(sessions_dir)
	if truncated {
		r.errors << 'Truncated at ${agent_usage_max_files} session files; totals understate.'
	}
	mut sessions := i64(0)
	mut calls := i64(0)
	mut parse_errors := 0
	mut latest_ts := ''
	for f in files {
		lines := os.read_lines(f) or {
			parse_errors++
			continue
		}
		mut file_calls := 0
		for line in lines {
			if !line.contains('"token_count"') {
				continue
			}
			decoded := json2.decode[json2.Any](line) or {
				parse_errors++
				continue
			}
			root := agent_usage_map(decoded)
			payload := agent_usage_child(root, 'payload')
			if json_str(payload, 'type') != 'token_count' {
				continue
			}
			info := agent_usage_child(payload, 'info')
			last := agent_usage_child(info, 'last_token_usage')
			if last.len == 0 {
				continue
			}
			file_calls++
			calls++
			r.input_tokens += agent_usage_i64(last, 'input_tokens')
			r.output_tokens += agent_usage_i64(last, 'output_tokens')
			r.cache_read_tokens += agent_usage_i64(last, 'cached_input_tokens')
			r.cache_write_tokens += agent_usage_i64(last, 'cache_write_input_tokens')
			r.reasoning_tokens += agent_usage_i64(last, 'reasoning_output_tokens')
			ts := json_str(root, 'timestamp')
			if ts > latest_ts {
				latest_ts = ts
				if r.period_start.len == 0 {
					r.period_start = ts
				}
				limits := agent_usage_child(payload, 'rate_limits')
				primary := agent_usage_child(limits, 'primary')
				if primary.len > 0 && 'resets_at' in primary {
					r.has_quota = true
					r.quota_used_percent = (primary['used_percent'] or { json2.Any(0) }).f64()
					r.quota_window_minutes = agent_usage_i64(primary, 'window_minutes')
					r.quota_resets_at_unix = agent_usage_i64(primary, 'resets_at')
				}
				credits := agent_usage_child(limits, 'credits')
				if credits.len > 0 {
					has := credits['has_credits'] or { json2.Any(false) }
					if has is bool && has as bool {
						r.balance = json_str(credits, 'balance')
					}
				}
			}
			if r.period_start.len == 0 || (ts.len > 0 && ts < r.period_start) {
				r.period_start = ts
			}
		}
		if file_calls > 0 {
			sessions++
			mt := agent_usage_mtime(f)
			if mt > r.measured_at_unix {
				r.measured_at_unix = mt
			}
		}
	}
	r.period_end = latest_ts
	if parse_errors > 0 {
		r.errors << '${parse_errors} unreadable session file(s)/line(s) skipped.'
	}
	if calls == 0 {
		r.status = 'error'
		r.errors << 'Codex sessions exist but carry no token_count usage events.'
		return r
	}
	r.status = 'ok'
	r.has_tokens = true
	r.sessions = sessions
	r.api_calls = calls
	return r
}

// --- Claude Code collector: the CLI's own stats-cache.json aggregate
// (bounded and provider-computed). Raw transcript rescans are
// deliberately not a source: fork/resume copies double-count. The
// cache's costUSD is never surfaced; there is no cost field. ---

pub fn collect_claude_usage_at(claude_dir string) AgentUsageRecord {
	mut r := agent_usage_base('claude-code', 'claude-stats-cache')
	path := os.join_path(claude_dir, 'stats-cache.json')
	r.measured_at_unix = agent_usage_mtime(path)
	raw := os.read_file(path) or {
		r.errors << 'No Claude Code stats cache at stats-cache.json (Claude Code not used here, or cache not yet computed).'
		return r
	}
	decoded := json2.decode[json2.Any](raw) or {
		r.status = 'error'
		r.errors << 'Claude Code stats cache is not valid JSON.'
		return r
	}
	root := agent_usage_map(decoded)
	model_usage := agent_usage_child(root, 'modelUsage')
	if model_usage.len == 0 {
		r.status = 'error'
		r.errors << 'Claude Code stats cache carries no modelUsage.'
		return r
	}
	mut models := []string{}
	mut names := model_usage.keys()
	names.sort()
	for name in names {
		u := agent_usage_map(model_usage[name])
		inp_tok := agent_usage_i64(u, 'inputTokens')
		out_tok := agent_usage_i64(u, 'outputTokens')
		r.input_tokens += inp_tok
		r.output_tokens += out_tok
		r.cache_read_tokens += agent_usage_i64(u, 'cacheReadInputTokens')
		r.cache_write_tokens += agent_usage_i64(u, 'cacheCreationInputTokens')
		models << '${name}:${inp_tok + out_tok}'
	}
	r.status = 'ok'
	r.has_tokens = true
	r.models = models.join(',')
	if 'totalSessions' in root {
		r.sessions = root['totalSessions'].i64()
	}
	r.period_start = json_str(root, 'firstSessionDate')
	r.period_end = json_str(root, 'lastComputedDate')
	return r
}

// --- Muse collector: session.jsonl usage records
// (payload.event.record.quantity), deduplicated by usage_id so a
// record copied into a subagent log counts once. Muse's key-endpoint
// quota is deliberately NOT probed: that needs the OAuth credential,
// and credential contents are never read here — quota stays unknown. ---

pub fn collect_muse_usage_at(sessions_dir string) AgentUsageRecord {
	mut r := agent_usage_base('muse', 'muse-session-jsonl')
	if !os.is_dir(sessions_dir) {
		r.errors << 'No Muse sessions directory (Muse not used on this machine?).'
		return r
	}
	files, truncated := agent_usage_jsonl_files(sessions_dir)
	if truncated {
		r.errors << 'Truncated at ${agent_usage_max_files} session files; totals understate.'
	}
	mut seen_ids := map[string]bool{}
	mut session_ids := map[string]bool{}
	mut calls := i64(0)
	mut parse_errors := 0
	for f in files {
		lines := os.read_lines(f) or {
			parse_errors++
			continue
		}
		mut file_used := false
		for line in lines {
			if !line.contains('"input_tokens"') {
				continue
			}
			decoded := json2.decode[json2.Any](line) or {
				parse_errors++
				continue
			}
			root := agent_usage_map(decoded)
			payload := agent_usage_child(root, 'payload')
			event := agent_usage_child(payload, 'event')
			record := agent_usage_child(event, 'record')
			quantity := agent_usage_child(record, 'quantity')
			if quantity.len == 0 {
				continue
			}
			uid := json_str(record, 'usage_id')
			if uid.len > 0 {
				if seen_ids[uid] {
					continue
				}
				seen_ids[uid] = true
			}
			owner := agent_usage_child(record, 'owner')
			sid := json_str(owner, 'session_id')
			if sid.len > 0 {
				session_ids[sid] = true
			}
			calls++
			file_used = true
			r.input_tokens += agent_usage_i64(quantity, 'input_tokens')
			r.output_tokens += agent_usage_i64(quantity, 'output_tokens')
			r.cache_read_tokens += agent_usage_i64(quantity, 'cached_tokens')
			r.reasoning_tokens += agent_usage_i64(quantity, 'reasoning_tokens')
		}
		if file_used {
			mt := agent_usage_mtime(f)
			if mt > r.measured_at_unix {
				r.measured_at_unix = mt
			}
		}
	}
	if parse_errors > 0 {
		r.errors << '${parse_errors} unreadable session file(s)/line(s) skipped.'
	}
	if calls == 0 {
		r.status = 'error'
		r.errors << 'Muse sessions exist but carry no usage quantity records.'
		return r
	}
	r.status = 'ok'
	r.has_tokens = true
	r.sessions = i64(session_ids.len)
	r.api_calls = calls
	return r
}

// --- OpenCode collector: the session table's own token aggregates in
// opencode.db, read-only SELECTs only. The db's recorded `cost`
// column is never read into this contract (no cost field exists). ---

pub fn collect_opencode_usage_at(db_path string) AgentUsageRecord {
	mut r := agent_usage_base('opencode', 'opencode-session-db')
	r.measured_at_unix = agent_usage_mtime(db_path)
	if !os.exists(db_path) {
		r.errors << 'No OpenCode database (OpenCode not used on this machine?).'
		return r
	}
	mut db := sqlite.connect(db_path) or {
		r.status = 'error'
		r.errors << 'Cannot open OpenCode database: ${err.msg()}'
		return r
	}
	defer {
		db.close()
	}
	rows := db.exec('SELECT COUNT(*), COALESCE(SUM(tokens_input),0), COALESCE(SUM(tokens_output),0), COALESCE(SUM(tokens_reasoning),0), COALESCE(SUM(tokens_cache_read),0), COALESCE(SUM(tokens_cache_write),0) FROM session') or {
		r.status = 'error'
		r.errors << 'OpenCode database has no session token aggregates.'
		return r
	}
	if rows.len == 0 || rows[0].vals[0].i64() == 0 {
		r.status = 'error'
		r.errors << 'OpenCode database has no sessions yet.'
		return r
	}
	t := rows[0].vals
	r.status = 'ok'
	r.has_tokens = true
	r.sessions = t[0].i64()
	r.input_tokens = t[1].i64()
	r.output_tokens = t[2].i64()
	r.reasoning_tokens = t[3].i64()
	r.cache_read_tokens = t[4].i64()
	r.cache_write_tokens = t[5].i64()
	return r
}

// --- aggregate entry point ---

pub fn agent_usage_collect(id string) []AgentUsageRecord {
	match id {
		'javi-hermes' { return [collect_hermes_usage_at(agent_usage_hermes_db())] }
		'codex' { return [collect_codex_usage_at(agent_usage_codex_sessions())] }
		'claude-code' { return [collect_claude_usage_at(agent_usage_claude_dir())] }
		'muse' { return [collect_muse_usage_at(agent_usage_muse_sessions())] }
		'opencode' { return [collect_opencode_usage_at(agent_usage_opencode_db())] }
		else {}
	}
	return [
		collect_hermes_usage_at(agent_usage_hermes_db()),
		collect_codex_usage_at(agent_usage_codex_sessions()),
		collect_claude_usage_at(agent_usage_claude_dir()),
		collect_muse_usage_at(agent_usage_muse_sessions()),
		collect_opencode_usage_at(agent_usage_opencode_db()),
	]
}

// agent_usage_result renders the normalized records for
// `horneroctl agent usage [id]`. ok=true iff at least one collector
// produced an 'ok' record; the data always carries every record
// (errors as explicit error states, never zeroed counters) so JSON
// consumers keep per-provider truth even on exit 1.
pub fn agent_usage_result(id string) CommandResult {
	return agent_usage_render(agent_usage_collect(id))
}

// agent_usage_render is the fixture-friendly render behind agent_usage_result.
pub fn agent_usage_render(records []AgentUsageRecord) CommandResult {
	mut data := map[string]string{}
	data['schemaVersion'] = agent_usage_schema_version.str()
	mut lines := []string{}
	mut providers := []string{}
	mut any_ok := false
	for r in records {
		providers << r.provider
		agent_usage_flat(mut data, r)
		if r.status == 'ok' {
			any_ok = true
			lines << '${r.provider}: ${r.input_tokens} in / ${r.output_tokens} out (source ${r.source}, ${r.freshness()}); quota ${data['usage.${r.provider}.quota']}'
		} else {
			lines << '${r.provider}: ${r.status} — ${r.errors.join('; ')}'
		}
	}
	data['providers'] = providers.join(',')
	data['count'] = records.len.str()
	data['records'] = agent_usage_encode(records)
	return CommandResult{
		command: 'agent usage'
		ok:      any_ok
		message: lines.join('\n')
		data:    data
	}
}
