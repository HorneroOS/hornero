module hornero_cli

import os

fn test_agent_help_is_discoverable() {
	assert command_help('agent').contains('horneroctl agent list')
	assert command_help('agent').contains('Examples:')
	assert command_help('agent list').contains('Read-only')
	assert command_help('agent doctor').contains('Read-only')
	assert command_help('agent launch').contains('Dry-run proposal only')
	assert command_help('agent default').contains('agent-default.json')
	assert dispatch(['horneroctl', 'agent', 'list', '--help']) == 0
	assert dispatch(['horneroctl', 'agent', '--help']) == 0
	assert root_help().contains('agent')
}

fn test_agent_completions_include_agent() {
	assert bash_completion().contains('agent')
	assert zsh_completion().contains('agent')
	assert fish_completion().contains('agent')
}

fn test_agent_read_only_commands_succeed() {
	assert dispatch(['horneroctl', 'agent', 'list']) == 0
	assert dispatch(['horneroctl', 'agent', 'status']) == 0
	assert dispatch(['horneroctl', 'agent', 'status', 'codex']) == 0
	assert dispatch(['horneroctl', 'agent', 'doctor']) == 0
	// launch is a dry-run proposal only; dispatching it executes nothing.
	assert dispatch(['horneroctl', 'agent', 'launch', 'codex']) == 0
}

fn test_agent_unknown_and_usage_fail() {
	assert dispatch(['horneroctl', 'agent']) != 0
	assert dispatch(['horneroctl', 'agent', 'nope']) != 0
	assert dispatch(['horneroctl', 'agent', 'status', 'nope']) != 0
	assert dispatch(['horneroctl', 'agent', 'launch']) != 0
	assert dispatch(['horneroctl', 'agent', 'launch', 'nope']) != 0
	assert dispatch(['horneroctl', 'agent', 'default', 'set']) != 0
	assert dispatch(['horneroctl', 'agent', 'default', 'set', 'codex']) != 0
	assert dispatch(['horneroctl', 'agent', 'default', 'set', 'codex', '--dry-run']) == 0
}

fn test_agent_config_help_and_read_only_commands() {
	assert command_help('agent config').contains('Canonical instructions/skills/MCP/ACP')
	assert command_help('agent config').contains('ownership receipts')
	assert command_help('agent config').contains('companion fragments')
	assert command_help('agent config').contains('do not load automatically')
	assert command_help('agent').contains('config apply')
	assert command_help('agent').contains('companion fragments')
	// isolated registry with one entry to exercise consent/dry-run paths
	tmp := '/tmp/hx-agent-config-dispatch-test'
	os.rmdir_all(tmp) or {}
	os.mkdir_all(tmp) or { assert false }
	cfg := tmp + '/agent-config.json'
	os.write_file(cfg, '{"schemaVersion":1,"entries":[{"id":"i1","kind":"instruction","name":"Base","targets":["codex"],"content":"hi"}]}') or { assert false }
	saved_cfg := os.getenv('HORNERO_AGENT_CONFIG_FILE')
	saved_state := os.getenv('HORNERO_AGENT_CONFIG_STATE_DIR')
	saved_codex_home := os.getenv('CODEX_HOME')
	saved_xdg_config := os.getenv('XDG_CONFIG_HOME')
	saved_xdg_state := os.getenv('XDG_STATE_HOME')
	os.setenv('HORNERO_AGENT_CONFIG_FILE', cfg, true)
	os.setenv('HORNERO_AGENT_CONFIG_STATE_DIR', tmp + '/state', true)
	os.setenv('CODEX_HOME', tmp + '/codex', true)
	os.setenv('XDG_CONFIG_HOME', tmp + '/xdg-config', true)
	os.setenv('XDG_STATE_HOME', tmp + '/xdg-state', true)
	defer {
		if saved_cfg.len == 0 {
			os.unsetenv('HORNERO_AGENT_CONFIG_FILE')
		} else {
			os.setenv('HORNERO_AGENT_CONFIG_FILE', saved_cfg, true)
		}
		if saved_state.len == 0 {
			os.unsetenv('HORNERO_AGENT_CONFIG_STATE_DIR')
		} else {
			os.setenv('HORNERO_AGENT_CONFIG_STATE_DIR', saved_state, true)
		}
		if saved_codex_home.len == 0 {
			os.unsetenv('CODEX_HOME')
		} else {
			os.setenv('CODEX_HOME', saved_codex_home, true)
		}
		if saved_xdg_config.len == 0 {
			os.unsetenv('XDG_CONFIG_HOME')
		} else {
			os.setenv('XDG_CONFIG_HOME', saved_xdg_config, true)
		}
		if saved_xdg_state.len == 0 {
			os.unsetenv('XDG_STATE_HOME')
		} else {
			os.setenv('XDG_STATE_HOME', saved_xdg_state, true)
		}
		os.rmdir_all(tmp) or {}
	}
	assert dispatch(['horneroctl', 'agent', 'config', 'status']) == 0
	assert dispatch(['horneroctl', 'agent', 'config', 'apply']) != 0
	assert dispatch(['horneroctl', 'agent', 'config', 'apply', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'agent', 'config', 'nope']) != 0
	// check fails closed on a registry that cannot be parsed.
	os.write_file(cfg, 'not json') or { assert false }
	assert dispatch(['horneroctl', 'agent', 'config', 'check']) != 0
}
