module hornero_core

import crypto.sha256
import net.http
import os
import time
import x.json2

// Hornero Assistant (Hermes slice 1): user-level, disabled by default.
// The assistant never runs as root, never auto-answers Hermes approvals,
// and slice 1 exposes read-only tools only. Design contract:
// HorneroOS/docs development/hermes-assistant-architecture.md.

pub const assistant_default_endpoint = 'http://127.0.0.1:8642'
pub const assistant_supported_hermes = 'gateway API /v1 (capabilities-negotiated)'

pub struct AssistantSettings {
pub mut:
	enabled  bool
	endpoint string
}

pub struct AssistantEvent {
pub:
	kind string
	data string
}

fn assistant_dir() string {
	paths := resolve_paths()
	return os.join_path(paths.config_dir, 'hornero')
}

pub fn assistant_settings_file() string {
	return os.join_path(assistant_dir(), 'assistant.json')
}

pub fn assistant_key_file() string {
	return os.join_path(assistant_dir(), 'assistant.key')
}

pub fn assistant_load_settings() AssistantSettings {
	raw := os.read_file(assistant_settings_file()) or {
		return AssistantSettings{
			enabled:  false
			endpoint: assistant_default_endpoint
		}
	}
	decoded := json2.decode[json2.Any](raw) or {
		return AssistantSettings{
			enabled:  false
			endpoint: assistant_default_endpoint
		}
	}
	if decoded !is map[string]json2.Any {
		return AssistantSettings{
			enabled:  false
			endpoint: assistant_default_endpoint
		}
	}
	root := decoded.as_map()
	endpoint := if 'endpoint' in root && root['endpoint'] is string {
		root['endpoint'].str()
	} else {
		assistant_default_endpoint
	}
	return AssistantSettings{
		enabled:  'enabled' in root && root['enabled'] is bool && root['enabled'].bool()
		endpoint: if endpoint.starts_with('http://127.0.0.1') || endpoint.starts_with('http://localhost') {
			endpoint
		} else {
			assistant_default_endpoint
		}
	}
}

fn assistant_save_settings(settings AssistantSettings) ! {
	os.mkdir_all(assistant_dir())!
	body := json2.encode({
		'enabled':  json2.Any(settings.enabled)
		'endpoint': json2.Any(settings.endpoint)
	}, escape_unicode: true)
	os.write_file(assistant_settings_file(), body + '\n')!
	os.chmod(assistant_settings_file(), 0o600) or {}
}

fn assistant_load_key() string {
	env := os.getenv('HORNERO_ASSISTANT_KEY')
	if env.len > 0 {
		return env
	}
	return os.read_file(assistant_key_file()) or { '' }.trim_space()
}

fn assistant_ensure_key() !string {
	existing := os.read_file(assistant_key_file()) or { '' }.trim_space()
	if existing.len >= 16 {
		return existing
	}
	seed := '${time.now().unix_nano()}-${os.getpid()}-${assistant_settings_file()}'
	key := sha256.hexhash(seed)
	os.mkdir_all(assistant_dir())!
	os.write_file(assistant_key_file(), key + '\n')!
	os.chmod(assistant_key_file(), 0o600)!
	return key
}

// assistant_tool_argv is the exhaustive slice-1 read-only allowlist.
// Unknown tools and unsafe ids are rejected; nothing here mutates state.
pub fn assistant_tool_argv(tool string, arg string) ![]string {
	match tool {
		'system_info' {
			return ['horneroctl', 'system', 'info', '--json']
		}
		'appearance_status' {
			return ['horneroctl', 'appearance', 'status', '--json']
		}
		'theme_list' {
			return ['horneroctl', 'appearance', 'theme', 'list', '--json']
		}
		'theme_show' {
			if arg.len == 0 || arg.contains('/') || arg.contains('..') {
				return error('theme_show needs a plain theme id')
			}
			return ['horneroctl', 'appearance', 'theme', 'show', arg, '--json']
		}
		'gtk_list' {
			return ['horneroctl', 'appearance', 'gtk', 'list', '--json']
		}
		'gtk_current' {
			return ['horneroctl', 'appearance', 'gtk', 'current', '--json']
		}
		'package_updates' {
			return ['horneroctl', 'package', 'updates', '--json']
		}
		else {
			return error('tool not in the assistant read-only allowlist: ${tool}')
		}
	}
}

pub fn assistant_tools_report() CommandResult {
	mut names := []string{}
	for tool in ['system_info', 'appearance_status', 'theme_list', 'theme_show', 'gtk_list',
		'gtk_current', 'package_updates'] {
		argv := assistant_tool_argv(tool, 'example') or { continue }
		names << '${tool} -> ${argv.join(' ')}'
	}
	return ok_result('assistant tools', 'Read-only tools the assistant may call (slice 1). Mutations need a later, approval-gated slice.', {
		'tools': names.join('; ')
		'class': 'safe-read-only'
	})
}

// parse_sse_events parses a Hermes SSE body into typed events.
// Pure and fixture-tested; unknown fields are preserved as raw data.
pub fn parse_sse_events(body string) []AssistantEvent {
	mut events := []AssistantEvent{}
	mut kind := 'message'
	mut data_lines := []string{}
	for line in body.split('\n') {
		trimmed := line.trim_space()
		if trimmed.len == 0 {
			if data_lines.len > 0 {
				events << AssistantEvent{
					kind: kind
					data: data_lines.join('\n')
				}
				data_lines = []string{}
				kind = 'message'
			}
		} else if trimmed.starts_with('event:') {
			kind = trimmed[6..].trim_space()
		} else if trimmed.starts_with('data:') {
			data_lines << trimmed[5..].trim_space()
		}
	}
	if data_lines.len > 0 {
		events << AssistantEvent{
			kind: kind
			data: data_lines.join('\n')
		}
	}
	return events
}

pub struct AssistantPending {
pub:
	kind    string // approval | clarify | none
	detail  string
	choices []string
}

// assistant_pending_request finds an approval.request or clarify event
// in a run's events. Hermes emits approval.request payloads with a
// redacted command and the choices the client may send back; nothing
// here answers them — the user decides via assistant approve/clarify.
pub fn assistant_pending_request(events []AssistantEvent) AssistantPending {
	for event in events {
		decoded := json2.decode[json2.Any](event.data) or { continue }
		if decoded !is map[string]json2.Any {
			continue
		}
		root := decoded.as_map()
		kind := if 'type' in root && root['type'] is string {
			root['type'].str()
		} else {
			event.kind
		}
		if kind == 'approval.request' || kind == 'approval' {
			detail := if 'command' in root && root['command'] is string {
				root['command'].str()
			} else if 'description' in root && root['description'] is string {
				root['description'].str()
			} else {
				'a tool action'
			}
			mut choices := []string{}
			if 'choices' in root && root['choices'] is []json2.Any {
				for c in root['choices'].as_array() {
					if c is string {
						choices << c.str()
					}
				}
			}
			return AssistantPending{
				kind:    'approval'
				detail:  detail
				choices: choices
			}
		}
		if kind == 'clarify.request' || kind == 'clarify' {
			question := if 'question' in root && root['question'] is string {
				root['question'].str()
			} else {
				'Hermes needs more information.'
			}
			return AssistantPending{
				kind:   'clarify'
				detail: question
			}
		}
	}
	return AssistantPending{
		kind: 'none'
	}
}

pub fn assistant_events_report(run_id string) CommandResult {
	settings := assistant_load_settings()
	if !settings.enabled {
		return fail_result('assistant events', 'Assistant is disabled. Enable it first: horneroctl assistant enable --yes')
	}
	if run_id.len == 0 || run_id.contains('/') || run_id.contains(' ') {
		return fail_result('assistant events', 'Missing or invalid run id. Example: horneroctl assistant events run_abc123')
	}
	resp := assistant_http(settings, .get, '/v1/runs/${run_id}/events', '') or {
		return fail_result('assistant events', 'Cannot reach the Hermes gateway: ${err.msg()}')
	}
	if resp.status_code >= 400 {
		return fail_result('assistant events', 'Hermes returned no events for run ${run_id} (HTTP ${resp.status_code}). The run id may be wrong or expired.')
	}
	events := parse_sse_events(resp.body)
	pending := assistant_pending_request(events)
	text := assistant_collect_text(events)
	mut data := {
		'runId':   run_id
		'events':  events.len.str()
		'pending': pending.kind
	}
	if pending.kind == 'approval' {
		data['detail'] = pending.detail
		return fail_result('assistant events', 'Hermes is waiting for approval on run ${run_id}: ${pending.detail}. Decide with: horneroctl assistant approve ${run_id} approve (or deny). Nothing is auto-approved.')
	}
	if pending.kind == 'clarify' {
		data['detail'] = pending.detail
		return fail_result('assistant events', 'Hermes is asking on run ${run_id}: ${pending.detail} Answer with: horneroctl assistant clarify ${run_id} "<answer>"')
	}
	if text.len == 0 {
		return ok_result('assistant events', 'Run ${run_id}: ${events.len} events, no text output yet.', data)
	}
	data['text'] = text
	return ok_result('assistant events', text, data)
}

// assistant_collect_text extracts user-visible text from run events:
// token deltas first (delta/text fields), else the final output field.
pub fn assistant_collect_text(events []AssistantEvent) string {
	mut streamed := ''
	mut final := ''
	for event in events {
		decoded := json2.decode[json2.Any](event.data) or { continue }
		if decoded !is map[string]json2.Any {
			continue
		}
		root := decoded.as_map()
		for key in ['delta', 'text', 'content'] {
			if key in root && root[key] is string {
				streamed += root[key].str()
			}
		}
		for key in ['output', 'result', 'final'] {
			if key in root && root[key] is string {
				final = root[key].str()
			}
		}
	}
	return if streamed.len > 0 { streamed } else { final }
}

fn assistant_http(settings AssistantSettings, method http.Method, path string, body string) !http.Response {
	mut req := http.Request{
		method: method
		url:    settings.endpoint.trim_right('/') + path
		data:   body
	}
	key := assistant_load_key()
	mut headers := {
		'Content-Type': 'application/json'
	}
	if key.len > 0 {
		headers['Authorization'] = 'Bearer ${key}'
	}
	req.header = http.new_custom_header_from_map(headers)!
	return req.do()
}

fn assistant_gateway_state(settings AssistantSettings) (bool, string) {
	resp := assistant_http(settings, .get, '/v1/capabilities', '') or {
		return false, 'unreachable: ${err.msg()}'
	}
	if resp.status_code != 200 {
		return false, 'HTTP ${resp.status_code}'
	}
	decoded := json2.decode[json2.Any](resp.body) or { return false, 'invalid JSON response' }
	if decoded !is map[string]json2.Any {
		return false, 'unexpected response shape'
	}
	return true, 'capabilities OK'
}

pub fn assistant_status_report() CommandResult {
	settings := assistant_load_settings()
	hermes := find_on_path('hermes')
	mut data := {
		'enabled':  settings.enabled.str()
		'endpoint': settings.endpoint
		'hermes':   if hermes.len > 0 { hermes } else { 'not-found' }
		'keyFile':  assistant_key_file()
	}
	if !settings.enabled {
		return ok_result('assistant status', 'Assistant is disabled (default). Enable it explicitly: horneroctl assistant enable --yes', data)
	}
	reachable, detail := assistant_gateway_state(settings)
	data['gateway'] = if reachable { 'reachable' } else { 'unreachable' }
	data['gatewayDetail'] = detail
	if hermes.len == 0 {
		return fail_result('assistant status', 'Assistant is enabled but Hermes Agent is not installed. Install Hermes through a pinned, auditable package, then run: horneroctl assistant status')
	}
	if !reachable {
		return fail_result('assistant status', 'Assistant is enabled but the Hermes gateway is not answering at ${settings.endpoint} (${detail}). Start Hermes, then retry.')
	}
	return ok_result('assistant status', 'Assistant enabled; Hermes gateway reachable (${assistant_supported_hermes}).', data)
}

pub fn assistant_enable_report(dry_run bool, yes bool) CommandResult {
	if dry_run {
		return ok_result('assistant enable', 'Dry run: would write ${assistant_settings_file()} (enabled=true, endpoint=${assistant_default_endpoint}), generate a local Bearer key at ${assistant_key_file()} (0600), and change nothing else.', {
			'dryRun': 'true'
		})
	}
	if !yes {
		return fail_result('assistant enable', 'Enabling the assistant needs explicit consent. Preview with --dry-run, then run: horneroctl assistant enable --yes')
	}
	hermes := find_on_path('hermes')
	if hermes.len == 0 {
		return fail_result('assistant enable', 'Hermes Agent was not found on PATH. Install Hermes first through a pinned, auditable package (never a remote install script), then retry.')
	}
	mut settings := assistant_load_settings()
	already := settings.enabled
	settings.enabled = true
	assistant_save_settings(settings) or {
		return fail_result('assistant enable', 'Cannot write assistant settings: ${err.msg()}')
	}
	assistant_ensure_key() or {
		return fail_result('assistant enable', 'Cannot write the local assistant key: ${err.msg()}')
	}
	msg := if already {
		'Assistant was already enabled; settings reaffirmed. Start Hermes so its gateway listens on ${settings.endpoint}.'
	} else {
		'Assistant enabled. Start Hermes so its gateway listens on ${settings.endpoint}, then check: horneroctl assistant status'
	}
	return ok_result('assistant enable', msg, {
		'enabled':  'true'
		'endpoint': settings.endpoint
		'hermes':   hermes
	})
}

pub fn assistant_disable_report(dry_run bool, yes bool) CommandResult {
	if dry_run {
		return ok_result('assistant disable', 'Dry run: would set enabled=false in ${assistant_settings_file()}. The key file and Hermes itself are left untouched.', {
			'dryRun': 'true'
		})
	}
	if !yes {
		return fail_result('assistant disable', 'Disabling needs --yes (it changes assistant state). Preview with --dry-run first if unsure.')
	}
	mut settings := assistant_load_settings()
	was := settings.enabled
	settings.enabled = false
	assistant_save_settings(settings) or {
		return fail_result('assistant disable', 'Cannot write assistant settings: ${err.msg()}')
	}
	msg := if was {
		'Assistant disabled. The desktop works exactly as before; no Hermes process is started by Hornero.'
	} else {
		'Assistant was already disabled; nothing changed.'
	}
	return ok_result('assistant disable', msg, {
		'enabled': 'false'
	})
}

pub fn assistant_ask_report(prompt string) CommandResult {
	settings := assistant_load_settings()
	if !settings.enabled {
		return fail_result('assistant ask', 'Assistant is disabled. Enable it first: horneroctl assistant enable --yes')
	}
	if prompt.trim_space().len == 0 {
		return fail_result('assistant ask', 'Missing prompt. Example: horneroctl assistant ask "what updates are available?"')
	}
	body := json2.encode({
		'input': json2.Any(prompt)
	}, escape_unicode: true)
	resp := assistant_http(settings, .post, '/v1/runs', body) or {
		return fail_result('assistant ask', 'Cannot reach the Hermes gateway at ${settings.endpoint}: ${err.msg()}. Start Hermes, then retry.')
	}
	if resp.status_code >= 400 {
		return fail_result('assistant ask', 'Hermes rejected the run (HTTP ${resp.status_code}). Check: horneroctl assistant status')
	}
	decoded := json2.decode[json2.Any](resp.body) or {
		return fail_result('assistant ask', 'Hermes returned an unreadable run response.')
	}
	if decoded !is map[string]json2.Any {
		return fail_result('assistant ask', 'Hermes returned an unexpected run response.')
	}
	root := decoded.as_map()
	run_id := if 'run_id' in root && root['run_id'] is string {
		root['run_id'].str()
	} else if 'id' in root && root['id'] is string {
		root['id'].str()
	} else {
		''
	}
	if run_id.len == 0 {
		return fail_result('assistant ask', 'Hermes did not return a run id.')
	}
	events_resp := assistant_http(settings, .get, '/v1/runs/${run_id}/events', '') or {
		return fail_result('assistant ask', 'Run ${run_id} started but its events could not be read: ${err.msg()}. Cancel with: horneroctl assistant stop ${run_id}')
	}
	events := parse_sse_events(events_resp.body)
	pending := assistant_pending_request(events)
	if pending.kind == 'approval' {
		return fail_result('assistant ask', 'Hermes is waiting for approval on run ${run_id}: ${pending.detail}. Decide with: horneroctl assistant approve ${run_id} approve (or deny). Nothing is auto-approved.')
	}
	if pending.kind == 'clarify' {
		return fail_result('assistant ask', 'Hermes is asking on run ${run_id}: ${pending.detail} Answer with: horneroctl assistant clarify ${run_id} "<answer>"')
	}
	text := assistant_collect_text(events)
	if text.len == 0 {
		return ok_result('assistant ask', 'Run ${run_id} finished without text output. Event count: ${events.len}.', {
			'runId':  run_id
			'events': events.len.str()
		})
	}
	return ok_result('assistant ask', text, {
		'runId':  run_id
		'events': events.len.str()
	})
}

pub fn assistant_stop_report(run_id string) CommandResult {
	settings := assistant_load_settings()
	if run_id.len == 0 || run_id.contains('/') || run_id.contains(' ') {
		return fail_result('assistant stop', 'Missing or invalid run id. Example: horneroctl assistant stop run_abc123')
	}
	resp := assistant_http(settings, .post, '/v1/runs/${run_id}/stop', '{}') or {
		return fail_result('assistant stop', 'Cannot reach the Hermes gateway: ${err.msg()}')
	}
	if resp.status_code >= 400 {
		return fail_result('assistant stop', 'Hermes could not stop run ${run_id} (HTTP ${resp.status_code}). It may already be finished.')
	}
	return ok_result('assistant stop', 'Stop requested for run ${run_id}.', {
		'runId': run_id
	})
}

pub fn assistant_approve_report(run_id string, decision string) CommandResult {
	settings := assistant_load_settings()
	if !settings.enabled {
		return fail_result('assistant approve', 'Assistant is disabled. Enable it first: horneroctl assistant enable --yes')
	}
	if run_id.len == 0 || run_id.contains('/') || run_id.contains(' ') {
		return fail_result('assistant approve', 'Missing or invalid run id. Example: horneroctl assistant approve run_abc123 approve')
	}
	if decision !in ['approve', 'deny'] {
		return fail_result('assistant approve', 'Decision must be approve or deny. Example: horneroctl assistant approve ${run_id} deny')
	}
	body := json2.encode({
		'decision': json2.Any(decision)
	}, escape_unicode: true)
	resp := assistant_http(settings, .post, '/v1/runs/${run_id}/approval', body) or {
		return fail_result('assistant approve', 'Cannot reach the Hermes gateway: ${err.msg()}')
	}
	if resp.status_code >= 400 {
		return fail_result('assistant approve', 'Hermes did not accept the ${decision} for run ${run_id} (HTTP ${resp.status_code}). The run may already be finished.')
	}
	return ok_result('assistant approve', 'Decision recorded for run ${run_id}: ${decision}.', {
		'runId':    run_id
		'decision': decision
	})
}

pub fn assistant_clarify_report(run_id string, answer string) CommandResult {
	settings := assistant_load_settings()
	if !settings.enabled {
		return fail_result('assistant clarify', 'Assistant is disabled. Enable it first: horneroctl assistant enable --yes')
	}
	if run_id.len == 0 || run_id.contains('/') || run_id.contains(' ') {
		return fail_result('assistant clarify', 'Missing or invalid run id. Example: horneroctl assistant clarify run_abc123 "use the dark theme"')
	}
	if answer.trim_space().len == 0 {
		return fail_result('assistant clarify', 'Missing answer text. Example: horneroctl assistant clarify ${run_id} "use the dark theme"')
	}
	body := json2.encode({
		'answer': json2.Any(answer)
	}, escape_unicode: true)
	resp := assistant_http(settings, .post, '/v1/runs/${run_id}/clarify', body) or {
		return fail_result('assistant clarify', 'Cannot reach the Hermes gateway: ${err.msg()}')
	}
	if resp.status_code >= 400 {
		return fail_result('assistant clarify', 'Hermes did not accept the clarification for run ${run_id} (HTTP ${resp.status_code}).')
	}
	return ok_result('assistant clarify', 'Clarification sent for run ${run_id}.', {
		'runId': run_id
	})
}
