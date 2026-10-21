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
	body := m.routes['${req.method} ${req.path}'] or { '{}' }
	conn.write_string('HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ${body.len}\r\nConnection: close\r\n\r\n${body}') or {}
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
		'XDG_CONFIG_HOME':                 os.getenv('XDG_CONFIG_HOME')
		'HORNERO_ASSISTANT_KEY':           os.getenv('HORNERO_ASSISTANT_KEY')
		'HORNERO_ASSISTANT_SESSIONS_FILE': os.getenv('HORNERO_ASSISTANT_SESSIONS_FILE')
	}
	tmp := os.join_path(os.temp_dir(), 'hornero-contract-${port}')
	os.mkdir_all(os.join_path(tmp, 'hornero')) or { panic(err) }
	os.write_file(os.join_path(tmp, 'hornero', 'assistant.json'), '{"enabled":true,"endpoint":"http://127.0.0.1:${port}"}\n') or {
		panic(err)
	}
	os.setenv('XDG_CONFIG_HOME', tmp, true)
	os.setenv('HORNERO_ASSISTANT_KEY', 'contract-test-key', true)
	os.setenv('HORNERO_ASSISTANT_SESSIONS_FILE', os.join_path(tmp, 'sessions.json'), true)
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
	result := assistant_approve_report('run_1', 'approve')
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
	result := assistant_approve_report('run_2', 'deny')
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
	result := assistant_approve_report('run_3', 'approve')
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
	result := assistant_events_report('run_6')
	assert !result.ok
	assert result.message.contains('waiting for approval')
	// Only the events GET may be recorded: no approval POST ever.
	reqs := mock_wait_requests(mock, 1)
	assert reqs.len == 1
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
	assert assistant_approve_report('run_9', 'approve').ok
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
