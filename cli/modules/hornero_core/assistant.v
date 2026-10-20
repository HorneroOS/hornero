module hornero_core

import crypto.rand
import crypto.sha256
import encoding.base64
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

// Protocol support is negotiated, not version-matched: Hermes exposes
// no gateway semver, so `assistant status` requires the feature flags
// this client actually uses. Studied upstream: NousResearch/hermes-agent
// f14699a1379838862d3020b97785796aa555d36d
// (gateway/platforms/api_server.py, _handle_capabilities).
pub const assistant_studied_hermes_commit = 'f14699a1379838862d3020b97785796aa555d36d'
pub const assistant_required_gateway_features = [
	'run_submission',
	'run_events_sse',
	'run_stop',
	'run_approval_response',
	'approval_events',
]

pub struct AssistantSettings {
pub mut:
	enabled  bool
	endpoint string
	// Stored endpoint that failed validation (never persisted, never used).
	rejected_endpoint string
}

// Structural loopback validation for the gateway endpoint (hornero#169).
// String-prefix checks accept spellings whose parsed host is not loopback,
// so parse scheme/host/port explicitly: http only, host exactly 127.0.0.1,
// localhost or [::1], no userinfo, port 1-65535 when present, no path
// beyond an optional trailing slash.
pub fn assistant_endpoint_is_loopback(raw string) bool {
	trimmed := raw.trim_space()
	if !trimmed.starts_with('http://') {
		return false
	}
	rest := trimmed['http://'.len..]
	if rest.len == 0 || rest.contains_any(' \t\r\n') {
		return false
	}
	authority := rest.split('/')[0]
	if rest.len > authority.len && rest[authority.len..] != '/' {
		return false
	}
	if authority.contains('@') {
		return false
	}
	mut host := authority
	if authority.starts_with('[') {
		close := authority.index(']') or { return false }
		host = authority[1..close]
		tail := authority[close + 1..]
		if tail.len > 0 {
			if !tail.starts_with(':') {
				return false
			}
			return host == '::1' && assistant_valid_port(tail[1..])
		}
		return host == '::1'
	}
	if authority.contains(':') {
		parts := authority.split(':')
		if parts.len != 2 {
			return false
		}
		host = parts[0]
		if !assistant_valid_port(parts[1]) {
			return false
		}
	}
	return host == '127.0.0.1' || host == 'localhost'
}

fn assistant_valid_port(port string) bool {
	if port.len == 0 || port.len > 5 {
		return false
	}
	for ch in port {
		if ch < `0` || ch > `9` {
			return false
		}
	}
	n := port.int()
	return n >= 1 && n <= 65535
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
	valid := assistant_endpoint_is_loopback(endpoint)
	return AssistantSettings{
		enabled:           'enabled' in root && root['enabled'] is bool && root['enabled'].bool()
		endpoint:          if valid { endpoint.trim_right('/') } else { assistant_default_endpoint }
		rejected_endpoint: if valid { '' } else { endpoint }
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

// New keys come from the OS CSPRNG (hornero#170): 32 random bytes,
// hex-encoded. Never derive a credential from time/pid/path again.
fn assistant_generate_key() !string {
	raw := rand.bytes(32)!
	return raw.hex()
}

fn assistant_ensure_key() !string {
	existing := os.read_file(assistant_key_file()) or { '' }.trim_space()
	if existing.len >= 16 {
		return existing
	}
	key := assistant_generate_key()!
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

// assistant_knowledge_report renders the live read-only catalogue as a
// dated, provenance-stamped snapshot for agents that cannot execute
// commands. It is generated from the same allowlist as `tools`, so it
// cannot drift from what the assistant may actually call; it never
// embeds the gateway key or any local secret.
pub fn assistant_knowledge_report() CommandResult {
	report := assistant_tools_report()
	tools := report.data['tools'] or { '' }
	return ok_result('assistant knowledge', 'Live HorneroOS knowledge snapshot for the assistant. Regenerate instead of copying by hand; truth is `horneroctl assistant tools --json`.', {
		'generated_by': cli_version()
		'generated_at': time.now().format()
		'tools':        tools
		'class':        'safe-read-only'
		'transport':    'loopback http://127.0.0.1:8642, local Bearer [REDACTED] (0600), never printed'
		'approvals':    'never auto-answered; approve/deny are explicit user actions'
		'default':      'assistant disabled by default, never required, never root'
	})
}

// SseStreamParser incrementally parses a Hermes SSE stream.
// feed() accepts arbitrary chunk boundaries (a line may be split
// across chunks) and returns the events completed by that chunk;
// finish() flushes a trailing event without a blank separator.
pub struct SseStreamParser {
mut:
	buffer     string
	kind       string = 'message'
	data_lines []string
}

pub fn (mut p SseStreamParser) feed(chunk string) []AssistantEvent {
	p.buffer += chunk
	mut events := []AssistantEvent{}
	for {
		idx := p.buffer.index('\n') or { break }
		line := p.buffer[..idx]
		p.buffer = p.buffer[idx + 1..]
		if ev := p.feed_line(line) {
			events << ev
		}
	}
	return events
}

pub fn (mut p SseStreamParser) finish() []AssistantEvent {
	mut events := []AssistantEvent{}
	if p.buffer.len > 0 {
		line := p.buffer
		p.buffer = ''
		if ev := p.feed_line(line) {
			events << ev
		}
	}
	if p.data_lines.len > 0 {
		events << AssistantEvent{
			kind: p.kind
			data: p.data_lines.join('\n')
		}
		p.data_lines = []string{}
		p.kind = 'message'
	}
	return events
}

fn (mut p SseStreamParser) feed_line(line string) ?AssistantEvent {
	trimmed := line.trim_space()
	if trimmed.len == 0 {
		if p.data_lines.len > 0 {
			ev := AssistantEvent{
				kind: p.kind
				data: p.data_lines.join('\n')
			}
			p.data_lines = []string{}
			p.kind = 'message'
			return ev
		}
		return none
	}
	if trimmed.starts_with('event:') {
		p.kind = trimmed[6..].trim_space()
	} else if trimmed.starts_with('data:') {
		p.data_lines << trimmed[5..].trim_space()
	}
	return none
}

// parse_sse_events parses a whole Hermes SSE body into typed events.
// Pure and fixture-tested; unknown fields are preserved as raw data.
pub fn parse_sse_events(body string) []AssistantEvent {
	mut parser := SseStreamParser{}
	mut events := parser.feed(body)
	events << parser.finish()
	return events
}

// assistant_event_text extracts the streamed text delta of a single
// event (delta/text/content fields); final-output fields are handled
// by assistant_collect_text / assistant_event_final.
pub fn assistant_event_text(event AssistantEvent) string {
	decoded := json2.decode[json2.Any](event.data) or { return '' }
	if decoded !is map[string]json2.Any {
		return ''
	}
	root := decoded.as_map()
	mut text := ''
	for key in ['delta', 'text', 'content'] {
		if key in root && root[key] is string {
			text += root[key].str()
		}
	}
	return text
}

pub fn assistant_event_final(event AssistantEvent) string {
	decoded := json2.decode[json2.Any](event.data) or { return '' }
	if decoded !is map[string]json2.Any {
		return ''
	}
	root := decoded.as_map()
	for key in ['output', 'result', 'final'] {
		if key in root && root[key] is string {
			return root[key].str()
		}
	}
	return ''
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
	return assistant_events_outcome('assistant events', run_id, events)
}

// assistant_event_trace classifies the non-answer activity of a run:
// the gateway maps provider reasoning previews to tool.progress events
// with tool_name "_thinking" (capability reasoning_streaming), tool
// lifecycle to tool.started/completed/failed, and mid-turn notes to
// assistant.commentary. This is the provider's emitted activity trace,
// never the model's raw chain-of-thought (providers do not expose it).
// Returns (kind, text) with kind thinking|tool|commentary, or ('','').
pub fn assistant_event_trace(event AssistantEvent) (string, string) {
	decoded := json2.decode[json2.Any](event.data) or { return '', '' }
	if decoded !is map[string]json2.Any {
		return '', ''
	}
	root := decoded.as_map()
	kind := if 'event' in root && root['event'] is string {
		root['event'].str()
	} else if 'type' in root && root['type'] is string {
		root['type'].str()
	} else {
		event.kind
	}
	field := fn (m map[string]json2.Any, k string) string {
		if k in m && m[k] is string {
			return m[k].str()
		}
		return ''
	}
	tool_name := if field(root, 'tool').len > 0 {
		field(root, 'tool')
	} else {
		field(root, 'tool_name')
	}
	match kind {
		'tool.progress' {
			delta := field(root, 'delta')
			if tool_name == '_thinking' {
				if delta.len > 0 {
					return 'thinking', delta
				}
				return '', ''
			}
			if tool_name.len > 0 && delta.len > 0 {
				return 'tool', '${tool_name}: ${delta}'
			}
			return '', ''
		}
		'tool.started' {
			if tool_name.len == 0 {
				return '', ''
			}
			preview := field(root, 'preview')
			if preview.len > 0 {
				short := if preview.len > 120 { preview[..120] + '…' } else { preview }
				return 'tool', '▸ ${tool_name}: ${short}'
			}
			return 'tool', '▸ ${tool_name}'
		}
		'tool.completed' {
			if tool_name.len == 0 {
				return '', ''
			}
			failed := 'error' in root && root['error'] is bool && root['error'].bool()
			if failed {
				return 'tool', '✗ ${tool_name}'
			}
			return 'tool', '✓ ${tool_name}'
		}
		'tool.failed' {
			if tool_name.len > 0 {
				return 'tool', '✗ ${tool_name}'
			}
			return '', ''
		}
		'assistant.commentary' {
			text := field(root, 'text')
			if text.len > 0 {
				return 'commentary', text
			}
			return '', ''
		}
		else {
			return '', ''
		}
	}
}

// assistant_trace_text joins the trace lines of a run (capped), for
// buffered results that have no live channel.
pub fn assistant_trace_text(events []AssistantEvent) string {
	mut lines := []string{}
	for event in events {
		kind, text := assistant_event_trace(event)
		if kind.len > 0 && text.len > 0 {
			lines << text
		}
	}
	joined := lines.join('\n')
	if joined.len > 8192 {
		return joined[..8192]
	}
	return joined
}

// assistant_collect_text extracts user-visible text from run events:
// token deltas first (delta/text fields), else the final output field.
pub fn assistant_collect_text(events []AssistantEvent) string {
	mut streamed := ''
	mut final := ''
	for event in events {
		streamed += assistant_event_text(event)
		f := assistant_event_final(event)
		if f.len > 0 {
			final = f
		}
	}
	return if streamed.len > 0 { streamed } else { final }
}

fn assistant_http(settings AssistantSettings, method http.Method, path string, body string) !http.Response {
	return assistant_http_ex(settings, method, path, body, {})
}

// Bounds for gateway work (hornero#172): a stuck or hostile local
// gateway must not hang the CLI or grow memory without limit.
pub const assistant_max_response_bytes = 8 * 1024 * 1024
pub const assistant_max_stream_bytes = 32 * 1024 * 1024
pub const assistant_max_stream_events = 8192

fn assistant_check_size(seen int, cap int, what string) ! {
	if seen > cap {
		return error('Hermes gateway ${what} exceeded the ${cap}-byte/event safety cap; refusing to keep buffering. Check the gateway, then retry.')
	}
}

fn assistant_http_ex(settings AssistantSettings, method http.Method, path string, body string, extra map[string]string) !http.Response {
	mut req := http.Request{
		method:       method
		url:          settings.endpoint.trim_right('/') + path
		data:         body
		read_timeout: 30 * time.second
	}
	key := assistant_load_key()
	mut headers := {
		'Content-Type': 'application/json'
	}
	if key.len > 0 {
		headers['Authorization'] = 'Bearer ${key}'
	}
	for k, v in extra {
		headers[k] = v
	}
	req.header = http.new_custom_header_from_map(headers)!
	mut seen := 0
	req.on_progress_body = fn [mut seen] (_req &http.Request, chunk []u8, _so_far u64, _expected u64, _status int) ! {
		seen += chunk.len
		assistant_check_size(seen, assistant_max_response_bytes, 'response')!
	}
	resp := req.do()!
	assistant_check_size(resp.body.len, assistant_max_response_bytes, 'response')!
	return resp
}

// --- Sessions (hornero#189) -------------------------------------------
// Hermes owns the real conversations; the gateway scopes continuity
// and per-channel memory with the X-Hermes-Session-Key header
// (advertised in /v1/capabilities as session_key_header). Hornero
// keeps only a small local registry of named keys so the panel and
// CLI can offer "New chat / switch chat" without inventing fake
// server-side sessions: the registry maps names to keys, Hermes
// owns everything behind them.

pub fn assistant_sessions_file() string {
	env := os.getenv('HORNERO_ASSISTANT_SESSIONS_FILE')
	if env.len > 0 {
		return env
	}
	return os.join_path(assistant_dir(), 'assistant-sessions.json')
}

pub struct AssistantSession {
pub:
	id      string
	title   string
	created string
}

pub struct AssistantSessions {
pub mut:
	current  string
	sessions []AssistantSession
}

pub fn assistant_sessions_load() AssistantSessions {
	mut out := AssistantSessions{}
	raw := os.read_file(assistant_sessions_file()) or { return out }
	for line in raw.split_into_lines() {
		parts := line.split('\t')
		if parts.len == 2 && parts[0] == 'current' {
			out.current = parts[1]
		} else if parts.len == 4 && parts[0] == 'session' {
			out.sessions << AssistantSession{
				id:      parts[1]
				title:   parts[2]
				created: parts[3]
			}
		}
	}
	return out
}

fn assistant_sessions_save(s AssistantSessions) ! {
	mut lines := []string{}
	if s.current.len > 0 {
		lines << 'current\t${s.current}'
	}
	for sess in s.sessions {
		lines << 'session\t${sess.id}\t${sess.title}\t${sess.created}'
	}
	os.mkdir_all(assistant_dir())!
	os.write_file(assistant_sessions_file(), lines.join('\n') + '\n')!
	os.chmod(assistant_sessions_file(), 0o600) or {}
}

// assistant_session_key is the gateway continuity key for a session
// id ('' when no session is selected — the gateway default applies).
pub fn assistant_session_key(id string) string {
	if id.len == 0 {
		return ''
	}
	return 'hornero:${id}'
}

// assistant_current_session_key resolves the key for ask: explicit
// id wins, else the registry's current session, else ''.
pub fn assistant_current_session_key(explicit string) string {
	if explicit.len > 0 {
		return assistant_session_key(explicit)
	}
	return assistant_session_key(assistant_sessions_load().current)
}

pub fn assistant_sessions_list_report() CommandResult {
	s := assistant_sessions_load()
	if s.sessions.len == 0 {
		return ok_result('assistant sessions', 'No Hornero chat sessions yet. Create one: horneroctl assistant sessions new "My chat". Hermes still owns the conversations; this registry only names the continuity keys.', {
			'count':   '0'
			'current': ''
		})
	}
	mut lines := []string{}
	for sess in s.sessions {
		mark := if sess.id == s.current { '*' } else { ' ' }
		lines << '${mark} ${sess.id} — ${sess.title} (since ${sess.created})'
	}
	return ok_result('assistant sessions', lines.join('\n'), {
		'count':   '${s.sessions.len}'
		'current': s.current
		'ids':     s.sessions.map(it.id).join(',')
	})
}

pub fn assistant_sessions_new_report(title string) CommandResult {
	clean := title.replace('\t', ' ').replace('\n', ' ').trim_space()
	if clean.len == 0 {
		return fail_result('assistant sessions', 'Missing chat title. Example: horneroctl assistant sessions new "Trip planning"')
	}
	mut s := assistant_sessions_load()
	id := 's${time.now().unix()}${s.sessions.len + 1}'
	s.sessions << AssistantSession{
		id:      id
		title:   clean
		created: time.now().format_ss()
	}
	s.current = id
	assistant_sessions_save(s) or { return fail_result('assistant sessions', err.msg()) }
	return ok_result('assistant sessions', 'Created and selected chat "${clean}" (${id}). Hermes keeps the conversation under its continuity key; only the name lives here.', {
		'id':      id
		'title':   clean
		'current': id
	})
}

pub fn assistant_sessions_use_report(id string) CommandResult {
	mut s := assistant_sessions_load()
	for sess in s.sessions {
		if sess.id == id {
			s.current = id
			assistant_sessions_save(s) or { return fail_result('assistant sessions', err.msg()) }
			return ok_result('assistant sessions', 'Selected chat "${sess.title}" (${id}).', {
				'id':      id
				'current': id
			})
		}
	}
	return fail_result('assistant sessions', 'Unknown chat id: ${id}. List them: horneroctl assistant sessions list')
}

// assistant_models_report implements `assistant model list`:
// capability-negotiated against GET /v1/models; fails honestly when
// the gateway does not answer.
pub fn assistant_models_report() CommandResult {
	settings := assistant_load_settings()
	resp := assistant_http(settings, .get, '/v1/models', '') or {
		return fail_result('assistant model', 'Cannot reach the Hermes gateway at ${settings.endpoint}: ${err.msg()}')
	}
	if resp.status_code >= 400 {
		return fail_result('assistant model', 'Hermes did not list models (HTTP ${resp.status_code}). Check: horneroctl assistant status')
	}
	decoded := json2.decode[json2.Any](resp.body) or {
		return fail_result('assistant model', 'Hermes returned an unreadable model list.')
	}
	if decoded !is map[string]json2.Any {
		return fail_result('assistant model', 'Hermes returned an unexpected model list.')
	}
	root := decoded.as_map()
	mut ids := []string{}
	if 'data' in root && root['data'] is []json2.Any {
		for item in root['data'] as []json2.Any {
			if item is map[string]json2.Any {
				m := item as map[string]json2.Any
				if 'id' in m && m['id'] is string {
					ids << m['id'].str()
				}
			}
		}
	}
	if ids.len == 0 {
		return fail_result('assistant model', 'Hermes reported no models.')
	}
	return ok_result('assistant model', 'Available models: ${ids.join(', ')}', {
		'models': ids.join(',')
		'model':  ids[0]
	})
}

// assistant_stream_events GETs a run's SSE events and invokes
// on_event for each event as it arrives (true streaming via the
// HTTP progress callback), instead of waiting for the whole body.
// The full response is still returned for status handling.
fn assistant_stream_events(settings AssistantSettings, run_id string, on_event fn (AssistantEvent)) !http.Response {
	mut req := http.Request{
		method:       .get
		url:          settings.endpoint.trim_right('/') + '/v1/runs/${run_id}/events'
		read_timeout: 600 * time.second
	}
	key := assistant_load_key()
	mut headers := {
		'Content-Type': 'application/json'
	}
	if key.len > 0 {
		headers['Authorization'] = 'Bearer ${key}'
	}
	req.header = http.new_custom_header_from_map(headers)!
	mut parser := SseStreamParser{}
	mut seen := 0
	mut count := 0
	req.on_progress_body = fn [mut parser, mut seen, mut count, on_event] (_req &http.Request, chunk []u8, _so_far u64, _expected u64, _status int) ! {
		seen += chunk.len
		assistant_check_size(seen, assistant_max_stream_bytes, 'event stream')!
		for ev in parser.feed(chunk.bytestr()) {
			count += 1
			assistant_check_size(count, assistant_max_stream_events, 'event stream')!
			on_event(ev)
		}
	}
	resp := req.do()!
	for ev in parser.finish() {
		count += 1
		assistant_check_size(count, assistant_max_stream_events, 'event stream')!
		on_event(ev)
	}
	return resp
}

// assistant_events_outcome applies the shared pending/text outcome
// rules for a collected event list (buffered or streamed).
fn assistant_events_outcome(command string, run_id string, events []AssistantEvent) CommandResult {
	pending := assistant_pending_request(events)
	text := assistant_collect_text(events)
	mut data := {
		'runId':   run_id
		'events':  events.len.str()
		'pending': pending.kind
	}
	trace := assistant_trace_text(events)
	if trace.len > 0 {
		data['trace'] = trace
	}
	if pending.kind == 'approval' {
		data['detail'] = pending.detail
		return fail_result(command, 'Hermes is waiting for approval on run ${run_id}: ${pending.detail}. Decide with: horneroctl assistant approve ${run_id} approve (or deny). Nothing is auto-approved.')
	}
	if pending.kind == 'clarify' {
		data['detail'] = pending.detail
		return fail_result(command, 'Hermes is asking on run ${run_id}: ${pending.detail} Answer with: horneroctl assistant clarify ${run_id} "<answer>"')
	}
	if text.len == 0 {
		return ok_result(command, 'Run ${run_id}: ${events.len} events, no text output yet.', data)
	}
	data['text'] = text
	return ok_result(command, text, data)
}

// assistant_events_stream_report streams run events live: each text
// delta is passed to emit() the moment it arrives. The returned
// result summarizes instead of repeating the streamed text.
pub fn assistant_events_stream_report(run_id string, emit fn (string)) CommandResult {
	return assistant_events_stream_report_traced(run_id, emit, fn (_ string, _ string) {})
}

pub fn assistant_events_stream_report_traced(run_id string, emit fn (string), on_trace fn (string, string)) CommandResult {
	settings := assistant_load_settings()
	if !settings.enabled {
		return fail_result('assistant events', 'Assistant is disabled. Enable it first: horneroctl assistant enable --yes')
	}
	if run_id.len == 0 || run_id.contains('/') || run_id.contains(' ') {
		return fail_result('assistant events', 'Missing or invalid run id. Example: horneroctl assistant events run_abc123')
	}
	// The closure only emits live deltas; event collection for the
	// final outcome uses the assembled response body, so it does not
	// depend on closure capture semantics.
	on_event := fn [emit, on_trace] (ev AssistantEvent) {
		delta := assistant_event_text(ev)
		if delta.len > 0 {
			emit(delta)
		}
		kind, text := assistant_event_trace(ev)
		if kind.len > 0 && text.len > 0 {
			on_trace(kind, text)
		}
	}
	resp := assistant_stream_events(settings, run_id, on_event) or {
		return fail_result('assistant events', 'Cannot reach the Hermes gateway: ${err.msg()}')
	}
	if resp.status_code >= 400 {
		return fail_result('assistant events', 'Hermes returned no events for run ${run_id} (HTTP ${resp.status_code}). The run id may be wrong or expired.')
	}
	events := parse_sse_events(resp.body)
	outcome := assistant_events_outcome('assistant events', run_id, events)
	if outcome.ok {
		text := assistant_collect_text(events)
		if text.len > 0 {
			had_delta := events.any(assistant_event_text(it).len > 0)
			if !had_delta {
				emit(text)
			}
			// Text already reached the user live; do not print twice.
			return ok_result('assistant events', '\nRun ${run_id}: ${events.len} events (streamed).', outcome.data)
		}
	}
	return outcome
}

// assistant_gateway_compat checks a /v1/capabilities body against the
// negotiated protocol contract: Hermes platform identity plus every
// feature flag this client calls. Returns (compatible, missing) where
// `missing` names each absent requirement (`platform:hermes-agent`
// when the responder is not a Hermes gateway at all).
pub fn assistant_gateway_compat(body string) (bool, []string) {
	mut missing := []string{}
	decoded := json2.decode[json2.Any](body) or { return false, ['valid JSON'] }
	if decoded !is map[string]json2.Any {
		return false, ['JSON object']
	}
	root := decoded as map[string]json2.Any
	if !('platform' in root && root['platform'] is string
		&& root['platform'].str() == 'hermes-agent') {
		missing << 'platform:hermes-agent'
	}
	features := if 'features' in root && root['features'] is map[string]json2.Any {
		root['features'] as map[string]json2.Any
	} else {
		map[string]json2.Any{}
	}
	for feature in assistant_required_gateway_features {
		if !(feature in features && features[feature] is bool
			&& features[feature].bool()) {
			missing << feature
		}
	}
	return missing.len == 0, missing
}

// Returns (reachable, compatible, detail).
fn assistant_gateway_state(settings AssistantSettings) (bool, bool, string) {
	resp := assistant_http(settings, .get, '/v1/capabilities', '') or {
		return false, false, 'unreachable: ${err.msg()}'
	}
	if resp.status_code != 200 {
		return false, false, 'HTTP ${resp.status_code}'
	}
	compatible, missing := assistant_gateway_compat(resp.body)
	if !compatible {
		return true, false, 'protocol incompatible: missing ${missing.join(', ')}'
	}
	return true, true, 'capabilities OK'
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
	if settings.rejected_endpoint.len > 0 {
		data['endpointRejected'] = settings.rejected_endpoint
		data['endpointWarning'] = 'stored endpoint is not a loopback http URL; using ${assistant_default_endpoint} instead'
	}
	if !settings.enabled {
		return ok_result('assistant status', 'Assistant is disabled (default). Enable it explicitly: horneroctl assistant enable --yes', data)
	}
	reachable, compatible, detail := assistant_gateway_state(settings)
	data['gateway'] = if reachable { 'reachable' } else { 'unreachable' }
	data['gatewayDetail'] = detail
	data['protocol'] = if compatible { 'compatible' } else { 'incompatible' }
	data['studiedHermes'] = assistant_studied_hermes_commit
	if hermes.len == 0 {
		return fail_result('assistant status', 'Assistant is enabled but Hermes Agent is not installed. Install Hermes through a pinned, auditable package, then run: horneroctl assistant status')
	}
	if !reachable {
		return fail_result('assistant status', 'Assistant is enabled but the Hermes gateway is not answering at ${settings.endpoint} (${detail}). Start Hermes, then retry.')
	}
	if !compatible {
		return fail_result('assistant status', 'Assistant is enabled and the gateway answers at ${settings.endpoint}, but its protocol is not compatible (${detail}). This client negotiates ${assistant_supported_hermes} and was studied against Hermes ${assistant_studied_hermes_commit}; update Hermes or HorneroOS so the required capabilities are advertised.')
	}
	return ok_result('assistant status', 'Assistant enabled; Hermes gateway reachable and protocol-compatible (${assistant_supported_hermes}).', data)
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

// -- Attachments (shell#241) -------------------------------------------
// Attachments are validated here, in the credential-holding CLI, never
// in QML: an allowlist of kinds, hard size caps, and an explicit
// secret-path refusal list. Images travel as input_image data URLs,
// text is inlined with delimiters and a cap, audio is referenced by
// local path so Hermes' own transcription tools can read it (the
// gateway's /v1/runs input has no audio part).
pub const assistant_attach_max_image_bytes = 10_000_000
pub const assistant_attach_max_audio_bytes = 25_000_000
pub const assistant_attach_max_text_bytes = 262_144
pub const assistant_attach_text_inline_cap = 32_768
pub const assistant_attach_max_count = 8

pub fn assistant_attachment_blocked(base string) bool {
	lower := base.to_lower()
	if lower == '.env' || lower.starts_with('.env.') || lower == 'assistant.key'
		|| lower == 'hermes-provider.env' || lower.contains('credential')
		|| lower.starts_with('id_rsa') || lower.starts_with('id_ed25519')
		|| lower.ends_with('.key') || lower.ends_with('.pem') || lower.ends_with('.kdbx')
		|| lower.ends_with('.p12') {
		return true
	}
	return false
}

pub fn assistant_attachment_kind(path string) string {
	ext := os.file_ext(path).trim_left('.').to_lower()
	return match ext {
		'png', 'jpg', 'jpeg', 'webp', 'gif' { 'image' }
		'wav', 'mp3', 'ogg', 'm4a', 'flac', 'opus' { 'audio' }
		'txt', 'md', 'log', 'json', 'yaml', 'yml', 'toml', 'ini', 'cfg', 'conf', 'v', 'py', 'js',
		'ts', 'sh', 'csv', 'xml', 'html', 'css', 'diff', 'patch', '' {
			'text'
		}
		else { 'unsupported' }
	}
}

fn assistant_image_mime(ext string) string {
	return match ext.trim_left('.').to_lower() {
		'png' { 'image/png' }
		'webp' { 'image/webp' }
		'gif' { 'image/gif' }
		else { 'image/jpeg' }
	}
}

// assistant_build_input assembles the /v1/runs `input` value: a plain
// string without attachments, or OpenAI-style content parts with them.
fn assistant_build_input(prompt string, attach []string) !(json2.Any, []string) {
	if attach.len == 0 {
		return json2.Any(prompt), []string{}
	}
	if attach.len > assistant_attach_max_count {
		return error('too many attachments: ${attach.len} (max ${assistant_attach_max_count})')
	}
	mut parts := []json2.Any{}
	parts << json2.Any({
		'type': json2.Any('text')
		'text': json2.Any(prompt)
	})
	mut names := []string{}
	for path in attach {
		base := os.base(path)
		if assistant_attachment_blocked(base) {
			return error('refusing to attach ${base}: it looks like a secret or credential file. Rename a redacted copy if you really need to share it.')
		}
		if !os.is_file(path) {
			return error('attachment not found or not a regular file: ${path}')
		}
		kind := assistant_attachment_kind(path)
		size := os.file_size(path)
		match kind {
			'image' {
				if size > assistant_attach_max_image_bytes {
					return error('image too large: ${base} (${size} bytes, max ${assistant_attach_max_image_bytes})')
				}
				raw := os.read_bytes(path) or { return error('cannot read attachment ${path}: ${err.msg()}') }
				parts << json2.Any({
					'type':      json2.Any('input_image')
					'image_url': json2.Any('data:${assistant_image_mime(os.file_ext(path))};base64,${base64.encode(raw)}')
				})
			}
			'audio' {
				if size > assistant_attach_max_audio_bytes {
					return error('audio too large: ${base} (${size} bytes, max ${assistant_attach_max_audio_bytes})')
				}
				abs := os.abs_path(path)
				parts << json2.Any({
					'type': json2.Any('text')
					'text': json2.Any("[Audio attachment stored locally at ${abs}. Transcribe it with your transcription tooling and treat the transcription as the user's message.]")
				})
			}
			'text' {
				if size > assistant_attach_max_text_bytes {
					return error('text attachment too large: ${base} (${size} bytes, max ${assistant_attach_max_text_bytes})')
				}
				content := os.read_file(path) or { return error('cannot read attachment ${path}: ${err.msg()}') }
				truncated := if content.len > assistant_attach_text_inline_cap {
					content[..assistant_attach_text_inline_cap] + '\n[... truncated by horneroctl at ${assistant_attach_text_inline_cap} bytes ...]'
				} else {
					content
				}
				parts << json2.Any({
					'type': json2.Any('text')
					'text': json2.Any('\n\n--- Attached file: ${base} ---\n${truncated}\n--- End of ${base} ---')
				})
			}
			else {
				return error('unsupported attachment type: ${base}. Supported: images (png/jpg/webp/gif), audio (wav/mp3/ogg/m4a/flac/opus), and text-like files.')
			}
		}
		names << base
	}
	mut messages := []json2.Any{}
	messages << json2.Any({
		'role':    json2.Any('user')
		'content': json2.Any(parts)
	})
	return json2.Any(messages), names
}

// assistant_run_create POSTs /v1/runs with the selected session's
// continuity header when one is active (hornero#189).
// One logical submission = one Idempotency-Key (hornero#173), drawn
// from the OS CSPRNG. Retries of the same submission reuse the key the
// caller generated once; a new ask generates a fresh key.
fn assistant_new_idempotency_key() string {
	raw := rand.bytes(16) or { return '' }
	return 'hornero-' + raw.hex()
}

fn assistant_run_headers(session_key string, idempotency_key string) map[string]string {
	mut headers := map[string]string{}
	if session_key.len > 0 {
		headers['X-Hermes-Session-Key'] = session_key
	}
	if idempotency_key.len > 0 {
		headers['Idempotency-Key'] = idempotency_key
	}
	return headers
}

fn assistant_run_create(settings AssistantSettings, body string, session_id string) !http.Response {
	key := assistant_current_session_key(session_id)
	headers := assistant_run_headers(key, assistant_new_idempotency_key())
	if headers.len > 0 {
		return assistant_http_ex(settings, .post, '/v1/runs', body, headers)
	}
	return assistant_http(settings, .post, '/v1/runs', body)
}

pub fn assistant_ask_report(prompt string) CommandResult {
	return assistant_ask_report_attached(prompt, [])
}

pub fn assistant_ask_report_attached(prompt string, attach []string) CommandResult {
	return assistant_ask_report_attached_session(prompt, attach, '')
}

pub fn assistant_ask_report_attached_session(prompt string, attach []string, session_id string) CommandResult {
	settings := assistant_load_settings()
	if !settings.enabled {
		return fail_result('assistant ask', 'Assistant is disabled. Enable it first: horneroctl assistant enable --yes')
	}
	if prompt.trim_space().len == 0 {
		return fail_result('assistant ask', 'Missing prompt. Example: horneroctl assistant ask "what updates are available?"')
	}
	input, _ := assistant_build_input(prompt, attach) or {
		return fail_result('assistant ask', err.msg())
	}
	body := json2.encode({
		'input': input
	}, escape_unicode: true)
	resp := assistant_run_create(settings, body, session_id) or {
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

// assistant_ask_stream_report starts a run like assistant ask, then
// streams its events live through emit() as deltas arrive.
pub fn assistant_ask_stream_report(prompt string, emit fn (string)) CommandResult {
	return assistant_ask_stream_report_attached(prompt, [], emit)
}

pub fn assistant_ask_stream_report_attached(prompt string, attach []string, emit fn (string)) CommandResult {
	return assistant_ask_stream_report_attached_session(prompt, attach, '', emit)
}

pub fn assistant_ask_stream_report_attached_session(prompt string, attach []string, session_id string, emit fn (string)) CommandResult {
	return assistant_ask_stream_report_traced(prompt, attach, session_id, emit, fn (_ string, _ string) {})
}

pub fn assistant_ask_stream_report_traced(prompt string, attach []string, session_id string, emit fn (string), on_trace fn (string, string)) CommandResult {
	settings := assistant_load_settings()
	if !settings.enabled {
		return fail_result('assistant ask', 'Assistant is disabled. Enable it first: horneroctl assistant enable --yes')
	}
	if prompt.trim_space().len == 0 {
		return fail_result('assistant ask', 'Missing prompt. Example: horneroctl assistant ask "what updates are available?"')
	}
	input, _ := assistant_build_input(prompt, attach) or {
		return fail_result('assistant ask', err.msg())
	}
	body := json2.encode({
		'input': input
	}, escape_unicode: true)
	resp := assistant_run_create(settings, body, session_id) or {
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
	result := assistant_events_stream_report_traced(run_id, emit, on_trace)
	if !result.ok {
		return result
	}
	mut data := result.data.clone()
	data['runId'] = run_id
	return ok_result('assistant ask', result.message, data)
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

// assistant_approval_choice maps the CLI words approve|deny to the
// Hermes gateway wire vocabulary. Upstream (pinned commit
// f14699a1379838862d3020b97785796aa555d36d, api_server_runs.py
// _handle_run_approval) reads only `choice`, allowing
// once|session|always|deny. `approve` deliberately maps to `once`
// (single action) — never to session/always widening.
pub fn assistant_approval_choice(decision string) string {
	return if decision == 'approve' { 'once' } else { 'deny' }
}

// assistant_pending_control extracts the pending approval control
// (prompt_id + execution_generation) from a run-status body. The
// gateway's authority path requires exactly these fields alongside
// the choice (api_server_authority_runs.respond_run).
pub fn assistant_pending_control(status_body string) (string, i64) {
	decoded := json2.decode[json2.Any](status_body) or { return '', 0 }
	if decoded !is map[string]json2.Any {
		return '', 0
	}
	root := decoded.as_map()
	if 'pending_controls' !in root || root['pending_controls'] !is []json2.Any {
		return '', 0
	}
	for control in root['pending_controls'].as_array() {
		if control !is map[string]json2.Any {
			continue
		}
		c := control.as_map()
		if 'kind' in c && c['kind'] is string && c['kind'].str() == 'approval' {
			prompt_id := if 'prompt_id' in c && c['prompt_id'] is string {
				c['prompt_id'].str()
			} else {
				''
			}
			mut gen := i64(0)
			if 'execution_generation' in c {
				gv := c['execution_generation']
				gen = match gv {
					i64 { gv }
					int { i64(gv) }
					f64 { i64(gv) }
					else { i64(0) }
				}
			}
			return prompt_id, gen
		}
	}
	return '', 0
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
	choice := assistant_approval_choice(decision)
	// Authority-path gateways require the exact pending-control
	// fields; read them from run status first. Fall back to the
	// plain choice body when no pending control is advertised.
	mut body := ''
	status_resp := assistant_http(settings, .get, '/v1/runs/${run_id}', '') or {
		return fail_result('assistant approve', 'Cannot reach the Hermes gateway: ${err.msg()}')
	}
	if status_resp.status_code < 400 {
		prompt_id, gen := assistant_pending_control(status_resp.body)
		if prompt_id.len > 0 {
			body = json2.encode({
				'request_id':           json2.Any(prompt_id)
				'execution_generation': json2.Any(gen)
				'choice':               json2.Any(choice)
			}, escape_unicode: true)
		}
	}
	if body.len == 0 {
		body = json2.encode({
			'choice': json2.Any(choice)
		}, escape_unicode: true)
	}
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
