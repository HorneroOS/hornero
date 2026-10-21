module hornero_core

fn test_assistant_gateway_unit_content_is_user_level() {
	content := assistant_gateway_unit_content('/home/user/.local/bin/hermes')
	assert content.contains('ExecStart=/home/user/.local/bin/hermes gateway run')
	assert content.contains('Type=simple')
	assert content.contains('Restart=on-failure')
	assert content.contains('[Install]')
	assert !content.contains('User=root')
	assert !content.contains('/usr/bin/hermes')
}

fn test_assistant_gateway_unit_file_lives_under_user_config() {
	path := assistant_gateway_unit_file()
	assert path.ends_with('systemd/user/hornero-hermes.service')
	assert assistant_gateway_unit_name == 'hornero-hermes.service'
}

fn test_assistant_gateway_classify_distinguishes_states() {
	assert assistant_gateway_classify(false, true, true, true) == 'disabled'
	assert assistant_gateway_classify(true, false, false, false) == 'not-installed'
	assert assistant_gateway_classify(true, true, false, false) == 'installed-not-running'
	assert assistant_gateway_classify(true, true, true, false) == 'running-incompatible'
	assert assistant_gateway_classify(true, true, true, true) == 'running-compatible'
}
