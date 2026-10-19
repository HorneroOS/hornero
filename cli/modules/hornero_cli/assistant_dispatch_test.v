module hornero_cli

fn test_assistant_help_has_examples() {
	help := command_help('assistant')
	assert help.contains('horneroctl assistant <status|enable|disable|tools|ask|stop|approve|clarify|events>')
	assert help.contains('Examples:')
	assert help.contains('horneroctl assistant enable --yes')
	assert dispatch(['horneroctl', 'assistant', '--help']) == 0
	assert dispatch(['horneroctl', 'assistant', 'status', '--help']) == 0
}

fn test_assistant_parser_rules() {
	opts := parse_assistant(['enable', '--dry-run']) or { panic(err) }
	assert opts.leaf == 'enable' && opts.dry_run && !opts.yes
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

fn test_assistant_enable_dry_run_dispatch_ok() {
	assert dispatch(['horneroctl', 'assistant', 'enable', '--dry-run']) == 0
}
