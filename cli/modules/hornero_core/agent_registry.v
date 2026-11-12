module hornero_core

import os
import x.json2

// Agent Registry (Workflow A, first vertical slice): declarative DATA for
// external coding/agent CLIs HorneroOS can discover on a workstation.
// This module never installs, uninstalls, launches, or approves anything:
// `agent list|status|doctor|default show` are read-only, `default set`
// only records the user's choice under XDG config, and `agent launch`
// returns a dry-run proposal only (no execution, no auto-approval/YOLO).
// Capability fields that Hornero has not verified upstream are recorded
// as 'unknown'/'not-detectable' rather than guessed. Auth detection is
// file-presence only; credential contents are never read. ACP/MCP are
// data formats, not security boundaries (see the Javi harness in
// assistant_*.v, which this registry does not replace).

pub const agent_schema_version = 1

pub struct AgentSpec {
pub:
	id               string
	name             string
	exec             string
	discovery        string
	install_source   string
	arch             string
	auth_detectable  string // probe kind: 'file-presence' or 'not-detectable'
	auth_path        string // '~/...' path probed for presence only, '' if none
	config_path      string // '~/...' primary config file/dir
	home_env         string // env var overriding the agent home, '' if none
	instruction_path string
	skills_path      string
	mcp_format       string
	acp              string
	session          string
	approval         string
	sandbox          string
	usage            string
	uninstall        string
}

pub fn agent_registry() []AgentSpec {
	return [
		AgentSpec{
			id:               'javi-hermes'
			name:             'Javi (Hermes)'
			exec:             'hermes'
			discovery:        'PATH lookup for `hermes`; home from $HERMES_HOME or ~/.hermes'
			install_source:   'Hornero assistant setup contract (pinned NousResearch/hermes-agent source); horneroctl never downloads it'
			arch:             'upstream Hermes Agent gateway (loopback HTTP API)'
			auth_detectable:  'file-presence'
			auth_path:        '~/.hermes/auth.json'
			config_path:      '~/.hermes/config.yaml'
			home_env:         'HERMES_HOME'
			instruction_path: '~/.hermes/SOUL.md (Hornero-managed via `assistant prompt`)'
			skills_path:      '~/.hermes/skills'
			mcp_format:       'unknown (not verified by Hornero; Hermes config.yaml owns it)'
			acp:              'none known; Hornero talks to the Hermes gateway API, not ACP'
			session:          '`horneroctl assistant sessions` names continuity keys; Hermes owns conversations'
			approval:         'manual only via `horneroctl assistant approve`; never auto-approved'
			sandbox:          'Hornero Javi harness (bubblewrap gateway unit, ABAC broker) — owned by assistant_*.v, not this registry'
			usage:            '`horneroctl assistant usage` (Hermes local state aggregates)'
			uninstall:        '`horneroctl assistant setup --remove --yes` removes Hornero-owned files only; the Hermes install itself is untouched'
		},
		AgentSpec{
			id:               'codex'
			name:             'OpenAI Codex'
			exec:             'codex'
			discovery:        'PATH lookup for `codex`; home from $CODEX_HOME or ~/.codex'
			install_source:   'upstream OpenAI Codex (OS package or npm @openai/codex); not installed by horneroctl'
			arch:             'standalone CLI binary (interactive TUI + `codex exec`)'
			auth_detectable:  'file-presence'
			auth_path:        '~/.codex/auth.json'
			config_path:      '~/.codex/config.toml'
			home_env:         'CODEX_HOME'
			instruction_path: 'AGENTS.md (project tree) and ~/.codex/AGENTS.md'
			skills_path:      '~/.codex/skills'
			mcp_format:       'TOML [mcp_servers] tables in config.toml'
			acp:              'via external codex-acp adapter (not bundled with HorneroOS)'
			session:          '`codex resume` (upstream-owned session store under Codex home)'
			approval:         'upstream approval modes (--ask-for-approval); horneroctl never passes an auto-approve flag'
			sandbox:          'upstream Codex sandbox (OS-enforced where supported); not a Hornero boundary'
			usage:            'unknown (no local usage command verified by Hornero)'
			uninstall:        'remove the upstream package/binary yourself; ~/.codex config and sessions remain until you delete them'
		},
		AgentSpec{
			id:               'claude-code'
			name:             'Claude Code'
			exec:             'claude'
			discovery:        'PATH lookup for `claude`; config under ~/.claude'
			install_source:   'upstream Anthropic Claude Code (OS package/npm/native installer); not installed by horneroctl'
			arch:             'standalone CLI binary (interactive TUI + headless -p)'
			auth_detectable:  'file-presence'
			auth_path:        '~/.claude/.credentials.json'
			config_path:      '~/.claude/settings.json'
			home_env:         ''
			instruction_path: 'CLAUDE.md (project tree) and ~/.claude/CLAUDE.md'
			skills_path:      '~/.claude/skills'
			mcp_format:       'JSON "mcpServers" in ~/.claude.json and project .mcp.json'
			acp:              'via external claude-code-acp adapter (not bundled with HorneroOS)'
			session:          '`claude --continue` / `claude --resume` (upstream-owned store)'
			approval:         'upstream permission modes; horneroctl never passes a skip-permissions flag'
			sandbox:          'upstream settings-level sandbox only; not a Hornero boundary'
			usage:            'unknown (no local usage command verified by Hornero)'
			uninstall:        'remove the upstream package/binary yourself; ~/.claude config and sessions remain until you delete them'
		},
		AgentSpec{
			id:               'muse'
			name:             'Muse Code'
			exec:             'muse'
			discovery:        'PATH lookup for `muse`; config under ~/.config/muse'
			install_source:   'upstream Muse Code distribution; not installed by horneroctl'
			arch:             'standalone CLI binary (interactive TUI, `muse exec`, `muse resume`)'
			auth_detectable:  'file-presence'
			auth_path:        '~/.config/muse/auth.json'
			config_path:      '~/.config/muse/settings.json'
			home_env:         ''
			instruction_path: 'unknown (no user instruction file verified by Hornero)'
			skills_path:      '~/.config/muse/skills'
			mcp_format:       'unknown (MSP wire protocol; not verified as MCP by Hornero)'
			acp:              'unknown (not verified by Hornero)'
			session:          '`muse resume` (upstream-owned session store)'
			approval:         'upstream approval flow; horneroctl never passes an auto-approve flag'
			sandbox:          'upstream `muse sandbox` OS sandbox support; not a Hornero boundary'
			usage:            'unknown (no local usage command verified by Hornero)'
			uninstall:        'remove the upstream binary yourself; ~/.config/muse config and sessions remain until you delete them'
		},
		AgentSpec{
			id:               'opencode'
			name:             'OpenCode'
			exec:             'opencode'
			discovery:        'PATH lookup for `opencode`; config under ~/.config/opencode'
			install_source:   'upstream OpenCode (OS package/npm/binary release); not installed by horneroctl'
			arch:             'standalone CLI binary (TUI + background server)'
			auth_detectable:  'file-presence'
			auth_path:        '~/.local/share/opencode/auth.json'
			config_path:      '~/.config/opencode/opencode.json'
			home_env:         ''
			instruction_path: 'AGENTS.md (project tree)'
			skills_path:      '~/.config/opencode/skills'
			mcp_format:       'JSON "mcp" object in opencode.json/opencode.jsonc'
			acp:              '`opencode acp` (upstream ACP server mode)'
			session:          '`opencode --continue` / `--session <id>` (upstream-owned store)'
			approval:         'upstream permission config; horneroctl never passes --auto'
			sandbox:          'permission-based only (no OS sandbox verified); not a Hornero boundary'
			usage:            'unknown (no local usage command verified by Hornero)'
			uninstall:        'remove the upstream package/binary yourself; ~/.config/opencode and ~/.local/share/opencode remain until you delete them'
		},
	]
}

pub fn agent_by_id(id string) ?AgentSpec {
	for spec in agent_registry() {
		if spec.id == id {
			return spec
		}
	}
	return none
}

pub fn agent_ids() []string {
	return agent_registry().map(it.id)
}

// agent_expand resolves a '~/...' registry path against the real home
// (or the agent's home env override when set). Non-'~' paths pass through.
pub fn agent_expand(spec AgentSpec, path string) string {
	if !path.starts_with('~/') {
		return path
	}
	rest := path[2..]
	if spec.home_env.len > 0 {
		override := os.getenv(spec.home_env)
		if override.len > 0 {
			// auth/config paths are recorded relative to the agent home.
			parts := rest.split('/')
			if parts.len > 1 {
				return os.join_path(override, parts[1..].join(os.path_separator))
			}
			return override
		}
	}
	return os.join_path(os.home_dir(), rest)
}

pub struct AgentStatus {
pub:
	spec           AgentSpec
	resolved_path  string
	installed      bool
	config_present bool
	auth_state     string // 'present', 'absent', or 'not-detectable'
}

// agent_probe is read-only: PATH lookup plus file-presence checks.
// Credential file contents are never read.
pub fn agent_probe(spec AgentSpec) AgentStatus {
	resolved := find_on_path(spec.exec)
	config := agent_expand(spec, spec.config_path)
	mut auth_state := 'not-detectable'
	if spec.auth_detectable == 'file-presence' && spec.auth_path.len > 0 {
		auth_state = if os.exists(agent_expand(spec, spec.auth_path)) {
			'present'
		} else {
			'absent'
		}
	}
	return AgentStatus{
		spec:           spec
		resolved_path:  resolved
		installed:      resolved.len > 0
		config_present: os.exists(config)
		auth_state:     auth_state
	}
}

fn agent_status_line(st AgentStatus) string {
	installed := if st.installed { st.resolved_path } else { 'not found on PATH' }
	config := if st.config_present { 'present' } else { 'absent' }
	return '${st.spec.id}: ${st.spec.name} — exec ${st.spec.exec} (${installed}); config ${config}; auth ${st.auth_state}'
}

fn agent_status_data(st AgentStatus) map[string]string {
	return {
		'id':             st.spec.id
		'name':           st.spec.name
		'exec':           st.spec.exec
		'resolved_path':  st.resolved_path
		'installed':      '${st.installed}'
		'config_path':    agent_expand(st.spec, st.spec.config_path)
		'config_present': '${st.config_present}'
		'auth':           st.auth_state
		'is_default':     '${agent_default_id() == st.spec.id}'
	}
}

pub fn agent_list_result() CommandResult {
	mut lines := []string{}
	mut data := map[string]string{}
	mut ids := []string{}
	for spec in agent_registry() {
		st := agent_probe(spec)
		lines << agent_status_line(st)
		ids << spec.id
		data['agent.${spec.id}.installed'] = '${st.installed}'
		data['agent.${spec.id}.exec'] = spec.exec
	}
	data['agents'] = ids.join(',')
	data['count'] = '${ids.len}'
	data['default'] = agent_default_id()
	lines << 'Registered agents: ${ids.len} (declarative registry; nothing installed or launched by this command).'
	return ok_result('agent list', lines.join('\n'), data)
}

pub fn agent_status_result(id string) CommandResult {
	if id.len == 0 {
		return agent_list_result()
	}
	spec := agent_by_id(id) or {
		return fail_result('agent status', 'Unknown agent id: ${id}. Known: ${agent_ids().join(', ')}')
	}
	st := agent_probe(spec)
	mut data := agent_status_data(st)
	data['install_source'] = spec.install_source
	data['arch'] = spec.arch
	data['discovery'] = spec.discovery
	data['instruction_path'] = spec.instruction_path
	data['skills_path'] = spec.skills_path
	data['mcp_format'] = spec.mcp_format
	data['acp'] = spec.acp
	data['session'] = spec.session
	data['approval'] = spec.approval
	data['sandbox'] = spec.sandbox
	data['usage'] = spec.usage
	data['uninstall'] = spec.uninstall
	return ok_result('agent status', agent_status_line(st), data)
}

pub fn agent_doctor_result() CommandResult {
	mut checks := []DoctorCheck{}
	for spec in agent_registry() {
		st := agent_probe(spec)
		// A missing optional agent is an observation, not a failure:
		// doctor only fails when the recorded default is unusable.
		checks << DoctorCheck{
			name:   'agent-${spec.id}'
			ok:     true
			detail: agent_status_line(st)
		}
	}
	def := agent_default_id()
	if def.len > 0 {
		spec := agent_by_id(def) or {
			checks << DoctorCheck{
				name:   'agent-default'
				ok:     false
				detail: 'recorded default "${def}" is not a registered agent id'
			}
			return agent_doctor_render(checks)
		}
		st := agent_probe(spec)
		checks << DoctorCheck{
			name:   'agent-default'
			ok:     st.installed
			detail: if st.installed {
				'default ${def} resolves to ${st.resolved_path}'
			} else {
				'default ${def} is recorded but ${spec.exec} is not on PATH'
			}
		}
	} else {
		checks << DoctorCheck{
			name:   'agent-default'
			ok:     true
			detail: 'no default agent recorded (set one with: horneroctl agent default set <id> --yes)'
		}
	}
	return agent_doctor_render(checks)
}

fn agent_doctor_render(checks []DoctorCheck) CommandResult {
	mut lines := []string{}
	mut failed := 0
	mut data := map[string]string{}
	for c in checks {
		mark := if c.ok { 'ok' } else { 'FAIL' }
		if !c.ok {
			failed++
		}
		lines << '${mark}  ${c.name}: ${c.detail}'
		data[c.name] = if c.ok { 'ok' } else { 'fail' }
	}
	if failed == 0 {
		lines << 'agent doctor: all ${checks.len} checks passed'
	} else {
		lines << 'agent doctor: ${failed}/${checks.len} checks failed'
	}
	return CommandResult{
		command: 'agent doctor'
		ok:      failed == 0
		message: lines.join('\n')
		data:    data
	}
}

// --- default agent selection (user-scoped XDG state) ---

pub fn agent_default_file() string {
	override := os.getenv('HORNERO_AGENT_DEFAULT_FILE')
	if override.len > 0 {
		return override
	}
	p := resolve_paths()
	return os.join_path(p.config_dir, 'hornero', 'agent-default.json')
}

// agent_default_id returns the recorded default, or '' when none/invalid.
// Invalid state is reported by doctor, never silently trusted here.
pub fn agent_default_id() string {
	path := agent_default_file()
	if !os.is_file(path) {
		return ''
	}
	raw := os.read_file(path) or { return '' }
	id := parse_agent_default(raw) or { return '' }
	return id
}

pub fn parse_agent_default(raw string) !string {
	decoded := json2.decode[json2.Any](raw) or { return error('invalid JSON: ${err.msg()}') }
	if decoded !is map[string]json2.Any {
		return error('agent default must be a JSON object')
	}
	root := decoded.as_map()
	version_any := root['schemaVersion'] or { return error('agent default needs schemaVersion') }
	if int(version_any.i64()) != agent_schema_version {
		return error('unsupported agent default schemaVersion ${version_any.i64()} (expected ${agent_schema_version})')
	}
	id_any := root['default'] or { return error('agent default needs "default"') }
	id := id_any.str().trim_space()
	agent_by_id(id) or { return error('unknown agent id ${id}') }
	return id
}

pub fn agent_encode_default(id string) string {
	return '{\n  "schemaVersion": ${agent_schema_version},\n  "default": "${id}"\n}\n'
}

pub fn agent_default_show_result() CommandResult {
	path := agent_default_file()
	def := agent_default_id()
	if def.len == 0 {
		if os.is_file(path) {
			return fail_result('agent default show', 'Recorded default at ${path} is invalid; fix or remove it. Known ids: ${agent_ids().join(', ')}')
		}
		return ok_result('agent default show', 'No default agent recorded at ${path}. Set one with: horneroctl agent default set <id> --yes', {
			'state':   'not-selected'
			'file':    path
			'default': ''
		})
	}
	return ok_result('agent default show', 'Default agent: ${def} (recorded at ${path}). Recording a default installs and launches nothing.', {
		'state':   'recorded'
		'file':    path
		'default': def
	})
}

pub fn agent_default_set_result(id string, dry_run bool, yes bool) CommandResult {
	agent_by_id(id) or {
		return fail_result('agent default set', 'Unknown agent id: ${id}. Known: ${agent_ids().join(', ')}')
	}
	path := agent_default_file()
	if dry_run {
		return ok_result('agent default set', 'Dry run: would record default agent ${id} at ${path}; nothing written, nothing installed or launched.', {
			'state':   'dry-run'
			'file':    path
			'default': id
		})
	}
	if !yes {
		return fail_result('agent default set', 'Recording a default needs explicit consent: re-run with --yes (or preview with --dry-run). Nothing written.')
	}
	dir := os.dir(path)
	os.mkdir_all(dir) or { return fail_result('agent default set', 'cannot create ${dir}: ${err.msg()}') }
	tmp := os.join_path(dir, '.agent-default.json.tmp')
	os.write_file(tmp, agent_encode_default(id)) or {
		return fail_result('agent default set', 'cannot write ${tmp}: ${err.msg()}')
	}
	os.mv(tmp, path) or { return fail_result('agent default set', 'cannot move ${tmp} to ${path}: ${err.msg()}') }
	return ok_result('agent default set', 'Recorded default agent ${id} at ${path}. Nothing was installed or launched.', {
		'state':   'recorded'
		'file':    path
		'default': id
	})
}

// agent_launch_result is a DRY-RUN proposal only: it builds the exact
// command line that *would* run and never executes it. There is no
// execution path and no auto-approval flag in this slice.
pub fn agent_launch_result(id string) CommandResult {
	spec := agent_by_id(id) or {
		return fail_result('agent launch', 'Unknown agent id: ${id}. Known: ${agent_ids().join(', ')}')
	}
	st := agent_probe(spec)
	prog := if st.installed { st.resolved_path } else { spec.exec }
	proposal := command_line(prog, []string{})
	mut note := 'Dry-run proposal only: nothing was executed, no approval was granted, and no auto-approve/YOLO flag is ever added by horneroctl.'
	if !st.installed {
		note = '${spec.exec} is not on PATH, so this proposal could not run yet. Install source: ${spec.install_source}. ' + note
	}
	return ok_result('agent launch', 'Would launch: ${proposal}\n${note}', {
		'id':        spec.id
		'proposal':  proposal
		'dry_run':   'true'
		'executed':  'false'
		'installed': '${st.installed}'
		'approval':  spec.approval
	})
}
