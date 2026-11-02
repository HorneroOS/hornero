module hornero_cli

fn test_bluetooth_help_has_examples() {
	for cmd in ['bluetooth', 'bluetooth doctor', 'hardware bluetooth', 'hardware bluetooth doctor'] {
		h := command_help(cmd)
		assert h.contains('Examples:'), cmd
		assert h.contains('doctor'), cmd
	}
	assert command_help('bluetooth doctor').contains('Read-only')
	assert command_help('bluetooth doctor').contains('rfkill')
	assert command_help('bluetooth doctor').contains('BlueZ')
	assert command_help('root').contains('bluetooth') || root_help().contains('bluetooth')
}

fn test_dispatch_bluetooth_doctor_and_aliases() {
	// Doctor is read-only: on a machine without Bluetooth it reports
	// failures (exit 1), never a usage error and never a crash.
	code := dispatch(['horneroctl', 'bluetooth', 'doctor'])
	assert code in [0, 1]
	assert dispatch(['horneroctl', 'hardware', 'bluetooth', 'doctor']) in [0, 1]
	assert dispatch(['horneroctl', '--json', 'bluetooth', 'doctor']) in [0, 1]
	assert dispatch(['horneroctl', '--json', 'hardware', 'bluetooth', 'doctor']) in [
		0,
		1,
	]
	assert dispatch(['horneroctl', '--quiet', 'bluetooth', 'doctor']) in [0, 1]
	assert dispatch(['horneroctl', 'bluetooth', 'doctor', '--help']) == 0
	assert dispatch(['horneroctl', 'hardware', 'bluetooth', '--help']) == 0
	assert dispatch(['horneroctl', 'hardware', 'bluetooth', 'doctor', '--help']) == 0
	assert dispatch(['horneroctl', 'bluetooth', '--help']) == 0
}

fn test_dispatch_bluetooth_reads_and_mutation_gating() {
	assert dispatch(['horneroctl', 'bluetooth', 'status', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'hardware', 'bluetooth', 'status', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'bluetooth', 'devices', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'bluetooth', 'power', 'on', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'bluetooth', 'power', 'off', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'bluetooth', 'restart', '--dry-run']) == 0
	// Mutations without --yes fail (exit 1).
	assert dispatch(['horneroctl', 'bluetooth', 'power', 'on']) == 1
	assert dispatch(['horneroctl', 'bluetooth', 'restart']) == 1
	assert dispatch(['horneroctl', 'hardware', 'bluetooth', 'power', 'off']) == 1
}

fn test_dispatch_bluetooth_usage_errors() {
	assert dispatch(['horneroctl', 'bluetooth']) == 2
	assert dispatch(['horneroctl', 'bluetooth', 'bogus']) == 2
	assert dispatch(['horneroctl', 'hardware', 'bluetooth']) == 2
	assert dispatch(['horneroctl', 'hardware', 'bluetooth', 'bogus']) == 2
	assert dispatch(['horneroctl', 'bluetooth', 'doctor', 'extra']) == 2
	assert dispatch(['horneroctl', 'bluetooth', 'doctor', '--bogus']) == 2
	assert dispatch(['horneroctl', 'bluetooth', 'status', '--yes']) == 2
	assert dispatch(['horneroctl', 'bluetooth', 'power']) == 2
	assert dispatch(['horneroctl', 'bluetooth', 'power', 'bogus', '--dry-run']) == 2
	assert dispatch(['horneroctl', 'bluetooth', 'power', 'on', '--bogus']) == 2
}
