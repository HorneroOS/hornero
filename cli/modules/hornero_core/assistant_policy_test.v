module hornero_core

import os

fn pol_req(action string, resource string, workspace string) AssistantPolicyRequest {
	return AssistantPolicyRequest{
		principal:      'javi.main'
		action:         action
		resource:       resource
		workspace_root: workspace
		mode:           'agent'
		interactive:    true
		now:            1000
	}
}

fn test_policy_default_deny() {
	d := assistant_policy_decide([]AssistantPolicyRule{}, pol_req('filesystem.read',
		'/tmp/ws/a.txt', '/tmp/ws'))
	assert d.decision == 'deny'
}

fn test_policy_workspace_read_write_scope() {
	rules := assistant_policy_preset('workspace-agent')
	assert assistant_policy_decide(rules, pol_req('filesystem.read', '/tmp/ws/a.txt',
		'/tmp/ws')).decision == 'allow'
	assert assistant_policy_decide(rules, pol_req('filesystem.write', '/tmp/ws/a.txt',
		'/tmp/ws')).decision == 'allow'
	// Outside the workspace: no rule matches -> deny.
	assert assistant_policy_decide(rules, pol_req('filesystem.write', '/tmp/other/a.txt',
		'/tmp/ws')).decision == 'deny'
	// Traversal must not escape lexically.
	assert assistant_policy_decide(rules, pol_req('filesystem.write', '/tmp/ws/../other/a.txt',
		'/tmp/ws')).decision == 'deny'
}

fn test_policy_explicit_deny_overrides_allow() {
	rules := [
		AssistantPolicyRule{'javi.main', 'desktop.screenshot', 'any', 'allow'},
		AssistantPolicyRule{'javi.main', 'desktop.screenshot', 'any', 'deny'},
	]
	assert assistant_policy_decide(rules, pol_req('desktop.screenshot', 'any',
		'')).decision == 'deny'
}

fn test_policy_screenshot_default_and_approval_flow() {
	rules := assistant_policy_preset('workspace-agent')
	assert assistant_policy_decide(rules, pol_req('desktop.screenshot', 'any',
		'')).decision == 'require_approval'
	mut req := pol_req('desktop.screenshot', 'window:42', '')
	req = AssistantPolicyRequest{
		...req
		approval_id:     'a1'
		approval_action: 'desktop.screenshot'
		approval_target: 'window:42'
		approval_exp:    2000
	}
	// Approval bound to the exact action+resource and unexpired: allowed.
	assert assistant_policy_decide(rules, req).decision == 'allow'
	mut req2 := AssistantPolicyRequest{
		...req
		resource:        'any'
		approval_target: 'any'
	}
	assert assistant_policy_decide(rules, req2).decision == 'allow'
	// Expired approval never allows.
	mut req3 := AssistantPolicyRequest{
		...req2
		approval_exp: 999
	}
	assert assistant_policy_decide(rules, req3).decision == 'require_approval'
	// Approval for different arguments never allows.
	mut req4 := AssistantPolicyRequest{
		...req2
		approval_target: 'window:99'
	}
	assert assistant_policy_decide(rules, req4).decision == 'require_approval'
}

fn test_policy_hard_denies_beat_user_allow() {
	home := os.home_dir()
	rules := [AssistantPolicyRule{'javi.main', 'filesystem.read', 'any', 'allow'}]
	assert assistant_policy_decide(rules, pol_req('filesystem.read', '${home}/.ssh/id_ed25519',
		'/tmp/ws')).decision == 'deny'
	assert assistant_policy_decide(rules, pol_req('filesystem.read', '${home}/.hermes/auth.json',
		'/tmp/ws')).decision == 'deny'
	// Unattended shell and package.remove are hard-denied.
	mut unattended := pol_req('shell.execute', 'workspace', '/tmp/ws')
	unattended = AssistantPolicyRequest{
		...unattended
		interactive: false
	}
	shell_rules := [AssistantPolicyRule{'javi.main', 'shell.execute', 'any', 'allow'}]
	assert assistant_policy_decide(shell_rules, unattended).decision == 'deny'
	assert assistant_policy_decide(shell_rules, pol_req('package.remove', 'vim',
		'')).decision == 'deny'
}

fn test_policy_modes_cannot_broaden() {
	rules := assistant_policy_preset('desktop-assistant')
	mut ask := pol_req('filesystem.write', '/tmp/ws/a', '/tmp/ws')
	ask = AssistantPolicyRequest{
		...ask
		mode: 'ask'
	}
	assert assistant_policy_decide(rules, ask).decision == 'deny'
	mut chat := pol_req('filesystem.read', '/tmp/ws/a', '/tmp/ws')
	chat = AssistantPolicyRequest{
		...chat
		mode: 'chat'
	}
	assert assistant_policy_decide(rules, chat).decision == 'deny'
	assert assistant_policy_decide(rules, pol_req('filesystem.read', '/tmp/ws/a',
		'/tmp/ws')).decision == 'allow'
}

fn test_policy_unknown_and_wildcard_fail_closed() {
	assert assistant_policy_decide(assistant_policy_preset('read-only'), pol_req('bogus.action',
		'x', '')).decision == 'deny'
	bad := [AssistantPolicyRule{'javi.main', '*', 'any', 'allow'}]
	assert assistant_policy_validate(bad).len > 0
	assert assistant_policy_decide(bad, pol_req('filesystem.read', '/tmp/ws/a',
		'/tmp/ws')).decision == 'deny'
	mut unknown_principal := pol_req('filesystem.read', '/tmp/ws/a', '/tmp/ws')
	unknown_principal = AssistantPolicyRequest{
		...unknown_principal
		principal: 'remote.stranger'
	}
	assert assistant_policy_decide(assistant_policy_preset('read-only'),
		unknown_principal).decision == 'deny'
}

fn test_policy_delegation_is_intersection() {
	parent := assistant_policy_preset('workspace-agent')
	requested := [
		AssistantPolicyRule{'javi.subagent', 'filesystem.read', 'workspace', 'allow'},
		AssistantPolicyRule{'javi.subagent', 'package.install', 'any', 'allow'},
	]
	child := assistant_policy_delegate(parent, requested)
	mut r := AssistantPolicyRequest{
		principal:      'javi.subagent'
		action:         'filesystem.read'
		resource:       '/tmp/ws/a'
		workspace_root: '/tmp/ws'
		mode:           'agent'
		interactive:    true
		now:            1000
	}
	assert assistant_policy_decide(child, r).decision == 'allow'
	r = AssistantPolicyRequest{
		...r
		action:   'package.install'
		resource: 'vim'
	}
	assert assistant_policy_decide(child, r).decision == 'deny'
	// Screenshot deny from the read-only base carries into the child.
	r = AssistantPolicyRequest{
		...r
		action:   'desktop.screenshot'
		resource: 'any'
	}
	assert assistant_policy_decide(child, r).decision == 'deny'
}

fn test_policy_symlink_escape_is_denied() {
	root := os.join_path(os.temp_dir(), 'javi-pol-test-${os.getpid()}')
	outside := '${root}-outside'
	os.mkdir_all('${root}/ws') or { assert false }
	os.mkdir_all(outside) or { assert false }
	os.write_file('${outside}/secret.txt', 'synthetic') or { assert false }
	os.symlink(outside, '${root}/ws/escape') or { assert false }
	defer {
		os.rmdir_all(root) or {}
		os.rmdir_all(outside) or {}
	}
	rules := assistant_policy_preset('workspace-agent')
	d := assistant_policy_decide(rules, pol_req('filesystem.read', '${root}/ws/escape/secret.txt',
		'${root}/ws'))
	assert d.decision == 'deny'
	d2 := assistant_policy_decide(rules, pol_req('filesystem.read', '${root}/ws/ok.txt',
		'${root}/ws'))
	assert d2.decision == 'allow'
}

fn test_policy_presets_validate() {
	for name in ['read-only', 'workspace-agent', 'desktop-assistant'] {
		assert assistant_policy_validate(assistant_policy_preset(name)).len == 0
	}
	assert assistant_policy_preset('bogus').len == 0
}
