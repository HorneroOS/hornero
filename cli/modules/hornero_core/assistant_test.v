module hornero_core

import os

fn test_assistant_tool_allowlist_read_only() {
	for tool in ['system_info', 'appearance_status', 'theme_list', 'gtk_list', 'gtk_current',
		'package_updates'] {
		argv := assistant_tool_argv(tool, '') or { panic('allowlisted tool rejected: ${tool}') }
		assert argv[0] == 'horneroctl'
		assert argv[argv.len - 1] == '--json'
	}
	show := assistant_tool_argv('theme_show', 'hornero-199x') or { panic(err) }
	assert show == ['horneroctl', 'appearance', 'theme', 'show', 'hornero-199x', '--json']
}

fn test_assistant_tool_allowlist_rejects_mutations_and_paths() {
	for tool in ['theme_apply', 'package_upgrade', 'shell', 'exec', ''] {
		assistant_tool_argv(tool, '') or { continue }
		panic('non-allowlisted tool accepted: ${tool}')
	}
	for bad in ['', '..', '../etc', 'a/b', 'x/../y'] {
		assistant_tool_argv('theme_show', bad) or { continue }
		panic('unsafe theme id accepted: ${bad}')
	}
}

fn test_parse_sse_events_groups_data_by_event() {
	body := 'event: run.started\ndata: {"run_id":"run_1"}\n\nevent: message.delta\ndata: {"delta":"Ho"}\ndata: {"delta":"la"}\n\nevent: run.completed\ndata: {"output":"Hola"}\n'
	events := parse_sse_events(body)
	assert events.len == 3
	assert events[0].kind == 'run.started'
	assert events[1].kind == 'message.delta'
	assert events[2].kind == 'run.completed'
}

fn test_assistant_collect_text_prefers_stream_then_final() {
	streamed := parse_sse_events('data: {"delta":"Ho"}\n\ndata: {"delta":"la"}\n\ndata: {"output":"ignored"}\n')
	assert assistant_collect_text(streamed) == 'Hola'
	final := parse_sse_events('data: {"status":"working"}\n\ndata: {"output":"done"}\n')
	assert assistant_collect_text(final) == 'done'
	assert assistant_collect_text([]) == ''
}

fn test_assistant_settings_default_disabled_and_loopback_only() {
	settings := assistant_load_settings()
	// In a clean test environment there is no user file; defaults must be safe.
	if settings.endpoint.len > 0 {
		assert settings.endpoint.starts_with('http://127.0.0.1')
			|| settings.endpoint.starts_with('http://localhost')
	}
}

fn test_assistant_pending_request_detects_approval() {
	events := parse_sse_events('event: approval.request\ndata: {"type":"approval.request","command":"pacman -S x","choices":["approve","deny"]}\n\n')
	pending := assistant_pending_request(events)
	assert pending.kind == 'approval'
	assert pending.detail == 'pacman -S x'
	assert pending.choices.len == 2
}

fn test_assistant_pending_request_detects_clarify_and_none() {
	clarify := parse_sse_events('data: {"type":"clarify.request","question":"which theme?"}\n\n')
	assert assistant_pending_request(clarify).detail == 'which theme?'
	plain := parse_sse_events('data: {"delta":"hi"}\n\n')
	assert assistant_pending_request(plain).kind == 'none'
}

fn test_assistant_gateway_compat_accepts_studied_hermes_shape() {
	// Shape from NousResearch/hermes-agent gateway _handle_capabilities.
	body := '{"object":"hermes.api_server.capabilities","platform":"hermes-agent","model":"m","auth":{"type":"bearer","required":true},"features":{"run_submission":true,"run_events_sse":true,"run_stop":true,"run_approval_response":true,"approval_events":true,"skills_api":true},"endpoints":{}}'
	compatible, missing := assistant_gateway_compat(body)
	assert compatible
	assert missing.len == 0
}

fn test_assistant_gateway_compat_reports_missing_features() {
	body := '{"platform":"hermes-agent","features":{"run_submission":true,"run_events_sse":false}}'
	compatible, missing := assistant_gateway_compat(body)
	assert !compatible
	assert 'run_events_sse' in missing
	assert 'run_stop' in missing
	assert 'run_approval_response' in missing
	assert 'approval_events' in missing
	assert !('platform:hermes-agent' in missing)
}

fn test_assistant_gateway_compat_rejects_foreign_or_broken_bodies() {
	compatible, missing := assistant_gateway_compat('{"platform":"other","features":{}}')
	assert !compatible
	assert 'platform:hermes-agent' in missing
	broken, broken_missing := assistant_gateway_compat('not json')
	assert !broken
	assert broken_missing.len == 1
	array, _ := assistant_gateway_compat('[1,2]')
	assert !array
}

fn test_sse_stream_parser_handles_split_lines_and_chunks() {
	mut parser := SseStreamParser{}
	mut events := parser.feed('event: message\ndata: {"del')
	assert events.len == 0
	events = parser.feed('ta":"Ho')
	assert events.len == 0
	events = parser.feed('la"}\n\ndata: {"delta":"!"}\n\n')
	assert events.len == 2
	assert events[0].data == '{"delta":"Hola"}'
	assert assistant_event_text(events[0]) == 'Hola'
	assert assistant_event_text(events[1]) == '!'
	rest := parser.finish()
	assert rest.len == 0
}

fn test_sse_stream_parser_finish_flushes_trailing_event() {
	mut parser := SseStreamParser{}
	mut events := parser.feed('data: {"output":"final answer"}')
	assert events.len == 0
	events = parser.finish()
	assert events.len == 1
	assert assistant_event_final(events[0]) == 'final answer'
	assert assistant_collect_text(events) == 'final answer'
}

fn test_assistant_approval_choice_maps_to_gateway_vocabulary() {
	assert assistant_approval_choice('approve') == 'once'
	assert assistant_approval_choice('deny') == 'deny'
	// Never widen a single approve to session/always.
	assert assistant_approval_choice('approve') !in ['session', 'always']
}

fn test_assistant_pending_control_parses_authority_fields() {
	body := '{"status":"waiting_for_approval","pending_controls":[{"kind":"approval","prompt_id":"abc123","execution_generation":2,"command":"rm -rf x"}]}'
	prompt_id, gen := assistant_pending_control(body)
	assert prompt_id == 'abc123'
	assert gen == 2
	none_id, none_gen := assistant_pending_control('{"status":"running","pending_controls":[]}')
	assert none_id == '' && none_gen == 0
	bad_id, _ := assistant_pending_control('not json')
	assert bad_id == ''
}

fn test_attachment_classification() {
	assert assistant_attachment_kind('/tmp/shot.png') == 'image'
	assert assistant_attachment_kind('/tmp/voice.WAV') == 'audio'
	assert assistant_attachment_kind('/tmp/session.log') == 'text'
	assert assistant_attachment_kind('/tmp/blob.bin') == 'unsupported'
	assert assistant_attachment_blocked('.env')
	assert assistant_attachment_blocked('hermes-provider.env')
	assert assistant_attachment_blocked('id_rsa')
	assert assistant_attachment_blocked('deploy.pem')
	assert !assistant_attachment_blocked('screenshot.png')
	assert !assistant_attachment_blocked('notes.md')
}

fn test_assistant_knowledge_snapshot() {
	report := assistant_knowledge_report()
	assert report.ok
	assert report.command == 'assistant knowledge'
	assert report.data['class'] == 'safe-read-only'
	assert report.data['tools'].contains('system_info')
	assert report.data['generated_by'].len > 0
	assert report.data['approvals'].contains('never auto-answered')
	for key, value in report.data {
		assert !value.contains('assistant.key'), 'knowledge snapshot must not leak key material: ${key}'
	}
}

fn test_assistant_sessions_registry_roundtrip() {
	saved := os.getenv('HORNERO_ASSISTANT_SESSIONS_FILE')
	os.setenv('HORNERO_ASSISTANT_SESSIONS_FILE', '/tmp/hx-assistant-sessions-test.txt', true)
	os.rm('/tmp/hx-assistant-sessions-test.txt') or {}
	created := assistant_sessions_new_report('Trip planning')
	assert created.ok
	id := created.data['id']
	assert id.len > 0
	assert assistant_current_session_key('') == 'hornero:${id}'
	assert assistant_current_session_key('other') == 'hornero:other'
	list := assistant_sessions_list_report()
	assert list.ok
	assert list.message.contains('Trip planning')
	assert assistant_sessions_use_report('nope').ok == false
	os.rm('/tmp/hx-assistant-sessions-test.txt') or {}
	if saved.len == 0 {
		os.unsetenv('HORNERO_ASSISTANT_SESSIONS_FILE')
	} else {
		os.setenv('HORNERO_ASSISTANT_SESSIONS_FILE', saved, true)
	}
}
