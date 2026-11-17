module hornero_core

import x.json2

// Experience modes (RFC 0001 §5a; shell docs/EXPERIENCE.md, docs/IPC.md).
//
// The shell owns the Experience service (services/Experience.qml) and
// persists the active mode itself. horneroctl is the system interface:
// every verb here is a thin, validated passthrough to
// `qs ipc call experience <verb>`. This module never writes the shell's
// state file and never invents state: when the shell is not running (or
// does not expose the `experience` target) the command fails with an
// explanation instead of reporting a guessed mode.

// experience_modes are the stable mode ids the shell accepts.
pub const experience_modes = ['focus', 'everyday', 'signal', 'gaming', 'studio']

// experience_ipc_timeout_sec bounds each IPC call so a wedged shell cannot
// hang the CLI.
const experience_ipc_timeout_sec = 10

pub struct ModeOptions {
pub:
	action  string // list | get | set | reset | status
	mode    string // set: target mode id
	dry_run bool
	yes     bool
	qs_bin  string
}

// valid_experience_mode reports whether id is one of the five modes.
pub fn valid_experience_mode(id string) bool {
	return id in experience_modes
}

fn mode_unreachable(name string, detail string) CommandResult {
	return fail_result(name,
		'cannot reach the Hornero Shell experience service: ${detail}\nStart the shell first (horneroctl shell start); mode state is owned by the running shell, so no mode is reported or changed while it is down.')
}

struct ModeIpcReply {
	ok     bool
	output string
	line   string
}

// mode_ipc runs `qs ipc call experience <args...>` and classifies the reply.
// The shell answers failures as `error: ...` text with exit 0, so both a
// non-zero exit and an `error` prefix count as failure.
fn mode_ipc(bin string, args []string) ModeIpcReply {
	mut full := ['ipc', 'call', 'experience']
	full << args
	rep := run_exec(ExecSpec{
		prog:        bin
		args:        full
		timeout_sec: experience_ipc_timeout_sec
	})
	if !rep.ok {
		return ModeIpcReply{
			ok:     false
			output: rep.output
			line:   rep.command_line
		}
	}
	if rep.output.starts_with('error') {
		return ModeIpcReply{
			ok:     false
			output: rep.output
			line:   rep.command_line
		}
	}
	return ModeIpcReply{
		ok:     true
		output: rep.output
		line:   rep.command_line
	}
}

fn mode_ipc_args(opts ModeOptions) []string {
	return match opts.action {
		'set' { ['set', opts.mode] }
		else { [opts.action] }
	}
}

// mode_report dispatches `mode <list|get|set|reset|status>`.
pub fn mode_report(opts ModeOptions) CommandResult {
	name := 'mode ${opts.action}'
	if opts.action == 'set' && !valid_experience_mode(opts.mode) {
		return fail_result(name,
			'unknown mode: ${opts.mode} (use ${experience_modes.join('|')}).\nExample: horneroctl mode set signal --dry-run')
	}
	if opts.action == 'reset' && !opts.yes && !opts.dry_run {
		return fail_result(name,
			'refusing to reset without --yes (preview with --dry-run). Reset restores the factory Everyday mode, the Cockpit layout and the Signal Night theme; per-mode customisations are kept.\nExample: horneroctl mode reset --dry-run')
	}
	bin := if opts.qs_bin.len > 0 { opts.qs_bin } else { resolve_qs_bin() }
	if opts.dry_run {
		prog := if bin.len > 0 { bin } else { 'qs' }
		mut args := ['ipc', 'call', 'experience']
		args << mode_ipc_args(opts)
		line := command_line(prog, args)
		return ok_result(name, 'would run: ${line}', {
			'command_line': line
			'dry_run':      'true'
		})
	}
	if shell_ipc_bypassed() {
		return fail_result(name, 'shell IPC is bypassed (HORNERO_BYPASS_QUICKSHELL=1); mode state is owned by the running shell, so nothing was read or changed.')
	}
	if bin.len == 0 {
		return fail_result(name, 'qs not found on PATH. Set HORNERO_QS_BIN.\nExample: horneroctl mode get --dry-run')
	}
	return match opts.action {
		'get' { mode_get(name, bin) }
		'list' { mode_list(name, bin) }
		'status' { mode_status(name, bin) }
		'set' { mode_set(name, bin, opts.mode) }
		else { mode_reset(name, bin) }
	}
}

fn mode_get(name string, bin string) CommandResult {
	r := mode_ipc(bin, ['get'])
	if !r.ok {
		return mode_unreachable(name, r.output)
	}
	if !valid_experience_mode(r.output) {
		return fail_result(name, 'the shell answered with an unknown mode: ${r.output}')
	}
	return ok_result(name, r.output, {
		'mode':         r.output
		'command_line': r.line
	})
}

fn mode_set(name string, bin string, mode string) CommandResult {
	r := mode_ipc(bin, ['set', mode])
	if !r.ok {
		return mode_unreachable(name, r.output)
	}
	if r.output != 'ok: ${mode}' {
		return fail_result(name, 'the shell did not confirm the switch to ${mode}: ${r.output}')
	}
	return ok_result(name, 'mode: ${mode}', {
		'mode':         mode
		'command_line': r.line
	})
}

fn mode_reset(name string, bin string) CommandResult {
	r := mode_ipc(bin, ['reset'])
	if !r.ok {
		return mode_unreachable(name, r.output)
	}
	if !r.output.starts_with('ok') {
		return fail_result(name, 'the shell did not confirm the reset: ${r.output}')
	}
	return ok_result(name, 'reset: ${r.output.all_after('ok:').trim_space()} (per-mode customisations kept)', {
		'mode':         'everyday'
		'result':       r.output
		'command_line': r.line
	})
}

fn any_str(m map[string]json2.Any, key string) string {
	v := m[key] or { return '' }
	return match v {
		string { v }
		else { '' }
	}
}

fn any_bool_text(m map[string]json2.Any, key string) string {
	v := m[key] or { return '' }
	return match v {
		bool { v.str() }
		else { '' }
	}
}

fn any_str_list(m map[string]json2.Any, key string) []string {
	v := m[key] or { return []string{} }
	mut out := []string{}
	if v is []json2.Any {
		for item in v {
			if item is string {
				out << item
			}
		}
	}
	return out
}

fn mode_list(name string, bin string) CommandResult {
	r := mode_ipc(bin, ['list'])
	if !r.ok {
		return mode_unreachable(name, r.output)
	}
	rows := json2.decode[[]json2.Any](r.output) or {
		return fail_result(name, 'the shell answered with invalid JSON: ${r.output}')
	}
	mut lines := []string{}
	mut ids := []string{}
	mut active := ''
	for row in rows {
		if row !is map[string]json2.Any {
			return fail_result(name, 'the shell answered with an unexpected list entry: ${r.output}')
		}
		m := row.as_map()
		id := any_str(m, 'id')
		if !valid_experience_mode(id) {
			return fail_result(name, 'the shell listed an unknown mode id: ${id}')
		}
		ids << id
		is_active := any_bool_text(m, 'active') == 'true'
		if is_active {
			active = id
		}
		custom := any_str_list(m, 'customised')
		mark := if is_active { '*' } else { ' ' }
		label := any_str(m, 'label')
		desc := any_str(m, 'description')
		mut line := '${mark} ${id}'
		if label.len > 0 {
			line += '  ${label}'
		}
		if desc.len > 0 {
			line += ' - ${desc}'
		}
		if custom.len > 0 {
			line += ' [customised: ${custom.join(', ')}]'
		}
		lines << line
	}
	return ok_result(name, lines.join('\n'), {
		'modes':        ids.join(',')
		'active':       active
		'entries':      r.output
		'command_line': r.line
	})
}

fn mode_status(name string, bin string) CommandResult {
	r := mode_ipc(bin, ['status'])
	if !r.ok {
		return mode_unreachable(name, r.output)
	}
	st := json2.decode[map[string]json2.Any](r.output) or {
		return fail_result(name, 'the shell answered with invalid JSON: ${r.output}')
	}
	mode := any_str(st, 'mode')
	if !valid_experience_mode(mode) {
		return fail_result(name, 'the shell reported an unknown mode: ${mode}')
	}
	auto_on := any_bool_text(st, 'autoEnabled')
	mut data := {
		'mode':         mode
		'previous':     any_str(st, 'previous')
		'source':       any_str(st, 'source')
		'auto_switch':  auto_on
		'auto_active':  any_bool_text(st, 'auto')
		'changed_at':   any_str(st, 'changedAt')
		'state_path':   any_str(st, 'statePath')
		'status':       r.output
		'command_line': r.line
	}
	mut lines := []string{}
	lines << 'mode: ${mode}'
	if data['previous'].len > 0 {
		lines << 'previous: ${data['previous']}'
	}
	if data['source'].len > 0 {
		lines << 'source: ${data['source']}'
	}
	lines << 'auto-switch: ${if auto_on == 'true' {
		'on'
	} else {
		'off'
	}}'
	if data['changed_at'].len > 0 {
		lines << 'changed: ${data['changed_at']}'
	}
	if data['state_path'].len > 0 {
		lines << 'state: ${data['state_path']}'
	}
	// The instrument deck is exposed per mode; ask only for the active one
	// and say so plainly when the shell does not answer.
	d := mode_ipc(bin, ['deck', mode])
	if d.ok {
		deck := json2.decode[map[string]json2.Any](d.output) or { map[string]json2.Any{} }
		data['deck'] = d.output
		inst := deck['instruments'] or { json2.Any([]json2.Any{}) }
		count := if inst is []json2.Any { inst.len } else { 0 }
		hidden := any_str_list(deck, 'hidden')
		mut dl := 'deck: ${count} instrument(s)'
		if hidden.len > 0 {
			dl += ', hidden: ${hidden.join(', ')}'
		}
		lines << dl
	} else {
		data['deck'] = ''
		lines << 'deck: unavailable (${d.output})'
	}
	return ok_result(name, lines.join('\n'), data)
}
