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

fn test_studio_jobs_help_is_discoverable() {
	assert command_help('studio jobs').contains('studio jobs submit')
	assert command_help('studio jobs').contains('ffmpeg-export')
	assert command_help('studio').contains('jobs')
}

fn test_studio_jobs_unknown_subcommand_fails() {
	assert dispatch(['horneroctl', 'studio', 'jobs', 'nope']) != 0
	assert dispatch(['horneroctl', 'studio', 'jobs', 'status']) != 0
}

fn test_studio_mode_help_is_discoverable() {
	assert command_help('studio mode').contains('studio mode restore')
	assert command_help('studio').contains('mode')
}

fn test_studio_mode_unknown_subcommand_fails() {
	assert dispatch(['horneroctl', 'studio', 'mode', 'nope']) != 0
	assert dispatch(['horneroctl', 'studio', 'mode', 'audio']) != 0
}
