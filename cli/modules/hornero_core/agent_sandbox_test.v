module hornero_core

import os
import time
import x.json2

fn find_arg_pair(argv []string, flag string, first string, second string) int {
	for i := 0; i + 2 < argv.len; i++ {
		if argv[i] == flag && argv[i + 1] == first && argv[i + 2] == second {
			return i
		}
	}
	return -1
}

fn find_arg_single(argv []string, flag string, val string) int {
	for i := 0; i + 1 < argv.len; i++ {
		if argv[i] == flag && argv[i + 1] == val {
			return i
		}
	}
	return -1
}

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

	// Read-only system mounts and rw workspace
	assert find_arg_pair(argv, '--ro-bind', '/usr', '/usr') >= 0
	assert find_arg_pair(argv, '--ro-bind-try', '/lib', '/lib') >= 0
	assert find_arg_pair(argv, '--ro-bind', '/etc', '/etc') >= 0
	home_tmpfs_idx := find_arg_single(argv, '--tmpfs', '/home/tester')
	ws_bind_idx := find_arg_pair(argv, '--bind', workspace, workspace)
	assert home_tmpfs_idx >= 0
	assert ws_bind_idx > home_tmpfs_idx
	assert find_arg_single(argv, '--chdir', workspace) > ws_bind_idx

	// Credential and browser directories explicitly masked with tmpfs
	for rel in ['.ssh', '.gnupg', '.aws', '.config/gh', '.mozilla', '.config/google-chrome',
		'.config/chromium', '.config/BraveSoftware'] {
		target := '/home/tester/${rel}'
		assert find_arg_single(argv, '--tmpfs', target) > ws_bind_idx, 'expected ${target} to be masked with --tmpfs after workspace bind'
	}

	// Command and extra args after '--'
	sep_idx := argv.index('--')
	assert sep_idx > 0
	assert argv[sep_idx + 1] == 'codex'
	assert argv[sep_idx + 2] == 'exec'
	assert argv[sep_idx + 3] == '--model'
	assert argv[sep_idx + 4] == 'o3'
}

fn test_build_agent_sandbox_argv_quotes_and_special_chars() {
	spec := AgentSpec{
		id:   'claude-code'
		name: 'Claude Code'
		exec: 'claude'
	}
	workspace := '/tmp/My "Quoted" \'Agent\' Workspace'
	argv := build_agent_sandbox_argv(spec, workspace, AgentSandboxOptions{
		home_dir:   '/home/tester'
		extra_args: ['-p', 'fix "$(whoami)" && echo hi']
	}) or { panic(err) }

	// Paths and prompts with quotes/metacharacters remain literal argv elements.
	assert find_arg_pair(argv, '--bind', workspace, workspace) >= 0
	assert find_arg_single(argv, '--chdir', workspace) >= 0
	sep_idx := argv.index('--')
	assert argv[sep_idx + 1] == 'claude'
	assert argv[sep_idx + 2] == '-p'
	assert argv[sep_idx + 3] == 'fix "$(whoami)" && echo hi'
}

fn test_build_agent_sandbox_argv_rejects_credential_binds_and_traversal() {
	spec := AgentSpec{
		id:   'claude-code'
		name: 'Claude Code'
		exec: 'claude'
	}
	for bad in ['/home/tester/.ssh', '/home/tester/.gnupg/private-keys-v1.d', '/home/tester/.aws',
		'/home/tester/.config/gh', '/home/tester/work/../.ssh', '/home/tester/.mozilla',
		'/home/tester/.config/google-chrome', '/home/tester', '/home', '/'] {
		if _ := build_agent_sandbox_argv(spec, bad, AgentSandboxOptions{
			home_dir: '/home/tester'
		})
		{
			assert false, 'expected error when workspace is ${bad}'
		}
	}
	for bad in ['/home/tester/.ssh', '/home/tester/.gnupg/private-keys-v1.d', '/home/tester/.aws',
		'/home/tester/.config/gh', '/home/tester/work/../.gnupg'] {
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

fn test_build_agent_sandbox_argv_binds_present_agent_config_dir_only() {
	root := '/tmp/hx-agent-sandbox-cfg-${os.getpid()}-${time.now().unix_nano()}'
	home := os.join_path(root, 'home')
	ws := os.join_path(root, 'ws')
	codex_dir := os.join_path(home, '.codex')
	claude_dir := os.join_path(home, '.claude')
	os.mkdir_all(ws) or { assert false }
	os.mkdir_all(codex_dir) or { assert false }
	// Intentionally leave claude_dir absent.
	saved_codex_home := os.getenv('CODEX_HOME')
	os.unsetenv('CODEX_HOME')
	defer {
		if saved_codex_home.len > 0 {
			os.setenv('CODEX_HOME', saved_codex_home, true)
		}
		os.rmdir_all(root) or {}
	}

	codex_spec := agent_by_id('codex') or {
		assert false
		return
	}
	codex_argv := build_agent_sandbox_argv(codex_spec, ws, AgentSandboxOptions{
		home_dir: home
	}) or { panic(err) }
	assert find_arg_pair(codex_argv, '--bind', codex_dir, codex_dir) >= 0

	claude_spec := agent_by_id('claude-code') or {
		assert false
		return
	}
	claude_argv := build_agent_sandbox_argv(claude_spec, ws, AgentSandboxOptions{
		home_dir: home
	}) or { panic(err) }
	assert find_arg_pair(claude_argv, '--bind', claude_dir, claude_dir) < 0
}

fn test_build_agent_sandbox_argv_allow_git_auth_keeps_gnupg_and_aws_blocked() {
	root := '/tmp/hx-agent-sandbox-git-${os.getpid()}-${time.now().unix_nano()}'
	home := os.join_path(root, 'home')
	ws := os.join_path(root, 'ws')
	ssh_dir := os.join_path(home, '.ssh')
	gh_dir := os.join_path(home, '.config', 'gh')
	gnupg_dir := os.join_path(home, '.gnupg')
	os.mkdir_all(ws) or { assert false }
	os.mkdir_all(ssh_dir) or { assert false }
	os.mkdir_all(gh_dir) or { assert false }
	os.mkdir_all(gnupg_dir) or { assert false }
	saved_sock := os.getenv('SSH_AUTH_SOCK')
	os.unsetenv('SSH_AUTH_SOCK')
	defer {
		if saved_sock.len > 0 {
			os.setenv('SSH_AUTH_SOCK', saved_sock, true)
		}
		os.rmdir_all(root) or {}
	}

	spec := agent_by_id('codex') or {
		assert false
		return
	}
	argv := build_agent_sandbox_argv(spec, ws, AgentSandboxOptions{
		home_dir:       home
		allow_git_auth: true
	}) or { panic(err) }

	assert find_arg_pair(argv, '--ro-bind', ssh_dir, ssh_dir) >= 0
	assert find_arg_pair(argv, '--ro-bind', gh_dir, gh_dir) >= 0
	assert find_arg_single(argv, '--tmpfs', ssh_dir) < 0
	assert find_arg_single(argv, '--tmpfs', gh_dir) < 0
	// Non-git secrets remain strictly masked and rejected.
	assert find_arg_single(argv, '--tmpfs', '${home}/.gnupg') >= 0
	assert find_arg_single(argv, '--tmpfs', '${home}/.aws') >= 0
	if _ := build_agent_sandbox_argv(spec, ws, AgentSandboxOptions{
		home_dir:       home
		allow_git_auth: true
		extra_ro_binds: [gnupg_dir]
	})
	{
		assert false, 'expected .gnupg to remain blocked even with allow_git_auth'
	}
}

fn test_agent_run_result_dry_run_and_validation() {
	// Unknown agent and missing --sandbox must fail closed.
	assert !agent_run_result(AgentRunOptions{
		id:      'nope'
		sandbox: true
		dry_run: true
	}).ok
	assert !agent_run_result(AgentRunOptions{
		id:      'codex'
		sandbox: false
		dry_run: true
	}).ok

	ws := '/tmp/hx workspace "quoted"'
	res := agent_run_result(AgentRunOptions{
		id:             'codex'
		sandbox:        true
		workspace:      ws
		no_net:         true
		allow_git_auth: false
		dry_run:        true
		extra_args:     ['exec', 'say "hello world"']
	})
	assert res.ok
	assert res.data['dry_run'] == 'true'
	assert res.data['executed'] == 'false'
	assert res.data['sandbox'] == 'true'
	assert res.data['no_net'] == 'true'
	assert res.data['allow_git_auth'] == 'false'
	assert res.data['workspace'] == ws

	decoded := json2.decode[[]string](res.data['argv_json']) or {
		assert false, 'argv_json must decode as []string: ${err.msg()}'
		return
	}
	assert '--unshare-net' in decoded
	assert find_arg_pair(decoded, '--bind', ws, ws) >= 0
	sep_idx := decoded.index('--')
	assert sep_idx > 0
	assert decoded[sep_idx + 2] == 'exec'
	assert decoded[sep_idx + 3] == 'say "hello world"'

	// Non-dry-run with a nonexistent workspace must fail without executing.
	missing := agent_run_result(AgentRunOptions{
		id:        'codex'
		sandbox:   true
		workspace: '/tmp/hx-does-not-exist-workspace-${os.getpid()}'
		dry_run:   false
	})
	assert !missing.ok
}
