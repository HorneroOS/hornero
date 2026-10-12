module hornero_core

import os
import time
import x.json2

#flag linux -D_GNU_SOURCE
fn C.renameat2(oldfd int, oldpath &char, newfd int, newpath &char, flags u32) int

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
	os.lstat(path) or {
		// Fail closed for every error except a missing path; unlike exists(),
		// lstat sees dangling symlinks as occupied paths.
		return C.errno != C.ENOENT
	}
	return true
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
