module hornero_cli

fn test_recovery_help_is_discoverable() {
	assert command_help('recovery').contains('horneroctl recovery doctor')
	assert command_help('recovery').contains('never OS rollback')
	assert command_help('recovery doctor').contains('Read-only')
	assert command_help('recovery doctor').contains('not proof')
	assert command_help('recovery doctor').contains('Examples:')
	assert dispatch(['horneroctl', 'recovery', 'doctor', '--help']) == 0
	assert root_help().contains('recovery')
}

fn test_recovery_completions_include_recovery() {
	assert bash_completion().contains('recovery')
	assert zsh_completion().contains('recovery')
	assert fish_completion().contains('recovery')
}

fn test_recovery_doctor_runs_and_reports_unavailable_backend() {
	// The doctor is read-only and safe on any host. With the shipped
	// backend still 'none', its backend check must fail, so the
	// command can never exit 0 claiming recovery readiness.
	assert dispatch(['horneroctl', 'recovery', 'doctor']) != 0
	assert dispatch(['horneroctl', '--json', 'recovery', 'doctor']) != 0
}

fn test_recovery_unknown_subcommand_fails() {
	assert dispatch(['horneroctl', 'recovery', 'nope']) != 0
	assert dispatch(['horneroctl', 'recovery']) != 0
	assert dispatch(['horneroctl', 'recovery', 'doctor', 'extra']) != 0
	// Restore/create must not exist until the backend is VM-proven:
	// a decorative recovery verb would be a fake rollback control.
	assert dispatch(['horneroctl', 'recovery', 'restore']) != 0
	assert dispatch(['horneroctl', 'recovery', 'create']) != 0
}
