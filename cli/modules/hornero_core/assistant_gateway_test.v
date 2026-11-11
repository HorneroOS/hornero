module hornero_core

import os

fn test_assistant_gateway_unit_content_is_user_level() {
	content := assistant_gateway_unit_content('/home/user/.local/bin/hermes')
	assert content.contains('ExecStart=/home/user/.local/bin/hermes gateway run')
	assert content.contains('Type=simple')
	assert content.contains('Restart=on-failure')
	assert content.contains('[Install]')
	assert !content.contains('User=root')
	assert !content.contains('/usr/bin/hermes')
}

fn test_assistant_gateway_unit_content_is_hardened() {
	content := assistant_gateway_unit_content('/home/user/.local/bin/hermes')
	assert content.contains('NoNewPrivileges=true')
	assert content.contains('PrivateTmp=true')
	assert content.contains('CapabilityBoundingSet=')
	assert content.contains('RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6')
	// Unsandboxed fallback is labelled honestly, never as sandboxed.
	assert content.contains('systemd-only (not sandboxed)')
}

fn test_assistant_gateway_bwrap_unit_omits_namespace_breaking_directives() {
	content := assistant_gateway_unit_content_for('/opt/hermes', '/usr/bin/bwrap',
		'/data/ws')
	// These two prevent bubblewrap from creating its namespace under
	// systemd (host-verified); the sandboxed unit must not carry them.
	assert !content.contains('RestrictSUIDSGID')
	assert !content.contains('CapabilityBoundingSet')
	assert content.contains('NoNewPrivileges=true')
	assert content.contains('isolation: bubblewrap')
	plain := assistant_gateway_unit_content('/opt/hermes')
	assert plain.contains('RestrictSUIDSGID=true')
	assert plain.contains('CapabilityBoundingSet=')
}

fn test_assistant_gateway_bwrap_argv_masks_home() {
	argv := assistant_gateway_bwrap_argv('/opt/hermes', '/home/user', '/data/ws')
	joined := argv.join(' ')
	assert joined.contains('--tmpfs /home/user')
	assert joined.contains('--bind /home/user/.hermes /home/user/.hermes')
	assert joined.contains('--bind /data/ws /data/ws')
	assert joined.contains('--share-net')
	assert joined.ends_with('/opt/hermes gateway run')
	// No compositor / session-bus socket is ever bound, and the session
	// runtime dir (Wayland + D-Bus sockets) is masked when present.
	assert !joined.contains('wayland')
	runtime_dir := os.getenv('XDG_RUNTIME_DIR')
	if runtime_dir.len > 0 {
		assert joined.contains('--tmpfs ${runtime_dir}')
	}
}

fn test_assistant_gateway_unit_file_lives_under_user_config() {
	path := assistant_gateway_unit_file()
	assert path.ends_with('systemd/user/hornero-hermes.service')
	assert assistant_gateway_unit_name == 'hornero-hermes.service'
}

fn test_assistant_gateway_unit_isolation_reads_execstart() {
	legacy := '[Service]\nExecStart=/home/user/.local/bin/hermes gateway run\n'
	assert assistant_gateway_unit_isolation(legacy) == 'systemd-only (not sandboxed)'
	sandboxed := assistant_gateway_unit_content_for('/opt/hermes', '/usr/bin/bwrap',
		'/data/ws')
	assert assistant_gateway_unit_isolation(sandboxed) == 'bubblewrap'
	spoof := '[Service]\nExecStart=/home/user/bwrap-notes/hermes gateway run\n'
	assert assistant_gateway_unit_isolation(spoof) == 'systemd-only (not sandboxed)'
	assert assistant_gateway_unit_isolation('') == 'systemd-only (not sandboxed)'
	assert assistant_gateway_unit_isolation('[Service]\n') == 'systemd-only (not sandboxed)'
}

fn test_assistant_gateway_classify_distinguishes_states() {
	assert assistant_gateway_classify(false, true, true, true) == 'disabled'
	assert assistant_gateway_classify(true, false, false, false) == 'not-installed'
	assert assistant_gateway_classify(true, true, false, false) == 'installed-not-running'
	assert assistant_gateway_classify(true, true, true, false) == 'running-incompatible'
	assert assistant_gateway_classify(true, true, true, true) == 'running-compatible'
}
