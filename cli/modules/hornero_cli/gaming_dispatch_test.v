module hornero_cli

fn test_gaming_help_is_discoverable() {
	assert command_help('gaming').contains('horneroctl gaming doctor')
	assert command_help('gaming doctor').contains('Read-only')
	assert command_help('gaming doctor').contains('not hardware qualification')
	assert root_help().contains('gaming')
}

fn test_gaming_completions_include_gaming() {
	assert bash_completion().contains('gaming')
	assert zsh_completion().contains('gaming')
	assert fish_completion().contains('gaming')
}

fn test_gaming_unknown_subcommand_fails() {
	assert dispatch(['horneroctl', 'gaming', 'nope']) != 0
	assert dispatch(['horneroctl', 'gaming']) != 0
	assert dispatch(['horneroctl', 'gaming', 'doctor', 'extra']) != 0
}
