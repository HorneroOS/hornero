module hornero_core

import crypto.sha256
import os
import time
import x.json2

// Agent config projection (Workflow C): a canonical, user-owned registry of
// instruction / skill / MCP / ACP intent that can be rendered into the native
// file shapes of the external agent CLIs tracked by agent_registry.v.
//
// This module never installs an agent, never executes one, never reads
// credential contents, and never grants approval. It manages text/config
// projection only, with ownership receipts, backups, and idempotent applies.
//
// Canonical registry file (override for tests): $HORNERO_AGENT_CONFIG_FILE,
// else $XDG_CONFIG_HOME/hornero/agent-config.json.
// Ownership receipts: $HORNERO_AGENT_CONFIG_STATE_DIR, else
// $XDG_STATE_HOME/hornero/agent-config/receipts/.
// Backups of pre-existing foreign/unmanaged files: <state>/backups/.

pub const agent_config_schema_version = 1
pub const agent_config_entry_kinds = ['instruction', 'skill', 'mcp', 'acp']

pub struct AgentConfigEntry {
pub:
	id   string
	kind string // instruction | skill | mcp | acp
	name string
	// target agent ids; empty means "all known agents in the registry".
	targets []string
	// content/payload semantics depend on kind:
	// - instruction: markdown/text content (rendered into native instruction file)
	// - skill: markdown content (rendered into <skills_path>/<id>/SKILL.md)
	// - mcp: JSON object string describing one server {name, command?, args?, url?, env?, ...}
	// - acp: JSON object string describing ACP adapter intent (data only)
	content string
	// for kind=skill, optional relative skill directory name; defaults to id.
	skill_id string
}

pub struct AgentConfigRegistry {
pub:
	schema_version int
	entries        []AgentConfigEntry
}

pub fn agent_config_file() string {
	override := os.getenv('HORNERO_AGENT_CONFIG_FILE')
	if override.len > 0 {
		return override
	}
	p := resolve_paths()
	return os.join_path(p.config_dir, 'hornero', 'agent-config.json')
}

pub fn agent_config_state_dir() string {
	override := os.getenv('HORNERO_AGENT_CONFIG_STATE_DIR')
	if override.len > 0 {
		return override
	}
	p := resolve_paths()
	return os.join_path(p.state_dir, 'hornero', 'agent-config')
}

fn agent_config_receipts_dir() string {
	return os.join_path(agent_config_state_dir(), 'receipts')
}

fn agent_config_backups_dir() string {
	return os.join_path(agent_config_state_dir(), 'backups')
}

fn json_str(m map[string]json2.Any, key string) string {
	if key in m && m[key] is string {
		return m[key].str()
	}
	if key in m {
		return m[key].str()
	}
	return ''
}

fn json_str_arr(m map[string]json2.Any, key string) []string {
	mut out := []string{}
	if key !in m {
		return out
	}
	v := m[key]
	if v is []json2.Any {
		for item in v.as_array() {
			out << item.str()
		}
	}
	return out
}

// parse_agent_config_registry decodes the canonical registry. It is strict:
// unknown schema, malformed entries, duplicate ids, or unknown kinds are
// errors (fail closed) rather than silently ignored.
pub fn parse_agent_config_registry(raw string) !AgentConfigRegistry {
	decoded := json2.decode[json2.Any](raw) or { return error('invalid JSON: ${err.msg()}') }
	if decoded !is map[string]json2.Any {
		return error('agent config must be a JSON object')
	}
	root := decoded.as_map()
	sv := if 'schemaVersion' in root { int(root['schemaVersion'].i64()) } else { 0 }
	if sv != agent_config_schema_version {
		return error('unsupported schemaVersion ${sv} (expected ${agent_config_schema_version})')
	}
	if 'entries' !in root || root['entries'] !is []json2.Any {
		return error('agent config needs an "entries" array')
	}
	mut entries := []AgentConfigEntry{}
	mut seen := map[string]bool{}
	for item in root['entries'].as_array() {
		if item !is map[string]json2.Any {
			return error('each entry must be an object')
		}
		em := item.as_map()
		id := json_str(em, 'id').trim_space()
		kind := json_str(em, 'kind').trim_space()
		name := json_str(em, 'name').trim_space()
		if id.len == 0 {
			return error('entry id must not be empty')
		}
		if seen[id] {
			return error('duplicate entry id: ${id}')
		}
		seen[id] = true
		if kind !in agent_config_entry_kinds {
			return error('entry ${id}: unknown kind ${kind} (expected: ${agent_config_entry_kinds.join(', ')})')
		}
		content := json_str(em, 'content')
		skill_id := json_str(em, 'skillId').trim_space()
		targets := json_str_arr(em, 'targets').map(it.trim_space()).filter(it.len > 0)
		// validate target ids against known agents when specified
		for t in targets {
			if t == 'all' {
				continue
			}
			agent_by_id(t) or { return error('entry ${id}: unknown target agent id ${t}') }
		}
		// basic kind payload validation / duplicate/format preflight hints
		if kind == 'mcp' && content.trim_space().len > 0 {
			decoded_mcp := json2.decode[json2.Any](content) or {
				return error('entry ${id}: MCP content must be a JSON object string: ${err.msg()}')
			}
			if decoded_mcp !is map[string]json2.Any {
				return error('entry ${id}: MCP content must be a JSON object')
			}
			mcp_m := decoded_mcp.as_map()
			mcp_name := json_str(mcp_m, 'name').trim_space()
			if mcp_name.len == 0 {
				return error('entry ${id}: MCP content needs a non-empty "name"')
			}
		}
		if kind == 'acp' && content.trim_space().len > 0 {
			decoded_acp := json2.decode[json2.Any](content) or {
				return error('entry ${id}: ACP content must be a JSON object string: ${err.msg()}')
			}
			if decoded_acp !is map[string]json2.Any {
				return error('entry ${id}: ACP content must be a JSON object')
			}
		}
		entries << AgentConfigEntry{
			id:       id
			kind:     kind
			name:     name
			targets:  targets
			content:  content
			skill_id: if skill_id.len > 0 { skill_id } else { id }
		}
	}
	return AgentConfigRegistry{
		schema_version: sv
		entries:        entries
	}
}

pub fn load_agent_config_registry() !AgentConfigRegistry {
	path := agent_config_file()
	if !os.is_file(path) {
		return AgentConfigRegistry{
			schema_version: agent_config_schema_version
			entries:        []AgentConfigEntry{}
		}
	}
	raw := os.read_file(path) or { return error('cannot read ${path}: ${err.msg()}') }
	return parse_agent_config_registry(raw)
}

pub fn agent_config_encode_registry(reg AgentConfigRegistry) string {
	mut parts := []string{}
	for e in reg.entries {
		targets_json := e.targets.map(json2.encode(it, escape_unicode: true)).join(', ')
		parts << '    {\n      "id": ${json2.encode(e.id, escape_unicode: true)},\n      "kind": ${json2.encode(e.kind,
			escape_unicode: true
		)},\n      "name": ${json2.encode(e.name, escape_unicode: true)},\n      "targets": [${targets_json}],\n      "skillId": ${json2.encode(e.skill_id,
			escape_unicode: true
		)},\n      "content": ${json2.encode(e.content, escape_unicode: true)}\n    }'
	}
	return '{\n  "schemaVersion": ${agent_config_schema_version},\n  "entries": [\n${parts.join(',\n')}\n  ]\n}\n'
}

// --- target resolution & native rendering ---

pub struct AgentRenderTarget {
pub:
	agent_id string
	entry_id string
	kind     string
	path     string
	format   string // markdown | toml-mcp | json-mcp-servers | json-mcp | skill-dir | unsupported
	content  string
	reason   string // for unsupported/skip
}

fn entry_applies_to(entry AgentConfigEntry, agent_id string) bool {
	if entry.targets.len == 0 {
		return true
	}
	for t in entry.targets {
		if t == 'all' || t == agent_id {
			return true
		}
	}
	return false
}

fn agent_instruction_target(spec AgentSpec) (string, string) {
	// Return (path, format). Path is the primary user-scope instruction file we own.
	// Formats are render hints; "unsupported" means we record but cannot safely write.
	return match spec.id {
		'javi-hermes' { agent_expand(spec, '~/.hermes/HORNERO.md'), 'markdown' }
		'codex' { os.join_path(os.home_dir(), '.codex', 'AGENTS.hornero.md'), 'markdown' }
		'claude-code' { os.join_path(os.home_dir(), '.claude', 'HORNERO.md'), 'markdown' }
		'opencode' { os.join_path(os.home_dir(), '.config', 'opencode', 'HORNERO.md'), 'markdown' }
		'muse' { '', 'unsupported' }
		else { '', 'unsupported' }
	}
}

fn agent_skills_base(spec AgentSpec) (string, string) {
	return match spec.id {
		'javi-hermes' { agent_expand(spec, spec.skills_path), 'skill-dir' }
		'codex' { agent_expand(spec, spec.skills_path), 'skill-dir' }
		'claude-code' { agent_expand(spec, spec.skills_path), 'skill-dir' }
		'opencode' { agent_expand(spec, spec.skills_path), 'skill-dir' }
		'muse' { agent_expand(spec, spec.skills_path), 'skill-dir' }
		else { '', 'unsupported' }
	}
}

fn agent_mcp_target(spec AgentSpec) (string, string) {
	// Hornero-managed MCP projection files, kept separate from the agent's
	// primary config to avoid clobbering user-owned formats we cannot fully
	// merge (e.g. TOML config.toml). We render canonical MCP intent into a
	// Hornero-owned companion JSON/TOML fragment where the format is known.
	return match spec.id {
		'codex' { os.join_path(os.home_dir(), '.codex', 'mcp.hornero.toml'), 'toml-mcp' }
		'claude-code' {
			os.join_path(os.home_dir(), '.claude', 'mcp.hornero.json'), 'json-mcp-servers'
		}
		'opencode' {
			os.join_path(os.home_dir(), '.config', 'opencode', 'mcp.hornero.json'), 'json-mcp'
		}
		else { '', 'unsupported' }
	}
}

fn agent_acp_target(spec AgentSpec) (string, string) {
	// ACP adapter intent is data-only; no agent has a verified native ACP
	// config file we can safely own. Record/render to a Hornero-owned JSON
	// projection for inspection.
	return match spec.id {
		'codex', 'claude-code', 'opencode' {
			os.join_path(os.home_dir(), '.config', 'hornero', 'agent-acp', '${spec.id}.json'), 'json-acp'
		}
		else { '', 'unsupported' }
	}
}

fn render_instruction_content(entries []AgentConfigEntry) string {
	mut blocks := []string{}
	blocks << '# Hornero managed instructions\n\nThis file is managed by `horneroctl agent config apply`. Manual edits may be preserved as backups on next apply if not Hornero-owned; prefer updating the canonical agent-config registry.\n'
	for e in entries {
		title := if e.name.len > 0 { e.name } else { e.id }
		body := e.content.trim_space()
		if body.len == 0 {
			continue
		}
		blocks << '## ${title} (${e.id})\n\n${body}\n'
	}
	return blocks.join('\n')
}

fn render_skill_content(e AgentConfigEntry) string {
	title := if e.name.len > 0 { e.name } else { e.id }
	body := e.content.trim_space()
	if body.starts_with('---') {
		return body + '\n'
	}
	return '---\nname: ${e.skill_id}\ndescription: ${title}\n---\n\n${body}\n'
}

fn mcp_entry_obj(e AgentConfigEntry) !map[string]json2.Any {
	decoded := json2.decode[json2.Any](e.content) or { return error('invalid MCP JSON: ${err.msg()}') }
	if decoded !is map[string]json2.Any {
		return error('MCP content must be a JSON object')
	}
	return decoded.as_map()
}

fn toml_quote(s string) string {
	mut out := s.replace('\\', '\\\\')
	out = out.replace('"', '\\"')
	out = out.replace('\n', '\\n')
	out = out.replace('\r', '\\r')
	out = out.replace('\t', '\\t')
	return '"${out}"'
}

fn render_mcp_toml(entries []AgentConfigEntry) !string {
	// Render into [mcp_servers.<name>] tables (Codex TOML convention) as a
	// Hornero-owned fragment file. Duplicate server names are an error.
	mut seen_name := map[string]string{}
	mut out := '# Hornero managed MCP servers (Codex fragment)\n# Managed by `horneroctl agent config apply`.\n\n'
	for e in entries {
		obj := mcp_entry_obj(e)!
		name := json_str(obj, 'name').trim_space()
		if name in seen_name {
			return error('duplicate MCP server name "${name}" (entries ${seen_name[name]} and ${e.id})')
		}
		seen_name[name] = e.id
		out += '[mcp_servers.${toml_quote(name)}]\n'
		if 'command' in obj {
			out += 'command = ${toml_quote(obj['command'].str())}\n'
		}
		if 'url' in obj {
			out += 'url = ${toml_quote(obj['url'].str())}\n'
		}
		if 'args' in obj && obj['args'] is []json2.Any {
			args := obj['args'].as_array().map(toml_quote(it.str())).join(', ')
			out += 'args = [${args}]\n'
		}
		if 'env' in obj && obj['env'] is map[string]json2.Any {
			mut keys := obj['env'].as_map().keys()
			keys.sort()
			for k in keys {
				out += '[mcp_servers.${toml_quote(name)}.env]\n'
				out += '${k} = ${toml_quote(obj['env'].as_map()[k].str())}\n'
				break
			}
		}
		out += '\n'
	}
	return out
}

fn render_mcp_json_servers(entries []AgentConfigEntry, wrapper_key string) !string {
	// wrapper_key "mcpServers" (Claude) or "mcp" (OpenCode)
	mut seen_name := map[string]string{}
	mut servers := []string{}
	for e in entries {
		obj := mcp_entry_obj(e)!
		name := json_str(obj, 'name').trim_space()
		if name in seen_name {
			return error('duplicate MCP server name "${name}" (entries ${seen_name[name]} and ${e.id})')
		}
		seen_name[name] = e.id
		// preserve all fields except top-level "name" as server config
		mut fields := []string{}
		mut keys := obj.keys()
		keys.sort()
		for k in keys {
			if k == 'name' {
				continue
			}
			fields << '      ${json2.encode(k, escape_unicode: true)}: ${obj[k].json_str()}'
		}
		servers << '    ${json2.encode(name, escape_unicode: true)}: {\n${fields.join(',\n')}\n    }'
	}
	return '{\n  ${json2.encode(wrapper_key, escape_unicode: true)}: {\n${servers.join(',\n')}\n  }\n}\n'
}

fn render_acp_json(entries []AgentConfigEntry) !string {
	mut seen_name := map[string]string{}
	mut items := []string{}
	for e in entries {
		decoded := json2.decode[json2.Any](e.content) or { return error('invalid ACP JSON: ${err.msg()}') }
		if decoded !is map[string]json2.Any {
			return error('ACP content must be a JSON object')
		}
		obj := decoded.as_map()
		name := json_str(obj, 'name').trim_space()
		key := if name.len > 0 { name } else { e.id }
		if key in seen_name {
			return error('duplicate ACP adapter name "${key}" (entries ${seen_name[key]} and ${e.id})')
		}
		seen_name[key] = e.id
		items << '    ${json2.encode(key, escape_unicode: true)}: ${decoded.json_str()}'
	}
	return '{\n  "adapters": {\n${items.join(',\n')}\n  }\n}\n'
}

pub fn agent_config_render_targets(reg AgentConfigRegistry, only_agent string) []AgentRenderTarget {
	mut targets := []AgentRenderTarget{}
	specs := agent_registry()
	for spec in specs {
		if only_agent.len > 0 && spec.id != only_agent {
			continue
		}
		// instructions: aggregate all instruction entries for this agent into one file
		mut instr_entries := []AgentConfigEntry{}
		mut skill_entries := []AgentConfigEntry{}
		mut mcp_entries := []AgentConfigEntry{}
		mut acp_entries := []AgentConfigEntry{}
		for e in reg.entries {
			if !entry_applies_to(e, spec.id) {
				continue
			}
			match e.kind {
				'instruction' { instr_entries << e }
				'skill' { skill_entries << e }
				'mcp' { mcp_entries << e }
				'acp' { acp_entries << e }
				else {}
			}
		}
		if instr_entries.len > 0 {
			path, format := agent_instruction_target(spec)
			if format == 'unsupported' || path.len == 0 {
				targets << AgentRenderTarget{
					agent_id: spec.id
					entry_id: instr_entries.map(it.id).join(',')
					kind:     'instruction'
					format:   'unsupported'
					reason:   'no supported native instruction renderer for ${spec.id}'
				}
			} else {
				targets << AgentRenderTarget{
					agent_id: spec.id
					entry_id: instr_entries.map(it.id).join(',')
					kind:     'instruction'
					path:     path
					format:   format
					content:  render_instruction_content(instr_entries)
				}
			}
		}
		for e in skill_entries {
			base, format := agent_skills_base(spec)
			if format == 'unsupported' || base.len == 0 {
				targets << AgentRenderTarget{
					agent_id: spec.id
					entry_id: e.id
					kind:     'skill'
					format:   'unsupported'
					reason:   'no supported native skills path for ${spec.id}'
				}
			} else {
				sid := if e.skill_id.len > 0 { e.skill_id } else { e.id }
				targets << AgentRenderTarget{
					agent_id: spec.id
					entry_id: e.id
					kind:     'skill'
					path:     os.join_path(base, sid, 'SKILL.md')
					format:   format
					content:  render_skill_content(e)
				}
			}
		}
		if mcp_entries.len > 0 {
			path, format := agent_mcp_target(spec)
			if format == 'unsupported' || path.len == 0 {
				targets << AgentRenderTarget{
					agent_id: spec.id
					entry_id: mcp_entries.map(it.id).join(',')
					kind:     'mcp'
					format:   'unsupported'
					reason:   'no supported native MCP renderer for ${spec.id}'
				}
			} else {
				content := match format {
					'toml-mcp' {
						render_mcp_toml(mcp_entries) or {
							targets << AgentRenderTarget{
								agent_id: spec.id
								entry_id: mcp_entries.map(it.id).join(',')
								kind:     'mcp'
								path:     path
								format:   format
								reason:   err.msg()
							}
							continue
						}
					}
					'json-mcp-servers' {
						render_mcp_json_servers(mcp_entries, 'mcpServers') or {
							targets << AgentRenderTarget{
								agent_id: spec.id
								entry_id: mcp_entries.map(it.id).join(',')
								kind:     'mcp'
								path:     path
								format:   format
								reason:   err.msg()
							}
							continue
						}
					}
					'json-mcp' {
						render_mcp_json_servers(mcp_entries, 'mcp') or {
							targets << AgentRenderTarget{
								agent_id: spec.id
								entry_id: mcp_entries.map(it.id).join(',')
								kind:     'mcp'
								path:     path
								format:   format
								reason:   err.msg()
							}
							continue
						}
					}
					else { '' }
				}
				targets << AgentRenderTarget{
					agent_id: spec.id
					entry_id: mcp_entries.map(it.id).join(',')
					kind:     'mcp'
					path:     path
					format:   format
					content:  content
				}
			}
		}
		if acp_entries.len > 0 {
			path, format := agent_acp_target(spec)
			if format == 'unsupported' || path.len == 0 {
				targets << AgentRenderTarget{
					agent_id: spec.id
					entry_id: acp_entries.map(it.id).join(',')
					kind:     'acp'
					format:   'unsupported'
					reason:   'no supported native ACP renderer for ${spec.id}'
				}
			} else {
				content := render_acp_json(acp_entries) or {
					targets << AgentRenderTarget{
						agent_id: spec.id
						entry_id: acp_entries.map(it.id).join(',')
						kind:     'acp'
						path:     path
						format:   format
						reason:   err.msg()
					}
					continue
				}
				targets << AgentRenderTarget{
					agent_id: spec.id
					entry_id: acp_entries.map(it.id).join(',')
					kind:     'acp'
					path:     path
					format:   format
					content:  content
				}
			}
		}
	}
	return targets
}

// detect duplicate target paths (two different render outputs claiming same path)
pub fn agent_config_duplicate_paths(targets []AgentRenderTarget) []string {
	mut seen := map[string]string{}
	mut dups := []string{}
	for t in targets {
		if t.path.len == 0 || t.format == 'unsupported' {
			continue
		}
		key := t.path
		label := '${t.agent_id}:${t.kind}:${t.entry_id}'
		if key in seen && seen[key] != label {
			dups << '${key} <= ${seen[key]} and ${label}'
		} else if key !in seen {
			seen[key] = label
		}
	}
	dups.sort()
	return dups
}

// --- ownership receipts & apply ---

fn agent_config_receipt_path(target AgentRenderTarget) string {
	// stable key from agent+kind+path
	key := sha256.hexhash('${target.agent_id}|${target.kind}|${target.path}')
	return os.join_path(agent_config_receipts_dir(), '${key}.json')
}

fn agent_config_hash(content string) string {
	return sha256.hexhash(content)
}

struct AgentConfigReceipt {
	path  string
	hash  string
	agent string
	kind  string
}

fn read_agent_config_receipt(path string) ?AgentConfigReceipt {
	raw := os.read_file(path) or { return none }
	decoded := json2.decode[json2.Any](raw) or { return none }
	if decoded !is map[string]json2.Any {
		return none
	}
	m := decoded.as_map()
	return AgentConfigReceipt{
		path:  json_str(m, 'path')
		hash:  json_str(m, 'hash')
		agent: json_str(m, 'agent')
		kind:  json_str(m, 'kind')
	}
}

fn write_agent_config_receipt(target AgentRenderTarget) ! {
	rdir := agent_config_receipts_dir()
	os.mkdir_all(rdir)!
	rpath := agent_config_receipt_path(target)
	payload := '{\n  "agent": ${json2.encode(target.agent_id, escape_unicode: true)},\n  "kind": ${json2.encode(target.kind,
		escape_unicode: true
	)},\n  "path": ${json2.encode(target.path, escape_unicode: true)},\n  "hash": ${json2.encode(agent_config_hash(target.content),
		escape_unicode: true
	)}\n}\n'
	tmp := rpath + '.tmp'
	os.write_file(tmp, payload)!
	os.chmod(tmp, 0o600)!
	os.mv(tmp, rpath)!
}

fn backup_foreign_file(path string) !string {
	bdir := agent_config_backups_dir()
	os.mkdir_all(bdir)!
	stamp := time.now().unix().str()
	base := os.file_name(path)
	backup := os.join_path(bdir, '${base}.${stamp}.bak')
	// preserve content
	content := os.read_file(path) or { return error('cannot read ${path} for backup: ${err.msg()}') }
	os.write_file(backup, content)!
	os.chmod(backup, 0o600)!
	return backup
}

fn apply_one_target(target AgentRenderTarget, dry_run bool) (string, string) {
	// returns (state, detail). states: applied, unchanged, would-apply, backed-up, unsupported, error, duplicate-content
	if target.format == 'unsupported' {
		return 'unsupported', target.reason
	}
	if target.reason.len > 0 && target.content.len == 0 {
		return 'error', target.reason
	}
	rpath := agent_config_receipt_path(target)
	receipt := read_agent_config_receipt(rpath)
	desired_hash := agent_config_hash(target.content)
	exists := os.is_file(target.path)
	mut current := ''
	if exists {
		current = os.read_file(target.path) or { return 'error', 'cannot read ${target.path}: ${err.msg()}' }
	}
	owned := if rec := receipt {
		exists && current.len >= 0 && rec.hash == agent_config_hash(current) && rec.path == target.path
	} else {
		false
	}
	if exists && agent_config_hash(current) == desired_hash {
		// idempotent: content already correct; ensure receipt exists if we own it or if content matches desired managed form? keep safe: only refresh receipt when already owned or missing file case handled below
		if !owned && receipt == none {
			if dry_run {
				return 'would-adopt', 'content matches desired output; would record ownership receipt for ${target.path}'
			}
			write_agent_config_receipt(target) or { return 'error', 'cannot write receipt: ${err.msg()}' }
			return 'adopted', 'content already matched; recorded ownership receipt'
		}
		return 'unchanged', 'already up to date'
	}
	if exists && !owned {
		if dry_run {
			return 'would-backup', 'would back up unmanaged existing file and write Hornero-owned content to ${target.path}'
		}
		_ = backup_foreign_file(target.path) or { return 'error', err.msg() }
	} else if dry_run {
		return 'would-apply', 'would write ${target.path}'
	}
	dir := os.dir(target.path)
	os.mkdir_all(dir) or { return 'error', 'cannot create ${dir}: ${err.msg()}' }
	tmp := target.path + '.tmp.hornero-agent-config'
	os.write_file(tmp, target.content) or { return 'error', 'cannot write ${tmp}: ${err.msg()}' }
	os.chmod(tmp, 0o600) or { return 'error', 'cannot chmod ${tmp}: ${err.msg()}' }
	os.mv(tmp, target.path) or { return 'error', 'cannot move into ${target.path}: ${err.msg()}' }
	write_agent_config_receipt(target) or { return 'error', 'cannot write receipt: ${err.msg()}' }
	if exists && !owned {
		return 'applied', 'backed up unmanaged file and wrote Hornero-owned content'
	}
	return 'applied', 'wrote Hornero-owned content'
}

pub struct AgentConfigApplySummary {
pub:
	results []map[string]string
	applied int
	changed int
	issues  int
}

pub fn agent_config_apply(reg AgentConfigRegistry, only_agent string, dry_run bool) AgentConfigApplySummary {
	targets := agent_config_render_targets(reg, only_agent)
	dups := agent_config_duplicate_paths(targets)
	mut results := []map[string]string{}
	mut applied := 0
	mut changed := 0
	mut issues := 0
	dup_set := dups.map(it.split(' <= ')[0]).filter(it.len > 0)
	for t in targets {
		// skip apply for duplicate target paths
		mut is_dup := false
		for d in dup_set {
			if d == t.path && t.path.len > 0 {
				is_dup = true
				break
			}
		}
		mut state := ''
		mut detail := ''
		if is_dup {
			state = 'error'
			detail = 'duplicate target path detected; refusing to apply'
			issues++
		} else {
			state, detail = apply_one_target(t, dry_run)
			if state in ['applied', 'adopted'] {
				applied++
				changed++
			} else if state in ['would-apply', 'would-backup', 'would-adopt'] {
				changed++
			} else if state in ['unsupported', 'error'] {
				issues++
			}
		}
		results << {
			'agent':  t.agent_id
			'kind':   t.kind
			'entry':  t.entry_id
			'path':   t.path
			'format': t.format
			'state':  state
			'detail': detail
		}
	}
	return AgentConfigApplySummary{
		results: results
		applied: applied
		changed: changed
		issues:  issues
	}
}

// --- reports ---

fn status_state_for_target(t AgentRenderTarget) (string, string) {
	if t.format == 'unsupported' {
		return 'unsupported', t.reason
	}
	if t.reason.len > 0 && t.content.len == 0 {
		return 'error', t.reason
	}
	exists := os.is_file(t.path)
	if !exists {
		return 'missing', 'target file not present'
	}
	current := os.read_file(t.path) or { return 'error', 'cannot read target' }
	rec := read_agent_config_receipt(agent_config_receipt_path(t)) or {
		if agent_config_hash(current) == agent_config_hash(t.content) {
			return 'untracked-match', 'content matches but no Hornero ownership receipt'
		}
		return 'unmanaged', 'existing file not owned by Hornero agent config'
	}
	if rec.hash != agent_config_hash(current) {
		return 'drifted', 'file changed since last Hornero apply'
	}
	if agent_config_hash(current) != agent_config_hash(t.content) {
		return 'stale', 'canonical registry changed since last apply'
	}
	return 'ok', 'managed and up to date'
}

pub fn agent_config_status_result(only_agent string) CommandResult {
	reg := load_agent_config_registry() or {
		return fail_result('agent config status', 'Cannot load agent config registry: ${err.msg()}')
	}
	if reg.entries.len == 0 {
		return ok_result('agent config status', 'No canonical agent config entries at ${agent_config_file()}. Registry is empty; nothing to project.', {
			'registry':   agent_config_file()
			'entries':    '0'
			'targets':    '0'
			'issues':     '0'
			'duplicates': ''
		})
	}
	targets := agent_config_render_targets(reg, only_agent)
	dups := agent_config_duplicate_paths(targets)
	mut lines := []string{}
	mut issues := 0
	for t in targets {
		state, detail := status_state_for_target(t)
		if state in ['unsupported', 'error', 'drifted', 'stale', 'missing', 'unmanaged'] {
			issues++
		}
		loc := if t.path.len > 0 { t.path } else { '(no target path)' }
		lines << '${t.agent_id} ${t.kind} [${t.entry_id}] -> ${loc}: ${state} (${detail})'
	}
	for d in dups {
		lines << 'duplicate target path: ${d}'
		issues++
	}
	lines << 'Registry ${agent_config_file()}: ${reg.entries.len} entries, ${targets.len} targets, ${issues} issue(s).'
	return ok_result('agent config status', lines.join('\n'), {
		'registry':   agent_config_file()
		'entries':    '${reg.entries.len}'
		'targets':    '${targets.len}'
		'issues':     '${issues}'
		'duplicates': dups.join('; ')
	})
}

pub fn agent_config_check_result(only_agent string) CommandResult {
	res := agent_config_status_result(only_agent)
	// check fails on issues (like doctor semantics for config drift/dups/unsupported)
	if (res.data['issues'] or { '0' }).int() > 0 {
		return CommandResult{
			ok:      false
			command: 'agent config check'
			message: res.message
			data:    res.data
		}
	}
	return CommandResult{
		ok:      true
		command: 'agent config check'
		message: res.message
		data:    res.data
	}
}

pub fn agent_config_apply_result(only_agent string, dry_run bool, yes bool) CommandResult {
	reg := load_agent_config_registry() or {
		return fail_result('agent config apply', 'Cannot load agent config registry: ${err.msg()}')
	}
	if reg.entries.len == 0 {
		return ok_result('agent config apply', 'No canonical agent config entries at ${agent_config_file()}; nothing to apply.', {
			'registry': agent_config_file()
			'entries':  '0'
			'applied':  '0'
			'changed':  '0'
			'issues':   '0'
		})
	}
	targets := agent_config_render_targets(reg, only_agent)
	dups := agent_config_duplicate_paths(targets)
	if dups.len > 0 {
		return fail_result('agent config apply', 'Duplicate target paths detected; refusing to apply:\n- ${dups.join('\n- ')}')
	}
	if !dry_run && !yes {
		return fail_result('agent config apply', 'Applying agent config writes Hornero-owned files (with backups for unmanaged existing files). Preview with --dry-run or confirm with --yes. Nothing written.')
	}
	summary := agent_config_apply(reg, only_agent, dry_run)
	mut lines := []string{}
	for r in summary.results {
		loc := if r['path'].len > 0 { r['path'] } else { '(no target path)' }
		lines << '${r['agent']} ${r['kind']} [${r['entry']}] ${loc}: ${r['state']} - ${r['detail']}'
	}
	verb := if dry_run { 'Dry run' } else { 'Apply' }
	lines << '${verb}: ${summary.applied} applied, ${summary.changed} changed/pending, ${summary.issues} issue(s).'
	data := {
		'registry': agent_config_file()
		'entries':  '${reg.entries.len}'
		'targets':  '${targets.len}'
		'applied':  '${summary.applied}'
		'changed':  '${summary.changed}'
		'issues':   '${summary.issues}'
		'dryRun':   '${dry_run}'
	}
	if summary.issues > 0 && !dry_run {
		// still return structured info but fail so CI/user sees issues (unsupported formats etc.)
		return CommandResult{
			ok:      false
			command: 'agent config apply'
			message: lines.join('\n')
			data:    data
		}
	}
	return ok_result('agent config apply', lines.join('\n'), data)
}
