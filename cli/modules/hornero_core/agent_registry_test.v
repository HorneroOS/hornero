module hornero_core

import os

const agent_test_root = '/tmp/hx-agent-test'

fn agent_set_file(tag string) string {
	dir := '${agent_test_root}/${tag}'
	if os.exists(dir) {
		os.rmdir_all(dir) or {}
	}
	os.mkdir_all(dir) or { assert false }
	path := '${dir}/agent-default.json'
	os.setenv('HORNERO_AGENT_DEFAULT_FILE', path, true)
	return path
}

fn test_agent_registry_has_five_truthful_specs() {
	registry := agent_registry()
	assert registry.len == 5
	assert agent_ids() == ['javi-hermes', 'codex', 'claude-code', 'muse', 'opencode']
	mut seen := map[string]bool{}
	for spec in registry {
		assert !seen[spec.id]
		seen[spec.id] = true
		assert spec.name.len > 0
		assert spec.exec.len > 0
		assert spec.discovery.len > 0
		assert spec.install_source.len > 0
		assert spec.arch.len > 0
		assert spec.config_path.starts_with('~/')
		assert spec.instruction_path.len > 0
		assert spec.skills_path.len > 0
		assert spec.mcp_format.len > 0
		assert spec.acp.len > 0
		assert spec.session.len > 0
		assert spec.approval.len > 0
		assert spec.sandbox.len > 0
		assert spec.usage.len > 0
		assert spec.uninstall.len > 0
	}
	if _ := agent_by_id('nope') {
		assert false, 'unknown id must not resolve'
	}
}

fn test_agent_probe_missing_binary_is_not_installed() {
	spec := AgentSpec{
		id:          'fake'
		name:        'Fake'
		exec:        'hx-no-such-agent-binary-xyz'
		config_path: '~/hx-no-such-config-xyz'
	}
	st := agent_probe(spec)
	assert !st.installed
	assert st.resolved_path == ''
	assert !st.config_present
	assert st.auth_state == 'not-detectable'
}

fn test_agent_default_roundtrip_and_fail_closed() {
	path := agent_set_file('roundtrip')
	defer {
		os.unsetenv('HORNERO_AGENT_DEFAULT_FILE')
	}
	assert agent_default_id() == ''
	set := agent_default_set_result('codex', false, true)
	assert set.ok
	assert agent_default_id() == 'codex'
	loaded := parse_agent_default(os.read_file(path) or { '' }) or {
		assert false, err.msg()
		return
	}
	assert loaded == 'codex'
	os.write_file(path, '{"schemaVersion": 1, "default": "nope"}\n') or { assert false }
	assert agent_default_id() == ''
	if _ := parse_agent_default('{"schemaVersion": 1, "default": "nope"}') {
		assert false, 'unknown default id must fail closed'
	}
	if _ := parse_agent_default('not json') {
		assert false, 'malformed JSON must fail closed'
	}
}

fn test_agent_default_set_requires_consent_and_known_id() {
	agent_set_file('consent')
	defer {
		os.unsetenv('HORNERO_AGENT_DEFAULT_FILE')
	}
	assert !agent_default_set_result('codex', false, false).ok
	assert agent_default_id() == ''
	assert agent_default_set_result('codex', true, false).ok
	assert agent_default_id() == '', 'dry run must not write'
	assert !agent_default_set_result('nope', false, true).ok
}

fn test_agent_launch_is_proposal_only() {
	res := agent_launch_result('codex')
	assert res.ok
	assert res.data['dry_run'] == 'true'
	assert res.data['executed'] == 'false'
	assert res.data['proposal'].contains('codex')
	assert !agent_launch_result('nope').ok
	assert agent_status_result('codex').ok
	assert !agent_status_result('nope').ok
}
