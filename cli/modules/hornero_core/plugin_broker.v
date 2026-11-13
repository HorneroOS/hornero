module hornero_core

import os
import time
import x.json2

// -- Typed plugin capability/action broker (hornero#408) ---------------------
// The plugin broker is the only horneroctl path from an installed Shell
// extension to an OS action. It exposes a fixed catalogue of typed
// actions (never a generic command or privileged shell endpoint),
// separates read-only from mutating actions, and evaluates every call
// through the existing ABAC policy (assistant_policy.v) under the
// `plugin` principal before anything executes.
//
// A call must clear every gate, in order; every gate fails closed:
//   1. The plugin id is well-formed (community_plugin_valid_id) and a
//      Hornero receipt owns it; payload and receipt are not symlinks.
//   2. The plugin is enabled and its current payload is trusted
//      (official catalogue, hash-pinned local trust, or signed).
//   3. The installed manifest declares the action in the additive
//      `capabilities.actions` array. Manifests written before this
//      field existed declare no actions and get none: the field is
//      opt-in and old manifests keep loading identically everywhere
//      else (list, validate, catalogue) because nothing here is read
//      outside this broker.
//   4. The action exists in the closed catalogue below and its typed
//      argument validates.
//   5. The ABAC policy allows principal `plugin` to perform the mapped
//      action on the exact resource. The read-only preset grants the
//      plugin principal desktop.observe and reading inside its own
//      payload; every mutation is denied until the user writes a
//      policy rule (approval rules are satisfied only by the human's
//      --yes at this trusted CLI, bound to one exact call).
//
// Honesty boundary: QML plugins are NOT sandboxed. They run with the
// logged-in user's privileges inside Quickshell, so a malicious plugin
// can ignore this broker entirely. The broker is the supported, typed,
// audited contract for well-behaved extensions; manifest capability
// declarations are review metadata, not enforcement. Enforcement here
// covers only calls made through this broker.

pub struct PluginBrokerAction {
pub:
	name     string
	action   string // ABAC action from assistant_policy_actions
	mutating bool
}

// plugin_broker_catalogue is exhaustive: anything not listed here does
// not exist as far as a plugin is concerned. Read-only actions come
// first; `mutating` separates the two classes in `--help`, `list`, and
// the CLI flag contract (mutations also require --yes at the CLI).
pub fn plugin_broker_catalogue() []PluginBrokerAction {
	return [
		PluginBrokerAction{'system_info', 'desktop.observe', false},
		PluginBrokerAction{'appearance_status', 'desktop.observe', false},
		PluginBrokerAction{'theme_list', 'desktop.observe', false},
		PluginBrokerAction{'theme_show', 'desktop.observe', false},
		PluginBrokerAction{'gtk_list', 'desktop.observe', false},
		PluginBrokerAction{'gtk_current', 'desktop.observe', false},
		PluginBrokerAction{'package_updates', 'desktop.observe', false},
		PluginBrokerAction{'studio_mode', 'desktop.observe', false},
		PluginBrokerAction{'studio_jobs_list', 'desktop.observe', false},
		PluginBrokerAction{'assistant_usage', 'desktop.observe', false},
		PluginBrokerAction{'window_list', 'desktop.window.list', false},
		PluginBrokerAction{'plugin_file_read', 'filesystem.read', false},
		PluginBrokerAction{'theme_set', 'appearance.modify', true},
		PluginBrokerAction{'window_focus', 'desktop.window.focus', true},
		PluginBrokerAction{'notify', 'notifications.send', true},
	]
}

pub fn plugin_broker_action(name string) (PluginBrokerAction, bool) {
	for a in plugin_broker_catalogue() {
		if a.name == name {
			return a, true
		}
	}
	return PluginBrokerAction{}, false
}

// plugin_broker_declared_actions reads the additive
// `capabilities.actions` manifest array. A manifest without the field
// (every shipped manifest today) declares no actions. A malformed
// field fails closed instead of being ignored.
pub fn plugin_broker_declared_actions(manifest map[string]json2.Any) ![]string {
	if 'capabilities' !in manifest {
		return []string{}
	}
	caps := manifest['capabilities']
	if caps !is map[string]json2.Any {
		return error('manifest capabilities must be an object')
	}
	caps_map := caps.as_map()
	if 'actions' !in caps_map {
		return []string{}
	}
	raw := caps_map['actions']
	if raw !is []json2.Any {
		return error('manifest capabilities.actions must be an array of action names')
	}
	mut out := []string{}
	for item in raw.as_array() {
		name := community_plugin_string(item) or {
			return error('manifest capabilities.actions entries must be strings')
		}
		if name !in out {
			out << name
		}
	}
	return out
}

// plugin_broker_argv returns literal argv for an action, or an error
// for anything outside the catalogue or with unsafe arguments. No
// argv is ever built from a shell string, and no catalogue entry runs
// a shell, sudo, or any privileged helper.
pub fn plugin_broker_argv(action string, arg string) ![]string {
	match action {
		'studio_mode' {
			return ['horneroctl', '--json', 'studio', 'mode']
		}
		'studio_jobs_list' {
			return ['horneroctl', '--json', 'studio', 'jobs', 'list']
		}
		'assistant_usage' {
			return ['horneroctl', 'assistant', 'usage', '--json']
		}
		'plugin_file_read' {
			// Executed in-process against the caller's own payload (see
			// plugin_broker_exec_report); there is intentionally no argv.
			return error('plugin_file_read has no external command')
		}
		else {
			// The remaining catalogue mirrors the assistant broker's
			// typed argv validation exactly, so both brokers share one
			// argument-safety implementation.
			return assistant_broker_argv(action, arg)
		}
	}
}

// plugin_broker_file_target resolves a plugin_file_read argument
// strictly inside the plugin's own payload directory. Absolute paths,
// `..` traversal, and symlink escapes are all refused: the final
// canonical path (symlinks resolved by assistant_policy_path_within)
// must stay within the payload, and the target itself may not be a
// symlink.
pub fn plugin_broker_file_target(payload string, rel string) !string {
	if rel.len == 0 {
		return error('plugin_file_read needs a path relative to the plugin payload')
	}
	if os.is_abs_path(rel) {
		return error('plugin_file_read path must be relative to the plugin payload, not absolute')
	}
	if rel.contains('\\') || rel.bytes().any(it < 0x20) {
		return error('plugin_file_read path contains unsafe characters')
	}
	for part in rel.split('/') {
		if part == '..' {
			return error('plugin_file_read path may not traverse outside the plugin payload')
		}
	}
	target := os.join_path(payload, rel)
	if !assistant_policy_path_within(payload, target) {
		return error('plugin_file_read path escapes the plugin payload')
	}
	if os.is_link(target) {
		return error('plugin_file_read refuses to follow a symbolic link')
	}
	canon := assistant_policy_canonical(target)
	if canon == assistant_policy_canonical(payload) {
		return error('plugin_file_read needs a file inside the plugin payload, not the payload itself')
	}
	return canon
}

struct PluginBrokerSubject {
	record   CommunityPluginReceipt
	payload  string
	declared []string
}

// plugin_broker_subject applies gates 1-3. Errors are returned as
// messages, never as a silently empty subject.
fn plugin_broker_subject(id string) !PluginBrokerSubject {
	if !community_plugin_valid_id(id) {
		return error('invalid plugin id.\nExample: horneroctl plugin action list example-clock')
	}
	root, receipts := community_plugin_roots()
	payload := os.join_path(root, id)
	receipt_path := os.join_path(receipts, '${id}.json')
	if os.is_link(payload) || os.is_link(receipt_path) {
		return error('refusing to follow a symbolic link in the owned plugin paths')
	}
	if !os.is_file(receipt_path) {
		return error('no Hornero receipt owns plugin ${id}; only installed plugins may use the action broker')
	}
	record := json2.decode[CommunityPluginReceipt](os.read_file(receipt_path) or { '' }) or {
		return error('plugin receipt is malformed; refusing broker access')
	}
	if record.schema_version != 1 || record.id != id {
		return error('plugin receipt does not own the requested plugin id')
	}
	if !os.is_dir(payload) {
		return error('plugin payload is missing at ${payload}; reinstall the package before using the broker')
	}
	if !record.enabled {
		return error('plugin ${id} is disabled; disabled plugins may not run broker actions. Enable it first: horneroctl plugin enable ${id} --yes')
	}
	trust := community_plugin_trust_state(record, payload)
	if trust !in ['official', 'trusted', 'signed'] {
		return error('plugin ${id} is ${trust}: broker actions require a trusted payload. Review the code, then run: horneroctl plugin trust ${id} --yes')
	}
	manifest := community_plugin_manifest(payload) or { return error(err.msg()) }
	declared := plugin_broker_declared_actions(manifest) or { return error(err.msg()) }
	return PluginBrokerSubject{
		record:   record
		payload:  payload
		declared: declared
	}
}

fn plugin_broker_resource(spec PluginBrokerAction, subject PluginBrokerSubject, arg string) string {
	match spec.name {
		'plugin_file_read' {
			return plugin_broker_file_target(subject.payload, arg) or { arg }
		}
		'theme_set', 'theme_show', 'window_focus' { return arg }
		'notify' { return 'local' }
		else { return 'any' }
	}
}

fn plugin_broker_log_file() string {
	paths := resolve_paths()
	return os.join_path(paths.state_dir, 'hornero', 'plugins', 'action.log')
}

fn plugin_broker_log_append(plugin_id string, action string, detail string, status string) {
	path := plugin_broker_log_file()
	os.mkdir_all(os.dir(path)) or { return }
	line := assistant_log_line(time.now().custom_format('YYYY-MM-DDTHH:mm:ss'),
		'plugin.${plugin_id}.${action}', '', detail, status)
	mut content := os.read_file(path) or { '' }
	content += line
	if content.len > assistant_log_max_bytes {
		content = assistant_log_rotate_text(content, assistant_log_max_bytes / 2)
	}
	os.write_file(path, content) or { return }
	os.chmod(path, 0o600) or {}
}

// plugin_broker_decide applies gates 4-5 without executing anything.
// `check` and `run` share it so a simulated decision can never drift
// from the enforced one.
fn plugin_broker_decide(subject PluginBrokerSubject, action string, arg string, approved_once bool) (PluginBrokerAction, AssistantPolicyDecision, string) {
	spec, found := plugin_broker_action(action)
	if !found {
		return spec, AssistantPolicyDecision{
			decision: 'deny'
			reason:   'unknown action: not in the typed plugin broker catalogue'
			rule:     -1
		}, ''
	}
	if action !in subject.declared {
		return spec, AssistantPolicyDecision{
			decision: 'deny'
			reason:   'plugin ${subject.record.id} does not declare action "${action}" in capabilities.actions'
			rule:     -1
		}, ''
	}
	resource := plugin_broker_resource(spec, subject, arg)
	rules, _ := assistant_policy_load()
	mut req := AssistantPolicyRequest{
		principal:      'plugin'
		action:         spec.action
		resource:       resource
		workspace_root: subject.payload
		mode:           'agent'
		interactive:    false
		now:            time.now().unix()
	}
	if approved_once {
		req = AssistantPolicyRequest{
			...req
			approval_id:     'cli-once'
			approval_action: spec.action
			approval_target: resource
			approval_exp:    req.now + 60
		}
	}
	return spec, assistant_policy_decide(rules, req), resource
}

pub fn plugin_broker_list_report(plugin_id string) CommandResult {
	if plugin_id.len == 0 {
		mut lines := ['Typed actions an installed plugin may declare in capabilities.actions (read-only first; mutating actions are policy-gated and need --yes at this CLI):']
		for a in plugin_broker_catalogue() {
			lines << '${a.name}  [${a.action}${if a.mutating { ', mutating' } else { ', read-only' }}]'
		}
		lines << 'Anything not listed cannot be invoked. There is no generic or privileged command action.'
		return ok_result('plugin action list', lines.join('\n'), {
			'class': 'broker-typed'
			'count': plugin_broker_catalogue().len.str()
		})
	}
	subject := plugin_broker_subject(plugin_id) or {
		return fail_result('plugin action list', err.msg())
	}
	mut lines := ['Actions declared by ${plugin_id} (capabilities.actions):']
	if subject.declared.len == 0 {
		lines << '(none — this manifest declares no broker actions; manifests without the additive capabilities.actions field get none)'
	}
	for name in subject.declared {
		spec, found := plugin_broker_action(name)
		if found {
			lines << '${name}  [${spec.action}${if spec.mutating {
				', mutating'
			} else {
				', read-only'
			}}]'
		} else {
			lines << '${name}  [unknown: not in the broker catalogue, will be denied]'
		}
	}
	return ok_result('plugin action list', lines.join('\n'), {
		'plugin':   plugin_id
		'declared': subject.declared.join(',')
		'count':    subject.declared.len.str()
	})
}

pub fn plugin_broker_check_report(plugin_id string, action string, arg string) CommandResult {
	subject := plugin_broker_subject(plugin_id) or {
		return fail_result('plugin action check', err.msg())
	}
	if action == 'plugin_file_read' {
		plugin_broker_file_target(subject.payload, arg) or {
			return fail_result('plugin action check', err.msg())
		}
	} else {
		_, known := plugin_broker_action(action)
		if known {
			plugin_broker_argv(action, arg) or {
				return fail_result('plugin action check', err.msg())
			}
		}
	}
	spec, decision, resource := plugin_broker_decide(subject, action, arg, false)
	return CommandResult{
		command: 'plugin action check'
		ok:      decision.decision == 'allow'
		message: '${decision.decision}: ${decision.reason} (rule ${decision.rule}). Nothing executed.'
		data:    {
			'plugin':   plugin_id
			'action':   action
			'abac':     spec.action
			'mutating': spec.mutating.str()
			'resource': resource
			'decision': decision.decision
			'reason':   decision.reason
		}
	}
}

// plugin_broker_exec_report runs one declared, catalogue action for
// one enabled, trusted plugin after the ABAC policy allows it.
// Mutating actions require the CLI caller's --yes (`approved_once`),
// which satisfies an approval rule for exactly this one call and is
// never persisted. Denied, undeclared, and unknown calls execute
// nothing and are audit-logged.
pub fn plugin_broker_exec_report(plugin_id string, action string, arg string, approved_once bool, dry_run bool) CommandResult {
	subject := plugin_broker_subject(plugin_id) or {
		plugin_broker_log_append(plugin_id, action, arg, 'deny:subject')
		return fail_result('plugin action run', err.msg())
	}
	spec, found := plugin_broker_action(action)
	if !found {
		plugin_broker_log_append(plugin_id, action, arg, 'deny:unknown-action')
		return fail_result('plugin action run', 'Unknown action "${action}". List actions with: horneroctl plugin action list')
	}
	if spec.mutating && !dry_run && !approved_once {
		plugin_broker_log_append(plugin_id, action, arg, 'deny:needs-yes')
		return fail_result('plugin action run', 'action "${action}" mutates state and requires --yes (preview with --dry-run).\nExample: horneroctl plugin action run ${plugin_id} ${action} --dry-run')
	}
	if action != 'plugin_file_read' {
		plugin_broker_argv(action, arg) or {
			return fail_result('plugin action run', err.msg())
		}
	}
	_, decision, resource := plugin_broker_decide(subject, action, arg, approved_once)
	if decision.decision != 'allow' {
		plugin_broker_log_append(plugin_id, action, '${spec.action} ${resource}',
			decision.decision)
		return CommandResult{
			command: 'plugin action run'
			ok:      false
			message: 'Policy ${decision.decision}: ${decision.reason}. Nothing executed. Plugin actions are governed by the ABAC policy (horneroctl assistant policy); a rule for principal "plugin" is required beyond the read-only baseline.'
			data:    {
				'plugin':   plugin_id
				'decision': decision.decision
				'action':   spec.action
				'resource': resource
			}
		}
	}
	if action == 'plugin_file_read' {
		target := plugin_broker_file_target(subject.payload, arg) or {
			plugin_broker_log_append(plugin_id, action, arg, 'deny:path')
			return fail_result('plugin action run', err.msg())
		}
		if dry_run {
			return ok_result('plugin action run', 'Dry run (policy allow): would read ${target} (inside the ${plugin_id} payload). Nothing read.', {
				'dryRun':   'true'
				'decision': 'allow'
				'target':   target
			})
		}
		if !os.is_file(target) {
			plugin_broker_log_append(plugin_id, action, target, 'error:not-a-file')
			return fail_result('plugin action run', 'plugin_file_read target is not a file inside the plugin payload: ${arg}')
		}
		content := os.read_file(target) or {
			plugin_broker_log_append(plugin_id, action, target, 'error:read')
			return fail_result('plugin action run', 'cannot read ${arg} from the plugin payload: ${err.msg()}')
		}
		plugin_broker_log_append(plugin_id, action, target, 'ok')
		out := if content.len > 4000 { content[..4000] } else { content }
		return ok_result('plugin action run', out, {
			'plugin':   plugin_id
			'action':   action
			'abac':     spec.action
			'decision': 'allow'
			'target':   target
			'audited':  'true'
		})
	}
	argv := plugin_broker_argv(action, arg) or {
		return fail_result('plugin action run', err.msg())
	}
	if dry_run {
		return ok_result('plugin action run', 'Dry run (policy allow): would run: ${argv.join(' ')}', {
			'dryRun':   'true'
			'decision': 'allow'
		})
	}
	rep := run_exec(ExecSpec{
		prog:        argv[0]
		args:        argv[1..]
		timeout_sec: 60
	})
	status := if rep.ok { 'ok' } else { 'error:${rep.exit_code}' }
	plugin_broker_log_append(plugin_id, action, '${spec.action} ${resource}', status)
	if !rep.ok {
		return fail_result('plugin action run', '${action} failed: ${rep.output}')
	}
	out := if rep.output.len > 4000 { rep.output[..4000] } else { rep.output }
	return ok_result('plugin action run', out, {
		'plugin':   plugin_id
		'action':   action
		'abac':     spec.action
		'decision': 'allow'
		'audited':  'true'
	})
}
