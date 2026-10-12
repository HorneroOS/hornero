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
	destination := os.join_path(base, 'example-clock')
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
	assert os.read_file(os.join_path(destination, 'LICENSE')) or { '' }.contains('MIT License')
	assert !community_plugin_new_report(CommunityPluginOptions{
		value: 'example-clock'
		yes:   true
	}, 'Example Clock', 'Your Name', 'A clock widget', 'MIT', destination).ok
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
