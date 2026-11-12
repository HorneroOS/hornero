module hornero_cli

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
