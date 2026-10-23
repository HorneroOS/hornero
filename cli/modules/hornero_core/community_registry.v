module hornero_core

import os
import os.filelock
import time
import x.json2

const community_registry_key_path = '/etc/hornero/registry.pub'
const community_registry_relative_index = 'community/index.json'
const community_registry_relative_signature = 'community/index.json.minisig'
const community_registry_max_index_bytes = 16 * 1024 * 1024
const community_registry_max_signature_bytes = 4 * 1024
const community_registry_max_public_key_bytes = 1024

struct CommunityRegistryEntry {
pub:
	id                     string
	repository             string
	revision               string
	sha256                 string
	author_key_fingerprint string @[json: 'authorKeyFingerprint']
}

struct CommunityRegistryIndex {
pub:
	schema_version int    @[json: 'schemaVersion']
	index_version  int    @[json: 'indexVersion']
	generated_from string @[json: 'generatedFrom']
	plugins        []CommunityRegistryEntry
}

fn community_registry_scan_value(mut scanner json2.Scanner, mut token json2.Token, depth int) ! {
	if depth > 16 {
		return error('community index JSON nesting exceeds the supported limit')
	}
	match token.kind {
		.lcbr {
			token = scanner.next()!
			mut keys := map[string]bool{}
			if token.kind == .rcbr {
				token = scanner.next()!
				return
			}
			for {
				if token.kind != .str {
					return error('community index object key must be a string')
				}
				key := token.literal()
				if key in keys {
					return error('community index contains duplicate JSON object key: ${key}')
				}
				keys[key] = true
				token = scanner.next()!
				if token.kind != .colon {
					return error('community index object key is missing a colon')
				}
				token = scanner.next()!
				community_registry_scan_value(mut scanner, mut token, depth + 1)!
				if token.kind == .comma {
					token = scanner.next()!
					continue
				}
				if token.kind == .rcbr {
					token = scanner.next()!
					return
				}
				return error('community index object is missing a comma or closing brace')
			}
		}
		.lsbr {
			token = scanner.next()!
			if token.kind == .rsbr {
				token = scanner.next()!
				return
			}
			for {
				community_registry_scan_value(mut scanner, mut token, depth + 1)!
				if token.kind == .comma {
					token = scanner.next()!
					continue
				}
				if token.kind == .rsbr {
					token = scanner.next()!
					return
				}
				return error('community index array is missing a comma or closing bracket')
			}
		}
		.str, .int, .float, .bool, .null {
			token = scanner.next()!
		}
		else {
			return error('community index contains an unexpected JSON token')
		}
	}
}

fn community_registry_check_unique_json_keys(text string) ! {
	mut scanner := json2.new_scanner(text)
	mut token := scanner.next()!
	community_registry_scan_value(mut scanner, mut token, 0)!
	if token.kind != .eof {
		return error('community index contains data after the JSON value')
	}
}

fn community_registry_exact_fields(value map[string]json2.Any, fields []string) bool {
	if value.len != fields.len {
		return false
	}
	for field in fields {
		if field !in value {
			return false
		}
	}
	return true
}

fn community_registry_string(value json2.Any) ?string {
	match value {
		string { return value }
		else { return none }
	}
}

fn community_registry_integer(value json2.Any) ?int {
	match value {
		int { return value }
		f64 {
			// json2.Any decodes JSON numbers as f64 first; accept only exact,
			// non-negative integers in the range supported by this CLI schema.
			if value >= 0 && value <= 2147483647 && value == f64(int(value)) {
				return int(value)
			}
		}
		i64 {
			if value >= 0 {
				return int(value)
			}
		}
		i32 {
			if value >= 0 { return int(value) }
		}
		i16 {
			if value >= 0 { return int(value) }
		}
		i8 {
			if value >= 0 { return int(value) }
		}
		u8 { return int(value) }
		u16 { return int(value) }
		u32 {
			if u64(value) <= u64(max_int) { return int(value) }
		}
		u64 {
			if value <= u64(max_int) { return int(value) }
		}
		else {}
	}
	return none
}

fn community_registry_lower_hex(value string) bool {
	if value.len == 0 {
		return false
	}
	for ch in value.bytes() {
		if !(ch >= `0` && ch <= `9`) && !(ch >= `a` && ch <= `f`) {
			return false
		}
	}
	return true
}

fn community_registry_repository_valid(value string) bool {
	if !value.starts_with('https://') || value.contains('@') || value.contains('?') || value.contains('#')
		|| value.contains('\\') || value.ends_with('/') {
		return false
	}
	rest := value[8..]
	separator := rest.index('/') or { return false }
	host := rest[..separator]
	if host !in ['github.com', 'codeberg.org', 'gitlab.com'] {
		return false
	}
	segments := rest[separator + 1..].split('/')
	if segments.len < 2 {
		return false
	}
	for i, segment in segments {
		mut part := segment
		if i == segments.len - 1 && segment.ends_with('.git') {
			part = segment[..segment.len - 4]
		}
		if part.len == 0 || part in ['.', '..'] {
			return false
		}
		for ch in part.bytes() {
			if !ch.is_alnum() && ch !in [`_`, `-`, `.`] {
				return false
			}
		}
	}
	return true
}

fn community_registry_validate_index(raw string) !CommunityRegistryIndex {
	community_registry_check_unique_json_keys(raw)!
	decoded := json2.decode[map[string]json2.Any](raw) or {
		return error('community index is not valid JSON: ${err.msg()}')
	}
	if !community_registry_exact_fields(decoded, ['schemaVersion', 'indexVersion', 'generatedFrom',
		'plugins']) {
		return error('community index has unsupported or missing top-level fields')
	}
	schema_version := community_registry_integer(decoded['schemaVersion']) or {
		return error('community index schemaVersion must be an integer')
	}
	if schema_version != 1 {
		return error('community index schemaVersion is unsupported')
	}
	index_version := community_registry_integer(decoded['indexVersion']) or {
		return error('community index indexVersion must be a positive integer')
	}
	if index_version < 1 {
		return error('community index indexVersion must be a positive integer')
	}
	generated_from := community_registry_string(decoded['generatedFrom']) or {
		return error('community index generatedFrom must be a full commit id')
	}
	if generated_from.len !in [40, 64] || !community_registry_lower_hex(generated_from) {
		return error('community index generatedFrom must be a full lowercase commit id')
	}
	if decoded['plugins'] !is []json2.Any {
		return error('community index plugins must be an array')
	}
	mut plugins := []CommunityRegistryEntry{}
	mut previous_id := ''
	for i, raw_entry in (decoded['plugins'] as []json2.Any) {
		if raw_entry !is map[string]json2.Any {
			return error('community index plugins[${i}] must be an object')
		}
		entry := raw_entry as map[string]json2.Any
		if !community_registry_exact_fields(entry, ['id', 'repository', 'revision', 'sha256',
			'authorKeyFingerprint']) {
			return error('community index plugins[${i}] has unsupported or missing fields')
		}
		id := community_registry_string(entry['id']) or { return error('community index plugins[${i}].id is invalid') }
		if !community_plugin_valid_id(id) || (previous_id.len > 0 && id <= previous_id) {
			return error('community index plugin ids must be valid and uniquely sorted')
		}
		previous_id = id
		repository := community_registry_string(entry['repository']) or {
			return error('community index plugins[${i}].repository is invalid')
		}
		if !community_registry_repository_valid(repository) {
			return error('community index plugins[${i}].repository must use an approved HTTPS repository host')
		}
		revision := community_registry_string(entry['revision']) or {
			return error('community index plugins[${i}].revision is invalid')
		}
		if revision.len !in [40, 64] || !community_registry_lower_hex(revision) {
			return error('community index plugins[${i}].revision must be a full lowercase commit id')
		}
		payload_hash := community_registry_string(entry['sha256']) or {
			return error('community index plugins[${i}].sha256 is invalid')
		}
		if payload_hash.len != 64 || !community_registry_lower_hex(payload_hash) {
			return error('community index plugins[${i}].sha256 must be a lowercase SHA-256 digest')
		}
		fingerprint := community_registry_string(entry['authorKeyFingerprint']) or {
			return error('community index plugins[${i}].authorKeyFingerprint is invalid')
		}
		if !fingerprint.starts_with('sha256:') || fingerprint.len != 71
			|| !community_registry_lower_hex(fingerprint[7..]) {
			return error('community index plugins[${i}].authorKeyFingerprint must be sha256 plus 64 lowercase hex characters')
		}
		plugins << CommunityRegistryEntry{
			id:                     id
			repository:             repository
			revision:               revision
			sha256:                 payload_hash
			author_key_fingerprint: fingerprint
		}
	}
	return CommunityRegistryIndex{
		schema_version: schema_version
		index_version:  index_version
		generated_from: generated_from
		plugins:        plugins
	}
}

fn community_registry_read_regular(path string, maximum int) ![]u8 {
	if os.is_link(path) || !os.is_file(path) {
		return error('required community registry file is missing or is not a regular file: ${path}')
	}
	if os.file_size(path) > u64(maximum) {
		return error('community registry file exceeds its size limit: ${path}')
	}
	data := os.read_bytes(path) or { return error('cannot read community registry file ${path}: ${err.msg()}') }
	if data.len > maximum {
		return error('community registry file exceeds its size limit: ${path}')
	}
	return data
}

fn community_registry_verify_bytes(index []u8, signature []u8, public_key []u8) ! {
	minisign := find_on_path('minisign')
	if minisign.len == 0 {
		return error('minisign is required to verify the community registry; install the minisign package')
	}
	temp_dir := os.join_path(os.temp_dir(), 'hornero-registry-${os.getpid()}-${time.now().unix_nano()}')
	os.mkdir(temp_dir, os.MkdirParams{ mode: 0o700 }) or {
		return error('cannot create a private community registry verification directory: ${err.msg()}')
	}
	defer {
		os.rmdir_all(temp_dir) or {}
	}
	index_path := os.join_path(temp_dir, 'index.json')
	signature_path := os.join_path(temp_dir, 'index.json.minisig')
	key_path := os.join_path(temp_dir, 'registry.pub')
	os.write_file(index_path, index.bytestr()) or { return error('cannot stage community index for verification') }
	os.write_file(signature_path, signature.bytestr()) or { return error('cannot stage community index signature') }
	os.write_file(key_path, public_key.bytestr()) or { return error('cannot stage community registry key') }
	for path in [index_path, signature_path, key_path] {
		os.chmod(path, 0o600) or { return error('cannot restrict access to community registry verification files') }
	}
	result := run_exec(ExecSpec{
		prog:        minisign
		args:        ['-V', '-m', index_path, '-x', signature_path, '-p', key_path]
		timeout_sec: 15
	})
	if !result.ok {
		return error('community registry signature verification failed: ${result.output.trim_space()}')
	}
}

fn community_registry_high_water(path string) !int {
	if os.is_link(path) {
		return error('community registry rollback state is a symbolic link; refusing to trust it')
	}
	if !os.exists(path) {
		return 0
	}
	if !os.is_file(path) {
		return error('community registry rollback state is not a regular file')
	}
	raw := os.read_file(path) or { return error('cannot read community registry rollback state: ${err.msg()}') }
	community_registry_check_unique_json_keys(raw)!
	decoded := json2.decode[map[string]json2.Any](raw) or {
		return error('community registry rollback state is malformed')
	}
	if !community_registry_exact_fields(decoded, ['indexVersion']) {
		return error('community registry rollback state has unsupported fields')
	}
	version := community_registry_integer(decoded['indexVersion']) or {
		return error('community registry rollback state has an invalid indexVersion')
	}
	if version < 1 {
		return error('community registry rollback state has an invalid indexVersion')
	}
	return version
}

fn community_registry_write_high_water(path string, version int) ! {
	parent := os.dir(path)
	os.mkdir_all(parent, os.MkdirParams{ mode: 0o700 }) or {
		return error('cannot create community registry state directory: ${err.msg()}')
	}
	if os.is_link(parent) || os.is_link(path) {
		return error('community registry state path contains a symbolic link')
	}
	lock_path := '${path}.lock'
	if os.is_link(lock_path) {
		return error('community registry state lock is a symbolic link')
	}
	if !os.exists(lock_path) {
		os.write_file(lock_path, '') or { return error('cannot create community registry state lock') }
		os.chmod(lock_path, 0o600) or { return error('cannot restrict community registry state lock permissions') }
	}
	mut registry_lock := filelock.new_file(lock_path)
	registry_lock.acquire() or { return error('cannot acquire community registry state lock: ${err.msg()}') }
	defer {
		registry_lock.release()
	}
	current := community_registry_high_water(path)!
	if version < current {
		return error('refusing to replace community registry rollback state with an older version')
	}
	if version == current {
		return
	}
	tmp := '${path}.tmp-${os.getpid()}-${time.now().unix_nano()}'
	os.write_file(tmp, '{"indexVersion":${version}}\n') or {
		return error('cannot write community registry rollback state: ${err.msg()}')
	}
	os.chmod(tmp, 0o600) or {
		os.rm(tmp) or {}
		return error('cannot restrict community registry rollback state permissions')
	}
	os.rename(tmp, path) or {
		os.rm(tmp) or {}
		return error('cannot atomically save community registry rollback state: ${err.msg()}')
	}
}

fn community_plugin_registry_list_from(repository string, public_key_path string, state_path string) CommandResult {
	index_path := os.join_path(repository, community_registry_relative_index)
	signature_path := os.join_path(repository, community_registry_relative_signature)
	index_bytes := community_registry_read_regular(index_path, community_registry_max_index_bytes) or {
		return fail_result('plugin community list', err.msg())
	}
	signature_bytes := community_registry_read_regular(signature_path, community_registry_max_signature_bytes) or {
		return fail_result('plugin community list', err.msg())
	}
	key_bytes := community_registry_read_regular(public_key_path, community_registry_max_public_key_bytes) or {
		return fail_result('plugin community list', 'trusted Hornero community registry key is unavailable: ${err.msg()}')
	}
	community_registry_verify_bytes(index_bytes, signature_bytes, key_bytes) or {
		return fail_result('plugin community list', err.msg())
	}
	index := community_registry_validate_index(index_bytes.bytestr()) or {
		return fail_result('plugin community list', 'signed community index is invalid: ${err.msg()}')
	}
	current := community_registry_high_water(state_path) or {
		return fail_result('plugin community list', err.msg())
	}
	if index.index_version < current {
		return fail_result('plugin community list', 'community index version ${index.index_version} is older than the highest accepted version ${current}; refusing rollback')
	}
	community_registry_write_high_water(state_path, index.index_version) or {
		return fail_result('plugin community list', err.msg())
	}
	return ok_result('plugin community list', 'Verified community registry index v${index.index_version}. Registry publication is not a code review; extensions remain unsandboxed and require review before installation or enablement.', {
		'indexVersion':  index.index_version.str()
		'generatedFrom': index.generated_from
		'plugins':       json2.encode(index.plugins)
		'source':        plugin_catalog_source
	})
}

pub fn community_plugin_registry_list_report() CommandResult {
	if os.is_link(community_registry_key_path) || !os.is_file(community_registry_key_path) {
		return fail_result('plugin community list', 'trusted Hornero community registry key is not installed at ${community_registry_key_path}; refusing unsigned or untrusted community entries')
	}
	stage, _ := community_plugin_clone_catalog() or {
		return fail_result('plugin community list', err.msg())
	}
	defer {
		os.rmdir_all(stage) or {}
	}
	paths := resolve_paths()
	state_path := os.join_path(paths.state_dir, 'hornero', 'plugins', 'community-registry.json')
	return community_plugin_registry_list_from(stage, community_registry_key_path, state_path)
}
