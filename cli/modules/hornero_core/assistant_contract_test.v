module hornero_core

import net
import os
import sync
import time

// Mock-Hermes contract suite (hornero#171). A loopback test double
// records the exact requests the assistant HTTP layer sends and
// answers with fixtures whose shapes follow the pinned upstream
// Hermes commit f14699a1379838862d3020b97785796aa555d36d (MIT;
// shapes already documented in assistant.v comments). Reverting
// the approval wire vocabulary (choice once/deny, request_id,
// execution_generation) must fail these tests.

struct RecordedRequest {
	method string
	path   string
	auth   string
	ctype  string
	body   string
}

struct MockGateway {
mut:
	requests []RecordedRequest
	mu       sync.Mutex
	routes   map[string]string
}

fn (mut m MockGateway) recorded() []RecordedRequest {
	m.mu.lock()
	defer { m.mu.unlock() }
	return m.requests.clone()
}

fn (mut m MockGateway) serve(listener &net.TcpListener) {
	for {
		mut conn := listener.accept() or { return }
		m.handle(mut conn)
	}
}

fn (mut m MockGateway) handle(mut conn net.TcpConn) {
	defer { conn.close() or {} }
	mut raw := []u8{}
	mut chunk := []u8{len: 8192}
	mut header_end := -1
	mut content_length := 0
	for {
		n := conn.read(mut chunk) or { return }
		if n == 0 {
			return
		}
		raw << chunk[..n]
		if header_end < 0 {
			text := raw.bytestr()
			idx := text.index('\r\n\r\n') or { -1 }
			if idx >= 0 {
				header_end = idx + 4
				for line in text[..idx].split('\r\n')[1..] {
					parts := line.split_n(':', 2)
					if parts.len == 2 && parts[0].trim_space().to_lower() == 'content-length' {
						content_length = parts[1].trim_space().int()
					}
				}
			}
		}
		if header_end >= 0 && raw.len >= header_end + content_length {
			break
		}
	}
	text := raw.bytestr()
	head := text[..header_end - 4].split('\r\n')
	first := head[0].split(' ')
	mut auth := ''
	mut ctype := ''
	for line in head[1..] {
		parts := line.split_n(':', 2)
		if parts.len != 2 {
			continue
		}
		match parts[0].trim_space().to_lower() {
			'authorization' { auth = parts[1].trim_space() }
			'content-type' { ctype = parts[1].trim_space() }
			else {}
		}
	}
	req := RecordedRequest{
		method: first[0]
		path:   first[1]
		auth:   auth
		ctype:  ctype
		body:   text[header_end..]
	}
	m.mu.lock()
	m.requests << req
	m.mu.unlock()
	mut body := m.routes['${req.method} ${req.path}'] or { '{}' }
	// a route value '!500' answers HTTP 500 (failure injection)
	mut status := '200 OK'
	if body == '!500' {
		status = '500 Internal Server Error'
		body = '{}'
	}
	conn.write_string('HTTP/1.1 ${status}\r\nContent-Type: application/json\r\nContent-Length: ${body.len}\r\nConnection: close\r\n\r\n${body}') or {}
}

// start_mock_gateway points the assistant settings (via
// XDG_CONFIG_HOME) at a fresh mock and returns it with the port.
// Caller must call mock_restore_env with the returned saved env.
fn start_mock_gateway(routes map[string]string) (&MockGateway, map[string]string) {
	mut listener := net.listen_tcp(.ip, '127.0.0.1:0') or { panic(err) }
	addr := listener.addr() or { panic(err) }
	port := addr.str().split(':').last().int()
	mut mock := &MockGateway{
		routes: routes
	}
	spawn mock.serve(listener)

	saved := {
		'XDG_CONFIG_HOME':                  os.getenv('XDG_CONFIG_HOME')
		'HORNERO_ASSISTANT_KEY':            os.getenv('HORNERO_ASSISTANT_KEY')
		'HORNERO_ASSISTANT_SESSIONS_FILE':  os.getenv('HORNERO_ASSISTANT_SESSIONS_FILE')
		'HORNERO_ASSISTANT_RUN_MODES_FILE': os.getenv('HORNERO_ASSISTANT_RUN_MODES_FILE')
		'HORNERO_ASSISTANT_LOG_FILE':       os.getenv('HORNERO_ASSISTANT_LOG_FILE')
	}
	tmp := os.join_path(os.temp_dir(), 'hornero-contract-${port}')
	os.mkdir_all(os.join_path(tmp, 'hornero')) or { panic(err) }
	os.write_file(os.join_path(tmp, 'hornero', 'assistant.json'), '{"enabled":true,"endpoint":"http://127.0.0.1:${port}"}\n') or {
		panic(err)
	}
	os.setenv('XDG_CONFIG_HOME', tmp, true)
	os.setenv('HORNERO_ASSISTANT_KEY', 'contract-test-key', true)
	os.setenv('HORNERO_ASSISTANT_SESSIONS_FILE', os.join_path(tmp, 'sessions.json'), true)
	os.setenv('HORNERO_ASSISTANT_RUN_MODES_FILE', os.join_path(tmp, 'run-modes.tsv'), true)
	os.setenv('HORNERO_ASSISTANT_LOG_FILE', os.join_path(tmp, 'assistant.log'), true)
	return mock, saved
}

fn mock_restore_env(saved map[string]string) {
	for k, v in saved {
		os.setenv(k, v, true)
	}
}

fn mock_wait_requests(mock &MockGateway, count int) []RecordedRequest {
	for _ in 0 .. 100 {
		got := mock.recorded()
		if got.len >= count {
			return got
		}
		time.sleep(20 * time.millisecond)
	}
	return mock.recorded()
}

const contract_capabilities_body = '{"object":"hermes.api_server.capabilities","platform":"hermes-agent","model":"m","auth":{"type":"bearer","required":true},"features":{"run_submission":true,"run_events_sse":true,"run_stop":true,"run_approval_response":true,"approval_events":true,"skills_api":true},"endpoints":{}}'

fn test_contract_capabilities_request_shape() {
	mock, saved := start_mock_gateway({
		'GET /v1/capabilities': contract_capabilities_body
	})
	defer { mock_restore_env(saved) }
	settings := assistant_load_settings()
	assert settings.enabled
	reachable, compatible, _ := assistant_gateway_state(settings)
	assert reachable
	assert compatible
	reqs := mock_wait_requests(mock, 1)
	assert reqs.len >= 1
	assert reqs[0].method == 'GET'
	assert reqs[0].path == '/v1/capabilities'
	assert reqs[0].auth == 'Bearer contract-test-key'
}

fn test_contract_approve_sends_once_with_pending_control() {
	status := '{"pending_controls":[{"kind":"approval","prompt_id":"prompt-1","execution_generation":7}]}'
	mock, saved := start_mock_gateway({
		'GET /v1/runs/run_1':           status
		'POST /v1/runs/run_1/approval': '{}'
	})
	defer { mock_restore_env(saved) }
	assistant_run_mode_record('run_1', 'agent') or { panic(err) }
	result := assistant_approve_report('run_1', 'approve', '')
	assert result.ok
	reqs := mock_wait_requests(mock, 2)
	assert reqs.len == 2
	assert reqs[1].method == 'POST'
	assert reqs[1].path == '/v1/runs/run_1/approval'
	assert reqs[1].ctype.contains('application/json')
	assert reqs[1].body.contains('"choice":"once"')
	assert reqs[1].body.contains('"request_id":"prompt-1"')
	assert reqs[1].body.contains('"execution_generation":7')
}

fn test_contract_deny_sends_deny_and_no_widening() {
	status := '{"pending_controls":[{"kind":"approval","prompt_id":"prompt-9","execution_generation":3}]}'
	mock, saved := start_mock_gateway({
		'GET /v1/runs/run_2':           status
		'POST /v1/runs/run_2/approval': '{}'
	})
	defer { mock_restore_env(saved) }
	assistant_run_mode_record('run_2', 'agent') or { panic(err) }
	result := assistant_approve_report('run_2', 'deny', '')
	assert result.ok
	reqs := mock_wait_requests(mock, 2)
	assert reqs.len == 2
	assert reqs[1].body.contains('"choice":"deny"')
	assert !reqs[1].body.contains('session')
	assert !reqs[1].body.contains('always')
}

fn test_contract_approve_falls_back_to_plain_choice() {
	mock, saved := start_mock_gateway({
		'GET /v1/runs/run_3':           '{"status":"running"}'
		'POST /v1/runs/run_3/approval': '{}'
	})
	defer { mock_restore_env(saved) }
	assistant_run_mode_record('run_3', 'agent') or { panic(err) }
	result := assistant_approve_report('run_3', 'approve', '')
	assert result.ok
	reqs := mock_wait_requests(mock, 2)
	assert reqs.len == 2
	assert reqs[1].body.contains('"choice":"once"')
	assert !reqs[1].body.contains('request_id')
}

fn test_contract_clarify_and_stop_payloads() {
	mock, saved := start_mock_gateway({
		'POST /v1/runs/run_4/clarify': '{}'
		'POST /v1/runs/run_4/stop':    '{}'
	})
	defer { mock_restore_env(saved) }
	assert assistant_clarify_report('run_4', 'use the dark theme').ok
	assert assistant_stop_report('run_4').ok
	reqs := mock_wait_requests(mock, 2)
	assert reqs.len == 2
	assert reqs[0].path == '/v1/runs/run_4/clarify'
	assert reqs[0].body.contains('"answer":"use the dark theme"')
	assert reqs[1].path == '/v1/runs/run_4/stop'
	assert reqs[1].body == '{}'
}

fn test_contract_events_sse_buffered_outcome() {
	sse := 'data: {"delta":"Ho"}\n\ndata: {"delta":"la"}\n\n'
	mock, saved := start_mock_gateway({
		'GET /v1/runs/run_5/events': sse
	})
	defer { mock_restore_env(saved) }
	result := assistant_events_report('run_5')
	assert result.ok
	assert result.data['text'] == 'Hola'
	reqs := mock_wait_requests(mock, 1)
	assert reqs[0].method == 'GET'
	assert reqs[0].path == '/v1/runs/run_5/events'
}

fn test_contract_events_pending_approval_is_not_auto_answered() {
	sse := 'data: {"type":"approval.request","command":"pacman -S x","choices":["approve","deny"]}\n\n'
	mock, saved := start_mock_gateway({
		'GET /v1/runs/run_6/events': sse
	})
	defer { mock_restore_env(saved) }
	assistant_run_mode_record('run_6', 'agent') or { panic(err) }
	result := assistant_events_report('run_6')
	assert !result.ok
	assert result.message.contains('waiting for approval')
	// Only GETs (events + the run-status verification): no approval POST ever.
	reqs := mock_wait_requests(mock, 1)
	assert reqs.all(it.method == 'GET')
}

fn test_contract_run_submission_shape() {
	mock, saved := start_mock_gateway({
		'POST /v1/runs': '{"run_id":"run_7","status":"queued"}'
	})
	defer { mock_restore_env(saved) }
	settings := assistant_load_settings()
	resp := assistant_run_create(settings, '{"input":"hola"}', '') or { panic(err) }
	assert resp.status_code == 200
	reqs := mock_wait_requests(mock, 1)
	assert reqs.len == 1
	assert reqs[0].method == 'POST'
	assert reqs[0].path == '/v1/runs'
	assert reqs[0].body == '{"input":"hola"}'
	assert reqs[0].auth == 'Bearer contract-test-key'
}

fn test_contract_readonly_ask_stops_run_when_model_requests_tool() {
	// hornero#414 negative test: in --mode ask the model requests a
	// terminal tool; the run must be stopped and must not succeed.
	sse := 'data: {"type":"tool.started","tool":"terminal","preview":"echo hi"}\n\ndata: {"delta":"4"}\n\n'
	mock, saved := start_mock_gateway({
		'POST /v1/runs':              '{"run_id":"run_ro","status":"queued"}'
		'GET /v1/runs/run_ro/events': sse
		'POST /v1/runs/run_ro/stop':  '{}'
	})
	defer { mock_restore_env(saved) }
	result := assistant_ask_report_attached_session_mode('What is 2+2?', [], '', 'ask')
	assert !result.ok
	assert result.message.contains('Tool execution denied by ask mode')
	reqs := mock_wait_requests(mock, 3)
	assert reqs.len == 3
	assert reqs[0].path == '/v1/runs'
	assert reqs[0].body.contains('"hornero_mode":"ask"')
	assert reqs[2].method == 'POST'
	assert reqs[2].path == '/v1/runs/run_ro/stop'
}

fn test_contract_default_ask_body_and_agent_tool_behaviour_unchanged() {
	// No explicit mode: wire body stays exactly {"input":...}.
	sse := 'data: {"type":"tool.started","tool":"terminal"}\n\ndata: {"delta":"done"}\n\n'
	mock, saved := start_mock_gateway({
		'POST /v1/runs':               '{"run_id":"run_def","status":"queued"}'
		'GET /v1/runs/run_def/events': sse
	})
	defer { mock_restore_env(saved) }
	result := assistant_ask_report_attached_session('What is 2+2?', [], '')
	assert result.ok
	assert result.data['text'] == 'done' || result.message.contains('done')
	reqs := mock_wait_requests(mock, 2)
	assert reqs[0].body == '{"input":"What is 2+2?"}'
	assert !reqs[0].body.contains('hornero_mode')
}

fn test_contract_ask_mode_without_tool_succeeds() {
	sse := 'data: {"delta":"4"}\n\n'
	mock, saved := start_mock_gateway({
		'POST /v1/runs':              '{"run_id":"run_ok","status":"queued"}'
		'GET /v1/runs/run_ok/events': sse
	})
	defer { mock_restore_env(saved) }
	result := assistant_ask_report_attached_session_mode('What is 2+2?', [], '', 'ask')
	assert result.ok
	assert result.message.contains('4')
	reqs := mock_wait_requests(mock, 2)
	assert reqs.len == 2, 'no stop may be issued for a tool-free ask run'
}

fn test_contract_ask_approve_stop_write_redacted_audit_log() {
	mock, saved := start_mock_gateway({
		'POST /v1/runs':                '{"run_id":"run_9","status":"queued"}'
		'GET /v1/runs/run_9/events':    'data: {"delta":"done"}\n\n'
		'GET /v1/runs/run_9':           '{"pending_controls":[{"kind":"approval","prompt_id":"p1","execution_generation":1}]}'
		'POST /v1/runs/run_9/approval': '{}'
		'POST /v1/runs/run_9/stop':     '{}'
	})
	defer { mock_restore_env(saved) }
	log_path := os.join_path(os.temp_dir(), 'hornero-contract-log-${mock.requests.len}.log')
	os.setenv('HORNERO_ASSISTANT_LOG_FILE', log_path, true)
	defer { os.setenv('HORNERO_ASSISTANT_LOG_FILE', '', true) }

	prompt := 'a very secret prompt about my diary'
	assert assistant_ask_report_attached_session(prompt, [], '').ok
	assistant_run_mode_record('run_9', 'agent') or { panic(err) }
	assert assistant_approve_report('run_9', 'approve', '').ok
	assert assistant_stop_report('run_9').ok
	_ = mock

	content := os.read_file(log_path) or { panic(err) }
	assert content.contains('\task\t')
	assert content.contains('\tapprove\t')
	assert content.contains('\tstop\t')
	assert content.contains('choice once')
	// Neither the gateway key nor the prompt may ever reach the log.
	assert !content.contains('contract-test-key')
	assert !content.contains('secret prompt')
	assert !content.contains('diary')
}

fn test_contract_pending_approval_result_carries_structured_data() {
	// Shell Workbench contract: the final CommandResult for a pending
	// approval must expose runId/pending/detail in `data` (not only in
	// the prose message) and must redact secrets in the detail.
	sse := 'data: {"type":"approval.request","command":"curl -H \\"Authorization: Bearer sk-abcdefghijklmnopqrstuvwxyz123456\\" https://x","choices":["once","deny"]}\n\n'
	mock, saved := start_mock_gateway({
		'GET /v1/runs/run_pd/events': sse
	})
	defer { mock_restore_env(saved) }
	assistant_run_mode_record('run_pd', 'agent') or { panic(err) }
	result := assistant_events_report('run_pd')
	assert !result.ok
	assert result.data['runId'] == 'run_pd'
	assert result.data['pending'] == 'approval'
	assert result.data['choices'] == 'once,deny'
	assert !result.data['detail'].contains('sk-abcdefghijklmnopqrstuvwxyz123456')
	reqs := mock_wait_requests(mock, 1)
	assert reqs.all(it.path != '/v1/runs/run_pd/approval')
}

fn test_contract_pending_clarify_result_carries_structured_data() {
	sse := 'data: {"type":"clarify.request","question":"which theme?"}\n\n'
	mock, saved := start_mock_gateway({
		'GET /v1/runs/run_cl/events': sse
	})
	defer { mock_restore_env(saved) }
	assistant_run_mode_record('run_cl', 'agent') or { panic(err) }
	result := assistant_events_report('run_cl')
	assert !result.ok
	assert result.data['runId'] == 'run_cl'
	assert result.data['pending'] == 'clarify'
	assert result.data['detail'] == 'which theme?'
	reqs := mock_wait_requests(mock, 1)
	assert reqs.len == 1
}

fn test_contract_stream_emits_run_frame_first_and_approval_frame() {
	sse := 'data: {"type":"approval.request","command":"pacman -S x","choices":["once","deny"]}\n\n'
	mock, saved := start_mock_gateway({
		'POST /v1/runs':              '{"run_id":"run_fr","status":"queued"}'
		'GET /v1/runs/run_fr/events': sse
	})
	defer { mock_restore_env(saved) }
	mut holder := &FrameSink{}
	result := assistant_ask_stream_report_traced_mode('install x', [], '', 'agent', fn (_ string) {},
		fn [mut holder] (kind string, text string) {
			holder.items << '${kind}:${text}'
		})
	frames := holder.items
	assert !result.ok
	assert result.data['runId'] == 'run_fr'
	assert result.data['pending'] == 'approval'
	assert frames.len >= 2
	assert frames[0] == 'run:run_fr'
	assert 'approval:pacman -S x' in frames
	reqs := mock_wait_requests(mock, 2)
	// Run creation and the events GET (+ status checks): no approval POST ever.
	assert reqs.len >= 2
	assert reqs.all(it.method != 'POST' || it.path == '/v1/runs')
}

// FrameSink is heap-allocated so closures capture it by reference.
struct FrameSink {
mut:
	items []string
}

fn test_status_approval_state_reads_pending_controls_and_status() {
	assert assistant_status_approval_state('{"pending_controls":[{"kind":"approval","prompt_id":"p"}]}') == 1
	assert assistant_status_approval_state('{"pending_controls":[]}') == 0
	assert assistant_status_approval_state('{"status":"waiting_for_approval"}') == 1
	assert assistant_status_approval_state('{"status":"running"}') == 0
	assert assistant_status_approval_state('not json') == -1
	assert assistant_status_approval_state('{}') == -1
}

fn test_contract_already_decided_approval_in_event_log_is_not_pending() {
	// Following a run after the user approved replays the old
	// approval.request; the run status says nothing is pending now.
	sse := 'data: {"type":"approval.request","command":"pacman -S x"}\n\ndata: {"delta":"installed"}\n\n'
	mock, saved := start_mock_gateway({
		'GET /v1/runs/run_dec/events': sse
		'GET /v1/runs/run_dec':        '{"status":"completed","pending_controls":[]}'
	})
	defer { mock_restore_env(saved) }
	assistant_run_mode_record('run_dec', 'agent') or { panic(err) }
	result := assistant_events_report('run_dec')
	assert result.ok
	assert result.data['text'] == 'installed'
	assert result.data['pending'] == 'none'
	_ = mock
}

fn test_run_id_shape_is_strict() {
	assert assistant_run_id_valid('run_abc-1.2')
	for bad in ['', '.', '..', 'a/b', 'a b', 'a?x=1', 'a%2f', 'run\n1', 'é', 'x'.repeat(65)] {
		assert !assistant_run_id_valid(bad), bad
	}
	assert assistant_request_ref_valid('p1') && assistant_request_ref_valid('p1@12')
	assert !assistant_request_ref_valid('p1@') && !assistant_request_ref_valid('p1@x')
		&& !assistant_request_ref_valid('a/b@1')
}

fn test_token_shapes_and_utf8_cut() {
	r := assistant_redact_tokens('curl -H sk-abcdefghijklmnopqrstuvwxyz1234 ghp_abcdefghijklmnopqrstuv --password hunter2 x')
	assert !r.contains('abcdefghijklmnopqrstuv') && !r.contains('hunter2')
	assert assistant_redact_tokens('ls -la /home') == 'ls -la /home'
	// never split a multi-byte rune
	cut := assistant_cut('ééééé', 3)
	assert cut == 'é'
	assert cut.len == 2
}

fn test_run_mode_registry_unknown_is_non_escalating() {
	_, saved := start_mock_gateway({})
	defer { mock_restore_env(saved) }
	assert assistant_run_mode('run_never_seen') == 'ask'
	assistant_run_mode_record('run_m1', 'agent') or { panic(err) }
	assistant_run_mode_record('run_m2', 'chat') or { panic(err) }
	assert assistant_run_mode('run_m1') == 'agent'
	assert assistant_run_mode('run_m2') == 'chat'
	assert !assistant_mode_escalates(assistant_run_mode('run_unknown'))
}

fn test_contract_events_for_unknown_run_deny_approval_even_without_status() {
	// H2/H4: no recorded mode -> non-escalating; the approval is denied
	// server-side regardless of what the status says.
	sse := 'data: {"type":"approval.request","command":"rm -rf /"}\n\n'
	mock, saved := start_mock_gateway({
		'GET /v1/runs/run_unk/events':    sse
		'GET /v1/runs/run_unk':           '{"status":"completed","pending_controls":[]}'
		'POST /v1/runs/run_unk/approval': '{}'
	})
	defer { mock_restore_env(saved) }
	result := assistant_events_report_opts('run_unk', true)
	assert !result.ok
	assert result.data['pending'] == 'denied-by-mode'
	reqs := mock_wait_requests(mock, 2)
	posts := reqs.filter(it.method == 'POST')
	assert posts.len == 1 && posts[0].path == '/v1/runs/run_unk/approval'
	assert posts[0].body.contains('deny') && !posts[0].body.contains('once')
}

fn test_contract_ask_mode_stream_denies_and_emits_no_approval_frame() {
	sse := 'data: {"type":"approval.request","command":"pacman -S x"}\n\n'
	mock, saved := start_mock_gateway({
		'POST /v1/runs':                 '{"run_id":"run_ak","status":"queued"}'
		'GET /v1/runs/run_ak/events':    sse
		'GET /v1/runs/run_ak':           '{"status":"completed","pending_controls":[]}'
		'POST /v1/runs/run_ak/approval': '{}'
	})
	defer { mock_restore_env(saved) }
	mut holder := &FrameSink{}
	result := assistant_ask_stream_report_traced_mode('install x', [], '', 'ask', fn (_ string) {},
		fn [mut holder] (kind string, text string) {
			holder.items << '${kind}:${text}'
		})
	assert !result.ok && result.data['pending'] == 'denied-by-mode'
	assert holder.items.all(!it.starts_with('approval'))
	assert 'mode:ask' in holder.items
	reqs := mock_wait_requests(mock, 3)
	assert reqs.any(it.method == 'POST' && it.path == '/v1/runs/run_ak/approval' && it.body.contains('deny'))
	assert assistant_run_mode('run_ak') == 'ask'
}

fn test_contract_pending_result_binds_request_id_and_shows_gateway_text() {
	// H1: the displayed text/id come from the pending control.
	sse := 'data: {"type":"approval.request","command":"event text"}\n\n'
	status := '{"pending_controls":[{"kind":"approval","prompt_id":"p7","execution_generation":3,"command":"gateway text"}]}'
	_, saved := start_mock_gateway({
		'GET /v1/runs/run_h1/events': sse
		'GET /v1/runs/run_h1':        status
	})
	defer { mock_restore_env(saved) }
	assistant_run_mode_record('run_h1', 'agent') or { panic(err) }
	result := assistant_events_report('run_h1')
	assert result.data['request'] == 'p7@3'
	assert result.data['promptId'] == 'p7' && result.data['generation'] == '3'
	assert result.data['detail'] == 'gateway text'
}

fn test_contract_approve_refuses_when_pending_request_changed() {
	status := '{"pending_controls":[{"kind":"approval","prompt_id":"p2","execution_generation":4}]}'
	mock, saved := start_mock_gateway({
		'GET /v1/runs/run_sw':           status
		'POST /v1/runs/run_sw/approval': '{}'
	})
	defer { mock_restore_env(saved) }
	// the card showed p1; the gateway now waits on p2
	assistant_run_mode_record('run_sw', 'agent') or { panic(err) }
	r := assistant_approve_report('run_sw', 'approve', 'p1@3')
	assert !r.ok && r.data['pending'] == 'changed'
	// generation mismatch is refused too
	assert !assistant_approve_report('run_sw', 'approve', 'p2@3').ok
	reqs := mock_wait_requests(mock, 2)
	assert reqs.all(it.method == 'GET')
	// the exact displayed request goes through, once
	ok := assistant_approve_report('run_sw', 'approve', 'p2@4')
	assert ok.ok
	posts := mock_wait_requests(mock, 5).filter(it.method == 'POST')
	assert posts.len == 1 && posts[0].body.contains('"request_id":"p2"') && posts[0].body.contains('once')
}

fn test_contract_approve_with_request_but_no_status_fails_closed() {
	_, saved := start_mock_gateway({})
	defer { mock_restore_env(saved) }
	assistant_run_mode_record('run_nostatus', 'agent') or { panic(err) }
	r := assistant_approve_report('run_nostatus', 'approve', 'p1@1')
	assert !r.ok
}

fn test_contract_failed_deny_stops_the_run_reports_failure_and_does_not_log_denied() {
	// F1: the deny POST is not routed (404): the deny failed.
	sse := 'data: {"type":"approval.request","command":"rm -rf /"}\n\n'
	mock, saved := start_mock_gateway({
		'GET /v1/runs/run_df/events':    sse
		'POST /v1/runs/run_df/approval': '!500'
		'POST /v1/runs/run_df/stop':     '{}'
	})
	defer { mock_restore_env(saved) }
	assistant_run_mode_record('run_df', 'ask') or { panic(err) }
	result := assistant_events_report_opts('run_df', true)
	assert !result.ok
	assert result.data['pending'] == 'deny-failed'
	assert !result.message.contains('denied by')
	reqs := mock_wait_requests(mock, 3)
	assert reqs.any(it.method == 'POST' && it.path == '/v1/runs/run_df/stop')
	log := os.read_file(assistant_log_file()) or { '' }
	assert !log.contains('mode-deny\t') && log.contains('mode-deny-failed')
}

fn test_contract_ask_stream_failed_deny_emits_deny_failed_frame_and_stops() {
	sse := 'data: {"type":"approval.request","command":"pacman -S x"}\n\n'
	mock, saved := start_mock_gateway({
		'POST /v1/runs':                 '{"run_id":"run_fd","status":"queued"}'
		'GET /v1/runs/run_fd/events':    sse
		'POST /v1/runs/run_fd/approval': '!500'
		'POST /v1/runs/run_fd/stop':     '{}'
	})
	defer { mock_restore_env(saved) }
	mut holder := &FrameSink{}
	result := assistant_ask_stream_report_traced_mode('install x', [], '', 'ask', fn (_ string) {},
		fn [mut holder] (kind string, text string) {
			holder.items << '${kind}:${text}'
		})
	assert !result.ok && result.data['pending'] == 'deny-failed'
	assert holder.items.any(it.starts_with('deny-failed:'))
	assert holder.items.all(!it.starts_with('approval'))
	reqs := mock_wait_requests(mock, 4)
	assert reqs.any(it.method == 'POST' && it.path == '/v1/runs/run_fd/stop')
}

fn test_contract_approve_refused_for_non_agent_runs_but_deny_allowed() {
	mock, saved := start_mock_gateway({
		'GET /v1/runs/run_na':           '{"pending_controls":[{"kind":"approval","prompt_id":"p1","execution_generation":1}]}'
		'POST /v1/runs/run_na/approval': '{}'
	})
	defer { mock_restore_env(saved) }
	for m in ['ask', 'chat'] {
		assistant_run_mode_record('run_na', m) or { panic(err) }
		r := assistant_approve_report('run_na', 'approve', 'p1@1')
		assert !r.ok && r.message.contains('not an Agent run')
	}
	// unknown run: refused too
	assert !assistant_approve_report('run_never', 'approve', '').ok
	assert assistant_approve_report('run_na', 'deny', '').ok
	posts := mock_wait_requests(mock, 2).filter(it.method == 'POST')
	assert posts.len == 1 && posts[0].body.contains('deny')
}

fn test_run_mode_registry_survives_concurrent_writers() {
	_, saved := start_mock_gateway({})
	defer { mock_restore_env(saved) }
	mut threads := []thread{}
	for i in 0 .. 8 {
		threads << spawn fn (n int) {
			assistant_run_mode_record('run_c${n}', 'agent') or { panic(err) }
		}(i)
	}
	threads.wait()
	for i in 0 .. 8 {
		assert assistant_run_mode('run_c${i}') == 'agent'
	}
	assert !os.exists(assistant_run_modes_file() + '.lock')
}

fn test_session_with_unknown_stored_mode_resolves_to_ask() {
	// K1: a hand-edited/corrupt session row must not grant Agent authority.
	_, saved := start_mock_gateway({})
	defer { mock_restore_env(saved) }
	os.write_file(assistant_sessions_file(), 'current\ts1\nsession\ts1\tT\t2026-01-01\tsuperuser\t\n') or {
		panic(err)
	}
	assert assistant_session_mode('s1') == 'ask'
	assert assistant_resolve_ask_mode('', 's1') == 'ask'
	assistant_run_mode_record('run_k1', 'superuser') or { panic(err) }
	assert assistant_run_mode('run_k1') == 'ask'
}

fn test_approval_display_binds_text_to_control_id() {
	// K5: event text is never shown under a control id it may not match.
	no_ctl := AssistantPendingControl{}
	t0, b0 := assistant_approval_display(no_ctl, 'event text')
	assert t0 == 'event text' && b0
	with_text := AssistantPendingControl{
		found:      true
		prompt_id:  'p1'
		generation: 2
		detail:     'gateway text'
	}
	t1, b1 := assistant_approval_display(with_text, 'event text')
	assert t1 == 'gateway text' && b1
	no_text := AssistantPendingControl{
		found:      true
		prompt_id:  'p1'
		generation: 2
	}
	t2, b2 := assistant_approval_display(no_text, 'event text')
	assert !b2 && t2 == assistant_unbound_approval_text && !t2.contains('event text')
}

fn test_contract_stream_never_pairs_event_text_with_control_id() {
	// K5: the status advertises p9@1 without text; the event says
	// something else. The card must not show the event text with p9@1.
	sse := 'data: {"type":"approval.request","command":"harmless ls"}\n\n'
	status := '{"pending_controls":[{"kind":"approval","prompt_id":"p9","execution_generation":1}]}'
	_, saved := start_mock_gateway({
		'POST /v1/runs':              '{"run_id":"run_k5","status":"queued"}'
		'GET /v1/runs/run_k5/events': sse
		'GET /v1/runs/run_k5':        status
	})
	defer { mock_restore_env(saved) }
	mut holder := &FrameSink{}
	result := assistant_ask_stream_report_traced_mode('x', [], '', 'agent', fn (_ string) {},
		fn [mut holder] (kind string, text string) {
			holder.items << '${kind}:${text}'
		})
	assert 'approval.control:p9@1' in holder.items
	assert 'approval:${assistant_unbound_approval_text}' in holder.items
	assert holder.items.all(!it.contains('harmless ls'))
	assert result.data['request'] == 'p9@1'
	assert result.data['detail'] == assistant_unbound_approval_text
	assert result.data['detailBound'] == 'false'
}

fn test_contract_buffered_ask_never_pairs_event_text_with_control_id() {
	sse := 'data: {"type":"approval.request","command":"harmless ls"}\n\n'
	status := '{"pending_controls":[{"kind":"approval","prompt_id":"p9","execution_generation":1}]}'
	_, saved := start_mock_gateway({
		'POST /v1/runs':               '{"run_id":"run_k5b","status":"queued"}'
		'GET /v1/runs/run_k5b/events': sse
		'GET /v1/runs/run_k5b':        status
	})
	defer { mock_restore_env(saved) }
	result := assistant_ask_report_attached_session_mode('x', [], '', 'agent')
	assert result.data['request'] == 'p9@1'
	assert result.data['detail'] == assistant_unbound_approval_text
	assert result.data['detailBound'] == 'false'
	assert !result.message.contains('harmless ls')
}

fn test_run_mode_registry_is_private_per_run_files() {
	// K3: one 0600 file per run in a 0700 dir; no lock files.
	_, saved := start_mock_gateway({})
	defer { mock_restore_env(saved) }
	assistant_run_mode_record('run_p1', 'agent') or { panic(err) }
	dir := assistant_run_modes_dir()
	dst := os.lstat(dir) or { panic(err) }
	assert dst.mode & 0o777 == 0o700
	fst := os.lstat(os.join_path(dir, 'run_p1')) or { panic(err) }
	assert fst.mode & 0o777 == 0o600
	assert (os.read_file(os.join_path(dir, 'run_p1')) or { '' }) == 'agent\n'
	assert (os.ls(dir) or { [] }) == ['run_p1']
	// A pre-existing wide directory is tightened on the next record.
	os.chmod(dir, 0o755) or { panic(err) }
	assistant_run_mode_record('run_p2', 'chat') or { panic(err) }
	dst2 := os.lstat(dir) or { panic(err) }
	assert dst2.mode & 0o777 == 0o700
	assert assistant_run_mode('run_p2') == 'chat'
}

fn test_run_mode_registry_rejects_tampered_records() {
	_, saved := start_mock_gateway({})
	defer { mock_restore_env(saved) }
	assistant_run_mode_record('run_t0', 'ask') or { panic(err) }
	dir := assistant_run_modes_dir()
	// Wrong shape, world-readable, symlinked and oversized records all
	// read as 'ask', even when they claim agent.
	os.write_file(os.join_path(dir, 'run_t1'), 'agent') or { panic(err) }
	os.chmod(os.join_path(dir, 'run_t1'), 0o600) or {}
	assert assistant_run_mode('run_t1') == 'ask'
	os.write_file(os.join_path(dir, 'run_t2'), 'agent\n') or { panic(err) }
	os.chmod(os.join_path(dir, 'run_t2'), 0o644) or {}
	assert assistant_run_mode('run_t2') == 'ask'
	target := os.join_path(os.dir(dir), 'elsewhere')
	os.write_file(target, 'agent\n') or { panic(err) }
	os.chmod(target, 0o600) or {}
	os.symlink(target, os.join_path(dir, 'run_t3')) or { panic(err) }
	assert assistant_run_mode('run_t3') == 'ask'
	os.write_file(os.join_path(dir, 'run_t4'), 'agent\nagent\nagent\nagent\n') or { panic(err) }
	os.chmod(os.join_path(dir, 'run_t4'), 0o600) or {}
	assert assistant_run_mode('run_t4') == 'ask'
	os.write_file(os.join_path(dir, 'run_t5'), 'root\n') or { panic(err) }
	os.chmod(os.join_path(dir, 'run_t5'), 0o600) or {}
	assert assistant_run_mode('run_t5') == 'ask'
	// A wide registry directory invalidates every record in it.
	os.write_file(os.join_path(dir, 'run_t6'), 'agent\n') or { panic(err) }
	os.chmod(os.join_path(dir, 'run_t6'), 0o600) or {}
	assert assistant_run_mode('run_t6') == 'agent'
	os.chmod(dir, 0o777) or { panic(err) }
	assert assistant_run_mode('run_t6') == 'ask'
	os.chmod(dir, 0o700) or {}
	// Path-shaped ids never reach the filesystem.
	assert assistant_run_mode('../run_t6') == 'ask'
	if _ := assistant_run_mode_record('../evil', 'agent') {
		assert false
	}
}

fn test_run_mode_record_failure_is_loud_and_refuses_symlinked_dir() {
	_, saved := start_mock_gateway({})
	defer { mock_restore_env(saved) }
	dir := assistant_run_modes_dir()
	real := dir + '-real'
	os.mkdir_all(real) or { panic(err) }
	os.chmod(real, 0o700) or {}
	os.symlink(real, dir) or { panic(err) }
	if _ := assistant_run_mode_record('run_s1', 'agent') {
		assert false, 'a symlinked registry directory must be refused'
	}
	assert (os.ls(real) or { [] }).len == 0
}

fn test_contract_ask_stops_run_when_mode_cannot_be_recorded() {
	// K3: never drop the record silently — the run is stopped and the
	// ask fails, instead of a later follow auto-denying an Agent run.
	sse := 'data: {"type":"response.output_text.delta","delta":"hi"}\n\n'
	mock, saved := start_mock_gateway({
		'POST /v1/runs':              '{"run_id":"run_rf","status":"queued"}'
		'GET /v1/runs/run_rf/events': sse
		'POST /v1/runs/run_rf/stop':  '{}'
	})
	defer { mock_restore_env(saved) }
	// Make the registry path unusable: a regular file where the dir goes.
	os.write_file(assistant_run_modes_dir(), 'not a dir') or { panic(err) }
	result := assistant_ask_report_attached_session_mode('x', [], '', 'agent')
	assert !result.ok
	assert result.data['pending'] == 'mode-record-failed'
	assert result.data['runId'] == 'run_rf'
	reqs := mock_wait_requests(mock, 2)
	assert reqs.any(it.method == 'POST' && it.path == '/v1/runs/run_rf/stop')
	assert !reqs.any(it.path == '/v1/runs/run_rf/events')
	log := os.read_file(assistant_log_file()) or { '' }
	assert log.contains('record-failed-stopped')
	// Streamed asks behave the same and never open the event stream.
	mut holder := &FrameSink{}
	streamed := assistant_ask_stream_report_traced_mode('x', [], '', 'agent', fn (_ string) {},
		fn [mut holder] (kind string, text string) {
			holder.items << '${kind}:${text}'
		})
	assert !streamed.ok && streamed.data['pending'] == 'mode-record-failed'
}

fn test_run_mode_registry_reads_legacy_tsv_and_prunes() {
	_, saved := start_mock_gateway({})
	defer { mock_restore_env(saved) }
	os.write_file(assistant_run_modes_file(), 'run_old\tagent\n') or { panic(err) }
	os.chmod(assistant_run_modes_file(), 0o600) or {}
	assert assistant_run_mode('run_old') == 'agent'
	os.chmod(assistant_run_modes_file(), 0o666) or {}
	assert assistant_run_mode('run_old') == 'ask'
	for i in 0 .. assistant_run_modes_keep + 5 {
		assistant_run_mode_record('run_q${i}', 'chat') or { panic(err) }
	}
	names := (os.ls(assistant_run_modes_dir()) or { [] }).filter(!it.starts_with('.'))
	assert names.len == assistant_run_modes_keep
}

fn k2_posts(mock &MockGateway, path string) int {
	return mock.recorded().filter(it.method == 'POST' && it.path == path).len
}

fn test_contract_ask_stream_denies_each_request_once() {
	// K2: the live stream denies; the final replay must not deny again
	// (that second deny used to fail and stop the run spuriously).
	sse := 'data: {"type":"approval.request","command":"pacman -S x"}\n\n'
	mock, saved := start_mock_gateway({
		'POST /v1/runs':                  '{"run_id":"run_k2a","status":"queued"}'
		'GET /v1/runs/run_k2a/events':    sse
		'GET /v1/runs/run_k2a':           '{"status":"running","pending_controls":[]}'
		'POST /v1/runs/run_k2a/approval': '{}'
		'POST /v1/runs/run_k2a/stop':     '{}'
	})
	defer { mock_restore_env(saved) }
	mut holder := &FrameSink{}
	result := assistant_ask_stream_report_traced_mode('install x', [], '', 'ask', fn (_ string) {},
		fn [mut holder] (kind string, text string) {
			holder.items << '${kind}:${text}'
		})
	assert !result.ok && result.data['pending'] == 'denied-by-mode'
	mock_wait_requests(mock, 3)
	assert k2_posts(mock, '/v1/runs/run_k2a/approval') == 1
	assert k2_posts(mock, '/v1/runs/run_k2a/stop') == 0
	assert holder.items.all(!it.starts_with('deny-failed'))
	// A later follow (new invocation) replays the log: still no deny,
	// no stop — the ledger remembers '#1'.
	follow := assistant_events_stream_report_traced('run_k2a', fn (_ string) {}, fn (_ string, _ string) {})
	assert follow.data['pending'] == 'denied-by-mode'
	assert k2_posts(mock, '/v1/runs/run_k2a/approval') == 1
	assert k2_posts(mock, '/v1/runs/run_k2a/stop') == 0
	assert '#1' in assistant_denials_load('run_k2a')
}

fn test_contract_deny_dedupes_by_request_id_and_generation() {
	sse := 'data: {"type":"approval.request","request_id":"p1","execution_generation":2,"command":"a"}\n\ndata: {"type":"approval.request","request_id":"p1","execution_generation":2,"command":"a"}\n\ndata: {"type":"approval.request","request_id":"p2","execution_generation":3,"command":"b"}\n\n'
	mock, saved := start_mock_gateway({
		'GET /v1/runs/run_k2b/events':    sse
		'POST /v1/runs/run_k2b/approval': '{}'
	})
	defer { mock_restore_env(saved) }
	reqs := assistant_approval_requests(parse_sse_events(sse))
	assert reqs.map(it.ref) == ['p1@2', 'p1@2', 'p2@3']
	assistant_run_mode_record('run_k2b', 'chat') or { panic(err) }
	r := assistant_events_report_opts('run_k2b', true)
	assert r.data['pending'] == 'denied-by-mode'
	assert k2_posts(mock, '/v1/runs/run_k2b/approval') == 2
	again := assistant_events_report_opts('run_k2b', true)
	assert again.data['pending'] == 'denied-by-mode'
	assert k2_posts(mock, '/v1/runs/run_k2b/approval') == 2
}

fn test_contract_plain_events_is_read_only() {
	// K2: plain `events` never denies or stops; --enforce does.
	sse := 'data: {"type":"approval.request","command":"rm -rf /"}\n\n'
	mock, saved := start_mock_gateway({
		'GET /v1/runs/run_k2c/events':    sse
		'POST /v1/runs/run_k2c/approval': '{}'
		'POST /v1/runs/run_k2c/stop':     '{}'
	})
	defer { mock_restore_env(saved) }
	assistant_run_mode_record('run_k2c', 'ask') or { panic(err) }
	ro := assistant_events_report('run_k2c')
	assert !ro.ok && ro.data['pending'] == 'needs-deny'
	assert ro.message.contains('--enforce')
	assert mock.recorded().all(it.method == 'GET')
	enforced := assistant_events_report_opts('run_k2c', true)
	assert enforced.data['pending'] == 'denied-by-mode'
	assert k2_posts(mock, '/v1/runs/run_k2c/approval') == 1
	// Once denied, the read-only view reports it as denied.
	after := assistant_events_report('run_k2c')
	assert after.data['pending'] == 'denied-by-mode'
	assert k2_posts(mock, '/v1/runs/run_k2c/approval') == 1
}

fn test_contract_plain_events_reports_tool_violation_without_stop() {
	sse := 'data: {"type":"tool.started","tool":"terminal","preview":"echo hi"}\n\n'
	mock, saved := start_mock_gateway({
		'GET /v1/runs/run_k2d/events': sse
		'POST /v1/runs/run_k2d/stop':  '{}'
	})
	defer { mock_restore_env(saved) }
	assistant_run_mode_record('run_k2d', 'ask') or { panic(err) }
	ro := assistant_events_report('run_k2d')
	assert !ro.ok && ro.data['pending'] == 'tool-violation'
	assert mock.recorded().all(it.method == 'GET')
	enforced := assistant_events_report_opts('run_k2d', true)
	assert !enforced.ok
	assert k2_posts(mock, '/v1/runs/run_k2d/stop') == 1
}

fn test_contract_rejected_deny_with_nothing_pending_is_stale_not_failure() {
	// The request was resolved elsewhere (e.g. the user denied it); the
	// gateway rejects our deny and status proves nothing is pending.
	sse := 'data: {"type":"approval.request","command":"x"}\n\n'
	mock, saved := start_mock_gateway({
		'GET /v1/runs/run_k2e/events':    sse
		'GET /v1/runs/run_k2e':           '{"status":"completed","pending_controls":[]}'
		'POST /v1/runs/run_k2e/approval': '!500'
		'POST /v1/runs/run_k2e/stop':     '{}'
	})
	defer { mock_restore_env(saved) }
	assistant_run_mode_record('run_k2e', 'ask') or { panic(err) }
	r := assistant_events_report_opts('run_k2e', true)
	assert r.data['pending'] == 'denied-by-mode'
	assert k2_posts(mock, '/v1/runs/run_k2e/stop') == 0
	log := os.read_file(assistant_log_file()) or { '' }
	assert log.contains('mode-deny-stale')
}
