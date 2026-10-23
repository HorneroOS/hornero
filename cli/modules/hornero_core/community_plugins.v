module hornero_core

import crypto.ed25519
import crypto.sha256
import encoding.base64
import os
import time
import x.json2

#flag linux -D_GNU_SOURCE
#include <errno.h>
#include <sys/stat.h>

fn C.renameat2(oldfd int, oldpath &char, newfd int, newpath &char, flags u32) int
fn C.lstat(path &char, metadata voidptr) int

pub struct CommunityPluginOptions {
pub:
	value             string
	dry_run           bool
	yes               bool
	expected_revision string
}

struct CommunityPluginReceipt {
pub mut:
	schema_version int
	id             string
	name           string
	version        string
	source         string
	revision       string
	installed_at   string
	// Enabled is the runtime lifecycle flag (M2). Receipts written before
	// this field existed decode as disabled: installed plugins never run
	// until the user explicitly enables them.
	enabled bool
	// TrustedHash records the payload SHA-256 the user explicitly
	// trusted via `plugin trust` (shell#251 local trust model).
	// Receipts written before this field decode as untrusted.
	// Official-catalogue receipts do not need it: their provenance is
	// the reviewed HorneroOS/plugins repo plus the catalogue hash.
	trusted_hash                  string
	catalog_sha256                string
	catalog_capabilities          json2.Any
	previous_catalog_sha256       string
	previous_catalog_capabilities json2.Any
	previous_payload_sha256       string
	previous_trusted_hash         string
	previous_revision             string
	previous_version              string
}

struct CommunityPluginListEntry {
	id                    string
	name                  string
	version               string
	installed             bool
	enabled               bool
	trust                 string
	source                string
	revision              string
	catalog_sha256        string
	capabilities          json2.Any
	capabilities_verified bool
	rollback_available    bool
}

fn community_plugin_declared_capabilities(record CommunityPluginReceipt, plugin_dir string) json2.Any {
	if record.source == plugin_catalog_source {
		if record.catalog_capabilities is map[string]json2.Any
			&& record.catalog_sha256.len > 0
			&& community_plugin_payload_hash(plugin_dir) == record.catalog_sha256 {
			return record.catalog_capabilities
		}
		manifest := community_plugin_manifest(plugin_dir) or {
			return json2.Any(map[string]json2.Any{})
		}
		if 'capabilities' in manifest && manifest['capabilities'] is map[string]json2.Any {
			return manifest['capabilities']
		}
		return json2.Any(map[string]json2.Any{})
	}
	manifest := community_plugin_manifest(plugin_dir) or {
		return json2.Any(map[string]json2.Any{})
	}
	if 'capabilities' in manifest && manifest['capabilities'] is map[string]json2.Any {
		return manifest['capabilities']
	}
	return json2.Any(map[string]json2.Any{})
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

fn community_plugin_valid_revision(revision string) bool {
	if revision.len != 40 && revision.len != 64 {
		return false
	}
	for c in revision.bytes() {
		if !(c >= `0` && c <= `9`) && !(c >= `a` && c <= `f`) && !(c >= `A` && c <= `F`) {
			return false
		}
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
	revision_result := run_exec(ExecSpec{
		prog:        git
		args:        ['-C', stage, 'rev-parse', '--verify', 'HEAD^{commit}']
		timeout_sec: 10
	})
	revision := revision_result.output.trim_space()
	if !revision_result.ok || !community_plugin_valid_revision(revision) {
		os.rmdir_all(stage) or {}
		return fail_result('plugin install', 'cannot record a valid Git commit for the staged plugin; refusing to install unpinned data')
	}
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
	receipt := CommunityPluginReceipt{
		schema_version: 1
		id:             id
		name:           name
		version:        version
		source:         opts.value
		revision:       revision
		installed_at:   time.now().unix_milli().str()
	}
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

// community_plugin_new_report creates a reviewable static package scaffold.
// It deliberately does not install or load the generated QML.
pub fn community_plugin_new_report(opts CommunityPluginOptions, name string, author string, description string, license string, output_dir string) CommandResult {
	if opts.value.len == 0 || !community_plugin_valid_id(opts.value) {
		return fail_result('plugin new', 'plugin id must use lowercase letters, digits, and internal hyphens (1–48 characters)')
	}
	if name.trim_space().len == 0 || name.len > 64 || author.trim_space().len == 0 || author.len > 120
		|| description.trim_space().len == 0 || description.len > 280 {
		return fail_result('plugin new', 'name, author, and description must be non-empty and within the manifest limits')
	}
	if license != 'MIT' {
		return fail_result('plugin new', 'only the MIT license text is generated; other licenses must be added manually')
	}
	if output_dir.trim_space().len == 0 {
		return fail_result('plugin new', 'missing output directory.\nExample: horneroctl plugin new example-clock --name "Example Clock" --author "Your Name" --description "A clock widget" --license MIT --dir ./example-clock --dry-run')
	}
	path := os.abs_path(output_dir)
	if community_plugin_path_occupied(path) {
		return fail_result('plugin new', 'output path already exists; refusing to overwrite: ${path}')
	}
	parent := os.dir(path)
	if !os.is_dir(parent) {
		return fail_result('plugin new', 'output parent directory does not exist: ${parent}')
	}
	if opts.dry_run {
		return ok_result('plugin new', 'would create an inert plugin scaffold at ${path}; no files were written or loaded', {
			'dry_run': 'true'
			'id':      opts.value
			'path':    path
		})
	}
	if !opts.yes {
		return fail_result('plugin new', 'refusing to create files without --yes (preview with --dry-run).\nExample: horneroctl plugin new example-clock --name "Example Clock" --author "Your Name" --description "A clock widget" --license MIT --dir ./example-clock --yes')
	}
	stage := os.join_path(parent, '.${os.file_name(path)}.hornero-${os.getpid()}')
	if os.exists(stage) {
		return fail_result('plugin new', 'temporary scaffold path already exists: ${stage}')
	}
	os.mkdir(stage) or { return fail_result('plugin new', 'cannot create temporary scaffold directory: ${err.msg()}') }
	manifest := '{\n' +
		'  "schemaVersion": 1,\n' +
		'  "id": ${community_plugin_json_string(opts.value)},\n' +
		'  "name": ${community_plugin_json_string(name)},\n' +
		'  "version": "0.1.0",\n' +
		'  "description": ${community_plugin_json_string(description)},\n' +
		'  "author": ${community_plugin_json_string(author)},\n' +
		'  "license": "MIT",\n' +
		'  "entrypoint": "Main.qml",\n' +
		'  "files": ["Main.qml", "README.md", "LICENSE"],\n' +
		'  "capabilities": {"processCommands": [], "networkHosts": [], "settings": {}}\n' +
		'}\n'
	qml := 'import QtQuick\nimport QtQuick.Controls\n\nItem {\n    id: root\n\n    implicitWidth: 240\n    implicitHeight: 64\n\n    Rectangle {\n        anchors.fill: parent\n        radius: 12\n        color: "#202127"\n        border.color: "#41434c"\n\n        Label {\n            anchors.centerIn: parent\n            text: qsTr("Plugin scaffold")\n            color: "#f0eee9"\n        }\n    }\n}\n'
	readme := '# ${name}\n\n${description}\n\n## Package contract\n\nThis repository is a static community extension package for Hornero Shell. The current Shell does not discover or load third-party QML packages. The horneroctl plugin new command creates files only; it does not install or execute them.\n\nQuickshell QML runs with the logged-in user’s permissions and is not sandboxed. Manifest capability declarations and static validation support review; they are not enforcement or a security certification. Review every source file before running code.\n\n## Validate\n\nFrom this directory, run:\n\n```sh\nhorneroctl plugin validate .\n```\n\n## License\n\nThis package declares MIT. Keep the manifest and LICENSE file aligned if you choose a different license.\n'
	license_text := 'MIT License\n\nCopyright (c) ${time.now().year} ${author}\n\nPermission is hereby granted, free of charge, to any person obtaining a copy\nof this software and associated documentation files (the "Software"), to deal\nin the Software without restriction, including without limitation the rights\nto use, copy, modify, merge, publish, distribute, sublicense, and/or sell\ncopies of the Software, and to permit persons to whom the Software is\nfurnished to do so, subject to the following conditions:\n\nThe above copyright notice and this permission notice shall be included in all\ncopies or substantial portions of the Software.\n\nTHE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR\nIMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,\nFITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE\nAUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER\nLIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,\nOUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE\nSOFTWARE.\n'
	for file, contents in {
		'manifest.json': manifest
		'Main.qml':      qml
		'README.md':     readme
		'LICENSE':       license_text
	} {
		os.write_file(os.join_path(stage, file), contents) or {
			os.rmdir_all(stage) or {}
			return fail_result('plugin new', 'cannot write ${file}: ${err.msg()}')
		}
	}
	community_plugin_rename_noreplace(stage, path) or {
		os.rmdir_all(stage) or {}
		return fail_result('plugin new', 'cannot publish scaffold at ${path} without replacing an existing path: ${err.msg()}')
	}
	return ok_result('plugin new', 'created inert plugin scaffold at ${path}; inspect and validate it before distribution', {
		'id':   opts.value
		'path': path
	})
}

fn community_plugin_path_occupied(path string) bool {
	mut metadata := C.stat{}
	if C.lstat(&char(path.str), &metadata) == 0 {
		return true
	}
	// Read errno immediately; even constructing an error object may overwrite it.
	return C.errno != C.ENOENT
}

fn community_plugin_rename_noreplace(source string, destination string) ! {
	$if linux {
		// RENAME_NOREPLACE makes publication atomic and preserves any path that
		// appears after the preflight check. A missing kernel/libc capability
		// fails safely rather than falling back to an overwriting rename.
		if C.renameat2(-100, &char(source.str), -100, &char(destination.str), 1) != 0 {
			return error(os.get_error_msg(int(C.errno)))
		}
	} $else {
		return error('atomic no-replace directory publication is only supported on Linux')
	}
}

fn community_plugin_json_string(value string) string {
	return json2.encode(value, escape_unicode: true)
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
		payload := os.join_path(root, record.id)
		list_entries << CommunityPluginListEntry{
			id:                    record.id
			name:                  record.name
			version:               record.version
			installed:             os.is_dir(payload)
			enabled:               record.enabled && os.is_dir(payload)
			trust:                 community_plugin_trust_state(record, payload)
			source:                record.source
			revision:              record.revision
			catalog_sha256:        record.catalog_sha256
			capabilities:          community_plugin_declared_capabilities(record, payload)
			capabilities_verified: record.source == plugin_catalog_source
				&& record.catalog_capabilities is map[string]json2.Any
				&& record.catalog_sha256.len > 0
				&& community_plugin_payload_hash(payload) == record.catalog_sha256
			rollback_available:    community_plugin_rollback_available(record, record.id, payload)
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

fn community_plugin_set_enabled_report(opts CommunityPluginOptions, enable bool) CommandResult {
	verb := if enable { 'enable' } else { 'disable' }
	id := opts.value
	if !community_plugin_valid_id(id) {
		return fail_result('plugin ${verb}', 'invalid plugin id.\nExample: horneroctl plugin ${verb} example-clock --dry-run')
	}
	if !opts.dry_run && !opts.yes {
		return fail_result('plugin ${verb}', 'refusing to ${verb} a plugin without --yes (preview with --dry-run).\nExample: horneroctl plugin ${verb} ${id} --dry-run')
	}
	root, receipts := community_plugin_roots()
	payload := os.join_path(root, id)
	receipt_path := os.join_path(receipts, '${id}.json')
	if os.is_link(payload) || os.is_link(receipt_path) {
		return fail_result('plugin ${verb}', 'refusing to follow a symbolic link in the owned plugin paths')
	}
	if !os.is_file(receipt_path) {
		return fail_result('plugin ${verb}', 'no Hornero receipt owns plugin ${id}. Install it first: horneroctl plugin install <https-url> --yes')
	}
	mut record := json2.decode[CommunityPluginReceipt](os.read_file(receipt_path) or { '' }) or {
		return fail_result('plugin ${verb}', 'plugin receipt is malformed; refusing to change lifecycle state')
	}
	if record.schema_version != 1 || record.id != id {
		return fail_result('plugin ${verb}', 'plugin receipt does not own the requested plugin id')
	}
	if !os.is_dir(payload) {
		return fail_result('plugin ${verb}', 'plugin payload is missing at ${payload}; reinstall the package before changing its state')
	}
	if enable {
		// Fail closed: an installed payload must still pass the static
		// contract before it may be marked runnable.
		community_plugin_run_validator(payload) or {
			return fail_result('plugin enable', 'installed payload no longer validates, so it stays disabled: ${err.msg()}')
		}
		// Local trust model (shell#251): non-official plugins need an
		// explicit, hash-pinned trust step before they may run.
		// Official-catalogue installs carry reviewed provenance.
		trust := community_plugin_trust_state(record, payload)
		if !opts.dry_run && trust != 'official' && trust != 'trusted' && trust != 'signed' {
			return fail_result('plugin enable', 'plugin ${id} is ${trust}: it did not come from the official catalogue, and no trust is recorded for the current payload. Review the code, then run: horneroctl plugin trust ${id} --yes')
		}
	}
	if record.enabled == enable {
		state := if enable { 'enabled' } else { 'disabled' }
		return ok_result('plugin ${verb}', 'plugin ${id} is already ${state}; nothing changed', {
			'id':      id
			'enabled': enable.str()
		})
	}
	if opts.dry_run {
		return ok_result('plugin ${verb}', 'would mark plugin ${id} as ${verb}d in its receipt. The Shell loads enabled plugins at next start; running QML has full user privileges and is not sandboxed.', {
			'dry_run': 'true'
			'id':      id
		})
	}
	record.enabled = enable
	tmp := '${receipt_path}.tmp-${time.now().unix_milli()}'
	os.write_file(tmp, json2.encode(record, escape_unicode: true) + '\n') or {
		return fail_result('plugin ${verb}', 'cannot write plugin receipt: ${err.msg()}')
	}
	os.chmod(tmp, 0o600) or {}
	os.rename(tmp, receipt_path) or {
		os.rm(tmp) or {}
		return fail_result('plugin ${verb}', 'cannot save plugin receipt: ${err.msg()}')
	}
	state := if enable { 'enabled' } else { 'disabled' }
	return ok_result('plugin ${verb}', 'plugin ${id} ${state}. ${if enable {
		'The Shell may load it at next start. Reminder: plugin QML runs with your user privileges; it is not sandboxed.'
	} else {
		'The Shell will not load it at next start.'
	}}', {
		'id':      id
		'enabled': enable.str()
	})
}

// Payload hash of an installed plugin directory ('' when unreadable).
fn community_plugin_payload_hash(payload string) string {
	raw := os.read_file(os.join_path(payload, 'manifest.json')) or { return '' }
	manifest := json2.decode[map[string]json2.Any](raw) or { return '' }
	return plugin_payload_sha256(payload, manifest)
}

fn community_plugin_rollback_available(record CommunityPluginReceipt, id string, payload string) bool {
	previous := '${payload}.previous'
	if record.schema_version != 1 || record.id != id || record.source != plugin_catalog_source
		|| record.previous_payload_sha256.len == 0 || os.is_link(payload) || os.is_link(previous)
		|| !os.is_dir(previous) {
		return false
	}
	return community_plugin_payload_hash(previous) == record.previous_payload_sha256
}

// Hash of the plugin's listed files only (manifest.json excluded).
// This is what an author signature signs: the manifest carries the
// signature, so the manifest itself cannot be inside the signed hash.
fn plugin_files_sha256(plugin_dir string, manifest map[string]json2.Any) string {
	mut names := []string{}
	if 'files' in manifest && manifest['files'] is []json2.Any {
		for f in manifest['files'].as_array() {
			if f is string && f.str() !in names {
				names << f.str()
			}
		}
	}
	names.sort()
	mut acc := ''
	for name in names {
		acc += name + '\0' + (os.read_file(os.join_path(plugin_dir, name)) or { '' }) + '\0'
	}
	return sha256.hexhash(acc)
}

// Verify a minisign legacy Ed25519 signature. Minisign public-key files
// store base64("Ed" + 8-byte key id + 32-byte key); the signature line
// stores base64("Ed" + the same key id + 64-byte signature). Authors
// sign the fixed-length files-hash text with `minisign -Sl`; default
// prehashed signatures use the incompatible `ED` BLAKE2b format.
fn minisign_verify(public_key_b64 string, signature string, message []u8) bool {
	pub_raw := base64.decode(public_key_b64)
	if pub_raw.len != 42 || pub_raw[0] != `E` || pub_raw[1] != `d` {
		return false
	}
	sig_raw := base64.decode(signature)
	if sig_raw.len != 74 || sig_raw[0] != `E` || sig_raw[1] != `d` {
		return false
	}
	for i in 2 .. 10 {
		if pub_raw[i] != sig_raw[i] {
			return false
		}
	}
	verify_key := ed25519.PublicKey(pub_raw[10..].clone())
	return ed25519.verify(verify_key, message, sig_raw[10..]) or { false }
}

// Author-signature state of an installed payload:
// none | signed | bad-signature. A present-but-invalid signature is
// always reported, never silently ignored.
fn community_plugin_signature_state(payload string) string {
	raw := os.read_file(os.join_path(payload, 'manifest.json')) or { return 'none' }
	manifest := json2.decode[map[string]json2.Any](raw) or { return 'none' }
	if 'signing' !in manifest {
		return 'none'
	}
	signing := manifest['signing']
	if signing !is map[string]json2.Any {
		return 'bad-signature'
	}
	signing_map := signing as map[string]json2.Any
	public_key := if 'publicKey' in signing_map { signing_map['publicKey'].str() } else { '' }
	signature := if 'signature' in signing_map { signing_map['signature'].str() } else { '' }
	if public_key.len == 0 || signature.len == 0 {
		return 'bad-signature'
	}
	message := plugin_files_sha256(payload, manifest)
	if minisign_verify(public_key, signature, message.bytes()) {
		return 'signed'
	}
	return 'bad-signature'
}

// Trust state of a receipt relative to the current payload on disk.
// Precedence: official provenance, then a broken signature (fail
// closed), then a verified author signature, then the local
// hash-pinned trust recorded via `plugin trust`.
fn community_plugin_trust_state(record CommunityPluginReceipt, payload string) string {
	if record.source == plugin_catalog_source {
		current := community_plugin_payload_hash(payload)
		if record.catalog_sha256.len > 0 && current == record.catalog_sha256 {
			return 'official'
		}
		if record.trusted_hash.len > 0 && current.len > 0 && current == record.trusted_hash {
			return 'trusted'
		}
		return if record.catalog_sha256.len == 0 { 'unverified' } else { 'modified' }
	}
	signature := community_plugin_signature_state(payload)
	if signature == 'bad-signature' {
		return 'bad-signature'
	}
	if signature == 'signed' {
		return 'signed'
	}
	if record.trusted_hash.len == 0 {
		return 'untrusted'
	}
	current := community_plugin_payload_hash(payload)
	if current.len > 0 && current == record.trusted_hash {
		return 'trusted'
	}
	return 'stale-trust'
}

// `plugin trust <id>`: the explicit "I trust this code" step
// (shell#251). Records the current payload hash in the receipt;
// never enables. Any later payload change invalidates the trust.
pub fn community_plugin_trust_report(opts CommunityPluginOptions) CommandResult {
	id := opts.value
	if !community_plugin_valid_id(id) {
		return fail_result('plugin trust', 'invalid plugin id.\nExample: horneroctl plugin trust example-clock --dry-run')
	}
	root, receipts := community_plugin_roots()
	payload := os.join_path(root, id)
	receipt_path := os.join_path(receipts, '${id}.json')
	if os.is_link(payload) || os.is_link(receipt_path) {
		return fail_result('plugin trust', 'refusing to follow a symbolic link in the owned plugin paths')
	}
	if !os.is_file(receipt_path) {
		return fail_result('plugin trust', 'no Hornero receipt owns plugin ${id}. Install it first: horneroctl plugin install <https-url> --yes')
	}
	mut record := json2.decode[CommunityPluginReceipt](os.read_file(receipt_path) or { '' }) or {
		return fail_result('plugin trust', 'plugin receipt is malformed; refusing to record trust')
	}
	if record.schema_version != 1 || record.id != id {
		return fail_result('plugin trust', 'plugin receipt does not own the requested plugin id')
	}
	if !os.is_dir(payload) {
		return fail_result('plugin trust', 'plugin payload is missing at ${payload}; reinstall before trusting it')
	}
	community_plugin_run_validator(payload) or {
		return fail_result('plugin trust', 'payload does not validate, so it cannot be trusted: ${err.msg()}')
	}
	hash := community_plugin_payload_hash(payload)
	if hash.len == 0 {
		return fail_result('plugin trust', 'cannot compute the payload hash for ${id}; refusing to record trust')
	}
	if opts.dry_run {
		return ok_result('plugin trust', 'would record trust for plugin ${id} from ${record.source} (revision ${record.revision}) at payload hash ${hash}. Trusting is not enabling: this code would still need `plugin enable`. Plugin QML runs with your user privileges and is not sandboxed.', {
			'dry_run': 'true'
			'id':      id
			'hash':    hash
			'source':  record.source
		})
	}
	if !opts.yes {
		return fail_result('plugin trust', 'refusing to record trust without --yes (preview with --dry-run).\nExample: horneroctl plugin trust ${id} --dry-run')
	}
	was_trusted := community_plugin_trust_state(record, payload) in ['official', 'trusted', 'signed']
	record.trusted_hash = hash
	// Trust records review of a specific payload; it is never an implicit
	// enable. If a previously enabled payload lost integrity, keep it disabled
	// after trust so the user must explicitly enable it again.
	if !was_trusted { record.enabled = false }
	tmp := '${receipt_path}.tmp-${time.now().unix_milli()}'
	os.write_file(tmp, json2.encode(record, escape_unicode: true) + '\n') or {
		return fail_result('plugin trust', 'cannot write plugin receipt: ${err.msg()}')
	}
	os.chmod(tmp, 0o600) or {}
	os.rename(tmp, receipt_path) or {
		os.rm(tmp) or {}
		return fail_result('plugin trust', 'cannot save plugin receipt: ${err.msg()}')
	}
	enabled_text := if record.enabled {
		'It remains enabled.'
	} else {
		'It remains disabled; enable it explicitly.'
	}
	return ok_result('plugin trust', 'trust recorded for plugin ${id} at payload hash ${hash}. ${enabled_text} If the payload changes, trust must be recorded again.', {
		'id':    id
		'hash':  hash
		'trust': 'trusted'
	})
}

pub fn community_plugin_enable_report(opts CommunityPluginOptions) CommandResult {
	return community_plugin_set_enabled_report(opts, true)
}

pub fn community_plugin_disable_report(opts CommunityPluginOptions) CommandResult {
	return community_plugin_set_enabled_report(opts, false)
}

// --- Official catalogue (HorneroOS/plugins marketplace) ---------------
// The catalogue repo carries one directory per official plugin plus a
// generated catalog.json (payload SHA-256 + pinned revision). Catalog
// installs verify the hash before the shell validator runs, then
// publish through the same receipt path as direct installs.

pub const plugin_catalog_source = 'https://github.com/HorneroOS/plugins.git'

pub struct PluginCatalogEntry {
pub:
	id             string
	name           string
	version        string
	description    string
	author         string
	license        string
	placement      string
	category       string
	trust          string
	path           string
	sha256         string
	homepage       string
	generated_from string
	capabilities   json2.Any
}

pub fn plugin_catalog_entries(catalog_json string) []PluginCatalogEntry {
	decoded := json2.decode[json2.Any](catalog_json) or { return [] }
	if decoded !is map[string]json2.Any {
		return []
	}
	root := decoded.as_map()
	generated_from := if 'generatedFrom' in root && root['generatedFrom'] is string {
		root['generatedFrom'].str()
	} else {
		''
	}
	if !('plugins' in root) || root['plugins'] !is []json2.Any {
		return []
	}
	mut entries := []PluginCatalogEntry{}
	for item in root['plugins'].as_array() {
		if item !is map[string]json2.Any {
			continue
		}
		m := item as map[string]json2.Any
		get := fn [m] (k string) string {
			if k in m && m[k] is string {
				return m[k].str()
			}
			return ''
		}
		entries << PluginCatalogEntry{
			id:             get('id')
			name:           get('name')
			version:        get('version')
			description:    get('description')
			author:         get('author')
			license:        get('license')
			placement:      get('placement')
			category:       get('category')
			trust:          get('trust')
			path:           get('path')
			sha256:         get('sha256')
			homepage:       get('homepage')
			generated_from: generated_from
			capabilities:   if 'capabilities' in m && m['capabilities'] is map[string]json2.Any {
				m['capabilities']
			} else {
				json2.Any(map[string]json2.Any{})
			}
		}
	}
	return entries
}

fn plugin_catalog_entry_json(entry PluginCatalogEntry, state string, rollback_available bool) json2.Any {
	return json2.Any({
		'id':                 json2.Any(entry.id)
		'name':               json2.Any(entry.name)
		'version':            json2.Any(entry.version)
		'description':        json2.Any(entry.description)
		'author':             json2.Any(entry.author)
		'license':            json2.Any(entry.license)
		'homepage':           json2.Any(entry.homepage)
		'placement':          json2.Any(entry.placement)
		'category':           json2.Any(entry.category)
		'trust':              json2.Any(entry.trust)
		'sha256':             json2.Any(entry.sha256)
		'generatedFrom':      json2.Any(entry.generated_from)
		'capabilities':       entry.capabilities
		'state':              json2.Any(state)
		'rollback_available': json2.Any(rollback_available)
	})
}

// Same framing as HorneroOS/plugins scripts/gen_catalog.py:
// for each name in sorted(manifest.json + files): name NUL bytes NUL.
pub fn plugin_payload_sha256(plugin_dir string, manifest map[string]json2.Any) string {
	mut names := ['manifest.json']
	if 'files' in manifest && manifest['files'] is []json2.Any {
		for f in manifest['files'].as_array() {
			if f is string && f.str() !in names {
				names << f.str()
			}
		}
	}
	names.sort()
	mut acc := ''
	for name in names {
		acc += name + '\0' + (os.read_file(os.join_path(plugin_dir, name)) or { '' }) + '\0'
	}
	return sha256.hexhash(acc)
}

fn community_plugin_clone_catalog(expected_revision string) !(string, string) {
	if expected_revision.len > 0 && !community_plugin_valid_revision(expected_revision) {
		return error('catalogue revision must be a full Git commit hash')
	}
	expected := expected_revision.to_lower()
	git := if os.getenv('HORNERO_GIT_BIN').len > 0 {
		os.getenv('HORNERO_GIT_BIN')
	} else {
		find_on_path('git')
	}
	env := find_on_path('env')
	if git.len == 0 || env.len == 0 {
		return error('git and env are required to read the plugin catalogue')
	}
	source := os.getenv('HORNERO_PLUGINS_CATALOG_URL')
	stage := os.join_path(os.temp_dir(), 'hornero-catalog-${os.getpid()}-${time.now().unix_milli()}')
	if source.len > 0 && os.is_dir(source) {
		copy_dir(source, stage)!
		return stage, 'local'
	}
	url := if source.len > 0 { source } else { plugin_catalog_source }
	if !community_plugin_safe_source(url) {
		return error('catalogue source must be an HTTPS Git URL')
	}
	clone := community_plugin_run_catalog_git(git, env, [
		'-c',
		'core.hooksPath=/dev/null',
		'-c',
		'credential.helper=',
		'-c',
		'protocol.allow=never',
		'-c',
		'protocol.https.allow=always',
		'clone',
		'--depth',
		'1',
		'--no-tags',
		'--',
		url,
		stage,
	], 120)
	if !clone.ok {
		os.rmdir_all(stage) or {}
		return error('git clone of the catalogue failed: ${clone.output}')
	}
	if expected_revision.len > 0 {
		fetch := community_plugin_run_catalog_git(git, env, [
			'-C',
			stage,
			'-c',
			'core.hooksPath=/dev/null',
			'-c',
			'credential.helper=',
			'-c',
			'protocol.allow=never',
			'-c',
			'protocol.https.allow=always',
			'fetch',
			'--depth=1',
			'--no-tags',
			'--no-recurse-submodules',
			'origin',
			expected,
		], 120)
		if !fetch.ok {
			os.rmdir_all(stage) or {}
			return error('cannot fetch the requested catalogue revision ${expected_revision}: ${fetch.output}; refusing to install different catalogue content')
		}
		checkout := community_plugin_run_catalog_git(git, env, [
			'-C',
			stage,
			'-c',
			'core.hooksPath=/dev/null',
			'checkout',
			'--detach',
			expected,
		], 30)
		if !checkout.ok {
			os.rmdir_all(stage) or {}
			return error('cannot check out the requested catalogue revision ${expected_revision}: ${checkout.output}; refusing to install different catalogue content')
		}
	}
	rev := community_plugin_run_catalog_git(git, env, [
		'-C',
		stage,
		'rev-parse',
		'--verify',
		'HEAD^{commit}',
	], 10)
	revision := rev.output.trim_space()
	if !rev.ok || !community_plugin_valid_revision(revision) {
		os.rmdir_all(stage) or {}
		return error('cannot pin a catalogue revision; refusing unpinned data')
	}
	if expected.len > 0 && revision.to_lower() != expected {
		os.rmdir_all(stage) or {}
		return error('checked out catalogue revision ${revision}, expected ${expected_revision}; refusing to use different catalogue content')
	}
	return stage, revision
}

fn community_plugin_run_catalog_git(git string, env string, args []string, timeout int) ExecReport {
	mut command_args := []string{}
	for name in ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_OBJECT_DIRECTORY',
		'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_COMMON_DIR', 'GIT_NAMESPACE', 'GIT_SHALLOW_FILE',
		'GIT_QUARANTINE_PATH', 'GIT_CONFIG', 'GIT_CONFIG_COUNT', 'GIT_CONFIG_PARAMETERS',
		'GIT_CONFIG_SYSTEM', 'GIT_CONFIG_KEY_0', 'GIT_CONFIG_VALUE_0', 'GIT_EXEC_PATH',
		'GIT_TEMPLATE_DIR', 'GIT_CEILING_DIRECTORIES', 'GIT_DISCOVERY_ACROSS_FILESYSTEM'] {
		command_args << '-u'
		command_args << name
	}
	command_args << [
		'GIT_TERMINAL_PROMPT=0',
		'GIT_CONFIG_NOSYSTEM=1',
		'GIT_CONFIG_GLOBAL=/dev/null',
	]
	command_args << git
	command_args << args
	return run_exec(ExecSpec{
		prog:        env
		args:        command_args
		timeout_sec: timeout
	})
}

fn copy_dir(src string, dst string) ! {
	os.mkdir_all(dst)!
	for entry in os.ls(src)! {
		if entry == '.git' {
			continue
		}
		s := os.join_path(src, entry)
		d := os.join_path(dst, entry)
		if os.is_dir(s) {
			copy_dir(s, d)!
		} else if os.is_file(s) {
			os.cp(s, d)!
		}
	}
}

pub fn community_plugin_catalog_report() CommandResult {
	stage, revision := community_plugin_clone_catalog('') or {
		return fail_result('plugin catalog', err.msg())
	}
	defer {
		os.rmdir_all(stage) or {}
	}
	raw := os.read_file(os.join_path(stage, 'catalog.json')) or {
		return fail_result('plugin catalog', 'catalogue has no catalog.json')
	}
	entries := plugin_catalog_entries(raw)
	root, receipts := community_plugin_roots()
	mut lines := []string{}
	mut rows := []json2.Any{}
	for e in entries {
		receipt := os.join_path(receipts, '${e.id}.json')
		state := if os.is_file(receipt) { 'installed' } else { 'available' }
		lines << '${e.id} ${e.version} [${e.trust}/${e.placement}] ${e.name} — ${state}'
		mut rollback_available := false
		if state == 'installed' && !os.is_link(receipt) {
			raw_receipt := os.read_file(receipt) or { '' }
			record := json2.decode[CommunityPluginReceipt](raw_receipt) or {
				CommunityPluginReceipt{}
			}
			rollback_available = community_plugin_rollback_available(record, e.id,
				os.join_path(root, e.id))
		}
		rows << plugin_catalog_entry_json(e, state, rollback_available)
	}
	return ok_result('plugin catalog', 'Official HorneroOS catalogue (${entries.len} plugins):\n${lines.join('\n')}', {
		'plugins':  json2.encode(rows, escape_unicode: true)
		'source':   plugin_catalog_source
		'revision': revision
	})
}

pub fn community_plugin_catalog_install_report(id string, opts CommunityPluginOptions) CommandResult {
	if !community_plugin_valid_id(id) {
		return fail_result('plugin catalog install', 'invalid plugin id.\nExample: horneroctl plugin catalog install hornero-pomodoro --dry-run')
	}
	if !opts.dry_run && !opts.yes {
		return fail_result('plugin catalog install', 'refusing to install without --yes (preview with --dry-run)')
	}
	stage, revision := community_plugin_clone_catalog(opts.expected_revision) or {
		return fail_result('plugin catalog install', err.msg())
	}
	defer {
		os.rmdir_all(stage) or {}
	}
	if opts.expected_revision.len > 0 && opts.expected_revision.to_lower() != revision.to_lower() {
		return fail_result('plugin catalog install', 'catalogue changed since it was displayed; refresh the catalogue and review the new version before installing')
	}
	raw := os.read_file(os.join_path(stage, 'catalog.json')) or {
		return fail_result('plugin catalog install', 'catalogue has no catalog.json')
	}
	mut found := PluginCatalogEntry{}
	for e in plugin_catalog_entries(raw) {
		if e.id == id {
			found = e
		}
	}
	if found.id.len == 0 {
		return fail_result('plugin catalog install', 'plugin ${id} is not in the official catalogue')
	}
	pkg := os.join_path(stage, found.path)
	if !os.is_dir(pkg) {
		return fail_result('plugin catalog install', 'catalogue entry path missing: ${found.path}')
	}
	manifest := community_plugin_manifest(pkg) or {
		return fail_result('plugin catalog install', err.msg())
	}
	digest := plugin_payload_sha256(pkg, manifest)
	if found.sha256.len == 0 || digest != found.sha256 {
		return fail_result('plugin catalog install', 'payload hash mismatch for ${id} (catalog ${found.sha256}, computed ${digest}); refusing to install')
	}
	if opts.dry_run {
		return ok_result('plugin catalog install', 'would install ${found.name} ${found.version} [${found.trust}] from the official catalogue at ${revision}; hash verified. This copies inert data only — enabling is a separate consent step.', {
			'dry_run':  'true'
			'id':       id
			'sha256':   digest
			'revision': revision
		})
	}
	community_plugin_run_validator(pkg) or {
		return fail_result('plugin catalog install', err.msg())
	}
	root, receipts := community_plugin_roots()
	destination := os.join_path(root, id)
	if os.exists(destination) || os.is_link(destination) {
		return fail_result('plugin catalog install', 'plugin ${id} is already installed; remove it explicitly before reinstalling')
	}
	os.mkdir_all(root) or { return fail_result('plugin catalog install', 'cannot create plugin data directory') }
	copy_dir(pkg, destination) or {
		return fail_result('plugin catalog install', 'cannot copy validated package: ${err.msg()}')
	}
	receipt := CommunityPluginReceipt{
		schema_version:       1
		id:                   found.id
		name:                 found.name
		version:              found.version
		source:               plugin_catalog_source
		revision:             revision
		installed_at:         time.now().unix_milli().str()
		catalog_sha256:       digest
		catalog_capabilities: found.capabilities
	}
	os.mkdir_all(receipts) or {
		os.rmdir_all(destination) or {}
		return fail_result('plugin catalog install', 'cannot create plugin receipt directory')
	}
	receipt_path := os.join_path(receipts, '${id}.json')
	tmp := '${receipt_path}.tmp-${time.now().unix_milli()}'
	os.write_file(tmp, json2.encode(receipt, escape_unicode: true) + '\n') or {
		os.rmdir_all(destination) or {}
		return fail_result('plugin catalog install', 'cannot write plugin receipt')
	}
	os.chmod(tmp, 0o600) or {}
	os.rename(tmp, receipt_path) or {
		os.rmdir_all(destination) or {}
		return fail_result('plugin catalog install', 'cannot save plugin receipt')
	}
	return ok_result('plugin catalog install', 'installed ${found.name} ${found.version} [${found.trust}] as inert package data. QML is not loaded or sandboxed; enable explicitly when you have reviewed it.', {
		'id':       id
		'path':     destination
		'revision': revision
		'sha256':   digest
	})
}

// community_plugin_catalog_update_report implements
// `plugin catalog update <id>`: replace a catalogue-installed
// payload with the current catalogue revision. Safety rules:
// the new payload is hash-verified and validated BEFORE the old
// one is touched; the previous payload is kept under
// `<id>.previous` so `plugin catalog rollback <id>` can restore it;
// the enabled flag is preserved (updating never enables, and an
// enabled plugin stays enabled only across a validated payload —
// enable itself re-validates anyway). Receipt must name the
// official catalogue as its source: URL-installed plugins are not
// silently re-sourced.
pub fn community_plugin_catalog_update_report(id string, opts CommunityPluginOptions) CommandResult {
	if !community_plugin_valid_id(id) {
		return fail_result('plugin catalog update', 'invalid plugin id.\nExample: horneroctl plugin catalog update hornero-pomodoro --dry-run')
	}
	if !opts.dry_run && !opts.yes {
		return fail_result('plugin catalog update', 'refusing to update without --yes (preview with --dry-run)')
	}
	root, receipts := community_plugin_roots()
	receipt_path := os.join_path(receipts, '${id}.json')
	destination := os.join_path(root, id)
	if os.is_link(receipt_path) || os.is_link(destination) {
		return fail_result('plugin catalog update', 'refusing to follow a symbolic link in the owned plugin paths')
	}
	if !os.is_file(receipt_path) {
		return fail_result('plugin catalog update', 'plugin ${id} is not installed; install it first')
	}
	mut record := json2.decode[CommunityPluginReceipt](os.read_file(receipt_path) or { '' }) or {
		return fail_result('plugin catalog update', 'plugin receipt is malformed; refusing to update unverified data')
	}
	if record.schema_version != 1 || record.id != id {
		return fail_result('plugin catalog update', 'plugin receipt does not own the requested plugin id')
	}
	if record.source != plugin_catalog_source {
		return fail_result('plugin catalog update', 'plugin ${id} was not installed from the official catalogue (source: ${record.source}); refusing to re-source it')
	}
	stage, revision := community_plugin_clone_catalog(opts.expected_revision) or {
		return fail_result('plugin catalog update', err.msg())
	}
	defer {
		os.rmdir_all(stage) or {}
	}
	if opts.expected_revision.len > 0 && opts.expected_revision.to_lower() != revision.to_lower() {
		return fail_result('plugin catalog update', 'catalogue changed since it was displayed; refresh the catalogue and review the new version before updating')
	}
	raw := os.read_file(os.join_path(stage, 'catalog.json')) or {
		return fail_result('plugin catalog update', 'catalogue has no catalog.json')
	}
	mut found := PluginCatalogEntry{}
	for e in plugin_catalog_entries(raw) {
		if e.id == id {
			found = e
		}
	}
	if found.id.len == 0 {
		return fail_result('plugin catalog update', 'plugin ${id} is no longer in the official catalogue; refusing to guess')
	}
	pkg := os.join_path(stage, found.path)
	if !os.is_dir(pkg) {
		return fail_result('plugin catalog update', 'catalogue entry path missing: ${found.path}')
	}
	manifest := community_plugin_manifest(pkg) or {
		return fail_result('plugin catalog update', err.msg())
	}
	digest := plugin_payload_sha256(pkg, manifest)
	if found.sha256.len == 0 || digest != found.sha256 {
		return fail_result('plugin catalog update', 'payload hash mismatch for ${id} (catalog ${found.sha256}, computed ${digest}); refusing to update')
	}
	installed_payload_hash := community_plugin_payload_hash(destination)
	if found.version == record.version && record.catalog_sha256 == digest && record.revision == revision && installed_payload_hash == digest {
		return ok_result('plugin catalog update', 'plugin ${id} is already current at catalogue version ${found.version}; nothing to do', {
			'id':       id
			'version':  found.version
			'revision': revision
		})
	}
	if found.version == record.version && installed_payload_hash != digest && record.trusted_hash != installed_payload_hash {
		return fail_result('plugin catalog update', 'installed payload for ${id} differs from the official catalogue. Trust the current payload explicitly or reinstall the official package before updating')
	}
	if opts.dry_run {
		return ok_result('plugin catalog update', 'would update ${found.name} ${record.version} -> ${found.version} from the official catalogue at ${revision}; hash verified. The current payload is kept for rollback.', {
			'dry_run': 'true'
			'id':      id
			'from':    record.version
			'to':      found.version
			'sha256':  digest
		})
	}
	community_plugin_run_validator(pkg) or {
		return fail_result('plugin catalog update', err.msg())
	}
	previous := '${destination}.previous'
	old_payload_digest := community_plugin_payload_hash(destination)
	old_trusted_hash := record.trusted_hash
	was_integrity_trusted := community_plugin_trust_state(record, destination) in [
		'official',
		'trusted',
		'signed',
	]
	if os.exists(previous) || os.is_link(previous) {
		os.rmdir_all(previous) or {
			return fail_result('plugin catalog update', 'cannot clear the previous rollback copy')
		}
	}
	if os.is_dir(destination) {
		os.rename(destination, previous) or {
			return fail_result('plugin catalog update', 'cannot preserve the current payload for rollback')
		}
	}
	copy_dir(pkg, destination) or {
		os.rmdir_all(destination) or {}
		if os.is_dir(previous) {
			os.rename(previous, destination) or {}
		}
		return fail_result('plugin catalog update', 'cannot copy validated package: ${err.msg()}')
	}
	old_version := record.version
	enabled_before := record.enabled
	record.previous_catalog_sha256 = record.catalog_sha256
	record.previous_catalog_capabilities = record.catalog_capabilities
	record.previous_revision = record.revision
	record.previous_version = record.version
	record.previous_payload_sha256 = old_payload_digest
	record.previous_trusted_hash = old_trusted_hash
	record.id = found.id
	record.name = found.name
	record.version = found.version
	record.source = plugin_catalog_source
	record.revision = revision
	record.installed_at = time.now().unix_milli().str()
	record.enabled = enabled_before && was_integrity_trusted
	record.catalog_sha256 = digest
	record.catalog_capabilities = found.capabilities
	tmp := '${receipt_path}.tmp-${time.now().unix_milli()}'
	os.write_file(tmp, json2.encode(record, escape_unicode: true) + '\n') or {
		os.rmdir_all(destination) or {}
		if os.is_dir(previous) { os.rename(previous, destination) or {} }
		return fail_result('plugin catalog update', 'cannot write plugin receipt')
	}
	os.chmod(tmp, 0o600) or {}
	os.rename(tmp, receipt_path) or {
		os.rm(tmp) or {}
		os.rmdir_all(destination) or {}
		if os.is_dir(previous) { os.rename(previous, destination) or {} }
		return fail_result('plugin catalog update', 'cannot save plugin receipt')
	}
	return ok_result('plugin catalog update', 'updated ${found.name} from ${old_version} to ${found.version} [${found.trust}] from the official catalogue. Previous payload kept for `plugin catalog rollback ${id}`. Enabled state is ${if record.enabled {
		'enabled'
	} else {
		'disabled'
	}} (was ${if enabled_before { 'enabled' } else { 'disabled' }}).', {
		'id':       id
		'from':     old_version
		'version':  found.version
		'revision': revision
		'sha256':   digest
	})
}

// community_plugin_catalog_rollback_report implements
// `plugin catalog rollback <id>`: restore the payload kept by the
// last update. The kept payload is validated before anything moves;
// rollback consumes the kept copy (a second rollback has nothing to
// restore and says so). Receipt version follows the restored
// manifest; enabled state is preserved.
pub fn community_plugin_catalog_rollback_report(id string, opts CommunityPluginOptions) CommandResult {
	if !community_plugin_valid_id(id) {
		return fail_result('plugin catalog rollback', 'invalid plugin id.\nExample: horneroctl plugin catalog rollback hornero-pomodoro --dry-run')
	}
	if !opts.dry_run && !opts.yes {
		return fail_result('plugin catalog rollback', 'refusing to roll back without --yes (preview with --dry-run)')
	}
	root, receipts := community_plugin_roots()
	receipt_path := os.join_path(receipts, '${id}.json')
	destination := os.join_path(root, id)
	previous := '${destination}.previous'
	if os.is_link(receipt_path) || os.is_link(destination) || os.is_link(previous) {
		return fail_result('plugin catalog rollback', 'refusing to follow a symbolic link in the owned plugin paths')
	}
	if !os.is_dir(previous) {
		return fail_result('plugin catalog rollback', 'no previous payload is kept for ${id}; nothing to roll back to')
	}
	if !os.is_file(receipt_path) {
		return fail_result('plugin catalog rollback', 'plugin ${id} has a kept payload but no receipt; refusing to guess ownership')
	}
	mut record := json2.decode[CommunityPluginReceipt](os.read_file(receipt_path) or { '' }) or {
		return fail_result('plugin catalog rollback', 'plugin receipt is malformed; refusing to roll back unverified data')
	}
	if record.schema_version != 1 || record.id != id {
		return fail_result('plugin catalog rollback', 'plugin receipt does not own the requested plugin id')
	}
	prev_manifest := community_plugin_manifest(previous) or {
		return fail_result('plugin catalog rollback', 'kept payload is unreadable: ${err.msg()}')
	}
	prev_version := (prev_manifest['version'] or { json2.Any('') }).str()
	prev_digest := community_plugin_payload_hash(previous)
	if record.source == plugin_catalog_source && (record.previous_payload_sha256.len == 0 || prev_digest != record.previous_payload_sha256) {
		return fail_result('plugin catalog rollback', 'kept payload does not match the previous catalogue hash; refusing to restore unverified data')
	}
	if opts.dry_run {
		return ok_result('plugin catalog rollback', 'would restore ${id} from the kept previous payload (version ${prev_version}); the current payload is discarded', {
			'dry_run': 'true'
			'id':      id
			'to':      prev_version
		})
	}
	community_plugin_run_validator(previous) or {
		return fail_result('plugin catalog rollback', err.msg())
	}
	staged_current := '${destination}.rollback-current'
	if os.exists(staged_current) || os.is_link(staged_current) {
		return fail_result('plugin catalog rollback', 'cannot safely stage the current payload for rollback')
	}
	if os.is_dir(destination) {
		os.rename(destination, staged_current) or {
			return fail_result('plugin catalog rollback', 'cannot preserve the current payload before rollback')
		}
	}
	os.rename(previous, destination) or {
		if os.is_dir(staged_current) { os.rename(staged_current, destination) or {} }
		return fail_result('plugin catalog rollback', 'cannot restore the kept payload')
	}
	enabled_before := record.enabled
	record.version = if record.previous_version.len > 0 {
		record.previous_version
	} else {
		prev_version
	}
	record.revision = record.previous_revision
	record.installed_at = time.now().unix_milli().str()
	record.enabled = enabled_before
	record.catalog_sha256 = record.previous_catalog_sha256
	record.catalog_capabilities = record.previous_catalog_capabilities
	record.trusted_hash = record.previous_trusted_hash
	record.previous_catalog_sha256 = ''
	record.previous_catalog_capabilities = json2.Any(map[string]json2.Any{})
	record.previous_revision = ''
	record.previous_version = ''
	record.previous_payload_sha256 = ''
	record.previous_trusted_hash = ''
	tmp := '${receipt_path}.tmp-${time.now().unix_milli()}'
	os.write_file(tmp, json2.encode(record, escape_unicode: true) + '\n') or {
		os.rename(destination, previous) or {}
		if os.is_dir(staged_current) { os.rename(staged_current, destination) or {} }
		return fail_result('plugin catalog rollback', 'cannot write plugin receipt')
	}
	os.chmod(tmp, 0o600) or {}
	os.rename(tmp, receipt_path) or {
		os.rm(tmp) or {}
		os.rename(destination, previous) or {}
		if os.is_dir(staged_current) { os.rename(staged_current, destination) or {} }
		return fail_result('plugin catalog rollback', 'cannot save plugin receipt')
	}
	os.rmdir_all(staged_current) or {}
	return ok_result('plugin catalog rollback', 'rolled back ${id} to the kept previous payload (version ${prev_version}). Enabled state unchanged (${if enabled_before {
		'enabled'
	} else {
		'disabled'
	}}).', {
		'id':      id
		'version': prev_version
	})
}
