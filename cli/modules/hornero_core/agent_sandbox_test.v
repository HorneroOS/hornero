module hornero_core

fn test_build_agent_sandbox_argv_basic_and_spaces() {
	spec := AgentSpec{
		id:   'codex'
		name: 'OpenAI Codex'
		exec: 'codex'
	}
	workspace := '/home/tester/My Projects/hornero app'
	argv := build_agent_sandbox_argv(spec, workspace, AgentSandboxOptions{
		home_dir:   '/home/tester'
		no_net:     true
		extra_args: ['exec', '--model', 'o3']
	}) or { panic(err) }

	assert argv[0] == 'bwrap'
	assert '--unshare-net' in argv

	// Read-only system mounts
	mut has_usr_ro := false
	mut has_lib_ro := false
	mut has_etc_ro := false
	mut has_ws_rw := false
	for i := 0; i < argv.len; i++ {
		if i + 2 < argv.len && argv[i] == '--ro-bind' && argv[i + 1] == '/usr'
			&& argv[i + 2] == '/usr' {
			has_usr_ro = true
		}
		if i + 2 < argv.len && argv[i] == '--ro-bind-try' && argv[i + 1] == '/lib'
			&& argv[i + 2] == '/lib' {
			has_lib_ro = true
		}
		if i + 2 < argv.len && argv[i] == '--ro-bind' && argv[i + 1] == '/etc'
			&& argv[i + 2] == '/etc' {
			has_etc_ro = true
		}
		if i + 2 < argv.len && argv[i] == '--bind' && argv[i + 1] == workspace
			&& argv[i + 2] == workspace {
			has_ws_rw = true
		}
	}
	assert has_usr_ro
	assert has_lib_ro
	assert has_etc_ro
	assert has_ws_rw

	// Credential directories explicitly masked with tmpfs
	for rel in ['.ssh', '.gnupg', '.aws', '.config/gh'] {
		target := '/home/tester/${rel}'
		mut masked := false
		for i := 0; i + 1 < argv.len; i++ {
			if argv[i] == '--tmpfs' && argv[i + 1] == target {
				masked = true
				break
			}
		}
		assert masked, 'expected ${target} to be masked with --tmpfs'
	}

	// Command and extra args after '--'
	sep_idx := argv.index('--')
	assert sep_idx > 0
	assert argv[sep_idx + 1] == 'codex'
	assert argv[sep_idx + 2] == 'exec'
	assert argv[sep_idx + 3] == '--model'
	assert argv[sep_idx + 4] == 'o3'
}

fn test_build_agent_sandbox_argv_rejects_credential_binds() {
	spec := AgentSpec{
		id:   'claude-code'
		name: 'Claude Code'
		exec: 'claude'
	}
	for bad in ['/home/tester/.ssh', '/home/tester/.gnupg/private-keys-v1.d', '/home/tester/.aws',
		'/home/tester/.config/gh'] {
		if _ := build_agent_sandbox_argv(spec, bad, AgentSandboxOptions{
			home_dir: '/home/tester'
		})
		{
			assert false, 'expected error when workspace is ${bad}'
		}
		if _ := build_agent_sandbox_argv(spec, '/home/tester/work', AgentSandboxOptions{
			home_dir:       '/home/tester'
			extra_ro_binds: [bad]
		})
		{
			assert false, 'expected error when extra_ro_binds contains ${bad}'
		}
		if _ := build_agent_sandbox_argv(spec, '/home/tester/work', AgentSandboxOptions{
			home_dir:       '/home/tester'
			extra_rw_binds: [bad]
		})
		{
			assert false, 'expected error when extra_rw_binds contains ${bad}'
		}
	}
}

fn test_build_agent_sandbox_argv_network_default_enabled() {
	spec := AgentSpec{
		id:   'codex'
		name: 'OpenAI Codex'
		exec: 'codex'
	}
	argv := build_agent_sandbox_argv(spec, '/tmp/ws', AgentSandboxOptions{
		home_dir: '/home/tester'
		no_net:   false
	}) or { panic(err) }
	assert '--unshare-net' !in argv
}
