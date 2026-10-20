module hornero_cli

fn test_assistant_help_has_examples() {
	help := command_help('assistant')
	assert help.contains('horneroctl assistant <status|enable|disable|tools|knowledge|sessions|model|ask|stop|approve|clarify|events>')
	assert help.contains('Examples:')
	assert help.contains('horneroctl assistant enable --yes')
	assert dispatch(['horneroctl', 'assistant', '--help']) == 0
	assert dispatch(['horneroctl', 'assistant', 'status', '--help']) == 0
}

fn test_assistant_parser_rules() {
	opts := parse_assistant(['enable', '--dry-run']) or { panic(err) }
	assert opts.leaf == 'enable' && opts.dry_run && !opts.yes
	knowledge := parse_assistant(['knowledge']) or { panic(err) }
	assert knowledge.leaf == 'knowledge'
	if _ := parse_assistant(['knowledge', 'extra']) {
		assert false, 'knowledge takes no value'
	}
	sess := parse_assistant(['sessions', 'new', 'Trip']) or { panic(err) }
	assert sess.leaf == 'sessions' && sess.arg1 == 'new'
	ask_sess := parse_assistant(['ask', 'hi', '--session', 's1']) or { panic(err) }
	assert ask_sess.session == 's1'
	if _ := parse_assistant(['tools', '--session', 's1']) {
		assert false, '--session only applies to ask'
	}
	ask := parse_assistant(['ask', 'what', 'updates', 'exist?']) or { panic(err) }
	assert ask.value == 'what updates exist?'
	if _ := parse_assistant(['enable', '--dry-run', '--yes']) {
		panic('dry-run plus yes must be rejected')
	}
	if _ := parse_assistant(['ask']) {
		panic('ask without prompt must be rejected')
	}
	if _ := parse_assistant(['fly']) {
		panic('unknown leaf must be rejected')
	}
}

fn test_assistant_usage_errors_exit_two() {
	assert dispatch(['horneroctl', 'assistant']) == 2
	assert dispatch(['horneroctl', 'assistant', 'fly']) == 2
	assert dispatch(['horneroctl', 'assistant', 'ask']) == 2
}

fn test_assistant_tools_dispatch_ok() {
	assert dispatch(['horneroctl', 'assistant', 'tools']) == 0
	assert dispatch(['horneroctl', 'assistant', 'tools', '--json']) == 0
}

fn test_assistant_approve_clarify_parser_rules() {
	ok := parse_assistant(['approve', 'run_1', 'deny']) or { panic(err) }
	assert ok.arg1 == 'run_1' && ok.arg2 == 'deny'
	cl := parse_assistant(['clarify', 'run_1', 'use', 'dark']) or { panic(err) }
	assert cl.arg1 == 'run_1' && cl.arg2 == 'use dark'
	if _ := parse_assistant(['approve', 'run_1', 'maybe']) {
		panic('invalid decision must be rejected')
	}
	if _ := parse_assistant(['approve', 'run_1']) {
		panic('approve without decision must be rejected')
	}
	assert dispatch(['horneroctl', 'assistant', 'approve', '--help']) == 0
	assert dispatch(['horneroctl', 'assistant', 'clarify', 'run_1']) == 2
}

fn test_assistant_events_parser_rules() {
	ok := parse_assistant(['events', 'run_1']) or { panic(err) }
	assert ok.value == 'run_1'
	if _ := parse_assistant(['events']) {
		panic('events without run id must be rejected')
	}
	assert dispatch(['horneroctl', 'assistant', 'events', '--help']) == 0
}

fn test_assistant_stream_flag_rules() {
	ask := parse_assistant(['ask', 'hola', '--stream']) or { panic(err) }
	assert ask.stream && ask.value == 'hola'
	ev := parse_assistant(['events', 'run_1', '--stream']) or { panic(err) }
	assert ev.stream && ev.value == 'run_1'
	if _ := parse_assistant(['status', '--stream']) {
		panic('--stream outside ask/events must be rejected')
	}
	help := command_help('assistant ask')
	assert help.contains('--stream')
}

fn test_assistant_enable_dry_run_dispatch_ok() {
	assert dispatch(['horneroctl', 'assistant', 'enable', '--dry-run']) == 0
}

fn test_stream_delta_frame_is_ndjson() {
	frame := stream_delta_frame('hola \"che\"')
	assert frame.starts_with('{')
	assert frame.contains('\"type\":\"delta\"')
	assert frame.contains('hola')
	assert !frame.contains('\n')
}
