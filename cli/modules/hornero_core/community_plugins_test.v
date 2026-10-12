module hornero_core

import os

const community_plugins_test_root = '/tmp/hx-community-plugins-test'

fn community_plugins_test_reset() {
	os.rmdir_all(community_plugins_test_root) or {}
	os.mkdir_all(community_plugins_test_root) or { panic(err) }
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

fn community_plugins_test_env() map[string]string {
	keys := ['XDG_DATA_HOME', 'XDG_STATE_HOME', 'HORNERO_PLUGIN_VALIDATOR', 'HORNERO_GIT_BIN',
		'HORNERO_TEST_PLUGIN_SOURCE', 'HORNERO_TEST_REVISION']
	mut saved := map[string]string{}
	for key in keys { saved[key] = os.getenv(key) }
	os.setenv('XDG_DATA_HOME', '${community_plugins_test_root}/data', true)
	os.setenv('XDG_STATE_HOME', '${community_plugins_test_root}/state', true)
	return saved
}

fn community_plugins_test_write_executable(path string, content string) {
	os.write_file(path, content) or { panic(err) }
	os.chmod(path, 0o755) or { panic(err) }
}

fn community_plugins_test_fixture() string {
	root := '${community_plugins_test_root}/fixture'
	os.mkdir_all(root) or { panic(err) }
	os.write_file('${root}/manifest.json', '{"schemaVersion":1,"id":"example-clock","name":"Example Clock","version":"1.0.0"}') or {
		panic(err)
	}
	os.write_file('${root}/Main.qml', 'import QtQuick\nItem {}\n') or { panic(err) }
	return root
}

fn test_community_plugin_install_validate_list_remove_round_trip() {
	community_plugins_test_reset()
	saved := community_plugins_test_env()
	fixture := community_plugins_test_fixture()
	validator := '${community_plugins_test_root}/validator'
	git := '${community_plugins_test_root}/git'
	community_plugins_test_write_executable(validator, '#!/bin/sh\nexit 0\n')
	community_plugins_test_write_executable(git, '#!/usr/bin/env python3\nimport os, pathlib, shutil, sys\nargs=sys.argv[1:]\nif "clone" in args:\n dst=pathlib.Path(args[-1]); shutil.copytree(os.environ["HORNERO_TEST_PLUGIN_SOURCE"], dst); (dst/".git").mkdir()\nelif "rev-parse" in args:\n revision=os.environ.get("HORNERO_TEST_REVISION", "0123456789abcdef0123456789abcdef01234567")\n if revision == "fail": raise SystemExit(1)\n print(revision)\nelse:\n raise SystemExit(2)\n')
	os.setenv('HORNERO_PLUGIN_VALIDATOR', validator, true)
	os.setenv('HORNERO_GIT_BIN', git, true)
	os.setenv('HORNERO_TEST_PLUGIN_SOURCE', fixture, true)
	source := 'https://example.invalid/community/example-clock.git'
	installed := community_plugin_install_report(CommunityPluginOptions{ value: source, yes: true })
	assert installed.ok, installed.message
	assert os.is_file('${community_plugins_test_root}/data/hornero/plugins/example-clock/Main.qml')
	assert !os.exists('${community_plugins_test_root}/data/hornero/plugins/example-clock/.git')
	listed := community_plugin_list_report()
	assert listed.ok
	assert listed.data['plugins'].contains('Example Clock')
	removed := community_plugin_remove_report(CommunityPluginOptions{ value: 'example-clock', yes: true })
	assert removed.ok, removed.message
	assert !os.exists('${community_plugins_test_root}/data/hornero/plugins/example-clock')
	assert !os.exists('${community_plugins_test_root}/state/hornero/plugins/receipts/example-clock.json')
	community_plugins_test_restore(saved)
	os.rmdir_all(community_plugins_test_root) or {}
}

fn test_community_plugin_rejected_by_validator_is_not_installed() {
	community_plugins_test_reset()
	saved := community_plugins_test_env()
	fixture := community_plugins_test_fixture()
	validator := '${community_plugins_test_root}/validator'
	git := '${community_plugins_test_root}/git'
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
	assert !os.exists('${community_plugins_test_root}/data/hornero/plugins/example-clock')
	community_plugins_test_restore(saved)
	os.rmdir_all(community_plugins_test_root) or {}
}

fn test_community_plugin_install_refuses_missing_or_invalid_commit_revision() {
	community_plugins_test_reset()
	saved := community_plugins_test_env()
	fixture := community_plugins_test_fixture()
	validator := '${community_plugins_test_root}/validator'
	git := '${community_plugins_test_root}/git'
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
		assert !os.exists('${community_plugins_test_root}/data/hornero/plugins/example-clock')
	}
	community_plugins_test_restore(saved)
	os.rmdir_all(community_plugins_test_root) or {}
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
