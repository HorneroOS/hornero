module hornero_core

import db.sqlite
import os

fn agent_usage_tmp(label string) string {
	dir := os.join_path(os.temp_dir(), 'hornero-agent-usage-${label}-${os.getpid()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err) }
	return dir
}

fn test_collect_hermes_usage_fixture() {
	dir := agent_usage_tmp('hermes')
	defer {
		os.rmdir_all(dir) or {}
	}
	db_path := os.join_path(dir, 'state.db')
	mut db := sqlite.connect(db_path) or { panic(err) }
	db.exec('CREATE TABLE session_model_usage (session_id TEXT, model TEXT, billing_provider TEXT, billing_base_url TEXT, billing_mode TEXT, task TEXT, api_call_count INTEGER, input_tokens INTEGER, output_tokens INTEGER, cache_read_tokens INTEGER, cache_write_tokens INTEGER, reasoning_tokens INTEGER, PRIMARY KEY (session_id, model, billing_provider, billing_base_url, billing_mode, task))') or {
		panic(err)
	}
	db.exec("INSERT INTO session_model_usage VALUES ('s1','gpt-5','','','','',2,100,10,3,1,4)") or {
		panic(err)
	}
	db.close()
	r := collect_hermes_usage_at(db_path)
	assert r.status == 'ok'
	assert r.provider == 'javi-hermes'
	assert r.account == 'unknown'
	assert r.input_tokens == 100
	assert r.output_tokens == 10
	assert r.sessions == 1
	assert r.api_calls == 2
	assert r.models == 'gpt-5:110'
	// Hermes state carries no official quota: never invented.
	assert !r.has_quota
	assert agent_usage_encode([r]).contains('"quota":"unknown"')
	missing := collect_hermes_usage_at(os.join_path(dir, 'nope.db'))
	assert missing.status == 'unavailable'
	assert !missing.has_tokens
}

fn test_collect_codex_usage_fixture() {
	dir := agent_usage_tmp('codex')
	defer {
		os.rmdir_all(dir) or {}
	}
	day := os.join_path(dir, '2026', '11', '13')
	os.mkdir_all(day) or { panic(err) }
	rollout := '{"timestamp":"2026-11-13T01:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":999,"output_tokens":999},"last_token_usage":{"input_tokens":40,"cached_input_tokens":5,"cache_write_input_tokens":1,"output_tokens":4,"reasoning_output_tokens":2}},"rate_limits":{"primary":{"used_percent":12.5,"window_minutes":300,"resets_at":1799999999},"credits":{"has_credits":true,"balance":"3.50"}}}}
{"timestamp":"2026-11-13T02:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1999,"output_tokens":1999},"last_token_usage":{"input_tokens":10,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}},"rate_limits":{"primary":{"used_percent":20.0,"window_minutes":300,"resets_at":1800000000},"credits":{"has_credits":true,"balance":"3.00"}}}}
{"timestamp":"2026-11-13T02:00:01Z","type":"response_item","payload":{"type":"message","content":"fixture-secret-should-never-appear"}}
'
	os.write_file(os.join_path(day, 'rollout-a.jsonl'), rollout) or { panic(err) }
	r := collect_codex_usage_at(dir)
	assert r.status == 'ok'
	// last_token_usage sums (40+10), never cumulative totals.
	assert r.input_tokens == 50
	assert r.output_tokens == 5
	assert r.cache_read_tokens == 5
	assert r.reasoning_tokens == 2
	assert r.sessions == 1
	assert r.api_calls == 2
	// Official quota only because Codex recorded it; latest wins.
	assert r.has_quota
	assert r.quota_resets_at_unix == 1800000000
	assert r.quota_window_minutes == 300
	assert r.balance == '3.00'
	assert r.period_start == '2026-11-13T01:00:00Z'
	assert r.period_end == '2026-11-13T02:00:00Z'
	encoded := agent_usage_encode([r])
	assert !encoded.contains('fixture-secret-should-never-appear')
	assert !encoded.contains('cost')
	missing := collect_codex_usage_at(os.join_path(dir, 'nope'))
	assert missing.status == 'unavailable'
	assert !missing.has_tokens
	assert missing.errors.len > 0
}

fn test_collect_claude_usage_fixture() {
	dir := agent_usage_tmp('claude')
	defer {
		os.rmdir_all(dir) or {}
	}
	cache := '{"firstSessionDate":"2026-09-01T00:00:00Z","lastComputedDate":"2026-11-10","totalSessions":7,"modelUsage":{"model-a":{"inputTokens":100,"outputTokens":20,"cacheReadInputTokens":9,"cacheCreationInputTokens":2,"costUSD":0},"model-b":{"inputTokens":5,"outputTokens":1,"cacheReadInputTokens":0,"cacheCreationInputTokens":0,"costUSD":0}}}'
	os.write_file(os.join_path(dir, 'stats-cache.json'), cache) or { panic(err) }
	r := collect_claude_usage_at(dir)
	assert r.status == 'ok'
	assert r.input_tokens == 105
	assert r.output_tokens == 21
	assert r.cache_read_tokens == 9
	assert r.cache_write_tokens == 2
	assert r.sessions == 7
	assert r.models == 'model-a:120,model-b:6'
	assert !r.has_quota
	assert !agent_usage_encode([r]).contains('costUSD')
	bad_dir := agent_usage_tmp('claude-bad')
	defer {
		os.rmdir_all(bad_dir) or {}
	}
	os.write_file(os.join_path(bad_dir, 'stats-cache.json'), 'not json') or { panic(err) }
	bad := collect_claude_usage_at(bad_dir)
	assert bad.status == 'error'
	assert !bad.has_tokens
}

fn test_collect_muse_usage_fixture() {
	dir := agent_usage_tmp('muse')
	defer {
		os.rmdir_all(dir) or {}
	}
	sess := os.join_path(dir, '2026', '11', '13', 'abc')
	os.mkdir_all(sess) or { panic(err) }
	line := '{"record_type":"event","payload_type":"runtime.session","recorded_at":1794462645250044,"payload":{"event":{"record":{"usage_id":"u1","owner":{"session_id":"s1"},"quantity":{"cached_tokens":3,"input_tokens":30,"output_tokens":6,"reasoning_tokens":1,"reported":true}}}}}'
	line2 := '{"record_type":"event","payload_type":"runtime.session","recorded_at":1794462645250045,"payload":{"event":{"record":{"usage_id":"u2","owner":{"session_id":"s1"},"quantity":{"cached_tokens":0,"input_tokens":10,"output_tokens":2,"reasoning_tokens":0,"reported":true}}}}}'
	// u1 duplicated (copied into a subagent log) must count once.
	os.write_file(os.join_path(sess, 'session.jsonl'), line + '\n' + line2 + '\n' + line +
		'\n') or { panic(err) }
	r := collect_muse_usage_at(dir)
	assert r.status == 'ok'
	assert r.input_tokens == 40
	assert r.output_tokens == 8
	assert r.cache_read_tokens == 3
	assert r.sessions == 1
	assert r.api_calls == 2
	// Muse quota needs its key endpoint + credential: never probed here.
	assert !r.has_quota
	missing := collect_muse_usage_at(os.join_path(dir, 'nope'))
	assert missing.status == 'unavailable'
}

fn test_collect_opencode_usage_fixture() {
	dir := agent_usage_tmp('opencode')
	defer {
		os.rmdir_all(dir) or {}
	}
	db_path := os.join_path(dir, 'opencode.db')
	mut db := sqlite.connect(db_path) or { panic(err) }
	db.exec('CREATE TABLE session (id TEXT, cost REAL, tokens_input INTEGER, tokens_output INTEGER, tokens_reasoning INTEGER, tokens_cache_read INTEGER, tokens_cache_write INTEGER)') or {
		panic(err)
	}
	db.exec("INSERT INTO session VALUES ('a', 9.99, 100, 10, 1, 4, 2)") or { panic(err) }
	db.exec("INSERT INTO session VALUES ('b', 9.99, 50, 5, 0, 0, 0)") or { panic(err) }
	db.close()
	r := collect_opencode_usage_at(db_path)
	assert r.status == 'ok'
	assert r.sessions == 2
	assert r.input_tokens == 150
	assert r.output_tokens == 15
	assert r.reasoning_tokens == 1
	assert r.cache_read_tokens == 4
	assert !agent_usage_encode([r]).contains('9.99')
	missing := collect_opencode_usage_at(os.join_path(dir, 'nope.db'))
	assert missing.status == 'unavailable'
	assert !missing.has_tokens
}

fn test_agent_usage_render_never_zeros_on_error() {
	mut err_rec := agent_usage_base('codex', 'codex-rollout-jsonl')
	err_rec.status = 'error'
	err_rec.errors << 'fixture failure'
	res := agent_usage_render([err_rec])
	assert !res.ok
	assert res.command == 'agent usage'
	assert res.data['schemaVersion'] == '1'
	assert res.data['usage.codex.inputTokens'] == 'unknown'
	assert res.data['usage.codex.quota'] == 'unknown'
	assert res.data['usage.codex.errors'] == 'fixture failure'
	assert !res.data['records'].contains('"inputTokens":0')
	mut ok_rec := agent_usage_base('muse', 'muse-session-jsonl')
	ok_rec.status = 'ok'
	ok_rec.has_tokens = true
	ok_rec.input_tokens = 3
	ok_rec.output_tokens = 1
	ok_rec.sessions = 1
	mixed := agent_usage_render([err_rec, ok_rec])
	assert mixed.ok
	assert mixed.data['providers'] == 'codex,muse'
	assert mixed.data['usage.muse.totalTokens'] == '4'
}
