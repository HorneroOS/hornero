module hornero_cli

import os
import time

fn test_assistant_help_has_examples() {
	help := command_help('assistant')
	assert help.contains('horneroctl assistant <status|health|enable|disable|setup|gateway|tools|knowledge|sessions|model|usage|ask|stop|approve|clarify|events|log|policy|workspace|profile|prompt|tool|shell-proposal|delegate>')
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
	vault := parse_assistant(['knowledge', 'vault', 'generate', '--yes']) or { panic(err) }
	assert vault.arg1 == 'vault' && vault.arg2 == 'generate' && vault.yes
	check := parse_assistant(['knowledge', 'vault', 'check']) or { panic(err) }
	assert check.arg1 == 'vault' && check.arg2 == 'check'
	if _ := parse_assistant(['knowledge', 'vault', 'fly']) {
		assert false, 'unknown vault action must be rejected'
	}
	assert command_help('assistant knowledge').contains('knowledge vault generate --yes')
	assert dispatch(['horneroctl', 'assistant', 'knowledge', '--help']) == 0
	sess := parse_assistant(['sessions', 'new', 'Trip']) or { panic(err) }
	assert sess.leaf == 'sessions' && sess.arg1 == 'new'
	ask_sess := parse_assistant(['ask', 'hi', '--session', 's1']) or { panic(err) }
	assert ask_sess.session == 's1'
	if _ := parse_assistant(['tools', '--session', 's1']) {
		assert false, '--session only applies to ask'
	}
	logf := parse_assistant(['log', '--filter', 'deny']) or { panic(err) }
	assert logf.leaf == 'log' && logf.filter == 'deny'
	if _ := parse_assistant(['status', '--filter', 'deny']) {
		assert false, '--filter only applies to log'
	}
	if _ := parse_assistant(['log', '--filter']) {
		assert false, '--filter needs a value'
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

fn test_assistant_ask_mode_parser_rules() {
	// hornero#414: --mode on ask accepts exactly the session modes.
	for m in ['ask', 'agent', 'chat'] {
		opts := parse_assistant(['ask', 'hi', '--mode', m]) or { panic(err) }
		assert opts.leaf == 'ask' && opts.mode == m && opts.value == 'hi'
	}
	plain := parse_assistant(['ask', 'hi']) or { panic(err) }
	assert plain.mode == '', 'no --mode must stay empty (legacy default)'
	if _ := parse_assistant(['ask', 'hi', '--mode', 'yolo']) {
		assert false, 'unknown mode must be rejected'
	}
	if _ := parse_assistant(['ask', 'hi', '--mode']) {
		assert false, '--mode without a value must be rejected'
	}
	if _ := parse_assistant(['status', '--mode', 'ask']) {
		assert false, '--mode outside ask/sessions must be rejected'
	}
	assert dispatch(['horneroctl', 'assistant', 'ask', 'hi', '--mode', 'yolo']) == 2
	assert dispatch(['horneroctl', 'assistant', 'ask', 'hi', '--mode']) == 2
	help := command_help('assistant ask')
	assert help.contains('--mode ask|agent|chat')
	assert help.contains('horneroctl assistant ask "what is 2+2?" --mode ask')
}

fn test_assistant_setup_parser_rules() {
	setup_help := command_help('assistant setup')
	assert setup_help.contains('horneroctl assistant setup --adopt-dotfiles --dry-run')
	setup := parse_assistant(['setup', '--dry-run']) or { panic(err) }
	assert setup.leaf == 'setup' && setup.dry_run && !setup.remove
	rm := parse_assistant(['setup', '--remove', '--yes']) or { panic(err) }
	assert rm.remove && rm.yes
	if _ := parse_assistant(['setup', 'extra']) {
		panic('setup takes no argument')
	}
	if _ := parse_assistant(['status', '--remove']) {
		panic('--remove outside setup must be rejected')
	}
	adopt := parse_assistant(['setup', '--adopt-dotfiles', '--dry-run']) or { panic(err) }
	assert adopt.adopt_dotfiles && adopt.dry_run && !adopt.yes
	if _ := parse_assistant(['setup', '--adopt-dotfiles', '--remove', '--yes']) {
		panic('adoption and removal must be separate operations')
	}
	if _ := parse_assistant(['status', '--adopt-dotfiles']) {
		panic('--adopt-dotfiles outside setup must be rejected')
	}
	assert dispatch(['horneroctl', 'assistant', 'setup', '--help']) == 0
	assert dispatch(['horneroctl', 'assistant', 'setup', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'assistant', 'setup', '--remove', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'assistant', 'setup', '--adopt-dotfiles']) == 1
	assert dispatch(['horneroctl', 'assistant', 'setup', 'extra']) == 2
}

fn test_assistant_dotfiles_adoption_dispatch_dry_run_uses_isolated_paths() {
	root := os.join_path(os.temp_dir(), 'hornero-cli-adopt-dry-${os.getpid()}-${time.now().unix_milli()}')
	defer { os.rmdir_all(root) or {} }
	old_config := os.getenv('XDG_CONFIG_HOME')
	old_state := os.getenv('XDG_STATE_HOME')
	old_hermes := os.getenv('HERMES_HOME')
	os.setenv('XDG_CONFIG_HOME', os.join_path(root, 'config'), true)
	os.setenv('XDG_STATE_HOME', os.join_path(root, 'state'), true)
	os.setenv('HERMES_HOME', os.join_path(root, 'hermes'), true)
	defer {
		if old_config.len > 0 {
			os.setenv('XDG_CONFIG_HOME', old_config, true)
		} else {
			os.unsetenv('XDG_CONFIG_HOME')
		}
		if old_state.len > 0 {
			os.setenv('XDG_STATE_HOME', old_state, true)
		} else {
			os.unsetenv('XDG_STATE_HOME')
		}
		if old_hermes.len > 0 {
			os.setenv('HERMES_HOME', old_hermes, true)
		} else {
			os.unsetenv('HERMES_HOME')
		}
	}

	assert dispatch(['horneroctl', 'assistant', 'setup', '--adopt-dotfiles', '--dry-run']) == 0
	assert !os.exists(root)
}

fn test_assistant_gateway_parser_rules() {
	gw := parse_assistant(['gateway']) or { panic(err) }
	assert gw.leaf == 'gateway' && gw.arg1 == ''
	start := parse_assistant(['gateway', 'start', '--yes']) or { panic(err) }
	assert start.arg1 == 'start' && start.yes && !start.dry_run
	stop := parse_assistant(['gateway', 'stop', '--dry-run']) or { panic(err) }
	assert stop.arg1 == 'stop' && stop.dry_run
	if _ := parse_assistant(['gateway', 'fly']) {
		panic('unknown gateway action must be rejected')
	}
	if _ := parse_assistant(['gateway', 'start', 'extra']) {
		panic('gateway start takes no extra argument')
	}
	assert dispatch(['horneroctl', 'assistant', 'gateway', '--help']) == 0
	assert dispatch(['horneroctl', 'assistant', 'gateway', 'fly']) == 2
	assert dispatch(['horneroctl', 'assistant', 'gateway', 'start', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'assistant', 'gateway', 'stop', '--dry-run']) == 0
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

fn test_stream_trace_frame_shapes() {
	frame := stream_trace_frame('thinking', 'checking themes')
	assert frame.contains('\"type\":\"thinking\"')
	assert frame.contains('checking themes')
	tool := stream_trace_frame('tool', '▸ terminal')
	assert tool.contains('\"type\":\"tool\"')
}

fn test_assistant_policy_workspace_dispatch() {
	assert dispatch(['horneroctl', 'assistant', 'policy', '--help']) == 0
	assert dispatch(['horneroctl', 'assistant', 'workspace', '--help']) == 0
	assert dispatch(['horneroctl', 'assistant', 'policy']) == 0
	assert dispatch(['horneroctl', 'assistant', 'workspace']) == 0
	// Mutating policy/workspace actions refuse without --yes (exit 1, not usage).
	assert dispatch(['horneroctl', 'assistant', 'policy', 'preset', 'workspace-agent']) == 1
	assert dispatch(['horneroctl', 'assistant', 'policy', 'preset', 'workspace-agent', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'assistant', 'policy', 'preset', 'bogus', '--dry-run']) == 1
	assert dispatch(['horneroctl', 'assistant', 'workspace', 'use', 'ws-nope']) == 1
	opts := parse_assistant(['policy', 'check', 'filesystem.read', '/tmp/x']) or { panic(err) }
	assert opts.parts.len == 3 && opts.parts[1] == 'filesystem.read'
}

fn test_assistant_profile_prompt_dispatch() {
	assert dispatch(['horneroctl', 'assistant', 'profile', '--help']) == 0
	assert dispatch(['horneroctl', 'assistant', 'prompt', '--help']) == 0
	assert dispatch(['horneroctl', 'assistant', 'prompt', 'history']) == 0
	assert dispatch(['horneroctl', 'assistant', 'profile', 'fix']) == 1
}

fn test_assistant_tool_dispatch() {
	assert dispatch(['horneroctl', 'assistant', 'tool', '--help']) == 0
	// Unknown tools are refused by the broker (exit 1), never executed.
	assert dispatch(['horneroctl', 'assistant', 'tool', 'rm_rf', '/']) == 1
	// Default read-only policy denies theme_set without executing it.
	assert dispatch(['horneroctl', 'assistant', 'tool', 'theme_set', 'pampa']) == 1
}

fn test_assistant_prompt_set_text_dispatch() {
	assert dispatch(['horneroctl', 'assistant', 'prompt', 'set-text', 'You are Javi.']) == 1
	assert dispatch(['horneroctl', 'assistant', 'prompt', 'set-text', 'You are Javi.', '--dry-run']) == 0
}

fn test_assistant_shell_proposal_dispatch() {
	assert command_help('assistant shell-proposal').contains('Examples:')
	assert command_help('assistant delegate').contains('Examples:')
	assert dispatch(['horneroctl', 'assistant', 'shell-proposal', '--help']) == 0
	assert dispatch(['horneroctl', 'assistant', 'delegate', '--help']) == 0
	assert dispatch(['horneroctl', 'assistant', 'shell-proposal', '--command', 'ls -la']) == 0
	assert dispatch(['horneroctl', 'assistant', 'shell-proposal', '--command', 'ls -la', '--json']) == 0
	// Missing --command is a usage error; an empty command fails closed.
	assert dispatch(['horneroctl', 'assistant', 'shell-proposal']) == 2
	assert dispatch(['horneroctl', 'assistant', 'shell-proposal', '--command', '']) == 1
	sp := parse_assistant(['shell-proposal', '--command', 'ls -la']) or { panic(err) }
	assert sp.leaf == 'shell-proposal' && sp.command == 'ls -la' && sp.has_command
	if _ := parse_assistant(['status', '--command', 'ls']) {
		assert false, '--command only applies to shell-proposal'
	}
}

fn test_assistant_delegate_dispatch() {
	assert dispatch(['horneroctl', 'assistant', 'delegate', 'codex', '--workspace', os.temp_dir(),
		'review the parser']) == 0
	assert dispatch(['horneroctl', 'assistant', 'delegate', 'nope', '--workspace', os.temp_dir(),
		'task']) == 1
	assert dispatch(['horneroctl', 'assistant', 'delegate', 'codex', '--workspace',
		'/tmp/hx-no-such-workspace-xyz-123', 'task']) == 1
	assert dispatch(['horneroctl', 'assistant', 'delegate', 'codex', '--workspace', os.temp_dir()]) == 1
	assert dispatch(['horneroctl', 'assistant', 'delegate']) == 2
	dl := parse_assistant(['delegate', 'codex', '--workspace', '/tmp', 'review', 'parser']) or {
		panic(err)
	}
	assert dl.leaf == 'delegate' && dl.arg1 == 'codex' && dl.workspace == '/tmp'
	assert dl.arg2 == 'review parser'
	if _ := parse_assistant(['status', '--workspace', '/tmp']) {
		assert false, '--workspace only applies to delegate'
	}
}

fn test_assistant_model_set_dispatch() {
	assert dispatch(['horneroctl', 'assistant', 'model', 'set', 'gpt-5']) == 1
	assert dispatch(['horneroctl', 'assistant', 'model', 'set', 'gpt-5', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'assistant', 'model', 'set', 'bad model', '--dry-run']) == 1
}
