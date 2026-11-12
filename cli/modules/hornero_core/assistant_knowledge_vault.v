module hornero_core

import crypto.sha256
import os
import time
import x.json2

// Knowledge Vault: persistent, user-scoped snapshot extending the
// ephemeral `assistant knowledge` report (assistant.v). The vault is
// generated only from Hornero's own bounded, allowlisted aggregates
// (system profile record, compositor/session names, assistant tool
// allowlist, assistant settings state). It never ingests private
// files, never reads $HOME content, and never embeds secrets: keys
// that look secret-like are dropped and values pass redact_secrets.
// Layout under $XDG_DATA_HOME/hornero/knowledge-vault/:
//   generated/<section>.md   Hornero-owned; rewritten on regeneration
//   notes/                   user-authored; never created over, never deleted
//   manifest.json            provenance + sha256 of every generated file
// Regeneration is explicit (`knowledge vault generate --yes`); a
// generated file the user edited (hash differs from the manifest) is
// preserved into notes/ before it is rewritten, never silently lost.

pub const knowledge_vault_schema = 'hornero.knowledge-vault/v1'
pub const knowledge_vault_max_section_chars = 4000
pub const knowledge_vault_sections = ['system', 'desktop', 'packages', 'services', 'capabilities',
	'agents']

pub struct KnowledgeVaultSources {
pub mut:
	system       map[string]string
	desktop      map[string]string
	packages     map[string]string
	services     map[string]string
	capabilities map[string]string
	agents       map[string]string
}

// knowledge_vault_dir resolves the user-scoped vault root:
// $HORNERO_KNOWLEDGE_VAULT_DIR, else $XDG_DATA_HOME/hornero/knowledge-vault.
pub fn knowledge_vault_dir() string {
	override := os.getenv('HORNERO_KNOWLEDGE_VAULT_DIR')
	if override.len > 0 {
		return override
	}
	paths := resolve_paths()
	return os.join_path(paths.data_dir, 'hornero', 'knowledge-vault')
}

fn knowledge_vault_section_sources(sources KnowledgeVaultSources, section string) map[string]string {
	return match section {
		'system' { sources.system }
		'desktop' { sources.desktop }
		'packages' { sources.packages }
		'services' { sources.services }
		'capabilities' { sources.capabilities }
		else { sources.agents }
	}
}

// knowledge_vault_collect_sources gathers the live snapshot inputs.
// Only Hornero-owned records and process environment names that are
// not credentials are read; no user file content is ingested.
pub fn knowledge_vault_collect_sources() KnowledgeVaultSources {
	profile := system_profile_result()
	pd := profile.data
	settings := assistant_load_settings()
	tools := assistant_tools_report().data['tools'] or { '' }
	uname := os.uname()
	return KnowledgeVaultSources{
		system:       {
			'edition':         pd['edition'] or { 'unrecorded' }
			'editionTitle':    pd['editionTitle'] or { '' }
			'editionMaturity': pd['editionMaturity'] or { '' }
			'role':            pd['role'] or { '' }
			'sourceRevision':  pd['sourceRevision'] or { '' }
			'kernel':          uname.release
			'machine':         uname.machine
			'os':              uname.sysname
		}
		desktop:      {
			'activeCompositor':   active_compositor()
			'compositor':         pd['compositor'] or { '' }
			'compositorMaturity': pd['compositorMaturity'] or { '' }
			'sessionType':        os.getenv('XDG_SESSION_TYPE')
			'sessionDesktop':     os.getenv('XDG_SESSION_DESKTOP')
		}
		packages:     {
			'packageSets':    pd['packageSets'] or { '' }
			'profilePackage': pd['profilePackage'] or { '' }
		}
		services:     {
			'assistantEnabled':  settings.enabled.str()
			'assistantEndpoint': settings.endpoint
			'gatewayFeatures':   assistant_required_gateway_features.join(',')
		}
		capabilities: {
			'class': 'safe-read-only'
			'tools': tools
		}
		agents:       {
			'default':          'assistant disabled by default, never required, never root'
			'approvals':        'never auto-answered; approve/deny are explicit user actions'
			'transport':        'loopback http://127.0.0.1:8642, local Bearer [REDACTED] (0600), never printed'
			'studiedHermes':    assistant_studied_hermes_commit
			'gatewayContract':  assistant_supported_hermes
			'knowledgeCommand': 'horneroctl assistant knowledge'
			'vaultCommand':     'horneroctl assistant knowledge vault generate --yes'
		}
	}
}

// knowledge_vault_sources_hash is the change-detection fingerprint:
// sha256 over the canonical (sorted-key) rendering of every section.
pub fn knowledge_vault_sources_hash(sources KnowledgeVaultSources) string {
	mut canonical := ''
	for section in knowledge_vault_sections {
		canonical += '[${section}]\n' + knowledge_vault_render_entries(knowledge_vault_section_sources(sources,
			section))
	}
	return sha256.hexhash(canonical)
}

fn knowledge_vault_render_entries(entries map[string]string) string {
	mut keys := entries.keys()
	keys.sort()
	mut lines := []string{}
	for key in keys {
		if key_is_secret(key) {
			continue
		}
		value := redact_secrets(entries[key].trim_space())
		if value.len == 0 {
			continue
		}
		lines << '- ${key}: ${value}'
	}
	return lines.join('\n') + '\n'
}

// knowledge_vault_render_section renders one bounded section document
// with its provenance header. Pure: same inputs, same bytes.
pub fn knowledge_vault_render_section(section string, sources KnowledgeVaultSources, generated_by string, generated_at string) string {
	header := '# HorneroOS knowledge vault — ${section}\n\nGenerated by ${generated_by} at ${generated_at} (schema ${knowledge_vault_schema}).\nRegenerate: `horneroctl assistant knowledge vault generate --yes`. Do not edit generated files; put annotations in `../notes/` — edited generated files are preserved there on refresh.\n\n'
	mut body := header + knowledge_vault_render_entries(knowledge_vault_section_sources(sources,
		section))
	if body.len > knowledge_vault_max_section_chars {
		body = body[..knowledge_vault_max_section_chars] +
			'\n- … (truncated; live truth is `horneroctl assistant knowledge`)\n'
	}
	return body
}

pub struct KnowledgeVaultStatus {
pub:
	exists         bool
	fresh          bool
	sources_hash   string
	stored_hash    string
	generated_at   string
	generated_by   string
	modified_files []string
	preserved      []string
}

fn knowledge_vault_manifest_path(dir string) string {
	return os.join_path(dir, 'manifest.json')
}

fn knowledge_vault_read_manifest(dir string) map[string]json2.Any {
	raw := os.read_file(knowledge_vault_manifest_path(dir)) or { return map[string]json2.Any{} }
	decoded := json2.decode[json2.Any](raw) or { return map[string]json2.Any{} }
	if decoded !is map[string]json2.Any {
		return map[string]json2.Any{}
	}
	return decoded.as_map()
}

fn knowledge_vault_manifest_string(m map[string]json2.Any, key string) string {
	if key in m && m[key] is string {
		return m[key].str()
	}
	return ''
}

fn knowledge_vault_manifest_files(m map[string]json2.Any) map[string]string {
	mut out := map[string]string{}
	if 'files' in m && m['files'] is map[string]json2.Any {
		for name, value in m['files'].as_map() {
			if value is string {
				out[name] = value.str()
			}
		}
	}
	return out
}

// knowledge_vault_check compares live sources and on-disk generated
// files against the manifest without writing anything.
pub fn knowledge_vault_check(dir string, sources KnowledgeVaultSources) KnowledgeVaultStatus {
	manifest := knowledge_vault_read_manifest(dir)
	if manifest.len == 0 {
		return KnowledgeVaultStatus{}
	}
	stored := knowledge_vault_manifest_string(manifest, 'sourcesHash')
	current := knowledge_vault_sources_hash(sources)
	mut modified := []string{}
	for name, hash in knowledge_vault_manifest_files(manifest) {
		content := os.read_file(os.join_path(dir, 'generated', name)) or {
			modified << name
			continue
		}
		if sha256.hexhash(content) != hash {
			modified << name
		}
	}
	modified.sort()
	return KnowledgeVaultStatus{
		exists:         true
		fresh:          stored == current && modified.len == 0
		sources_hash:   current
		stored_hash:    stored
		generated_at:   knowledge_vault_manifest_string(manifest, 'generatedAt')
		generated_by:   knowledge_vault_manifest_string(manifest, 'generatedBy')
		modified_files: modified
	}
}

pub struct KnowledgeVaultWrite {
pub:
	dir          string
	files        []string
	preserved    []string
	sources_hash string
	changed      bool
}

// knowledge_vault_generate_at writes a fresh snapshot into `dir`.
// User content is preserved: notes/ is only ever added to, and a
// generated file edited since the last manifest is copied into
// notes/ before being rewritten.
pub fn knowledge_vault_generate_at(dir string, sources KnowledgeVaultSources, generated_by string, generated_at string) !KnowledgeVaultWrite {
	previous := knowledge_vault_check(dir, sources)
	old_hashes := knowledge_vault_manifest_files(knowledge_vault_read_manifest(dir))
	generated_dir := os.join_path(dir, 'generated')
	notes_dir := os.join_path(dir, 'notes')
	os.mkdir_all(generated_dir)!
	os.mkdir_all(notes_dir)!
	mut preserved := []string{}
	mut files := map[string]string{}
	mut names := []string{}
	for section in knowledge_vault_sections {
		name := '${section}.md'
		path := os.join_path(generated_dir, name)
		if os.is_file(path) {
			old := os.read_file(path) or { '' }
			if name in old_hashes && sha256.hexhash(old) != old_hashes[name] {
				mut dest := os.join_path(notes_dir, '${section}.user.md')
				if os.exists(dest) {
					dest = os.join_path(notes_dir, '${section}.user-${sha256.hexhash(old)[..8]}.md')
				}
				if !os.exists(dest) {
					os.write_file(dest, old)!
					preserved << 'generated/${name} -> notes/${os.base(dest)}'
				}
			}
		}
		content := knowledge_vault_render_section(section, sources, generated_by, generated_at)
		os.write_file(path, content)!
		os.chmod(path, 0o600) or {}
		files[name] = sha256.hexhash(content)
		names << name
	}
	sources_hash := knowledge_vault_sources_hash(sources)
	mut file_entries := []string{}
	for name in names {
		encoded := json2.encode(name, escape_unicode: true)
		hash := json2.encode(files[name], escape_unicode: true)
		file_entries << '    ${encoded}: ${hash}'
	}
	manifest := '{\n  "schema": ${json2.encode(knowledge_vault_schema, escape_unicode: true)},\n  "generatedBy": ${json2.encode(generated_by,
		escape_unicode: true
	)},\n  "generatedAt": ${json2.encode(generated_at, escape_unicode: true)},\n  "sourcesHash": ${json2.encode(sources_hash,
		escape_unicode: true
	)},\n  "files": {\n${file_entries.join(',\n')}\n  }\n}\n'
	os.write_file(knowledge_vault_manifest_path(dir), manifest)!
	os.chmod(knowledge_vault_manifest_path(dir), 0o600) or {}
	return KnowledgeVaultWrite{
		dir:          dir
		files:        names
		preserved:    preserved
		sources_hash: sources_hash
		changed:      !previous.exists || previous.stored_hash != sources_hash
	}
}

fn knowledge_vault_status_data(status KnowledgeVaultStatus, dir string) map[string]string {
	return {
		'vaultDir':     dir
		'schema':       knowledge_vault_schema
		'exists':       status.exists.str()
		'fresh':        status.fresh.str()
		'sourcesHash':  status.sources_hash
		'storedHash':   status.stored_hash
		'generatedAt':  status.generated_at
		'generatedBy':  status.generated_by
		'modified':     status.modified_files.join(',')
		'regenerate':   'horneroctl assistant knowledge vault generate --yes'
		'userNotesDir': os.join_path(dir, 'notes')
	}
}

// assistant_knowledge_vault_status_report is read-only change
// detection: missing, fresh, stale, or user-modified snapshot.
pub fn assistant_knowledge_vault_status_report() CommandResult {
	dir := knowledge_vault_dir()
	status := knowledge_vault_check(dir, knowledge_vault_collect_sources())
	if !status.exists {
		return ok_result('assistant knowledge vault', 'No knowledge vault snapshot yet at ${dir}. Generate one explicitly: horneroctl assistant knowledge vault generate --yes', knowledge_vault_status_data(status,
			dir))
	}
	mut state := 'fresh'
	if status.modified_files.len > 0 {
		state = 'user-modified (preserved on regeneration)'
	} else if !status.fresh {
		state = 'stale (sources changed since generation)'
	}
	return ok_result('assistant knowledge vault', 'Knowledge vault at ${dir}: ${state}. Generated by ${status.generated_by} at ${status.generated_at}.', knowledge_vault_status_data(status,
		dir))
}

// assistant_knowledge_vault_generate_report is the explicit
// regeneration path. Writes only with --yes; --dry-run previews.
pub fn assistant_knowledge_vault_generate_report(dry_run bool, yes bool) CommandResult {
	dir := knowledge_vault_dir()
	if dry_run {
		status := knowledge_vault_check(dir, knowledge_vault_collect_sources())
		mut data := knowledge_vault_status_data(status, dir)
		data['dryRun'] = 'true'
		return ok_result('assistant knowledge vault', 'Dry run: would regenerate ${knowledge_vault_sections.len} bounded sections under ${dir}/generated plus manifest.json. User files under ${dir}/notes are never overwritten; edited generated files are preserved there first.', data)
	}
	if !yes {
		return fail_result('assistant knowledge vault', 'Regenerating the knowledge vault writes under ${dir}. Preview with --dry-run or confirm explicitly: horneroctl assistant knowledge vault generate --yes')
	}
	sources := knowledge_vault_collect_sources()
	by := cli_version()
	at := time.now().format()
	write := knowledge_vault_generate_at(dir, sources, by, at) or {
		return fail_result('assistant knowledge vault', 'Cannot write the knowledge vault at ${dir}: ${err.msg()}')
	}
	mut data := knowledge_vault_status_data(knowledge_vault_check(dir, sources), dir)
	data['files'] = write.files.join(',')
	data['preserved'] = write.preserved.join('; ')
	data['changed'] = write.changed.str()
	data['generatedBy'] = by
	data['generatedAt'] = at
	msg := 'Knowledge vault regenerated at ${dir} (${write.files.len} sections, changed: ${write.changed}). User notes preserved${if write.preserved.len > 0 {
		': ' + write.preserved.join('; ')
	} else {
		''
	}}.'
	return ok_result('assistant knowledge vault', msg, data)
}
