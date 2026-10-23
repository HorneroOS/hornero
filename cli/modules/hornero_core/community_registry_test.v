module hornero_core

import os
import time

fn community_registry_test_repeat(ch u8, count int) string {
	mut value := ''
	for _ in 0 .. count {
		value += ch.ascii_str()
	}
	return value
}

fn community_registry_test_index(version int, plugins string) string {
	return '{"schemaVersion":1,"indexVersion":${version},"generatedFrom":"${community_registry_test_repeat(`a`, 40)}","plugins":${plugins}}\n'
}

fn community_registry_test_new_root(suffix string) string {
	root := os.join_path(os.temp_dir(), 'hornero-community-registry-${os.getpid()}-${time.now().unix_nano()}-${suffix}')
	os.mkdir(root, os.MkdirParams{ mode: 0o700 }) or { panic(err) }
	return root
}

fn community_registry_test_entry(id string) string {
	return '{"id":"${id}","repository":"https://github.com/example/${id}.git","revision":"${community_registry_test_repeat(`b`, 40)}","sha256":"${community_registry_test_repeat(`c`, 64)}","authorKeyFingerprint":"sha256:${community_registry_test_repeat(`d`, 64)}"}'
}

fn test_community_registry_schema_accepts_sorted_pins_and_rejects_ambiguous_or_malformed_json() {
	raw := community_registry_test_index(3, '[${community_registry_test_entry('alpha')},${community_registry_test_entry('zulu')}]')
	index := community_registry_validate_index(raw) or {
		assert false, err.msg()
		return
	}
	assert index.schema_version == 1
	assert index.index_version == 3
	assert index.plugins.len == 2
	assert index.plugins[0].repository == 'https://github.com/example/alpha.git'

	duplicate_key := '{"schemaVersion":1,"schemaVersion":1,"indexVersion":3,"generatedFrom":"${community_registry_test_repeat(`a`, 40)}","plugins":[]}'
	if _ := community_registry_validate_index(duplicate_key) {
		assert false, 'duplicate JSON keys must fail closed'
	} else {
		assert err.msg().contains('duplicate JSON object key')
	}
	unsorted := community_registry_test_index(3, '[${community_registry_test_entry('zulu')},${community_registry_test_entry('alpha')}]')
	if _ := community_registry_validate_index(unsorted) {
		assert false, 'registry entries must use deterministic id order'
	} else {
		assert err.msg().contains('uniquely sorted')
	}
	mutable := community_registry_test_index(3, '[${community_registry_test_entry('alpha').replace(community_registry_test_repeat(`b`, 40), 'main')}]')
	if _ := community_registry_validate_index(mutable) {
		assert false, 'mutable source refs must fail closed'
	} else {
		assert err.msg().contains('full lowercase commit id')
	}
}

fn test_community_registry_integer_fits_the_native_int_range() {
	assert community_registry_integer(i64(max_int)) or { -1 } == max_int
	if i64(max_int) < 9223372036854775807 {
		too_large := i64(max_int) + 1
		if _ := community_registry_integer(too_large) {
			assert false, 'registry integer must not overflow the native int range'
		}
	}
}

fn test_community_registry_file_reads_enforce_the_bound() {
	root := community_registry_test_new_root('read-bound')
	defer { os.rmdir_all(root) or {} }
	path := os.join_path(root, 'bounded.json')
	os.write_file(path, '1234') or { panic(err) }
	if _ := community_registry_read_regular(path, 3) {
		assert false, 'registry reads must reject content beyond the configured limit'
	} else {
		assert err.msg().contains('exceeds its size limit')
	}
}

fn test_community_registry_listing_verifies_a_snapshot_and_rejects_rollback() {
	root := community_registry_test_new_root('snapshot')
	defer { os.rmdir_all(root) or {} }
	repository := os.join_path(root, 'plugins')
	community_dir := os.join_path(repository, 'community')
	bin_dir := os.join_path(root, 'bin')
	os.mkdir_all(community_dir) or { panic(err) }
	os.mkdir(bin_dir, os.MkdirParams{ mode: 0o700 }) or { panic(err) }
	index_path := os.join_path(community_dir, 'index.json')
	os.write_file(index_path, community_registry_test_index(2, '[]')) or { panic(err) }
	os.write_file(os.join_path(community_dir, 'index.json.minisig'), 'ephemeral test signature') or { panic(err) }
	key_path := os.join_path(root, 'registry.pub')
	os.write_file(key_path, 'ephemeral test public key') or { panic(err) }
	state_path := os.join_path(root, 'state', 'community-registry.json')
	replacement := os.join_path(root, 'replacement.json')
	os.write_file(replacement, community_registry_test_index(999, '[]')) or { panic(err) }
	fake_minisign := os.join_path(bin_dir, 'minisign')
	// The verifier replaces the caller-owned path while returning success. The
	// command must parse the bytes captured before verification, not reopen it.
	os.write_file(fake_minisign, '#!/bin/sh\n[ "$1" = "-V" ] && [ -s "$3" ] && [ -s "$5" ] && [ -s "$7" ] || exit 2\n/usr/bin/cat "$HORNERO_TEST_REGISTRY_REPLACEMENT" > "$HORNERO_TEST_REGISTRY_INDEX"\nexit 0\n') or {
		panic(err)
	}
	os.chmod(fake_minisign, 0o755) or { panic(err) }
	saved_path := os.getenv('PATH')
	saved_index := os.getenv('HORNERO_TEST_REGISTRY_INDEX')
	saved_replacement := os.getenv('HORNERO_TEST_REGISTRY_REPLACEMENT')
	os.setenv('PATH', '${bin_dir}:/usr/bin:/bin', true)
	os.setenv('HORNERO_TEST_REGISTRY_INDEX', index_path, true)
	os.setenv('HORNERO_TEST_REGISTRY_REPLACEMENT', replacement, true)
	defer {
		os.setenv('PATH', saved_path, true)
		if saved_index.len == 0 {
			os.unsetenv('HORNERO_TEST_REGISTRY_INDEX')
		} else {
			os.setenv('HORNERO_TEST_REGISTRY_INDEX', saved_index, true)
		}
		if saved_replacement.len == 0 {
			os.unsetenv('HORNERO_TEST_REGISTRY_REPLACEMENT')
		} else {
			os.setenv('HORNERO_TEST_REGISTRY_REPLACEMENT', saved_replacement, true)
		}
	}
	listed := community_plugin_registry_list_from(repository, key_path, state_path)
	assert listed.ok, listed.message
	assert listed.data['indexVersion'] == '2'
	state_after_list := os.read_file(state_path) or { '' }
	assert state_after_list == '{"indexVersion":2}\n'

	// Replace the index with a valid older signed payload and keep the test
	// verifier successful. The persistent high-water mark must reject it.
	os.write_file(index_path, community_registry_test_index(1, '[]')) or { panic(err) }
	os.write_file(fake_minisign, '#!/bin/sh\n[ "$1" = "-V" ] && [ -s "$3" ] && [ -s "$5" ] && [ -s "$7" ]\n') or {
		panic(err)
	}
	os.chmod(fake_minisign, 0o755) or { panic(err) }
	rolled_back := community_plugin_registry_list_from(repository, key_path, state_path)
	assert !rolled_back.ok
	assert rolled_back.message.contains('older than the highest accepted version 2')
	state_after_rollback := os.read_file(state_path) or { '' }
	assert state_after_rollback == '{"indexVersion":2}\n'
}

fn test_community_registry_listing_with_real_minisign_and_tamper_rejection() {
	minisign := find_on_path('minisign')
	if minisign.len == 0 {
		println('SKIP community registry cryptographic integration: minisign is unavailable')
		return
	}
	root := community_registry_test_new_root('minisign')
	defer { os.rmdir_all(root) or {} }
	repository := os.join_path(root, 'plugins')
	community_dir := os.join_path(repository, 'community')
	os.mkdir_all(community_dir) or { panic(err) }
	index_path := os.join_path(community_dir, 'index.json')
	signature_path := os.join_path(community_dir, 'index.json.minisig')
	public_key_path := os.join_path(root, 'registry.pub')
	secret_key_path := os.join_path(root, 'registry.key')
	state_path := os.join_path(root, 'state', 'community-registry.json')
	os.write_file(index_path, community_registry_test_index(7, '[]')) or { panic(err) }
	generated := run_exec(ExecSpec{
		prog:        minisign
		args:        ['-G', '-s', secret_key_path, '-p', public_key_path, '-W']
		timeout_sec: 10
	})
	assert generated.ok, generated.output
	signed := run_exec(ExecSpec{
		prog:        minisign
		args:        ['-S', '-s', secret_key_path, '-m', index_path, '-x', signature_path]
		timeout_sec: 10
	})
	assert signed.ok, signed.output
	accepted := community_plugin_registry_list_from(repository, public_key_path, state_path)
	assert accepted.ok, accepted.message
	assert accepted.data['indexVersion'] == '7'

	// Editing a valid file after signing must invalidate the detached signature.
	os.write_file(index_path, community_registry_test_index(8, '[]')) or { panic(err) }
	tampered := community_plugin_registry_list_from(repository, public_key_path, state_path)
	assert !tampered.ok
	assert tampered.message.contains('signature verification failed')
	state := os.read_file(state_path) or { '' }
	assert state == '{"indexVersion":7}\n'
}
