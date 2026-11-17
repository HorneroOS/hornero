module hornero_core

import os

// isolate_broker_env keeps broker tests (which append to the audit log
// and read the policy) away from the developer's real ~/.config/hornero.
fn isolate_broker_env() {
	root := os.join_path(os.temp_dir(), 'hornero-broker-test-${os.getpid()}')
	os.mkdir_all(os.join_path(root, 'config')) or {}
	os.setenv('HOME', root, true)
	os.setenv('XDG_CONFIG_HOME', os.join_path(root, 'config'), true)
	os.setenv('XDG_STATE_HOME', os.join_path(root, 'state'), true)
	os.setenv('XDG_DATA_HOME', os.join_path(root, 'data'), true)
	os.setenv('HORNERO_ASSISTANT_LOG_FILE', os.join_path(root, 'assistant.log'), true)
}

fn test_broker_catalogue_is_typed_and_closed() {
	_, found := assistant_broker_tool('shell')
	assert !found
	_, found2 := assistant_broker_tool('run_command')
	assert !found2
	t, found3 := assistant_broker_tool('theme_set')
	assert found3 && t.action == 'appearance.modify' && t.mutating
}

fn test_broker_argv_validation() {
	argv := assistant_broker_argv('theme_set', 'hornero-signal-day') or { panic(err) }
	assert argv == ['horneroctl', 'appearance', 'theme', 'set', 'hornero-signal-day', '--yes']
	if _ := assistant_broker_argv('theme_set', 'vapor-dreams') {
		assert false, 'non-official theme must be rejected'
	}
	if _ := assistant_broker_argv('theme_set', 'hornero-signal-day; rm -rf /') {
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
	isolate_broker_env()
	// Default (no policy file) is the read-only preset: mutations denied,
	// and dry-run proves nothing executed even when policy would allow.
	denied := assistant_broker_exec_report('theme_set', 'hornero-signal-day', 'agent', false, false)
	assert !denied.ok
	assert denied.data['decision'] == 'deny' || denied.data['decision'] == 'require_approval'
	unknown := assistant_broker_exec_report('rm_rf', '/', 'agent', false, false)
	assert !unknown.ok
	// Ask mode can never mutate, regardless of approval flag at this layer.
	ask := assistant_broker_exec_report('theme_set', 'hornero-signal-day', 'ask', true, false)
	assert !ask.ok
}

fn test_broker_screenshot_is_policy_gated() {
	isolate_broker_env()
	t, found := assistant_broker_tool('screenshot')
	assert found && t.action == 'desktop.screenshot'
	// Read-only preset denies screenshots outright: nothing is captured.
	denied := assistant_broker_exec_report('screenshot', '', 'agent', false, false)
	assert !denied.ok
}
