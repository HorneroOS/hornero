module hornero_core

import os
import time

const agent_config_test_root = '/tmp/hx-agent-config-test'

struct AgentConfigTestEnv {
	root  string
	cfg   string
	state string
	saved map[string]string
}

// agent_config_test_env isolates every path the projection code touches via
// env overrides only (no HOME mutation, per cli/AGENTS.md).
fn agent_config_test_env(tag string) AgentConfigTestEnv {
	root := '${agent_config_test_root}/${tag}-${os.getpid()}-${time.now().unix_nano()}'
	os.rmdir_all(root) or {}
	os.mkdir_all(root) or { assert false }
	keys := ['HORNERO_AGENT_CONFIG_FILE', 'HORNERO_AGENT_CONFIG_STATE_DIR', 'CODEX_HOME',
		'XDG_CONFIG_HOME', 'XDG_STATE_HOME']
	mut saved := map[string]string{}
	for key in keys {
		saved[key] = os.getenv(key)
	}
	cfg := os.join_path(root, 'agent-config.json')
	state := os.join_path(root, 'state')
	os.setenv('HORNERO_AGENT_CONFIG_FILE', cfg, true)
	os.setenv('HORNERO_AGENT_CONFIG_STATE_DIR', state, true)
	os.setenv('CODEX_HOME', os.join_path(root, 'codex'), true)
	os.setenv('XDG_CONFIG_HOME', os.join_path(root, 'xdg-config'), true)
	os.setenv('XDG_STATE_HOME', os.join_path(root, 'xdg-state'), true)
	return AgentConfigTestEnv{
		root:  root
		cfg:   cfg
		state: state
		saved: saved
	}
}

fn agent_config_test_cleanup(env AgentConfigTestEnv) {
	for key, value in env.saved {
		if value.len == 0 {
			os.unsetenv(key)
		} else {
			os.setenv(key, value, true)
		}
	}
	os.rmdir_all(env.root) or {}
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

fn test_agent_config_rejects_unsafe_ids_and_skill_ids() {
	unsafe_ids := ['..', '.', '../escape', 'a/b', 'a b', 'a:b']
	for id in unsafe_ids {
		raw := '{"schemaVersion":1,"entries":[{"id":"${id}","kind":"skill","name":"X","targets":["codex"],"content":"x"}]}'
		if _ := parse_agent_config_registry(raw) {
			assert false, 'unsafe id accepted: ${id}'
		}
	}
	bad_skill := '{"schemaVersion":1,"entries":[{"id":"ok","kind":"skill","name":"X","targets":["codex"],"skillId":"../escape","content":"x"}]}'
	if _ := parse_agent_config_registry(bad_skill) {
		assert false, 'unsafe skillId accepted'
	}
	ok := parse_agent_config_registry('{"schemaVersion":1,"entries":[{"id":"a.b-c_1","kind":"skill","name":"X","targets":["codex"],"content":"x"}]}') or {
		assert false, err.msg()
		return
	}
	assert ok.entries[0].skill_id == 'a.b-c_1'
	// Defense in depth: a joined skill path must stay under its skills base.
	base := '/tmp/hx-agent-config-base'
	assert agent_config_path_within(base, '${base}/one/SKILL.md')
	assert !agent_config_path_within(base, '${base}/../escape/SKILL.md')
	assert !agent_config_path_within(base, '${base}/one/../../escape/SKILL.md')
}

fn test_agent_config_rejects_malformed_targets() {
	cases := [
		'{"schemaVersion":1,"entries":[{"id":"a","kind":"instruction","name":"A","targets":"codex","content":"hi"}]}',
		'{"schemaVersion":1,"entries":[{"id":"a","kind":"instruction","name":"A","targets":null,"content":"hi"}]}',
		'{"schemaVersion":1,"entries":[{"id":"a","kind":"instruction","name":"A","targets":[1],"content":"hi"}]}',
		'{"schemaVersion":1,"entries":[{"id":"a","kind":"instruction","name":"A","targets":["codex",2],"content":"hi"}]}',
		'{"schemaVersion":1,"entries":[{"id":"a","kind":"instruction","name":"A","targets":[""],"content":"hi"}]}',
	]
	for raw in cases {
		if _ := parse_agent_config_registry(raw) {
			assert false, 'malformed targets accepted: ${raw}'
		}
	}
}

fn test_agent_config_status_empty_registry() {
	env := agent_config_test_env('empty')
	defer {
		agent_config_test_cleanup(env)
	}
	res := agent_config_status_result('')
	assert res.ok
	assert (res.data['entries'] or { '' }) == '0'
}

fn test_agent_config_status_reports_projection_scope() {
	env := agent_config_test_env('scope')
	defer {
		agent_config_test_cleanup(env)
	}
	os.write_file(env.cfg, '{"schemaVersion":1,"entries":[{"id":"s1","kind":"skill","name":"S","targets":["codex"],"skillId":"s1","content":"body"}]}') or {
		assert false
	}
	res := agent_config_status_result('codex')
	assert res.ok
	assert res.message.contains('companion fragments')
	assert res.message.contains('do not load automatically')
}

fn test_agent_config_render_and_detect_duplicates() {
	env := agent_config_test_env('render')
	defer {
		agent_config_test_cleanup(env)
	}
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
	env := agent_config_test_env('unsupported')
	defer {
		agent_config_test_cleanup(env)
	}
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

fn test_agent_config_check_fails_closed_on_bad_registry() {
	env := agent_config_test_env('check')
	defer {
		agent_config_test_cleanup(env)
	}
	os.write_file(env.cfg, 'not json') or { assert false }
	bad := agent_config_check_result('')
	assert !bad.ok
	assert bad.message.contains('Cannot load agent config registry')

	dup := '{"schemaVersion":1,"entries":[{"id":"a","kind":"instruction","name":"A","targets":["codex"],"content":"hi"},{"id":"a","kind":"instruction","name":"B","targets":["codex"],"content":"hi"}]}'
	os.write_file(env.cfg, dup) or { assert false }
	duplicate := agent_config_check_result('')
	assert !duplicate.ok
	assert duplicate.message.contains('duplicate entry id')

	os.write_file(env.cfg, '{"schemaVersion":1,"entries":[{"id":"a","kind":"instruction","name":"A","targets":"codex","content":"hi"}]}') or {
		assert false
	}
	malformed := agent_config_check_result('')
	assert !malformed.ok

	// Parse errors must not echo registry content (secret hygiene, P3-12).
	os.write_file(env.cfg, '{broken SECRET_TOKEN_12345') or { assert false }
	leaky := agent_config_check_result('')
	assert !leaky.ok
	assert !leaky.message.contains('SECRET_TOKEN_12345')
}

fn test_agent_config_apply_dry_run_and_idempotent_with_receipts() {
	env := agent_config_test_env('apply')
	defer {
		agent_config_test_cleanup(env)
	}
	codex_home := os.getenv('CODEX_HOME')
	reg_json := '{"schemaVersion":1,"entries":[{"id":"inst1","kind":"instruction","name":"Base","targets":["codex"],"content":"hello world"},{"id":"sk1","kind":"skill","name":"My Skill","targets":["codex"],"skillId":"my-skill","content":"Do the thing."}]}'
	os.write_file(env.cfg, reg_json) or { assert false }
	// apply requires consent
	denied := agent_config_apply_result('codex', false, false)
	assert !denied.ok
	assert denied.message.contains('--yes') || denied.message.contains('--dry-run')
	dry := agent_config_apply_result('codex', true, false)
	assert dry.ok
	assert (dry.data['dryRun'] or { '' }) == 'true'
	instr_path := os.join_path(codex_home, 'AGENTS.hornero.md')
	assert !os.exists(instr_path)
	applied := agent_config_apply_result('codex', false, true)
	assert applied.ok
	assert os.is_file(instr_path)
	content := os.read_file(instr_path) or { '' }
	assert content.contains('hello world')
	skill_path := os.join_path(codex_home, 'skills', 'my-skill', 'SKILL.md')
	assert os.is_file(skill_path)
	assert os.is_dir(os.join_path(env.state, 'receipts'))
	// idempotent re-apply
	again := agent_config_apply_result('codex', false, true)
	assert again.ok
	assert (again.data['changed'] or { '' }) == '0' || again.message.contains('unchanged')
}

fn test_agent_config_backup_unmanaged_and_duplicate_mcp_detection() {
	env := agent_config_test_env('backupdup')
	defer {
		agent_config_test_cleanup(env)
	}
	codex_home := os.getenv('CODEX_HOME')
	instr_path := os.join_path(codex_home, 'AGENTS.hornero.md')
	os.mkdir_all(os.dir(instr_path)) or { assert false }
	os.write_file(instr_path, 'user content') or { assert false }
	reg_json := '{"schemaVersion":1,"entries":[{"id":"inst1","kind":"instruction","name":"Base","targets":["codex"],"content":"managed"}]}'
	os.write_file(env.cfg, reg_json) or { assert false }
	res := agent_config_apply_result('codex', false, true)
	assert res.ok
	assert (os.read_file(instr_path) or { '' }).contains('managed')
	// backup created for unmanaged pre-existing file
	assert os.is_dir(os.join_path(env.state, 'backups'))
	backups := os.ls(os.join_path(env.state, 'backups')) or { []string{} }
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

fn test_agent_config_backup_collision_preserves_both() {
	env := agent_config_test_env('backup-collision')
	defer {
		agent_config_test_cleanup(env)
	}
	codex_home := os.getenv('CODEX_HOME')
	one := os.join_path(codex_home, 'skills', 'one')
	two := os.join_path(codex_home, 'skills', 'two')
	os.mkdir_all(one) or { assert false }
	os.mkdir_all(two) or { assert false }
	os.write_file(os.join_path(one, 'SKILL.md'), 'user-one') or { assert false }
	os.write_file(os.join_path(two, 'SKILL.md'), 'user-two') or { assert false }
	reg := '{"schemaVersion":1,"entries":[{"id":"s1","kind":"skill","name":"One","targets":["codex"],"skillId":"one","content":"managed-one"},{"id":"s2","kind":"skill","name":"Two","targets":["codex"],"skillId":"two","content":"managed-two"}]}'
	os.write_file(env.cfg, reg) or { assert false }
	res := agent_config_apply_result('codex', false, true)
	assert res.ok
	backup_dir := os.join_path(env.state, 'backups')
	backups := os.ls(backup_dir) or { []string{} }
	assert backups.len == 2
	mut contents := []string{}
	for b in backups {
		contents << (os.read_file(os.join_path(backup_dir, b)) or { '' })
	}
	assert 'user-one' in contents
	assert 'user-two' in contents
}

fn test_agent_config_mcp_toml_all_env_keys() {
	env := agent_config_test_env('mcp-env')
	defer {
		agent_config_test_cleanup(env)
	}
	reg := parse_agent_config_registry('{"schemaVersion":1,"entries":[{"id":"m1","kind":"mcp","name":"S","targets":["codex"],"content":"{\\"name\\":\\"srv\\",\\"command\\":\\"echo\\",\\"env\\":{\\"B_KEY\\":\\"2\\",\\"A_KEY\\":\\"1\\",\\"weird.key\\":\\"3\\"}}"}]}') or {
		assert false, err.msg()
		return
	}
	targets := agent_config_render_targets(reg, 'codex')
	mut rendered := ''
	for t in targets {
		if t.kind == 'mcp' {
			rendered = t.content
		}
	}
	assert rendered.count('[mcp_servers."srv".env]') == 1
	assert rendered.contains('A_KEY = "1"')
	assert rendered.contains('B_KEY = "2"')
	assert rendered.contains('"weird.key" = "3"')
}

fn test_agent_config_honors_codex_home_and_xdg() {
	env := agent_config_test_env('homes')
	defer {
		agent_config_test_cleanup(env)
	}
	codex_home := os.getenv('CODEX_HOME')
	xdg_config := os.getenv('XDG_CONFIG_HOME')
	reg_json := '{"schemaVersion":1,"entries":[{"id":"i1","kind":"instruction","name":"I","targets":["codex","opencode"],"content":"hi"},{"id":"s1","kind":"skill","name":"Codex Skill","targets":["codex"],"skillId":"codex-skill","content":"body"},{"id":"s2","kind":"skill","name":"OpenCode Skill","targets":["opencode"],"skillId":"opencode-skill","content":"body"},{"id":"m1","kind":"mcp","name":"M","targets":["codex","opencode"],"content":"{\\"name\\":\\"srv\\",\\"command\\":\\"echo\\"}"}]}'
	os.write_file(env.cfg, reg_json) or { assert false }
	reg := parse_agent_config_registry(reg_json) or {
		assert false, err.msg()
		return
	}
	for t in agent_config_render_targets(reg, 'codex') {
		assert t.path.starts_with(codex_home + '/')
	}
	for t in agent_config_render_targets(reg, 'opencode') {
		assert t.path.starts_with(xdg_config + '/opencode/')
	}
	res := agent_config_apply_result('', false, true)
	assert res.ok
	assert os.is_file(os.join_path(codex_home, 'AGENTS.hornero.md'))
	assert os.is_file(os.join_path(codex_home, 'mcp.hornero.toml'))
	assert os.is_file(os.join_path(codex_home, 'skills', 'codex-skill', 'SKILL.md'))
	assert os.is_file(os.join_path(xdg_config, 'opencode', 'HORNERO.md'))
	assert os.is_file(os.join_path(xdg_config, 'opencode', 'mcp.hornero.json'))
	assert os.is_file(os.join_path(xdg_config, 'opencode', 'skills', 'opencode-skill', 'SKILL.md'))
}

fn test_agent_config_apply_preflight_refuses_unsupported() {
	env := agent_config_test_env('preflight')
	defer {
		agent_config_test_cleanup(env)
	}
	codex_home := os.getenv('CODEX_HOME')
	reg := '{"schemaVersion":1,"entries":[{"id":"i1","kind":"instruction","name":"I","targets":["codex","muse"],"content":"hi"}]}'
	os.write_file(env.cfg, reg) or { assert false }
	res := agent_config_apply_result('', false, true)
	assert !res.ok
	assert res.message.contains('Refusing to apply before any write')
	assert res.message.contains('muse')
	assert !os.exists(os.join_path(codex_home, 'AGENTS.hornero.md'))
	// dry-run is allowed to preview the blockers without writing.
	dry := agent_config_apply_result('', true, false)
	assert dry.ok
	assert (dry.data['issues'] or { '' }).int() > 0
	assert !os.exists(os.join_path(codex_home, 'AGENTS.hornero.md'))
}
