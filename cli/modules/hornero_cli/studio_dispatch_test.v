module hornero_cli

fn test_studio_help_is_discoverable() {
	assert command_help('studio').contains('horneroctl studio selection set')
	assert command_help('studio doctor').contains('Read-only')
	assert command_help('studio selection').contains('--dry-run')
	assert root_help().contains('studio')
}

fn test_studio_completions_include_studio() {
	assert bash_completion().contains('studio')
	assert zsh_completion().contains('studio')
	assert fish_completion().contains('studio')
}

fn test_studio_unknown_subcommand_fails() {
	assert dispatch(['horneroctl', 'studio', 'nope']) != 0
	assert dispatch(['horneroctl', 'studio']) != 0
}
