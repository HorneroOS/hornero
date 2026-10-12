module hornero_core

import os
import time
import x.json2

pub struct CommunityPluginOptions {
pub:
	value   string
	dry_run bool
	yes     bool
}

struct CommunityPluginReceipt {
	schema_version int
	id             string
	name           string
	version        string
	source         string
	revision       string
	installed_at   string
}

struct CommunityPluginListEntry {
	id        string
	name      string
	version   string
	installed bool
}

pub fn resolve_community_plugin_validator() string {
	override := os.getenv('HORNERO_PLUGIN_VALIDATOR')
	if override.len > 0 { return override }
	installed := '/usr/lib/hornero/hornero-shell-plugin-validate'
	if os.is_file(installed) { return installed }
	return find_on_path('hornero-shell-plugin-validate')
}

fn community_plugin_roots() (string, string) {
	paths := resolve_paths()
	return os.join_path(paths.data_dir, 'hornero', 'plugins'), os.join_path(paths.state_dir,
		'hornero', 'plugins', 'receipts')
}

fn community_plugin_valid_id(id string) bool {
	first := id.len > 0 && ((id[0] >= `a` && id[0] <= `z`) || (id[0] >= `0` && id[0] <= `9`))
	if id.len == 0 || id.len > 48 || !first || id[id.len - 1] == `-` {
		return false
	}
	for c in id.bytes() {
		if !(c >= `a` && c <= `z`) && !(c >= `0` && c <= `9`) && c != `-` { return false }
	}
	return true
}

fn community_plugin_safe_source(source string) bool {
	if !source.starts_with('https://') || source.contains('@') || source.contains('?')
		|| source.contains('#') || source.contains('\\') || source.contains('..') {
		return false
	}
	for c in source.bytes() {
		if !(c.is_alnum() || c in [`:`, `/`, `.`, `-`, `_`, `+`]) { return false }
	}
	return source.count('/') >= 3
}

fn community_plugin_string(value json2.Any) ?string {
	match value {
		string { return value }
		else { return none }
	}
}

fn community_plugin_manifest(path string) !map[string]json2.Any {
	raw := os.read_file(os.join_path(path, 'manifest.json')) or {
		return error('plugin manifest.json is missing or unreadable')
	}
	return json2.decode[map[string]json2.Any](raw) or {
		return error('plugin manifest.json is not valid JSON: ${err.msg()}')
	}
}

fn community_plugin_run_validator(path string) !string {
	validator := resolve_community_plugin_validator()
	if validator.len == 0 || !os.is_file(validator) {
		return error('Hornero Shell plugin validator is not installed. Install a compatible hornero-shell package first.')
	}
	report := run_exec(ExecSpec{ prog: validator, args: [path], timeout_sec: 20 })
	if !report.ok { return error('plugin validation failed: ${report.output}') }
	return report.output
}

pub fn community_plugin_validate_report(opts CommunityPluginOptions) CommandResult {
	if opts.value.len == 0 {
		return fail_result('plugin validate', 'missing package directory.\nExample: horneroctl plugin validate ./my-plugin')
	}
	path := os.abs_path(opts.value)
	if !os.is_dir(path) {
		return fail_result('plugin validate', 'package directory not found: ${path}')
	}
	result := community_plugin_run_validator(path) or {
		return fail_result('plugin validate', err.msg())
	}
	return ok_result('plugin validate', if result.len > 0 {
		result
	} else {
		'plugin package is valid'
	}, {
		'path': path
	})
}

pub fn community_plugin_install_report(opts CommunityPluginOptions) CommandResult {
	if opts.value.len == 0 {
		return fail_result('plugin install', 'missing HTTPS Git URL.\nExample: horneroctl plugin install https://github.com/example/my-plugin.git --dry-run')
	}
	if !opts.dry_run && !opts.yes {
		return fail_result('plugin install', 'refusing to install without --yes (preview with --dry-run).\nExample: horneroctl plugin install https://github.com/example/my-plugin.git --dry-run')
	}
	if !community_plugin_safe_source(opts.value) {
		return fail_result('plugin install', 'source must be an HTTPS Git URL without credentials, query strings, or fragments')
	}
	root, _ := community_plugin_roots()
	if opts.dry_run {
		return ok_result('plugin install', 'would clone, validate, and copy the inert plugin package under ${root}; this does not load or sandbox its QML.', {
			'dry_run': 'true'
			'source':  opts.value
		})
	}
	git := if os.getenv('HORNERO_GIT_BIN').len > 0 {
		os.getenv('HORNERO_GIT_BIN')
	} else {
		find_on_path('git')
	}
	env := find_on_path('env')
	if git.len == 0 || env.len == 0 {
		return fail_result('plugin install', 'git and env are required to install a plugin')
	}
	os.mkdir_all(root) or { return fail_result('plugin install', 'cannot create plugin data directory: ${err.msg()}') }
	stage := os.join_path(root, '.staging-${os.getpid()}-${time.now().unix_milli()}')
	clone := run_exec(ExecSpec{
		prog:        env
		args:        ['GIT_TERMINAL_PROMPT=0', 'GIT_CONFIG_NOSYSTEM=1', 'GIT_CONFIG_GLOBAL=/dev/null',
			git, '-c', 'core.hooksPath=/dev/null', '-c', 'credential.helper=', '-c',
			'protocol.allow=never', '-c', 'protocol.https.allow=always', 'clone', '--depth', '1',
			'--no-tags', '--', opts.value, stage]
		timeout_sec: 120
	})
	if !clone.ok {
		os.rmdir_all(stage) or {}
		return fail_result('plugin install', 'git clone failed: ${clone.output}')
	}
	revision_result := run_exec(ExecSpec{ prog: git, args: ['-C', stage, 'rev-parse', 'HEAD'], timeout_sec: 10 })
	revision := if revision_result.ok { revision_result.output.trim_space() } else { '' }
	if os.is_dir(os.join_path(stage, '.git')) {
		os.rmdir_all(os.join_path(stage, '.git')) or {
			os.rmdir_all(stage) or {}
			return fail_result('plugin install', 'cannot remove Git metadata from staged package: ${err.msg()}')
		}
	}
	community_plugin_run_validator(stage) or {
		os.rmdir_all(stage) or {}
		return fail_result('plugin install', err.msg())
	}
	manifest := community_plugin_manifest(stage) or {
		os.rmdir_all(stage) or {}
		return fail_result('plugin install', err.msg())
	}
	id := community_plugin_string(manifest['id'] or { json2.Any('') }) or { '' }
	name := community_plugin_string(manifest['name'] or { json2.Any('') }) or { '' }
	version := community_plugin_string(manifest['version'] or { json2.Any('') }) or { '' }
	if !community_plugin_valid_id(id) || name.len == 0 || version.len == 0 {
		os.rmdir_all(stage) or {}
		return fail_result('plugin install', 'validated manifest is missing a usable id, name, or version')
	}
	destination := os.join_path(root, id)
	if os.exists(destination) || os.is_link(destination) {
		os.rmdir_all(stage) or {}
		return fail_result('plugin install', 'plugin ${id} already has a data directory; remove it explicitly before reinstalling')
	}
	os.rename(stage, destination) or {
		os.rmdir_all(stage) or {}
		return fail_result('plugin install', 'cannot install validated package: ${err.msg()}')
	}
	receipt := CommunityPluginReceipt{1, id, name, version, opts.value, revision, time.now().unix_milli().str()}
	_, receipts := community_plugin_roots()
	os.mkdir_all(receipts) or {
		os.rmdir_all(destination) or {}
		return fail_result('plugin install', 'cannot create plugin receipt directory: ${err.msg()}')
	}
	receipt_path := os.join_path(receipts, '${id}.json')
	tmp := '${receipt_path}.tmp-${time.now().unix_milli()}'
	os.write_file(tmp, json2.encode(receipt, escape_unicode: true) + '\n') or {
		os.rmdir_all(destination) or {}
		return fail_result('plugin install', 'cannot write plugin receipt: ${err.msg()}')
	}
	os.chmod(tmp, 0o600) or {}
	os.rename(tmp, receipt_path) or {
		os.rm(tmp) or {}
		os.rmdir_all(destination) or {}
		return fail_result('plugin install', 'cannot save plugin receipt: ${err.msg()}')
	}
	return ok_result('plugin install', 'installed ${name} ${version} as inert package data. Third-party QML is not loaded or sandboxed.', {
		'id':       id
		'path':     destination
		'revision': revision
	})
}

pub fn community_plugin_list_report() CommandResult {
	root, receipts := community_plugin_roots()
	if !os.is_dir(receipts) {
		return ok_result('plugin list', 'no community plugins installed', {
			'plugins': '[]'
		})
	}
	mut list_entries := []CommunityPluginListEntry{}
	files := os.ls(receipts) or { return fail_result('plugin list', 'cannot read plugin receipts: ${err.msg()}') }
	for file in files.sorted() {
		if !file.ends_with('.json') { continue }
		path := os.join_path(receipts, file)
		if os.is_link(path) { continue }
		raw := os.read_file(path) or { continue }
		record := json2.decode[CommunityPluginReceipt](raw) or { continue }
		if record.schema_version != 1 || !community_plugin_valid_id(record.id) || file != '${record.id}.json' {
			continue
		}
		list_entries << CommunityPluginListEntry{
			id:        record.id
			name:      record.name
			version:   record.version
			installed: os.is_dir(os.join_path(root, record.id))
		}
	}
	data := json2.encode(list_entries, escape_unicode: true)
	return ok_result('plugin list', if list_entries.len > 0 {
		'${list_entries.len} community plugin receipt(s)'
	} else {
		'no community plugins installed'
	}, {
		'plugins': data
	})
}

pub fn community_plugin_remove_report(opts CommunityPluginOptions) CommandResult {
	id := opts.value
	if !community_plugin_valid_id(id) {
		return fail_result('plugin remove', 'invalid plugin id.\nExample: horneroctl plugin remove example-clock --dry-run')
	}
	if !opts.dry_run && !opts.yes {
		return fail_result('plugin remove', 'refusing to remove a plugin without --yes (preview with --dry-run).\nExample: horneroctl plugin remove example-clock --dry-run')
	}
	root, receipts := community_plugin_roots()
	payload := os.join_path(root, id)
	receipt := os.join_path(receipts, '${id}.json')
	if os.is_link(payload) || os.is_link(receipt) {
		return fail_result('plugin remove', 'refusing to follow a symbolic link in the owned plugin paths')
	}
	if !os.is_file(receipt) {
		return fail_result('plugin remove', 'no Hornero receipt owns plugin ${id}')
	}
	record := json2.decode[CommunityPluginReceipt](os.read_file(receipt) or { '' }) or {
		return fail_result('plugin remove', 'plugin receipt is malformed; refusing to remove unverified data')
	}
	if record.schema_version != 1 || record.id != id {
		return fail_result('plugin remove', 'plugin receipt does not own the requested plugin id')
	}
	if opts.dry_run {
		return ok_result('plugin remove', 'would remove only the receipt-owned payload ${payload} and its receipt', {
			'dry_run': 'true'
		})
	}
	if os.exists(payload) {
		os.rmdir_all(payload) or { return fail_result('plugin remove', 'cannot remove owned plugin payload: ${err.msg()}') }
	}
	os.rm(receipt) or { return fail_result('plugin remove', 'cannot remove plugin receipt: ${err.msg()}') }
	return ok_result('plugin remove', 'removed Hornero-owned data for ${id}', {
		'id': id
	})
}
