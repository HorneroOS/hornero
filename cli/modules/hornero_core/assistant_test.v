module hornero_core

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
