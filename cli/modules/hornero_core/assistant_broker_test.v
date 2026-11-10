module hornero_core

fn test_broker_catalogue_is_typed_and_closed() {
	_, found := assistant_broker_tool('shell')
	assert !found
	_, found2 := assistant_broker_tool('run_command')
	assert !found2
	t, found3 := assistant_broker_tool('theme_set')
	assert found3 && t.action == 'appearance.modify' && t.mutating
}

fn test_broker_argv_validation() {
	argv := assistant_broker_argv('theme_set', 'pampa') or { panic(err) }
	assert argv == ['horneroctl', 'appearance', 'theme', 'set', 'pampa', '--yes']
	if _ := assistant_broker_argv('theme_set', 'vapor-dreams') {
		assert false, 'non-official theme must be rejected'
	}
	if _ := assistant_broker_argv('theme_set', 'pampa; rm -rf /') {
		assert false, 'injection-shaped theme must be rejected'
	}
	if _ := assistant_broker_argv('window_focus', 'window:1;evil') {
		assert false, 'non-hex window address must be rejected'
	}
	focus := assistant_broker_argv('window_focus', '0x1a2b') or { panic(err) }
	assert focus[focus.len - 1] == 'address:0x1a2b'
	if _ := assistant_broker_argv('notify', '') {
		assert false, 'empty notify must be rejected'
	}
}

fn test_broker_policy_gate_denies_without_preset() {
	// Default (no policy file) is the read-only preset: mutations denied,
	// and dry-run proves nothing executed even when policy would allow.
	denied := assistant_broker_exec_report('theme_set', 'pampa', 'agent', false, false)
	assert !denied.ok
	assert denied.data['decision'] == 'deny' || denied.data['decision'] == 'require_approval'
	unknown := assistant_broker_exec_report('rm_rf', '/', 'agent', false, false)
	assert !unknown.ok
	// Ask mode can never mutate, regardless of approval flag at this layer.
	ask := assistant_broker_exec_report('theme_set', 'pampa', 'ask', true, false)
	assert !ask.ok
}
