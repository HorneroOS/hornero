module hornero_core

import os
import time

fn community_plugins_test_new_root(suffix string) string {
	root := os.join_path(os.temp_dir(), 'hornero-community-plugins-${os.getpid()}-${time.now().unix_milli()}-${suffix}')
	if os.exists(root) {
		panic('refusing to reuse an existing plugin test directory: ${root}')
	}
	os.mkdir_all(root) or { panic(err) }
	return root
}

fn community_plugins_test_restore(saved map[string]string) {
	for key, value in saved {
		if value.len == 0 {
			os.unsetenv(key)
		} else {
			os.setenv(key, value, true)
		}
	}
}

fn community_plugins_test_env(root string) map[string]string {
	keys := ['XDG_DATA_HOME', 'XDG_STATE_HOME', 'HORNERO_PLUGIN_VALIDATOR', 'HORNERO_GIT_BIN',
		'HORNERO_TEST_PLUGIN_SOURCE', 'HORNERO_TEST_REVISION', 'HORNERO_PLUGIN_TEST_ROOT']
	mut saved := map[string]string{}
	for key in keys { saved[key] = os.getenv(key) }
	os.setenv('HORNERO_PLUGIN_TEST_ROOT', root, true)
	os.setenv('XDG_DATA_HOME', '${root}/data', true)
	os.setenv('XDG_STATE_HOME', '${root}/state', true)
	return saved
}

fn community_plugins_test_write_executable(path string, content string) {
	os.write_file(path, content) or { panic(err) }
	os.chmod(path, 0o755) or { panic(err) }
}

fn community_plugins_test_fixture(root string) string {
	fixture := os.join_path(root, 'fixture')
	os.mkdir_all(fixture) or { panic(err) }
	os.write_file('${fixture}/manifest.json', '{"schemaVersion":1,"id":"example-clock","name":"Example Clock","version":"1.0.0"}') or {
		panic(err)
	}
	os.write_file('${fixture}/Main.qml', 'import QtQuick\nItem {}\n') or { panic(err) }
	return fixture
}

fn test_community_plugin_install_validate_list_remove_round_trip() {
	root := community_plugins_test_new_root('round-trip')
	saved := community_plugins_test_env(root)
	defer {
		community_plugins_test_restore(saved)
		os.rmdir_all(root) or {}
	}
	fixture := community_plugins_test_fixture(root)
	validator := os.join_path(root, 'validator')
	git := os.join_path(root, 'git')
	community_plugins_test_write_executable(validator, '#!/bin/sh\nexit 0\n')
	community_plugins_test_write_executable(git, '#!/usr/bin/env python3\nimport os, pathlib, shutil, sys\nargs=sys.argv[1:]\nif "clone" in args:\n dst=pathlib.Path(args[-1]); shutil.copytree(os.environ["HORNERO_TEST_PLUGIN_SOURCE"], dst); (dst/".git").mkdir()\nelif "rev-parse" in args:\n revision=os.environ.get("HORNERO_TEST_REVISION", "0123456789abcdef0123456789abcdef01234567")\n if revision == "fail": raise SystemExit(1)\n print(revision)\nelse:\n raise SystemExit(2)\n')
	os.setenv('HORNERO_PLUGIN_VALIDATOR', validator, true)
	os.setenv('HORNERO_GIT_BIN', git, true)
	os.setenv('HORNERO_TEST_PLUGIN_SOURCE', fixture, true)
	source := 'https://example.invalid/community/example-clock.git'
	installed := community_plugin_install_report(CommunityPluginOptions{ value: source, yes: true })
	assert installed.ok, installed.message
	assert os.is_file('${root}/data/hornero/plugins/example-clock/Main.qml')
	assert !os.exists('${root}/data/hornero/plugins/example-clock/.git')
	listed := community_plugin_list_report()
	assert listed.ok
	assert listed.data['plugins'].contains('Example Clock')
	removed := community_plugin_remove_report(CommunityPluginOptions{ value: 'example-clock', yes: true })
	assert removed.ok, removed.message
	assert !os.exists('${root}/data/hornero/plugins/example-clock')
	assert !os.exists('${root}/state/hornero/plugins/receipts/example-clock.json')
}

fn test_community_plugin_rejected_by_validator_is_not_installed() {
	root := community_plugins_test_new_root('validator-reject')
	saved := community_plugins_test_env(root)
	defer {
		community_plugins_test_restore(saved)
		os.rmdir_all(root) or {}
	}
	fixture := community_plugins_test_fixture(root)
	validator := os.join_path(root, 'validator')
	git := os.join_path(root, 'git')
	community_plugins_test_write_executable(validator, '#!/bin/sh\necho contract violation >&2\nexit 1\n')
	community_plugins_test_write_executable(git, '#!/usr/bin/env python3\nimport os, pathlib, shutil, sys\nargs=sys.argv[1:]\nif "clone" in args:\n dst=pathlib.Path(args[-1]); shutil.copytree(os.environ["HORNERO_TEST_PLUGIN_SOURCE"], dst); (dst/".git").mkdir()\nelif "rev-parse" in args:\n print("0123456789abcdef0123456789abcdef01234567")\n')
	os.setenv('HORNERO_PLUGIN_VALIDATOR', validator, true)
	os.setenv('HORNERO_GIT_BIN', git, true)
	os.setenv('HORNERO_TEST_PLUGIN_SOURCE', fixture, true)
	r := community_plugin_install_report(CommunityPluginOptions{
		value: 'https://example.invalid/community/example-clock.git'
		yes:   true
	})
	assert !r.ok
	assert r.message.contains('contract violation')
	assert !os.exists('${root}/data/hornero/plugins/example-clock')
}

fn test_community_plugin_install_refuses_missing_or_invalid_commit_revision() {
	root := community_plugins_test_new_root('revision-reject')
	saved := community_plugins_test_env(root)
	defer {
		community_plugins_test_restore(saved)
		os.rmdir_all(root) or {}
	}
	fixture := community_plugins_test_fixture(root)
	validator := os.join_path(root, 'validator')
	git := os.join_path(root, 'git')
	community_plugins_test_write_executable(validator, '#!/bin/sh\nexit 0\n')
	community_plugins_test_write_executable(git, '#!/usr/bin/env python3\nimport os, pathlib, shutil, sys\nargs=sys.argv[1:]\nif "clone" in args:\n dst=pathlib.Path(args[-1]); shutil.copytree(os.environ["HORNERO_TEST_PLUGIN_SOURCE"], dst); (dst/".git").mkdir()\nelif "rev-parse" in args:\n revision=os.environ.get("HORNERO_TEST_REVISION", "fail")\n if revision == "fail": raise SystemExit(1)\n print(revision)\nelse:\n raise SystemExit(2)\n')
	os.setenv('HORNERO_PLUGIN_VALIDATOR', validator, true)
	os.setenv('HORNERO_GIT_BIN', git, true)
	os.setenv('HORNERO_TEST_PLUGIN_SOURCE', fixture, true)
	for revision in ['fail', 'not-a-commit'] {
		os.setenv('HORNERO_TEST_REVISION', revision, true)
		result := community_plugin_install_report(CommunityPluginOptions{
			value: 'https://example.invalid/community/example-clock.git'
			yes:   true
		})
		assert !result.ok
		assert result.message.contains('valid Git commit')
		assert !os.exists('${root}/data/hornero/plugins/example-clock')
	}
}

fn test_community_plugin_mutations_require_yes_and_sources_are_restricted() {
	assert !community_plugin_install_report(CommunityPluginOptions{
		value: 'https://example.invalid/plugin.git'
	}).ok
	assert !community_plugin_install_report(CommunityPluginOptions{
		value:   'https://user:password@example.invalid/plugin.git'
		dry_run: true
	}).ok
	assert !community_plugin_remove_report(CommunityPluginOptions{ value: 'example-clock' }).ok
}

fn test_community_plugin_new_writes_complete_mit_scaffold_and_refuses_overwrite() {
	base := community_plugins_test_new_root('new-scaffold')
	defer {
		os.rmdir_all(base) or {}
	}
	destination := os.join_path(base, 'custom-location')
	preview := community_plugin_new_report(CommunityPluginOptions{
		value:   'example-clock'
		dry_run: true
	}, 'Example Clock', 'Your Name', 'A clock widget', 'MIT', destination)
	assert preview.ok
	assert !os.exists(destination)
	created := community_plugin_new_report(CommunityPluginOptions{
		value: 'example-clock'
		yes:   true
	}, 'Example Clock', 'Your Name', 'A clock widget', 'MIT', destination)
	assert created.ok
	assert os.is_file(os.join_path(destination, 'manifest.json'))
	assert os.is_file(os.join_path(destination, 'Main.qml'))
	assert os.is_file(os.join_path(destination, 'README.md'))
	assert os.is_file(os.join_path(destination, 'LICENSE'))
	manifest := os.read_file(os.join_path(destination, 'manifest.json')) or {
		assert false, err.msg()
		return
	}
	assert manifest.contains('example-clock')
	assert manifest.contains('MIT')
	assert manifest.contains('Main.qml')
	readme := os.read_file(os.join_path(destination, 'README.md')) or { '' }
	assert readme.contains('horneroctl plugin validate .')
	assert !readme.contains('horneroctl plugin validate ./example-clock')
	assert os.read_file(os.join_path(destination, 'LICENSE')) or { '' }.contains('MIT License')
	assert !community_plugin_new_report(CommunityPluginOptions{
		value: 'example-clock'
		yes:   true
	}, 'Example Clock', 'Your Name', 'A clock widget', 'MIT', destination).ok
}

fn test_community_plugin_new_refuses_dangling_symlink_destination() {
	base := community_plugins_test_new_root('dangling-destination')
	defer {
		os.rmdir_all(base) or {}
	}
	destination := os.join_path(base, 'occupied')
	os.symlink(os.join_path(base, 'missing-target'), destination) or { panic(err) }
	assert community_plugin_path_occupied(destination)
	result := community_plugin_new_report(CommunityPluginOptions{
		value: 'example-clock'
		yes:   true
	}, 'Example Clock', 'Your Name', 'A clock widget', 'MIT', destination)
	assert !result.ok
	assert os.is_link(destination)
	assert !os.exists(os.join_path(base, 'missing-target'))
}

fn test_community_plugin_publish_never_replaces_existing_directory() {
	base := community_plugins_test_new_root('no-replace-publish')
	defer {
		os.rmdir_all(base) or {}
	}
	source := os.join_path(base, 'staged')
	destination := os.join_path(base, 'destination')
	os.mkdir(source) or { panic(err) }
	os.write_file(os.join_path(source, 'owned.txt'), 'staged') or { panic(err) }
	os.mkdir(destination) or { panic(err) }
	os.write_file(os.join_path(destination, 'keep.txt'), 'preserve') or { panic(err) }
	mut refused := false
	community_plugin_rename_noreplace(source, destination) or { refused = true }
	assert refused
	assert os.read_file(os.join_path(destination, 'keep.txt')) or { '' } == 'preserve'
	assert os.is_file(os.join_path(source, 'owned.txt'))
}

fn test_community_plugin_new_validates_license_metadata_and_output_parent() {
	assert !community_plugin_new_report(CommunityPluginOptions{
		value: 'example-clock'
		yes:   true
	}, 'Example Clock', 'Your Name', 'A clock widget', 'GPL-3.0', '/tmp/plugin-new').ok
	assert !community_plugin_new_report(CommunityPluginOptions{
		value: 'example-clock'
		yes:   true
	}, 'Example Clock', 'Your Name', 'A clock widget', 'MIT', '/tmp/no-such-parent-hornero/plugin').ok
}

fn test_community_plugin_enable_disable_lifecycle() {
	root := community_plugins_test_new_root('lifecycle')
	saved := community_plugins_test_env(root)
	defer {
		community_plugins_test_restore(saved)
		os.rmdir_all(root) or {}
	}
	fixture := community_plugins_test_fixture(root)
	validator := os.join_path(root, 'validator')
	git := os.join_path(root, 'git')
	community_plugins_test_write_executable(validator, '#!/bin/sh\nexit 0\n')
	community_plugins_test_write_executable(git, '#!/usr/bin/env python3\nimport os, pathlib, shutil, sys\nargs=sys.argv[1:]\nif "clone" in args:\n dst=pathlib.Path(args[-1]); shutil.copytree(os.environ["HORNERO_TEST_PLUGIN_SOURCE"], dst); (dst/".git").mkdir()\nelif "rev-parse" in args:\n print(os.environ.get("HORNERO_TEST_REVISION", "0123456789abcdef0123456789abcdef01234567"))\nelse:\n raise SystemExit(2)\n')
	os.setenv('HORNERO_PLUGIN_VALIDATOR', validator, true)
	os.setenv('HORNERO_GIT_BIN', git, true)
	os.setenv('HORNERO_TEST_PLUGIN_SOURCE', fixture, true)
	installed := community_plugin_install_report(CommunityPluginOptions{
		value: 'https://example.invalid/community/example-clock.git'
		yes:   true
	})
	assert installed.ok, installed.message
	// Fresh installs start disabled.
	listed := community_plugin_list_report()
	assert listed.data['plugins'].contains('"enabled":false'), listed.data['plugins']
	// Mutations require consent.
	refused := community_plugin_enable_report(CommunityPluginOptions{ value: 'example-clock' })
	assert !refused.ok
	preview := community_plugin_enable_report(CommunityPluginOptions{
		value:   'example-clock'
		dry_run: true
	})
	assert preview.ok
	still := community_plugin_list_report()
	assert still.data['plugins'].contains('"enabled":false')
	assert still.data['plugins'].contains('"trust":"untrusted"'), still.data['plugins']
	// Local trust model (shell#251): a non-official plugin cannot be
	// enabled until trust is recorded for the exact current payload.
	untrusted := community_plugin_enable_report(CommunityPluginOptions{
		value: 'example-clock'
		yes:   true
	})
	assert !untrusted.ok && untrusted.message.contains('untrusted'), untrusted.message
	trust_refused := community_plugin_trust_report(CommunityPluginOptions{ value: 'example-clock' })
	assert !trust_refused.ok
	trusted := community_plugin_trust_report(CommunityPluginOptions{
		value: 'example-clock'
		yes:   true
	})
	assert trusted.ok, trusted.message
	// Trust records provenance but never enables by itself.
	trust_listed := community_plugin_list_report()
	assert trust_listed.data['plugins'].contains('"trust":"trusted"'), trust_listed.data['plugins']
	assert trust_listed.data['plugins'].contains('"enabled":false'), trust_listed.data['plugins']
	enabled := community_plugin_enable_report(CommunityPluginOptions{
		value: 'example-clock'
		yes:   true
	})
	assert enabled.ok, enabled.message
	after := community_plugin_list_report()
	assert after.data['plugins'].contains('"enabled":true'), after.data['plugins']
	again := community_plugin_enable_report(CommunityPluginOptions{
		value: 'example-clock'
		yes:   true
	})
	assert again.ok && again.message.contains('already enabled')
	disabled := community_plugin_disable_report(CommunityPluginOptions{
		value: 'example-clock'
		yes:   true
	})
	assert disabled.ok, disabled.message
	final := community_plugin_list_report()
	assert final.data['plugins'].contains('"enabled":false')
	// A payload change after trust invalidates it (stale-trust) and
	// blocks enabling until trust is recorded again.
	payload_root, _ := community_plugin_roots()
	manifest_path := os.join_path(payload_root, 'example-clock', 'manifest.json')
	orig_manifest := os.read_file(manifest_path) or { '' }
	os.write_file(manifest_path, orig_manifest.replace('1.0.0', '6.6.6')) or {
		assert false, 'cannot tamper payload'
	}
	stale := community_plugin_enable_report(CommunityPluginOptions{
		value: 'example-clock'
		yes:   true
	})
	assert !stale.ok && stale.message.contains('stale-trust'), stale.message
	stale_listed := community_plugin_list_report()
	assert stale_listed.data['plugins'].contains('"trust":"stale-trust"'), stale_listed.data['plugins']
}

fn test_community_plugin_enable_unknown_and_invalid_payload() {
	root := community_plugins_test_new_root('lifecycle-bad')
	saved := community_plugins_test_env(root)
	defer {
		community_plugins_test_restore(saved)
		os.rmdir_all(root) or {}
	}
	unknown := community_plugin_enable_report(CommunityPluginOptions{ value: 'nope', yes: true })
	assert !unknown.ok && unknown.message.contains('no Hornero receipt')
	bad_id := community_plugin_enable_report(CommunityPluginOptions{ value: '../evil', yes: true })
	assert !bad_id.ok
}

fn test_plugin_catalog_entries_and_payload_hash() {
	catalog := '{"schemaVersion":1,"plugins":[{"id":"hornero-pomodoro","name":"Hornero Pomodoro","version":"1.0.0","trust":"official","placement":"bar","path":"plugins/hornero-pomodoro","sha256":"abc"}]}'
	entries := plugin_catalog_entries(catalog)
	assert entries.len == 1
	assert entries[0].id == 'hornero-pomodoro'
	assert entries[0].trust == 'official'
	assert plugin_catalog_entries('not json').len == 0
	assert plugin_catalog_entries('{}').len == 0
	// Hash framing must match scripts/gen_catalog.py in HorneroOS/plugins.
	dir := '/tmp/hx-catalog-hash-fixture'
	os.mkdir_all(dir) or { panic('mkdir') }
	os.write_file('${dir}/manifest.json', '{"files":["Main.qml"]}') or { panic('write') }
	os.write_file('${dir}/Main.qml', 'import QtQuick\n') or { panic('write') }
	manifest := community_plugin_manifest(dir) or { panic('manifest') }
	digest := plugin_payload_sha256(dir, manifest)
	assert digest.len == 64
	assert digest == plugin_payload_sha256(dir, manifest)
	os.rmdir_all(dir) or {}
}

fn test_catalog_update_requires_catalogue_source() {
	root := community_plugins_test_new_root('upd-src')
	saved := community_plugins_test_env(root)
	data := os.join_path(root, 'data', 'hornero', 'plugins')
	receipts := os.join_path(root, 'state', 'hornero', 'plugins', 'receipts')
	os.mkdir_all(os.join_path(data, 'hornero-pomodoro')) or { panic(err) }
	os.mkdir_all(receipts) or { panic(err) }
	receipt := '{"schema_version":1,"id":"hornero-pomodoro","name":"Hornero Pomodoro","version":"1.0.0","source":"https://example.com/other.git","revision":"local","installed_at":"1","enabled":false}'
	os.write_file(os.join_path(receipts, 'hornero-pomodoro.json'), receipt) or { panic(err) }
	res := community_plugin_catalog_update_report('hornero-pomodoro', CommunityPluginOptions{
		yes: true
	})
	assert !res.ok
	assert res.message.contains('not installed from the official catalogue')
	community_plugins_test_restore(saved)
	os.rmdir_all(root) or {}
}

fn test_catalog_rollback_without_previous_kept_refuses() {
	root := community_plugins_test_new_root('rb-none')
	saved := community_plugins_test_env(root)
	res := community_plugin_catalog_rollback_report('hornero-pomodoro', CommunityPluginOptions{
		yes: true
	})
	assert !res.ok
	assert res.message.contains('nothing to roll back to')
	community_plugins_test_restore(saved)
	os.rmdir_all(root) or {}
}

fn test_catalog_update_requires_yes() {
	res := community_plugin_catalog_update_report('hornero-pomodoro', CommunityPluginOptions{})
	assert !res.ok
	assert res.message.contains('without --yes')
}

fn test_catalog_rollback_restores_kept_payload() {
	root := community_plugins_test_new_root('rb-ok')
	saved := community_plugins_test_env(root)
	data := os.join_path(root, 'data', 'hornero', 'plugins')
	receipts := os.join_path(root, 'state', 'hornero', 'plugins', 'receipts')
	current := os.join_path(data, 'hornero-pomodoro')
	previous := '${current}.previous'
	for dir, ver in {
		current:  '9.9.9'
		previous: '1.0.0'
	} {
		os.mkdir_all(dir) or { panic(err) }
		manifest := '{"schemaVersion":1,"id":"hornero-pomodoro","name":"Hornero Pomodoro","version":"${ver}","description":"d","author":"a","license":"MIT","entrypoint":"Main.qml","files":["Main.qml"],"capabilities":{"processCommands":[],"networkHosts":[],"settings":{}}}'
		os.write_file(os.join_path(dir, 'manifest.json'), manifest) or { panic(err) }
		os.write_file(os.join_path(dir, 'Main.qml'), 'import QtQuick\nItem {}\n') or { panic(err) }
	}
	os.mkdir_all(receipts) or { panic(err) }
	receipt := '{"schema_version":1,"id":"hornero-pomodoro","name":"Hornero Pomodoro","version":"9.9.9","source":"${plugin_catalog_source}","revision":"local","installed_at":"1","enabled":false}'
	os.write_file(os.join_path(receipts, 'hornero-pomodoro.json'), receipt) or { panic(err) }
	validator := os.join_path(root, 'validator.py')
	os.write_file(validator, '#!/bin/sh\nexit 0\n') or { panic(err) }
	os.chmod(validator, 0o755) or { panic(err) }
	os.setenv('HORNERO_PLUGIN_VALIDATOR', validator, true)
	res := community_plugin_catalog_rollback_report('hornero-pomodoro', CommunityPluginOptions{
		yes: true
	})
	assert res.ok, res.message
	restored := os.read_file(os.join_path(current, 'manifest.json')) or { panic(err) }
	assert restored.contains('"version":"1.0.0"') || restored.contains('"version": "1.0.0"')
	assert !os.exists(previous)
	saved2 := os.getenv('HORNERO_PLUGIN_VALIDATOR')
	_ = saved2
	os.unsetenv('HORNERO_PLUGIN_VALIDATOR')
	community_plugins_test_restore(saved)
	os.rmdir_all(root) or {}
}
