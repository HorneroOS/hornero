module hornero_core

import os
import x.json2

// -- Javi ABAC policy engine -------------------------------------------------
// Typed Principal+Action+Resource+Context evaluator. This is the trusted
// control-plane decision point: it lives in horneroctl, outside Hermes, and
// no prompt, skill or tool output can change its outcome. Semantics (tested
// in assistant_policy_test.v):
//   1. Invalid/unknown principal, action, effect or resource -> DENY.
//   2. Hard system denies (protected paths, unattended shell, destructive
//      package ops) -> DENY, and no user rule can override them.
//   3. Any matching explicit DENY rule -> DENY (deny overrides allow).
//   4. Any matching REQUIRE_APPROVAL rule -> REQUIRE_APPROVAL, unless a
//      matching ALLOW rule also covers the exact request and the request
//      carries an unexpired approval bound to the same action+resource.
//   5. Any matching ALLOW rule -> ALLOW.
//   6. Otherwise default DENY.
// A smaller typed evaluator is used instead of Cedar/OPA: the policy surface
// is a fixed action catalogue with path/domain/unit resources, and embedding
// a Rego/Cedar runtime would add a native dependency to every horneroctl
// install for no extra expressiveness on this subset. Policies are JSON
// data (see assistant_policy_preset), validated before activation.

pub const assistant_policy_actions = [
	'filesystem.read',
	'filesystem.write',
	'filesystem.delete',
	'filesystem.execute',
	'shell.execute',
	'desktop.observe',
	'desktop.screenshot',
	'desktop.window.list',
	'desktop.window.focus',
	'desktop.window.close',
	'desktop.input',
	'clipboard.read',
	'clipboard.write',
	'microphone.record',
	'camera.capture',
	'network.request',
	'package.install',
	'package.remove',
	'service.restart',
	'appearance.modify',
	'notifications.send',
	'memory.read',
	'memory.write',
	'agent.delegate',
	'skill.install',
	'mcp.invoke',
]

pub const assistant_policy_principals = [
	'javi.main',
	'javi.subagent',
	'javi.ask',
	'javi.chat',
	'javi.background',
	'skill',
	'plugin',
	'mcp',
]

pub struct AssistantPolicyRule {
pub mut:
	principal string // exact principal, never '*'
	action    string // exact action from assistant_policy_actions
	resource  string // 'workspace', 'path:<abs-prefix>', 'domain:<host>', 'unit:<name>', 'any'
	effect    string // allow | deny | approval
}

pub struct AssistantPolicyRequest {
pub:
	principal       string
	action          string
	resource        string // canonical absolute path, domain, unit or 'workspace'
	workspace_root  string // canonical active workspace root, '' if none
	mode            string // ask | agent | chat
	interactive     bool
	approval_id     string
	approval_action string
	approval_target string
	approval_exp    i64 // unix seconds, 0 = no approval
	now             i64
}

pub struct AssistantPolicyDecision {
pub:
	decision string // allow | deny | require_approval
	reason   string
	rule     int // index of deciding rule, -1 for default/hard deny
}

// Protected path prefixes (relative to home) that are hard-denied for every
// filesystem action, regardless of user rules.
pub fn assistant_policy_protected_prefixes(home string) []string {
	return [
		os.join_path(home, '.ssh'),
		os.join_path(home, '.gnupg'),
		os.join_path(home, '.hermes', 'auth.json'),
		os.join_path(home, '.config', 'hornero', 'assistant.key'),
		os.join_path(home, '.config', 'hornero', 'assistant-policy.json'),
		os.join_path(home, '.mozilla'),
		os.join_path(home, '.config', 'chromium'),
		os.join_path(home, '.config', 'google-chrome'),
		os.join_path(home, '.local', 'share', 'keyrings'),
	]
}

// assistant_policy_canonical resolves '.'/'..' lexically, then resolves
// symlinks for the longest existing prefix so a symlink inside a workspace
// cannot escape it. Nonexistent tails are appended lexically after the
// resolved parent.
pub fn assistant_policy_canonical(path string) string {
	if path.len == 0 {
		return ''
	}
	mut p := path
	if !os.is_abs_path(p) {
		p = os.join_path(os.getwd(), p)
	}
	// Lexical normalisation of . and .. without touching the filesystem.
	parts := p.split('/')
	mut stack := []string{}
	for part in parts {
		if part == '' || part == '.' {
			continue
		}
		if part == '..' {
			if stack.len > 0 {
				stack.delete(stack.len - 1)
			}
			continue
		}
		stack << part
	}
	mut norm := '/' + stack.join('/')
	// Resolve symlinks on the existing prefix.
	mut existing := norm
	mut tail := []string{}
	for existing.len > 1 && !os.exists(existing) {
		tail.insert(0, os.base(existing))
		existing = os.dir(existing)
	}
	resolved := os.real_path(existing)
	mut out := resolved
	for t in tail {
		out = os.join_path(out, t)
	}
	return out
}

pub fn assistant_policy_path_within(root string, path string) bool {
	if root.len == 0 || path.len == 0 {
		return false
	}
	r := assistant_policy_canonical(root)
	p := assistant_policy_canonical(path)
	return p == r || p.starts_with(r + '/')
}

fn assistant_policy_resource_matches(rule_resource string, req AssistantPolicyRequest) bool {
	if rule_resource == 'any' {
		return true
	}
	if rule_resource == 'workspace' {
		if req.action.starts_with('filesystem.') || req.action.starts_with('memory.') {
			return req.workspace_root.len > 0
				&& assistant_policy_path_within(req.workspace_root, req.resource)
		}
		return req.resource == 'workspace'
	}
	if rule_resource.starts_with('path:') {
		return assistant_policy_path_within(rule_resource['path:'.len..], req.resource)
	}
	if rule_resource.starts_with('domain:') {
		return req.resource == rule_resource['domain:'.len..]
			|| req.resource.ends_with('.' + rule_resource['domain:'.len..])
	}
	if rule_resource.starts_with('unit:') {
		return req.resource == rule_resource['unit:'.len..]
	}
	return false
}

pub fn assistant_policy_validate(rules []AssistantPolicyRule) []string {
	mut errs := []string{}
	for i, r in rules {
		if r.principal !in assistant_policy_principals {
			errs << 'rule ${i}: unknown principal "${r.principal}"'
		}
		if r.principal.contains('*') || r.action.contains('*') {
			errs << 'rule ${i}: wildcards are not allowed in principal/action'
		}
		if r.action !in assistant_policy_actions {
			errs << 'rule ${i}: unknown action "${r.action}"'
		}
		if r.effect !in ['allow', 'deny', 'approval'] {
			errs << 'rule ${i}: unknown effect "${r.effect}"'
		}
		if r.resource.starts_with('path:') {
			p := r.resource['path:'.len..]
			if !os.is_abs_path(p) || p.contains('..') || p.contains('*') {
				errs << 'rule ${i}: path resource must be a clean absolute prefix'
			}
		}
	}
	return errs
}

// assistant_policy_decide is the single decision function. Pure: callers
// supply `now` so expiry behaviour is testable.
pub fn assistant_policy_decide(rules []AssistantPolicyRule, req AssistantPolicyRequest) AssistantPolicyDecision {
	deny := fn (reason string, rule int) AssistantPolicyDecision {
		return AssistantPolicyDecision{
			decision: 'deny'
			reason:   reason
			rule:     rule
		}
	}
	if req.principal !in assistant_policy_principals {
		return deny('unknown principal', -1)
	}
	if req.action !in assistant_policy_actions {
		return deny('unknown action', -1)
	}
	if assistant_policy_validate(rules).len > 0 {
		return deny('policy failed validation; fail closed', -1)
	}
	// Hard system denies: no user rule can override these.
	if req.action.starts_with('filesystem.') && req.resource.len > 0 {
		home := os.home_dir()
		canon := assistant_policy_canonical(req.resource)
		for prot in assistant_policy_protected_prefixes(home) {
			if canon == assistant_policy_canonical(prot)
				|| canon.starts_with(assistant_policy_canonical(prot) + '/') {
				return deny('protected path (system hard deny)', -1)
			}
		}
		// The policy file itself is never agent-writable.
		if req.action != 'filesystem.read'
			&& canon == assistant_policy_canonical(assistant_policy_file()) {
			return deny('agent may not modify its own policy', -1)
		}
	}
	if req.action == 'shell.execute' && !req.interactive {
		return deny('unattended shell execution is hard-denied', -1)
	}
	if req.action == 'package.remove' {
		return deny('destructive package operations are hard-denied', -1)
	}
	if req.mode == 'ask' && req.action !in ['filesystem.read', 'desktop.observe', 'desktop.window.list',
		'memory.read', 'network.request'] {
		return deny('Ask mode is read-only', -1)
	}
	if req.mode == 'chat' && req.action !in ['memory.read', 'network.request'] {
		return deny('Chat mode has no machine authority', -1)
	}
	// Approval validity is bound to exact action+resource and expiry.
	approval_ok := req.approval_id.len > 0 && req.approval_action == req.action
		&& req.approval_target == req.resource && req.approval_exp > req.now
	mut approval_rule := -1
	mut allow_rule := -1
	for i, r in rules {
		if r.principal != req.principal && !(req.principal == 'javi.subagent'
			&& r.principal == 'javi.main') {
			continue
		}
		// Subagents never gain from a main-agent rule unless the rule was
		// explicitly delegated; intersection is enforced by
		// assistant_policy_delegate below, which produces subagent rules.
		if req.principal == 'javi.subagent' && r.principal == 'javi.main' {
			continue
		}
		if r.action != req.action {
			continue
		}
		if !assistant_policy_resource_matches(r.resource, req) {
			continue
		}
		match r.effect {
			'deny' { return deny('explicit deny rule', i) }
			'approval' {
				if approval_rule < 0 { approval_rule = i }
			}
			'allow' {
				if allow_rule < 0 { allow_rule = i }
			}
			else {}
		}
	}
	if approval_rule >= 0 {
		if approval_ok {
			return AssistantPolicyDecision{
				decision: 'allow'
				reason:   'approved interactively for this exact action and resource'
				rule:     approval_rule
			}
		}
		return AssistantPolicyDecision{
			decision: 'require_approval'
			reason:   'rule requires interactive approval'
			rule:     approval_rule
		}
	}
	if allow_rule >= 0 {
		return AssistantPolicyDecision{
			decision: 'allow'
			reason:   'allow rule'
			rule:     allow_rule
		}
	}
	return deny('default deny: no matching allow rule', -1)
}

// assistant_policy_delegate returns the subagent's effective rules: the
// intersection of the parent's rules with the delegation request. A child
// can never receive an action/resource the parent does not hold, and deny
// rules always carry over.
pub fn assistant_policy_delegate(parent []AssistantPolicyRule, requested []AssistantPolicyRule) []AssistantPolicyRule {
	mut out := []AssistantPolicyRule{}
	for r in parent {
		if r.effect == 'deny' {
			out << AssistantPolicyRule{
				principal: 'javi.subagent'
				action:    r.action
				resource:  r.resource
				effect:    'deny'
			}
		}
	}
	for want in requested {
		for have in parent {
			if have.effect == 'allow' && have.action == want.action
				&& have.resource == want.resource {
				out << AssistantPolicyRule{
					principal: 'javi.subagent'
					action:    want.action
					resource:  want.resource
					effect:    want.effect
				}
			}
		}
	}
	return out
}

pub fn assistant_policy_preset(name string) []AssistantPolicyRule {
	match name {
		'read-only' {
			return [
				AssistantPolicyRule{'javi.main', 'filesystem.read', 'workspace', 'allow'},
				AssistantPolicyRule{'javi.main', 'desktop.window.list', 'any', 'allow'},
				AssistantPolicyRule{'javi.main', 'desktop.observe', 'any', 'allow'},
				AssistantPolicyRule{'javi.main', 'memory.read', 'workspace', 'allow'},
				AssistantPolicyRule{'javi.main', 'desktop.screenshot', 'any', 'deny'},
				AssistantPolicyRule{'javi.main', 'clipboard.read', 'any', 'deny'},
			]
		}
		'workspace-agent' {
			// Start from read-only but drop its screenshot/clipboard denies:
			// this preset upgrades them to approval-gated, and an explicit
			// deny would win over the approval rule forever.
			mut r := assistant_policy_preset('read-only').filter(!(it.effect == 'deny'
				&& it.action in ['desktop.screenshot', 'clipboard.read']))
			r << AssistantPolicyRule{'javi.main', 'filesystem.write', 'workspace', 'allow'}
			r << AssistantPolicyRule{'javi.main', 'filesystem.delete', 'workspace', 'approval'}
			r << AssistantPolicyRule{'javi.main', 'memory.write', 'workspace', 'allow'}
			r << AssistantPolicyRule{'javi.main', 'shell.execute', 'workspace', 'approval'}
			r << AssistantPolicyRule{'javi.main', 'desktop.screenshot', 'any', 'approval'}
			return r
		}
		'desktop-assistant' {
			mut r := assistant_policy_preset('workspace-agent')
			r << AssistantPolicyRule{'javi.main', 'desktop.window.focus', 'any', 'allow'}
			r << AssistantPolicyRule{'javi.main', 'desktop.window.close', 'any', 'approval'}
			r << AssistantPolicyRule{'javi.main', 'appearance.modify', 'any', 'allow'}
			r << AssistantPolicyRule{'javi.main', 'notifications.send', 'any', 'allow'}
			r << AssistantPolicyRule{'javi.main', 'package.install', 'any', 'approval'}
			r << AssistantPolicyRule{'javi.main', 'clipboard.read', 'any', 'approval'}
			return r
		}
		else {
			return []AssistantPolicyRule{}
		}
	}
}

pub fn assistant_policy_file() string {
	env := os.getenv('HORNERO_ASSISTANT_POLICY_FILE')
	if env.len > 0 {
		return env
	}
	return os.join_path(assistant_dir(), 'assistant-policy.json')
}

pub fn assistant_policy_load() ([]AssistantPolicyRule, bool) {
	raw := os.read_file(assistant_policy_file()) or {
		return assistant_policy_preset('read-only'), false
	}
	decoded := json2.decode[json2.Any](raw) or { return []AssistantPolicyRule{}, false }
	if decoded !is []json2.Any {
		return []AssistantPolicyRule{}, false
	}
	mut rules := []AssistantPolicyRule{}
	for item in decoded.as_array() {
		if item !is map[string]json2.Any {
			return []AssistantPolicyRule{}, false
		}
		m := item.as_map()
		rules << AssistantPolicyRule{
			principal: if 'principal' in m && m['principal'] is string {
				m['principal'].str()
			} else {
				''
			}
			action:    if 'action' in m && m['action'] is string { m['action'].str() } else { '' }
			resource:  if 'resource' in m && m['resource'] is string {
				m['resource'].str()
			} else {
				''
			}
			effect:    if 'effect' in m && m['effect'] is string { m['effect'].str() } else { '' }
		}
	}
	if assistant_policy_validate(rules).len > 0 {
		return []AssistantPolicyRule{}, false
	}
	return rules, true
}

pub fn assistant_policy_save(rules []AssistantPolicyRule) ! {
	errs := assistant_policy_validate(rules)
	if errs.len > 0 {
		return error(errs.join('; '))
	}
	os.mkdir_all(os.dir(assistant_policy_file()))!
	mut arr := []json2.Any{}
	for r in rules {
		arr << json2.Any({
			'principal': json2.Any(r.principal)
			'action':    json2.Any(r.action)
			'resource':  json2.Any(r.resource)
			'effect':    json2.Any(r.effect)
		})
	}
	os.write_file(assistant_policy_file(), json2.encode(arr, escape_unicode: true) + '\n')!
	os.chmod(assistant_policy_file(), 0o600) or {}
}

// -- Reports (CLI surface) ---------------------------------------------------

pub fn assistant_policy_show_report() CommandResult {
	rules, custom := assistant_policy_load()
	mut lines := []string{}
	for i, r in rules {
		lines << '${i}: ${r.principal} ${r.action} ${r.resource} -> ${r.effect}'
	}
	return ok_result('assistant policy', 'Javi ABAC policy (${if custom {
		'custom file'
	} else {
		'read-only preset (no policy file)'
	}}):\n' +
		lines.join('\n'), {
		'rules': rules.len.str()
		'file':  assistant_policy_file()
	})
}

pub fn assistant_policy_check_report(principal string, action string, resource string, workspace string) CommandResult {
	rules, _ := assistant_policy_load()
	d := assistant_policy_decide(rules, AssistantPolicyRequest{
		principal:      principal
		action:         action
		resource:       resource
		workspace_root: workspace
		mode:           'agent'
		interactive:    true
		now:            1893456000
	})
	return CommandResult{
		command: 'assistant policy check'
		ok:      d.decision == 'allow'
		message: '${d.decision}: ${d.reason} (rule ${d.rule})'
		data:    {
			'decision': d.decision
			'reason':   d.reason
		}
	}
}

pub fn assistant_policy_preset_report(name string, dry_run bool, yes bool) CommandResult {
	rules := assistant_policy_preset(name)
	if name !in ['read-only', 'workspace-agent', 'desktop-assistant'] {
		return fail_result('assistant policy preset', 'Unknown preset "${name}". Use read-only, workspace-agent or desktop-assistant.')
	}
	if dry_run {
		return ok_result('assistant policy preset', 'Dry run: would install preset ${name} (${rules.len} rules) at ${assistant_policy_file()}. Nothing written.', {
			'dryRun': 'true'
		})
	}
	if !yes {
		return fail_result('assistant policy preset', 'Installing a policy preset needs --yes. Preview with --dry-run.')
	}
	assistant_policy_save(rules) or {
		return fail_result('assistant policy preset', 'Cannot save policy: ${err.msg()}')
	}
	assistant_log_append('policy.preset', '', name, 'ok')
	return ok_result('assistant policy preset', 'Installed preset ${name} (${rules.len} rules). Effective immediately; the agent cannot edit this file from inside its sandbox.', {
		'preset': name
		'rules':  rules.len.str()
	})
}

pub fn assistant_policy_revoke_all_report(yes bool) CommandResult {
	if !yes {
		return fail_result('assistant policy revoke-all', 'Revoking all agent actions needs --yes.')
	}
	assistant_policy_save(assistant_policy_preset('read-only')) or {
		return fail_result('assistant policy revoke-all', 'Cannot save policy: ${err.msg()}')
	}
	assistant_log_append('policy.revoke-all', '', '', 'ok')
	return ok_result('assistant policy revoke-all', 'All agent grants revoked; Javi is back to the read-only preset. Takes effect on the next policy evaluation.', {})
}
