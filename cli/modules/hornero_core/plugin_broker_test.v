module hornero_core

import os
import time
import x.json2

fn plugin_broker_test_env(suffix string) (string, map[string]string) {
	root := os.join_path(os.temp_dir(), 'hornero-plugin-broker-${os.getpid()}-${time.now().unix_milli()}-${suffix}')
	if os.exists(root) {
		panic('refusing to reuse an existing plugin broker test directory: ${root}')
	}
	os.mkdir_all(root) or { panic(err) }
	keys := ['XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_CONFIG_HOME', 'HORNERO_ASSISTANT_POLICY_FILE']
	mut saved := map[string]string{}
	for key in keys {
		saved[key] = os.getenv(key)
	}
	os.setenv('XDG_DATA_HOME', '${root}/data', true)
	os.setenv('XDG_STATE_HOME', '${root}/state', true)
	os.setenv('XDG_CONFIG_HOME', '${root}/config', true)
	// No policy file: the read-only preset (with the plugin baseline)
	// is the active policy, exactly as on a fresh install.
	os.setenv('HORNERO_ASSISTANT_POLICY_FILE', '${root}/no-policy.json', true)
	return root, saved
}

fn plugin_broker_test_restore(saved map[string]string) {
	for key, value in saved {
		if value.len == 0 {
			os.unsetenv(key)
		} else {
			os.setenv(key, value, true)
		}
	}
}

// plugin_broker_test_install writes an enabled payload + receipt the
// same way the lifecycle commands leave them, with a hash-pinned
// local trust record (or none, when trusted is false).
fn plugin_broker_test_install(id string, actions string, enabled bool, trusted bool) string {
	root, receipts := community_plugin_roots()
	payload := os.join_path(root, id)
	os.mkdir_all(payload) or { panic(err) }
	os.mkdir_all(receipts) or { panic(err) }
	manifest := '{"schemaVersion":1,"id":"${id}","name":"Broker Fixture","version":"1.0.0","files":["Main.qml","notes.txt"],"capabilities":{"processCommands":[],"networkHosts":[],"settings":{}${actions}}}'
	os.write_file(os.join_path(payload, 'manifest.json'), manifest) or { panic(err) }
	os.write_file(os.join_path(payload, 'Main.qml'), 'import QtQuick\nItem {}\n') or {
		panic(err)
	}
	os.write_file(os.join_path(payload, 'notes.txt'), 'payload note\n') or { panic(err) }
	hash := community_plugin_payload_hash(payload)
	assert hash.len > 0
	record := CommunityPluginReceipt{
		schema_version: 1
		id:             id
		name:           'Broker Fixture'
		version:        '1.0.0'
		source:         'https://example.invalid/${id}.git'
		revision:       'a'.repeat(40)
		enabled:        enabled
		trusted_hash:   if trusted { hash } else { '' }
	}
	os.write_file(os.join_path(receipts, '${id}.json'), json2.encode(record, escape_unicode: true) +
		'\n') or { panic(err) }
	return payload
}

fn test_plugin_broker_catalogue_is_typed_closed_and_separated() {
	for name in ['shell', 'run_command', 'sudo', 'exec', 'package_install'] {
		_, found := plugin_broker_action(name)
		assert !found, '${name} must not exist in the plugin broker catalogue'
	}
	read, read_found := plugin_broker_action('system_info')
	assert read_found && !read.mutating && read.action == 'desktop.observe'
	mutating, mut_found := plugin_broker_action('theme_set')
	assert mut_found && mutating.mutating && mutating.action == 'appearance.modify'
	// Every catalogue ABAC action must be a known policy action, and no
	// entry may map to shell or package authority.
	for a in plugin_broker_catalogue() {
		assert a.action in assistant_policy_actions
		assert a.action !in ['shell.execute', 'package.install', 'package.remove', 'filesystem.execute',
			'service.restart']
	}
}

fn test_plugin_broker_argv_validation() {
	argv := plugin_broker_argv('studio_jobs_list', '') or { panic(err) }
	assert argv == ['horneroctl', '--json', 'studio', 'jobs', 'list']
	if _ := plugin_broker_argv('theme_set', 'pampa; rm -rf /') {
		assert false, 'injection-shaped theme must be rejected'
	}
	if _ := plugin_broker_argv('shell', 'id') {
		assert false, 'there is no shell action'
	}
	if _ := plugin_broker_argv('plugin_file_read', 'notes.txt') {
		assert false, 'plugin_file_read must not produce an external argv'
	}
}

fn test_plugin_broker_declared_actions_additive_and_fail_closed() {
	// Every shipped manifest shape today: no `actions` key at all.
	old := json2.decode[map[string]json2.Any]('{"id":"x","capabilities":{"processCommands":["horneroctl"],"networkHosts":[],"settings":{}}}') or {
		panic(err)
	}
	declared := plugin_broker_declared_actions(old) or { panic(err) }
	assert declared.len == 0
	no_caps := json2.decode[map[string]json2.Any]('{"id":"x"}') or { panic(err) }
	assert (plugin_broker_declared_actions(no_caps) or { panic(err) }).len == 0
	with_actions := json2.decode[map[string]json2.Any]('{"capabilities":{"actions":["system_info","system_info","notify"]}}') or {
		panic(err)
	}
	assert plugin_broker_declared_actions(with_actions) or { panic(err) } == [
		'system_info',
		'notify',
	]
	malformed := json2.decode[map[string]json2.Any]('{"capabilities":{"actions":"system_info"}}') or {
		panic(err)
	}
	if _ := plugin_broker_declared_actions(malformed) {
		assert false, 'a non-array actions field must fail closed'
	}
	bad_entry := json2.decode[map[string]json2.Any]('{"capabilities":{"actions":[42]}}') or {
		panic(err)
	}
	if _ := plugin_broker_declared_actions(bad_entry) {
		assert false, 'a non-string action entry must fail closed'
	}
}

fn test_plugin_broker_file_target_rejects_traversal_and_symlinks() {
	root, saved := plugin_broker_test_env('paths')
	defer {
		plugin_broker_test_restore(saved)
		os.rmdir_all(root) or {}
	}
	payload := plugin_broker_test_install('broker-paths', ',"actions":["plugin_file_read"]',
		true, true)
	ok := plugin_broker_file_target(payload, 'notes.txt') or { panic(err) }
	assert ok == assistant_policy_canonical(os.join_path(payload, 'notes.txt'))
	for bad in ['../secret.txt', 'sub/../../secret.txt', '/etc/passwd', '', '.'] {
		if _ := plugin_broker_file_target(payload, bad) {
			assert false, 'path "${bad}" must be refused'
		}
	}
	// A symlink inside the payload pointing outside is an escape, both
	// as the target itself and as an intermediate directory.
	outside := os.join_path(root, 'outside')
	os.mkdir_all(outside) or { panic(err) }
	os.write_file(os.join_path(outside, 'secret.txt'), 'outside\n') or { panic(err) }
	os.symlink(os.join_path(outside, 'secret.txt'), os.join_path(payload, 'linked.txt')) or {
		panic(err)
	}
	if _ := plugin_broker_file_target(payload, 'linked.txt') {
		assert false, 'a symlinked target must be refused'
	}
	os.symlink(outside, os.join_path(payload, 'escape')) or { panic(err) }
	if _ := plugin_broker_file_target(payload, 'escape/secret.txt') {
		assert false, 'a symlinked directory escape must be refused'
	}
}

fn test_plugin_broker_exec_gates() {
	root, saved := plugin_broker_test_env('gates')
	defer {
		plugin_broker_test_restore(saved)
		os.rmdir_all(root) or {}
	}
	plugin_broker_test_install('broker-ok', ',"actions":["plugin_file_read","system_info","theme_set"]',
		true, true)

	// Happy path: declared read inside the plugin's own payload.
	read := plugin_broker_exec_report('broker-ok', 'plugin_file_read', 'notes.txt', false,
		false)
	assert read.ok
	assert read.message.contains('payload note')
	assert read.data['decision'] == 'allow'

	// Path traversal and absolute paths execute nothing.
	for bad in ['../receipts/broker-ok.json', '/etc/passwd'] {
		denied := plugin_broker_exec_report('broker-ok', 'plugin_file_read', bad, false,
			false)
		assert !denied.ok, 'traversal "${bad}" must be denied'
	}

	// Undeclared action: the manifest never asked for notify.
	undeclared := plugin_broker_exec_report('broker-ok', 'notify', 'hi', true, false)
	assert !undeclared.ok
	assert undeclared.data['decision'] == 'deny'

	// Unknown and shell-shaped actions do not exist.
	assert !plugin_broker_exec_report('broker-ok', 'shell', 'id', true, false).ok
	assert !plugin_broker_exec_report('broker-ok', 'run_command', 'id', true, false).ok

	// Declared mutation without --yes is refused at the CLI contract,
	// and with --yes it is still denied by the default ABAC policy
	// (no plugin appearance.modify rule exists in any preset).
	no_yes := plugin_broker_exec_report('broker-ok', 'theme_set', 'pampa', false, false)
	assert !no_yes.ok
	policy_denied := plugin_broker_exec_report('broker-ok', 'theme_set', 'pampa', true,
		false)
	assert !policy_denied.ok
	assert policy_denied.data['decision'] == 'deny'

	// check simulates the same decisions without executing.
	allowed := plugin_broker_check_report('broker-ok', 'system_info', '')
	assert allowed.ok && allowed.data['decision'] == 'allow'
	denied_check := plugin_broker_check_report('broker-ok', 'theme_set', 'pampa')
	assert !denied_check.ok && denied_check.data['decision'] == 'deny'

	// A traversal-shaped plugin id never reaches the filesystem.
	assert !plugin_broker_exec_report('../outside', 'system_info', '', false, false).ok
	// An uninstalled plugin has no broker access.
	assert !plugin_broker_exec_report('not-installed', 'system_info', '', false, false).ok
}

fn test_plugin_broker_exec_requires_enabled_and_trusted() {
	root, saved := plugin_broker_test_env('lifecycle')
	defer {
		plugin_broker_test_restore(saved)
		os.rmdir_all(root) or {}
	}
	plugin_broker_test_install('broker-disabled', ',"actions":["system_info"]', false, true)
	disabled := plugin_broker_exec_report('broker-disabled', 'system_info', '', false, false)
	assert !disabled.ok
	assert disabled.message.contains('disabled')

	plugin_broker_test_install('broker-untrusted', ',"actions":["system_info"]', true,
		false)
	untrusted := plugin_broker_exec_report('broker-untrusted', 'system_info', '', false,
		false)
	assert !untrusted.ok
	assert untrusted.message.contains('trust')

	// Old manifests (no capabilities.actions) install and enable as
	// before, but declare no actions: every broker call is denied.
	plugin_broker_test_install('broker-legacy', '', true, true)
	legacy := plugin_broker_exec_report('broker-legacy', 'system_info', '', false, false)
	assert !legacy.ok
	assert legacy.data['decision'] == 'deny'
	list := plugin_broker_list_report('broker-legacy')
	assert list.ok && list.data['count'] == '0'
}

fn test_plugin_broker_symlink_escape_denied_end_to_end() {
	root, saved := plugin_broker_test_env('symlink')
	defer {
		plugin_broker_test_restore(saved)
		os.rmdir_all(root) or {}
	}
	payload := plugin_broker_test_install('broker-link', ',"actions":["plugin_file_read"]',
		true, true)
	outside := os.join_path(root, 'outside')
	os.mkdir_all(outside) or { panic(err) }
	os.write_file(os.join_path(outside, 'secret.txt'), 'outside secret\n') or { panic(err) }
	os.symlink(outside, os.join_path(payload, 'escape')) or { panic(err) }
	denied := plugin_broker_exec_report('broker-link', 'plugin_file_read', 'escape/secret.txt',
		false, false)
	assert !denied.ok
	assert !denied.message.contains('outside secret')
}

fn test_plugin_broker_policy_baseline_is_read_only() {
	rules := assistant_policy_preset('read-only')
	base := AssistantPolicyRequest{
		principal:      'plugin'
		resource:       'any'
		workspace_root: '/tmp/plugin-payload'
		mode:           'agent'
		now:            1893456000
	}
	observe := assistant_policy_decide(rules, AssistantPolicyRequest{
		...base
		action: 'desktop.observe'
	})
	assert observe.decision == 'allow'
	for action in ['appearance.modify', 'notifications.send', 'desktop.window.focus', 'filesystem.write',
		'filesystem.delete', 'shell.execute', 'package.install'] {
		d := assistant_policy_decide(rules, AssistantPolicyRequest{
			...base
			action: action
		})
		assert d.decision == 'deny', '${action} must stay denied for the plugin principal'
	}
	// A user-written deny still wins over the baseline allow.
	mut custom := assistant_policy_preset('read-only')
	custom << AssistantPolicyRule{'plugin', 'desktop.observe', 'any', 'deny'}
	assert assistant_policy_decide(custom, AssistantPolicyRequest{
		...base
		action: 'desktop.observe'
	}).decision == 'deny'
}
