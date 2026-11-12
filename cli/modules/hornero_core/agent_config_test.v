module hornero_core

import os
import time

const agent_config_test_root = '/tmp/hx-agent-config-test'

fn agent_config_test_env(tag string) (string, string) {
	dir := '${agent_config_test_root}/${tag}-${os.getpid()}-${time.now().unix_nano()}'
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { assert false }
	cfg := os.join_path(dir, 'agent-config.json')
	state := os.join_path(dir, 'state')
	os.setenv('HORNERO_AGENT_CONFIG_FILE', cfg, true)
	os.setenv('HORNERO_AGENT_CONFIG_STATE_DIR', state, true)
	return cfg, state
}

fn agent_config_test_cleanup() {
	os.unsetenv('HORNERO_AGENT_CONFIG_FILE')
	os.unsetenv('HORNERO_AGENT_CONFIG_STATE_DIR')
}

fn test_agent_config_parse_rejects_duplicates_and_bad_kinds() {
	if _ := parse_agent_config_registry('{"schemaVersion":1,"entries":[{"id":"a","kind":"instruction","name":"A","targets":[],"content":"hi"},{"id":"a","kind":"instruction","name":"B","targets":[],"content":"hi"}]}') {
		assert false, 'duplicate id must fail'
	}
	if _ := parse_agent_config_registry('{"schemaVersion":1,"entries":[{"id":"a","kind":"bogus","name":"A","targets":[],"content":"hi"}]}') {
		assert false, 'unknown kind must fail'
	}
	if _ := parse_agent_config_registry('{"schemaVersion":1,"entries":[{"id":"a","kind":"mcp","name":"A","targets":[],"content":"not json"}]}') {
		assert false, 'invalid MCP content must fail'
	}
	reg := parse_agent_config_registry('{"schemaVersion":1,"entries":[{"id":"a","kind":"mcp","name":"A","targets":["codex"],"content":"{\\"name\\":\\"srv\\",\\"command\\":\\"x\\"}"}]}') or {
		assert false, err.msg()
		return
	}
	assert reg.entries.len == 1
	assert reg.entries[0].kind == 'mcp'
}

fn test_agent_config_status_empty_registry() {
	cfg, _ := agent_config_test_env('empty')
	defer {
		agent_config_test_cleanup()
		os.rmdir_all(os.dir(cfg)) or {}
	}
	res := agent_config_status_result('')
	assert res.ok
	assert (res.data['entries'] or { '' }) == '0'
}

fn test_agent_config_render_and_detect_duplicates() {
	reg := parse_agent_config_registry('{"schemaVersion":1,"entries":[{"id":"i1","kind":"instruction","name":"Base","targets":["codex"],"content":"hello"},{"id":"i2","kind":"instruction","name":"Extra","targets":["codex"],"content":"world"},{"id":"m1","kind":"mcp","name":"S1","targets":["codex"],"content":"{\\"name\\":\\"srv\\",\\"command\\":\\"echo\\"}"}]}') or {
		assert false, err.msg()
		return
	}
	targets := agent_config_render_targets(reg, 'codex')
	assert targets.len >= 2
	mut saw_instr := false
	mut saw_mcp := false
	for t in targets {
		if t.kind == 'instruction' {
			saw_instr = true
			assert t.format == 'markdown'
			assert t.content.contains('hello')
			assert t.content.contains('world')
			assert t.path.contains('AGENTS.hornero.md')
		}
		if t.kind == 'mcp' {
			saw_mcp = true
			assert t.format == 'toml-mcp'
			assert t.content.contains('mcp_servers')
			assert t.content.contains('srv')
		}
	}
	assert saw_instr && saw_mcp
	assert agent_config_duplicate_paths(targets).len == 0
	// force a duplicate by crafting same path targets
	dup_targets := [
		AgentRenderTarget{ agent_id: 'a', entry_id: '1', kind: 'instruction', path: '/tmp/x', format: 'markdown', content: 'a' },
		AgentRenderTarget{ agent_id: 'b', entry_id: '2', kind: 'instruction', path: '/tmp/x', format: 'markdown', content: 'b' },
	]
	dups := agent_config_duplicate_paths(dup_targets)
	assert dups.len == 1
	assert dups[0].contains('/tmp/x')
}

fn test_agent_config_unsupported_format_detected() {
	reg := parse_agent_config_registry('{"schemaVersion":1,"entries":[{"id":"i1","kind":"instruction","name":"Muse","targets":["muse"],"content":"hi"}]}') or {
		assert false, err.msg()
		return
	}
	targets := agent_config_render_targets(reg, 'muse')
	assert targets.len == 1
	assert targets[0].format == 'unsupported'
	state, _ := status_state_for_target(targets[0])
	assert state == 'unsupported'
}

fn test_agent_config_apply_dry_run_and_idempotent_with_receipts() {
	cfg, state := agent_config_test_env('apply')
	target_home := os.join_path(os.dir(cfg), 'home')
	os.mkdir_all(os.join_path(target_home, '.codex')) or { assert false }
	// redirect home-dependent rendering by using an agent we can control? easier: write registry targeting codex
	// and temporarily set HOME so render targets land under test dir.
	saved_home := os.getenv('HOME')
	os.setenv('HOME', target_home, true)
	defer {
		if saved_home.len == 0 { os.unsetenv('HOME') } else { os.setenv('HOME', saved_home, true) }
		agent_config_test_cleanup()
		os.rmdir_all(os.dir(cfg)) or {}
	}
	reg_json := '{"schemaVersion":1,"entries":[{"id":"inst1","kind":"instruction","name":"Base","targets":["codex"],"content":"hello world"},{"id":"sk1","kind":"skill","name":"My Skill","targets":["codex"],"skillId":"my-skill","content":"Do the thing."}]}'
	os.write_file(cfg, reg_json) or { assert false }
	// apply requires consent
	denied := agent_config_apply_result('codex', false, false)
	assert !denied.ok
	assert denied.message.contains('--yes') || denied.message.contains('--dry-run')
	dry := agent_config_apply_result('codex', true, false)
	assert dry.ok
	assert (dry.data['dryRun'] or { '' }) == 'true'
	instr_path := os.join_path(target_home, '.codex', 'AGENTS.hornero.md')
	assert !os.exists(instr_path)
	applied := agent_config_apply_result('codex', false, true)
	assert applied.ok
	assert os.is_file(instr_path)
	content := os.read_file(instr_path) or { '' }
	assert content.contains('hello world')
	skill_path := os.join_path(target_home, '.codex', 'skills', 'my-skill', 'SKILL.md')
	assert os.is_file(skill_path)
	assert os.is_dir(os.join_path(state, 'receipts'))
	// idempotent re-apply
	again := agent_config_apply_result('codex', false, true)
	assert again.ok
	assert (again.data['changed'] or { '' }) == '0' || again.message.contains('unchanged')
}

fn test_agent_config_backup_unmanaged_and_duplicate_mcp_detection() {
	cfg, state := agent_config_test_env('backupdup')
	target_home := os.join_path(os.dir(cfg), 'home')
	os.mkdir_all(os.join_path(target_home, '.codex')) or { assert false }
	saved_home := os.getenv('HOME')
	os.setenv('HOME', target_home, true)
	defer {
		if saved_home.len == 0 { os.unsetenv('HOME') } else { os.setenv('HOME', saved_home, true) }
		agent_config_test_cleanup()
		os.rmdir_all(os.dir(cfg)) or {}
	}
	instr_path := os.join_path(target_home, '.codex', 'AGENTS.hornero.md')
	os.write_file(instr_path, 'user content') or { assert false }
	reg_json := '{"schemaVersion":1,"entries":[{"id":"inst1","kind":"instruction","name":"Base","targets":["codex"],"content":"managed"}]}'
	os.write_file(cfg, reg_json) or { assert false }
	res := agent_config_apply_result('codex', false, true)
	assert res.ok
	assert (os.read_file(instr_path) or { '' }).contains('managed')
	// backup created for unmanaged pre-existing file
	assert os.is_dir(os.join_path(state, 'backups'))
	backups := os.ls(os.join_path(state, 'backups')) or { []string{} }
	assert backups.len >= 1
	// duplicate MCP server names within render
	bad := parse_agent_config_registry('{"schemaVersion":1,"entries":[{"id":"m1","kind":"mcp","name":"A","targets":["codex"],"content":"{\\"name\\":\\"srv\\",\\"command\\":\\"a\\"}"},{"id":"m2","kind":"mcp","name":"B","targets":["codex"],"content":"{\\"name\\":\\"srv\\",\\"command\\":\\"b\\"}"}]}') or {
		assert false, err.msg()
		return
	}
	targets := agent_config_render_targets(bad, 'codex')
	mut saw_err := false
	for t in targets {
		if t.kind == 'mcp' && t.reason.contains('duplicate MCP server name') {
			saw_err = true
		}
	}
	assert saw_err
}
