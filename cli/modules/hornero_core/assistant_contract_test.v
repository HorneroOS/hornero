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
	assistant_run_mode_record('run_1', 'agent')
	result := assistant_approve_report_presence('run_1', 'approve', '', k4_tty)
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
	assistant_run_mode_record('run_2', 'agent')
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
	assistant_run_mode_record('run_3', 'agent')
	result := assistant_approve_report_presence('run_3', 'approve', '', k4_tty)
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
	assistant_run_mode_record('run_6', 'agent')
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
	assistant_run_mode_record('run_9', 'agent')
	assert assistant_approve_report_presence('run_9', 'approve', '', k4_tty).ok
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
	assistant_run_mode_record('run_pd', 'agent')
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
	assistant_run_mode_record('run_cl', 'agent')
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
	assistant_run_mode_record('run_dec', 'agent')
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
	assistant_run_mode_record('run_m1', 'agent')
	assistant_run_mode_record('run_m2', 'chat')
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
	result := assistant_events_report('run_unk')
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
	assistant_run_mode_record('run_h1', 'agent')
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
	assistant_run_mode_record('run_sw', 'agent')
	r := assistant_approve_report_presence('run_sw', 'approve', 'p1@3', k4_tty)
	assert !r.ok && r.data['pending'] == 'changed'
	// generation mismatch is refused too
	assert !assistant_approve_report_presence('run_sw', 'approve', 'p2@3', k4_tty).ok
	reqs := mock_wait_requests(mock, 2)
	assert reqs.all(it.method == 'GET')
	// the exact displayed request goes through, once
	ok := assistant_approve_report_presence('run_sw', 'approve', 'p2@4', k4_tty)
	assert ok.ok
	posts := mock_wait_requests(mock, 5).filter(it.method == 'POST')
	assert posts.len == 1 && posts[0].body.contains('"request_id":"p2"') && posts[0].body.contains('once')
}

fn test_contract_approve_with_request_but_no_status_fails_closed() {
	_, saved := start_mock_gateway({})
	defer { mock_restore_env(saved) }
	assistant_run_mode_record('run_nostatus', 'agent')
	r := assistant_approve_report_presence('run_nostatus', 'approve', 'p1@1', k4_tty)
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
	assistant_run_mode_record('run_df', 'ask')
	result := assistant_events_report('run_df')
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
		assistant_run_mode_record('run_na', m)
		r := assistant_approve_report_presence('run_na', 'approve', 'p1@1', k4_tty)
		assert !r.ok && r.message.contains('not an Agent run')
	}
	// unknown run: refused too
	assert !assistant_approve_report_presence('run_never', 'approve', '', k4_tty).ok
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
			assistant_run_mode_record('run_c${n}', 'agent')
		}(i)
	}
	threads.wait()
	for i in 0 .. 8 {
		assert assistant_run_mode('run_c${i}') == 'agent'
	}
	assert !os.exists(assistant_run_modes_file() + '.lock')
}

const k4_tty = AssistantApprovalPresence{
	tty_confirmed: true
}

const k4_token = 'k4-presence-token-0123456789abcdefABCDEF'

fn k4_presence_env() (string, string) {
	dir := os.join_path(os.dir(assistant_run_modes_file()), 'presence')
	old := os.getenv('HORNERO_ASSISTANT_PRESENCE_DIR')
	os.setenv('HORNERO_ASSISTANT_PRESENCE_DIR', dir, true)
	os.mkdir_all(dir) or { panic(err) }
	os.chmod(dir, 0o700) or { panic(err) }
	return dir, old
}

fn k4_issue(run_id string, ref string, token string) string {
	path := assistant_presence_file(run_id, ref)
	os.write_file(path, token + '\n') or { panic(err) }
	os.chmod(path, 0o600) or { panic(err) }
	return path
}

const k4_status = '{"pending_controls":[{"kind":"approval","prompt_id":"p1","execution_generation":2,"command":"pacman -S x"}]}'

fn test_contract_approve_requires_presence_by_default_but_deny_does_not() {
	mock, saved := start_mock_gateway({
		'GET /v1/runs/run_k4a':           k4_status
		'POST /v1/runs/run_k4a/approval': '{}'
	})
	defer { mock_restore_env(saved) }
	assistant_run_mode_record('run_k4a', 'agent')
	assert assistant_load_settings().require_presence
	r := assistant_approve_report('run_k4a', 'approve', 'p1@2')
	assert !r.ok && r.data['pending'] == 'presence-required'
	assert mock.recorded().len == 0
	d := assistant_approve_report('run_k4a', 'deny', '')
	assert d.ok
	posts := mock_wait_requests(mock, 2).filter(it.method == 'POST')
	assert posts.len == 1 && posts[0].body.contains('deny')
	log := os.read_file(assistant_log_file()) or { '' }
	assert log.contains('no presence proof\trefused')
}

fn test_contract_presence_token_is_bound_and_single_use() {
	mock, saved := start_mock_gateway({
		'GET /v1/runs/run_k4b':           k4_status
		'POST /v1/runs/run_k4b/approval': '{}'
	})
	defer { mock_restore_env(saved) }
	_, old := k4_presence_env()
	defer { os.setenv('HORNERO_ASSISTANT_PRESENCE_DIR', old, true) }
	assistant_run_mode_record('run_k4b', 'agent')
	path := k4_issue('run_k4b', 'p1@2', k4_token)
	tok := AssistantApprovalPresence{
		token: k4_token
	}
	// Wrong nonce, unbound ref and a ref without generation are refused
	// and do not burn the token.
	bad := AssistantApprovalPresence{
		token: k4_token.replace('k4', 'x4')
	}
	assert assistant_approve_report_presence('run_k4b', 'approve', 'p1@2', bad).data['pending'] == 'presence-invalid'
	assert !assistant_approve_report_presence('run_k4b', 'approve', '', tok).ok
	assert !assistant_approve_report_presence('run_k4b', 'approve', 'p1', tok).ok
	assert !assistant_approve_report_presence('run_other', 'approve', 'p1@2', tok).ok
	assert os.exists(path)
	assert mock.recorded().filter(it.method == 'POST').len == 0
	ok := assistant_approve_report_presence('run_k4b', 'approve', 'p1@2', tok)
	assert ok.ok, ok.message
	assert !os.exists(path)
	again := assistant_approve_report_presence('run_k4b', 'approve', 'p1@2', tok)
	assert !again.ok && again.data['pending'] == 'presence-invalid'
	posts := mock_wait_requests(mock, 3).filter(it.method == 'POST')
	assert posts.len == 1 && posts[0].body.contains('once') && posts[0].body.contains('"request_id":"p1"')
	log := os.read_file(assistant_log_file()) or { '' }
	assert log.contains('recorded presence=token')
}

fn test_contract_presence_token_must_be_private_fresh_and_match_pending() {
	mock, saved := start_mock_gateway({
		'GET /v1/runs/run_k4c':           k4_status
		'POST /v1/runs/run_k4c/approval': '{}'
	})
	defer { mock_restore_env(saved) }
	dir, old := k4_presence_env()
	defer { os.setenv('HORNERO_ASSISTANT_PRESENCE_DIR', old, true) }
	assistant_run_mode_record('run_k4c', 'agent')
	tok := AssistantApprovalPresence{
		token: k4_token
	}
	path := k4_issue('run_k4c', 'p1@2', k4_token)
	// world-readable file
	os.chmod(path, 0o644) or {}
	assert assistant_presence_check('run_k4c', 'p1@2', k4_token).contains('private')
	os.chmod(path, 0o600) or {}
	// expired
	past := time.now().unix() - assistant_presence_ttl_seconds - 5
	os.utime(path, int(past), int(past)) or { panic(err) }
	assert assistant_presence_check('run_k4c', 'p1@2', k4_token).contains('expired')
	k4_issue('run_k4c', 'p1@2', k4_token)
	// wide directory
	os.chmod(dir, 0o755) or {}
	assert assistant_presence_check('run_k4c', 'p1@2', k4_token).contains('directory')
	os.chmod(dir, 0o700) or {}
	// short/odd tokens
	assert !assistant_presence_token_shape_ok('short')
	assert !assistant_presence_token_shape_ok('a/b' + 'c'.repeat(40))
	assert assistant_presence_check('run_k4c', 'p1@2', k4_token) == ''
	// A valid token for a request that is no longer pending is refused
	// by the binding check and is not consumed.
	k4_issue('run_k4c', 'p0@1', k4_token)
	r := assistant_approve_report_presence('run_k4c', 'approve', 'p0@1', tok)
	assert !r.ok && r.data['pending'] == 'changed'
	assert os.exists(assistant_presence_file('run_k4c', 'p0@1'))
	assert mock.recorded().filter(it.method == 'POST').len == 0
}

fn test_contract_require_presence_can_be_turned_off_and_survives_save() {
	mock, saved := start_mock_gateway({
		'GET /v1/runs/run_k4d':           k4_status
		'POST /v1/runs/run_k4d/approval': '{}'
	})
	defer { mock_restore_env(saved) }
	mut s := assistant_load_settings()
	s.require_presence = false
	assistant_save_settings(s) or { panic(err) }
	raw := os.read_file(assistant_settings_file()) or { '' }
	assert raw.contains('"requirePresence":false')
	s2 := assistant_load_settings()
	assert !s2.require_presence && s2.enabled
	// enable/disable round-trips keep the user's choice
	mut s3 := s2
	s3.enabled = true
	assistant_save_settings(s3) or { panic(err) }
	assert !assistant_load_settings().require_presence
	assistant_run_mode_record('run_k4d', 'agent')
	assert assistant_approve_report('run_k4d', 'approve', 'p1@2').ok
	assert mock_wait_requests(mock, 2).filter(it.method == 'POST').len == 1
	// non-boolean values keep the safe default
	os.write_file(assistant_settings_file(), '{"enabled":true,"approvals":{"requirePresence":"no"}}') or {
		panic(err)
	}
	assert assistant_load_settings().require_presence
}
