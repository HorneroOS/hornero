module hornero_cli

fn test_plugin_action_parser_shapes() {
	list := parse_plugin(['action', 'list']) or {
		assert false, err.msg()
		return
	}
	assert list.leaf == 'action' && list.value == 'list' && list.action_plugin == ''

	run := parse_plugin(['action', 'run', 'example-clock', 'plugin_file_read', 'notes.txt']) or {
		assert false, err.msg()
		return
	}
	assert run.action_plugin == 'example-clock'
	assert run.action_name == 'plugin_file_read'
	assert run.action_arg == 'notes.txt'
	assert !run.dry_run && !run.yes

	mutate := parse_plugin(['action', 'run', 'example-clock', 'theme_set', 'pampa', '--yes']) or {
		assert false, err.msg()
		return
	}
	assert mutate.yes && mutate.action_arg == 'pampa'

	invalid := [
		['action'],
		['action', 'exec', 'example-clock', 'system_info'],
		['action', 'run', 'example-clock'],
		['action', 'check', 'example-clock', 'system_info', '--yes'],
		['action', 'list', 'example-clock', 'system_info'],
		['action', 'run', 'example-clock', 'system_info', '--dry-run', '--yes'],
		['action', 'run', 'example-clock', 'system_info', 'a', 'b'],
	]
	for args in invalid {
		if _ := parse_plugin(args) {
			assert false, 'invalid plugin action form must be rejected: ${args}'
		}
	}
}

fn test_plugin_action_help_and_dispatch_exit_codes() {
	assert command_help('plugin action').contains('Examples:')
	assert command_help('plugin action').contains('horneroctl plugin action run')
	assert command_help('plugin action').contains('not sandboxed')
	assert command_help('plugin').contains('action <list|check|run>')
	assert dispatch(['horneroctl', 'plugin', 'action', '--help']) == 0
	// The catalogue listing is read-only and needs no installed plugin.
	assert dispatch(['horneroctl', 'plugin', 'action', 'list']) == 0
	// Unknown/uninstalled subjects fail closed with exit 1, never 0.
	assert dispatch(['horneroctl', 'plugin', 'action', 'run', 'no-such-plugin-408', 'system_info']) == 1
	assert dispatch(['horneroctl', 'plugin', 'action', 'run', '../outside', 'system_info']) == 1
	assert dispatch(['horneroctl', 'plugin', 'action', 'bogus']) == 2
}
