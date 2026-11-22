module hornero_core

import db.sqlite
import net.http
import os
import time
import x.json2

// Provider quota probes for the normalized usage contract (schema
// v2, credential scope B). Each probe is isolated: it only ever
// fills quota windows, plan, billing and auth status on its own
// record, and every failure degrades to quota-unknown plus a plain
// `note` — local usage is never discarded and no figure is invented.
//
// What each probe is allowed to touch (nothing else):
// - Muse Code: runs Muse's own first-party `muse usage --json`
//   (no model turn, no credential read by Hornero).
// - Claude Code: reads the access token Muse itself stored
//   in `.credentials.json`, in memory only, and asks Anthropic's
//   OAuth usage endpoint about that account. The token is never
//   printed, logged, cached, refreshed, or sent anywhere else.
// - Cursor: reads the sign-in token from the Cursor editor's state
//   database, in memory only, and calls the same dashboard RPCs the
//   Cursor CLI calls (undocumented upstream; handled fail-closed).
//
// Cached payloads under the XDG cache contain provider usage JSON
// only — never tokens — in a user-private directory.

struct AgentUsageHttp {
	status int
	body   string
	failed bool
}

// agent_usage_http performs one bounded JSON request. Errors are
// reported generically so no transport detail can leak a header.
fn agent_usage_http(method http.Method, url string, body string, headers map[string]string) AgentUsageHttp {
	mut req := http.Request{
		method:       method
		url:          url
		data:         body
		read_timeout: 20 * time.second
	}
	req.header = http.new_custom_header_from_map(headers) or {
		return AgentUsageHttp{ failed: true }
	}
	resp := req.do() or { return AgentUsageHttp{ failed: true } }
	if resp.body.len > 8 * 1024 * 1024 {
		return AgentUsageHttp{ failed: true }
	}
	return AgentUsageHttp{
		status: resp.status_code
		body:   resp.body
	}
}

fn agent_usage_quota_cache_dir() string {
	return os.join_path(resolve_paths().cache_dir, 'hornero', 'agent-usage')
}

// agent_usage_quota_cache_read returns (payload, fetchedAtUnix).
fn agent_usage_quota_cache_read(name string) (string, i64) {
	raw := os.read_file(os.join_path(agent_usage_quota_cache_dir(), '${name}.json')) or {
		return '', 0
	}
	decoded := json2.decode[json2.Any](raw) or { return '', 0 }
	root := agent_usage_map(decoded)
	return json_str(root, 'payload'), agent_usage_i64(root, 'fetchedAtUnix')
}

fn agent_usage_quota_cache_write(name string, payload string) {
	dir := agent_usage_quota_cache_dir()
	os.mkdir_all(dir) or { return }
	os.chmod(dir, 0o700) or {}
	mut m := map[string]json2.Any{}
	m['fetchedAtUnix'] = json2.Any(time.now().unix())
	m['payload'] = payload
	path := os.join_path(dir, '${name}.json')
	os.write_file(path, json2.encode(m, escape_unicode: true)) or { return }
	os.chmod(path, 0o600) or {}
}

// --- whole-result cache: one collection for every UI surface ---

fn agent_usage_records_cache_name(id string) string {
	return 'records-${if id.len > 0 { id } else { 'all' }}'
}

fn agent_usage_records_cache_store(id string, res CommandResult) {
	mut data := map[string]json2.Any{}
	for k, v in res.data {
		data[k] = v
	}
	mut m := map[string]json2.Any{}
	m['ok'] = json2.Any(res.ok)
	m['message'] = res.message
	m['data'] = json2.Any(data)
	agent_usage_quota_cache_write(agent_usage_records_cache_name(id),
		json2.encode(m, escape_unicode: true))
}

fn agent_usage_records_cache_hit(id string) ?CommandResult {
	payload, fetched := agent_usage_quota_cache_read(agent_usage_records_cache_name(id))
	if payload.len == 0 || time.now().unix() - fetched >= agent_usage_records_cache_ttl_sec {
		return none
	}
	decoded := json2.decode[json2.Any](payload) or { return none }
	root := agent_usage_map(decoded)
	data_any := agent_usage_child(root, 'data')
	if json_str(data_any, 'schemaVersion') != agent_usage_schema_version.str() {
		return none
	}
	mut data := map[string]string{}
	for k, v in data_any {
		data[k] = v.str()
	}
	ok_any := root['ok'] or { json2.Any(false) }
	return CommandResult{
		command: 'agent usage'
		ok:      ok_any is bool && ok_any as bool
		message: json_str(root, 'message')
		data:    data
	}
}

// agent_usage_parse_iso converts a provider RFC3339 timestamp to
// unix seconds; unparseable or empty values stay unknown (0).
fn agent_usage_parse_iso(s string) i64 {
	if s.len == 0 {
		return 0
	}
	t := time.parse_rfc3339(s) or { return 0 }
	return t.unix()
}

fn agent_usage_f64(m map[string]json2.Any, key string) f64 {
	if key in m {
		return m[key].f64()
	}
	return 0
}

// agent_usage_ms reads an epoch that may arrive as milliseconds or
// seconds, as a number or a string (Connect JSON writes i64 as str).
fn agent_usage_ms(m map[string]json2.Any, key string) i64 {
	mut v := agent_usage_i64(m, key)
	if v == 0 {
		v = json_str(m, key).i64()
	}
	if v > 100_000_000_000 {
		return v / 1000
	}
	return v
}

// --- Muse Code quota: first-party `muse usage --json` ---

// agent_usage_apply_muse_quota maps one `muse usage --json` payload
// onto its record. Fixture-friendly: no process is spawned here.
pub fn agent_usage_apply_muse_quota(mut r AgentUsageRecord, raw string) bool {
	decoded := json2.decode[json2.Any](raw) or { return false }
	root := agent_usage_map(decoded)
	allowance := agent_usage_child(root, 'allowance')
	if allowance.len == 0 {
		reason := json_str(root, 'reason')
		r.note = if reason.len > 0 {
			'Muse quota unavailable (${reason}); local activity shown.'
		} else {
			'Muse quota unavailable; local activity shown.'
		}
		return false
	}
	mut wins := []AgentUsageWindow{}
	window := agent_usage_child(allowance, 'window')
	if 'usedPercent' in window {
		wins << AgentUsageWindow{
			id:             'window'
			label:          'Window'
			used_percent:   agent_usage_f64(window, 'usedPercent')
			window_minutes: -1
			resets_at_unix: agent_usage_ms(window, 'resetsAtMs')
		}
	}
	weekly := agent_usage_child(allowance, 'weekly')
	if 'usedPercent' in weekly {
		wins << AgentUsageWindow{
			id:             'weekly'
			label:          'Weekly'
			used_percent:   agent_usage_f64(weekly, 'usedPercent')
			window_minutes: 10080
			resets_at_unix: agent_usage_ms(weekly, 'resetsAtMs')
		}
	}
	if wins.len == 0 {
		return false
	}
	r.windows = wins
	agent_usage_sync_legacy(mut r)
	tier := json_str(allowance, 'tier')
	if tier.len > 0 {
		r.plan = tier
		r.billing = 'subscription'
	}
	r.auth_status = 'signed-in'
	// A signed-in account with reported quota is a usable record even
	// before this machine has any local sessions.
	r.status = 'ok'
	as_of := agent_usage_ms(allowance, 'asOfMs')
	r.quota_at_unix = if as_of > 0 { as_of } else { time.now().unix() }
	return true
}

pub fn collect_muse_usage_full(force bool) AgentUsageRecord {
	mut r := collect_muse_usage_at(agent_usage_muse_sessions())
	bin := find_on_path('muse')
	if bin.len == 0 {
		if r.note.len == 0 {
			r.note = 'Quota unknown: the Muse executable was not found.'
		}
		return r
	}
	if !force {
		cached, fetched := agent_usage_quota_cache_read('muse-usage')
		if cached.len > 0 && time.now().unix() - fetched < agent_usage_quota_cache_ttl_sec {
			if agent_usage_apply_muse_quota(mut r, cached) {
				r.quota_at_unix = fetched
				return r
			}
		}
	}
	rep := run_exec(ExecSpec{
		prog:        bin
		args:        ['usage', '--json']
		timeout_sec: 20
	})
	if rep.ok && rep.output.len > 0 {
		agent_usage_quota_cache_write('muse-usage', rep.output)
		agent_usage_apply_muse_quota(mut r, rep.output)
		return r
	}
	cached, fetched := agent_usage_quota_cache_read('muse-usage')
	if cached.len > 0 && time.now().unix() - fetched < agent_usage_quota_stale_max_sec {
		if agent_usage_apply_muse_quota(mut r, cached) {
			r.quota_at_unix = fetched
			r.note = 'Showing the last known Muse quota; a fresh check failed.'
			return r
		}
	}
	if r.note.len == 0 {
		r.note = 'Muse quota could not be checked right now; local activity shown.'
	}
	return r
}

// --- Claude Code quota: Anthropic OAuth usage endpoint (scope B) ---

// agent_usage_claude_plan_label leads with the subscription the
// credentials name and qualifies it with the rate-limit multiplier,
// so Max 5x reads as itself and a Team seat is never passed as Max.
fn agent_usage_claude_plan_label(subscription string, tier string) string {
	mut plan := subscription
	if plan.len > 0 {
		plan = plan[0].ascii_str().to_upper() + plan[1..]
	}
	idx := tier.to_lower().index('max_') or { return plan }
	rest := tier.to_lower()[(idx + 4)..]
	mut mult := ''
	for ch in rest {
		if ch.is_digit() || ch == `x` {
			mult += ch.ascii_str()
		} else {
			break
		}
	}
	if mult.len < 2 || !mult.ends_with('x') {
		return plan
	}
	return '${if plan.len > 0 { plan } else { 'Max' }} ${mult}'
}

// agent_usage_apply_claude_quota maps one OAuth usage payload. The
// endpoint reports percentages (0.6 means 0.6% used), matching what
// Claude Code's own /usage renders.
pub fn agent_usage_apply_claude_quota(mut r AgentUsageRecord, raw string) bool {
	decoded := json2.decode[json2.Any](raw) or { return false }
	root := agent_usage_map(decoded)
	mut wins := []AgentUsageWindow{}
	for spec in [['five_hour', 'session', '5-hour', '300'], ['seven_day', 'weekly', 'Weekly', '10080']] {
		bucket := agent_usage_child(root, spec[0])
		if 'utilization' in bucket {
			wins << AgentUsageWindow{
				id:             spec[1]
				label:          spec[2]
				used_percent:   agent_usage_f64(bucket, 'utilization')
				window_minutes: spec[3].i64()
				resets_at_unix: agent_usage_parse_iso(json_str(bucket, 'resets_at'))
			}
		}
	}
	// Model-scoped allowances only appear in the `limits` array.
	if 'limits' in root {
		if root['limits'] is []json2.Any {
			for any_entry in root['limits'] as []json2.Any {
				entry := agent_usage_map(any_entry)
				scope := agent_usage_child(entry, 'scope')
				model := agent_usage_child(scope, 'model')
				name := json_str(model, 'display_name')
				if name.len == 0 || 'percent' !in entry {
					continue
				}
				kind := json_str(entry, 'kind').to_lower()
				weekly := kind.contains('week') || kind.contains('day')
				wins << AgentUsageWindow{
					id:             'scoped-${name.to_lower()}'
					label:          if weekly { '${name} weekly' } else { name }
					used_percent:   agent_usage_f64(entry, 'percent')
					window_minutes: if weekly { i64(10080) } else { i64(-1) }
					resets_at_unix: agent_usage_parse_iso(json_str(entry, 'resets_at'))
				}
			}
		}
	}
	if wins.len == 0 {
		return false
	}
	r.windows = wins
	agent_usage_sync_legacy(mut r)
	r.auth_status = 'signed-in'
	r.status = 'ok'
	r.quota_at_unix = time.now().unix()
	return true
}

pub fn collect_claude_usage_full(force bool) AgentUsageRecord {
	dir := agent_usage_claude_dir()
	mut r := collect_claude_usage_at(dir)
	raw_cred := os.read_file(os.join_path(dir, '.credentials.json')) or {
		r.note = 'Quota unknown: no stored Claude Code sign-in. Local activity shown.'
		return r
	}
	decoded := json2.decode[json2.Any](raw_cred) or {
		r.note = 'Quota unknown: the stored Claude Code sign-in is unreadable.'
		return r
	}
	oauth := agent_usage_child(agent_usage_map(decoded), 'claudeAiOauth')
	token := json_str(oauth, 'accessToken')
	if token.len == 0 {
		r.auth_status = 'authorization-needed'
		r.note = 'Sign in with `claude auth login` to see subscription quota.'
		return r
	}
	expires_ms := agent_usage_i64(oauth, 'expiresAt')
	if expires_ms > 0 && expires_ms < time.now().unix() * 1000 {
		r.auth_status = 'authorization-needed'
		r.note = 'Claude Code sign-in expired; run `claude auth login`. Local activity shown.'
		return r
	}
	plan := agent_usage_claude_plan_label(json_str(oauth, 'subscriptionType'),
		json_str(oauth, 'rateLimitTier'))
	if plan.len > 0 {
		r.plan = plan
		r.billing = 'subscription'
		r.auth_status = 'signed-in'
	}
	if !force {
		cached, fetched := agent_usage_quota_cache_read('claude-usage')
		if cached.len > 0 && time.now().unix() - fetched < agent_usage_quota_cache_ttl_sec {
			if agent_usage_apply_claude_quota(mut r, cached) {
				r.quota_at_unix = fetched
				return r
			}
		}
	}
	resp := agent_usage_http(.get, 'https://api.anthropic.com/api/oauth/usage', '', {
		'Authorization':  'Bearer ${token}'
		'anthropic-beta': 'oauth-2025-04-20'
	})
	if !resp.failed && resp.status == 200 {
		agent_usage_quota_cache_write('claude-usage', resp.body)
		agent_usage_apply_claude_quota(mut r, resp.body)
		return r
	}
	if resp.status == 401 || resp.status == 403 {
		r.auth_status = 'authorization-needed'
		r.note = 'Anthropic refused the stored sign-in; run `claude auth login`.'
		return r
	}
	cached, fetched := agent_usage_quota_cache_read('claude-usage')
	if cached.len > 0 && time.now().unix() - fetched < agent_usage_quota_stale_max_sec {
		if agent_usage_apply_claude_quota(mut r, cached) {
			r.quota_at_unix = fetched
			r.note = 'Showing the last known Claude quota; Anthropic did not answer just now.'
			return r
		}
	}
	r.note = if resp.status == 429 {
		'Anthropic rate-limited the quota check; try again shortly.'
	} else {
		'Claude quota could not be checked right now; local activity shown.'
	}
	return r
}

// --- Cursor: dashboard RPCs with the stored editor sign-in (B) ---

// agent_usage_cursor_state reads one non-secret-or-token value from
// the Cursor editor state DB. Only the access token and membership
// keys are ever queried; the token never leaves process memory.
fn agent_usage_cursor_state(db_path string, key string) string {
	mut db := sqlite.connect(db_path) or { return '' }
	defer {
		db.close()
	}
	rows := db.exec("SELECT value FROM ItemTable WHERE key='${key}'") or { return '' }
	if rows.len == 0 || rows[0].vals.len == 0 {
		return ''
	}
	return rows[0].vals[0]
}

fn agent_usage_cursor_call(token string, method string, body string) AgentUsageHttp {
	return agent_usage_http(.post, 'https://api2.cursor.sh/aiserver.v1.DashboardService/${method}',
		body, {
			'Content-Type':             'application/json'
			'Connect-Protocol-Version': '1'
			'Authorization':            'Bearer ${token}'
			'x-cursor-client-type':     'cli'
		})
}

// agent_usage_apply_cursor_usage maps GetCurrentPeriodUsage (+ the
// planInfo object from GetPlanInfo). Cursor reports whole-percent
// meters itself; spend figures are never divided into an allowance.
pub fn agent_usage_apply_cursor_usage(mut r AgentUsageRecord, period_raw string, plan_raw string) bool {
	decoded := json2.decode[json2.Any](period_raw) or { return false }
	period := agent_usage_map(decoded)
	plan_usage := agent_usage_child(period, 'planUsage')
	if plan_usage.len == 0 {
		return false
	}
	mut plan_info := map[string]json2.Any{}
	if plan_raw.len > 0 {
		pd := json2.decode[json2.Any](plan_raw) or { json2.Any('') }
		plan_info = agent_usage_child(agent_usage_map(pd), 'planInfo')
	}
	billing_end := agent_usage_ms(period, 'billingCycleEnd')
	period_kind := json_str(plan_info, 'includedUsagePeriod').to_upper()
	weekly := period_kind == '2' || period_kind.contains('WEEKLY')
	mut window_name := 'Monthly'
	mut resets := billing_end
	mut minutes := i64(-1)
	if weekly {
		window_name = 'Weekly'
		minutes = 10080
		wr := agent_usage_ms(plan_info, 'includedUsageResetsAt')
		if wr > 0 {
			resets = wr
		}
	}
	mut wins := []AgentUsageWindow{}
	for spec in [['totalPercentUsed', 'included', 'Included total'],
		['autoPercentUsed', 'auto', 'Auto models'], ['apiPercentUsed', 'named', 'Named models']] {
		if spec[0] in plan_usage {
			wins << AgentUsageWindow{
				id:             spec[1]
				label:          '${spec[2]} · ${window_name}'
				used_percent:   agent_usage_f64(plan_usage, spec[0])
				window_minutes: minutes
				resets_at_unix: resets
			}
		}
	}
	spend := agent_usage_child(period, 'spendLimitUsage')
	limit_cents := agent_usage_f64(spend, 'individualLimit')
	if limit_cents > 0 {
		mut used_cents := agent_usage_f64(spend, 'individualUsed')
		if 'individualUsed' !in spend && 'individualRemaining' in spend {
			used_cents = limit_cents - agent_usage_f64(spend, 'individualRemaining')
		}
		if used_cents >= 0 {
			wins << AgentUsageWindow{
				id:             'on-demand'
				label:          'On-demand · Monthly'
				used_percent:   used_cents / limit_cents * 100.0
				window_minutes: -1
				resets_at_unix: billing_end
			}
		}
	}
	if wins.len == 0 {
		return false
	}
	r.windows = wins
	agent_usage_sync_legacy(mut r)
	plan_name := json_str(plan_info, 'planName')
	if plan_name.len > 0 {
		r.plan = plan_name
	}
	r.billing = 'subscription'
	r.auth_status = 'signed-in'
	r.status = 'ok'
	r.measured_at_unix = time.now().unix()
	r.quota_at_unix = time.now().unix()
	return true
}

// agent_usage_apply_cursor_events sums one GetAggregatedUsageEvents
// reply (account-global token use for the asked range).
pub fn agent_usage_apply_cursor_events(mut r AgentUsageRecord, raw string) bool {
	decoded := json2.decode[json2.Any](raw) or { return false }
	root := agent_usage_map(decoded)
	if 'aggregations' !in root || root['aggregations'] !is []json2.Any {
		return false
	}
	mut by_model := map[string]i64{}
	for any_row in root['aggregations'] as []json2.Any {
		row := agent_usage_map(any_row)
		inp := agent_usage_i64(row, 'inputTokens')
		out := agent_usage_i64(row, 'outputTokens')
		r.input_tokens += inp
		r.output_tokens += out
		r.cache_read_tokens += agent_usage_i64(row, 'cacheReadTokens')
		r.cache_write_tokens += agent_usage_i64(row, 'cacheWriteTokens')
		model := json_str(row, 'modelIntent')
		if model.len > 0 {
			by_model[model] += inp + out
		}
	}
	if by_model.len == 0 && r.input_tokens == 0 && r.output_tokens == 0 {
		return false
	}
	r.has_tokens = true
	mut names := by_model.keys()
	names.sort()
	mut parts := []string{cap: names.len}
	for n in names {
		parts << '${n}:${by_model[n]}'
	}
	r.models = parts.join(',')
	return true
}

pub fn collect_cursor_usage(force bool) AgentUsageRecord {
	mut r := agent_usage_base_ex('cursor', 'cursor', 'Cursor', 'cursor-dashboard-rpc',
		'account')
	db_path := agent_usage_cursor_db()
	if !os.exists(db_path) && !os.is_dir(os.join_path(os.home_dir(), '.cursor')) {
		r.errors << 'Cursor is not installed or has never run on this machine.'
		return r
	}
	token := agent_usage_cursor_state(db_path, 'cursorAuth/accessToken')
	if token.len == 0 {
		r.auth_status = 'authorization-needed'
		r.errors << 'Sign in to the Cursor editor, or run `cursor-agent login`, to see Cursor usage.'
		return r
	}
	membership := agent_usage_cursor_state(db_path, 'cursorAuth/stripeMembershipType')
	if membership.len > 0 {
		r.plan = membership
		r.billing = 'subscription'
		r.auth_status = 'signed-in'
	}
	if !force {
		period, fetched := agent_usage_quota_cache_read('cursor-period')
		if period.len > 0 && time.now().unix() - fetched < agent_usage_quota_cache_ttl_sec {
			plan, _ := agent_usage_quota_cache_read('cursor-plan')
			if agent_usage_apply_cursor_usage(mut r, period, plan) {
				r.quota_at_unix = fetched
				r.measured_at_unix = fetched
				return r
			}
		}
	}
	period_resp := agent_usage_cursor_call(token, 'GetCurrentPeriodUsage', '{}')
	if period_resp.status == 401 || period_resp.status == 403 {
		r.auth_status = 'authorization-needed'
		r.errors << 'Cursor refused the stored sign-in; sign in again in the editor.'
		return r
	}
	if period_resp.failed || period_resp.status != 200 {
		period, fetched := agent_usage_quota_cache_read('cursor-period')
		if period.len > 0 && time.now().unix() - fetched < agent_usage_quota_stale_max_sec {
			plan, _ := agent_usage_quota_cache_read('cursor-plan')
			if agent_usage_apply_cursor_usage(mut r, period, plan) {
				r.quota_at_unix = fetched
				r.measured_at_unix = fetched
				r.note = 'Showing the last known Cursor usage; the dashboard did not answer just now.'
				return r
			}
		}
		r.status = 'error'
		r.errors << if period_resp.status == 429 {
			'Cursor rate-limited the usage check; try again shortly.'
		} else {
			"Cursor's dashboard could not be reached right now."
		}
		return r
	}
	plan_resp := agent_usage_cursor_call(token, 'GetPlanInfo', '{}')
	plan_raw := if !plan_resp.failed && plan_resp.status == 200 { plan_resp.body } else { '' }
	agent_usage_quota_cache_write('cursor-period', period_resp.body)
	if plan_raw.len > 0 {
		agent_usage_quota_cache_write('cursor-plan', plan_raw)
	}
	if !agent_usage_apply_cursor_usage(mut r, period_resp.body, plan_raw) {
		r.status = 'error'
		r.errors << "Cursor's dashboard sent usage in a form Hornero does not read yet."
		return r
	}
	// Account token activity for the current billing cycle (one call).
	period := agent_usage_map(json2.decode[json2.Any](period_resp.body) or { json2.Any('') })
	start_ms := agent_usage_ms(period, 'billingCycleStart') * 1000
	end_ms := time.now().unix() * 1000
	if start_ms > 0 && start_ms < end_ms {
		events := agent_usage_cursor_call(token, 'GetAggregatedUsageEvents',
			'{"startDate":"${start_ms}","endDate":"${end_ms}"}')
		if !events.failed && events.status == 200 {
			agent_usage_apply_cursor_events(mut r, events.body)
		}
	}
	return r
}
