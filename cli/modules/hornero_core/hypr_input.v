module hornero_core

import os

// --- Input settings (shell#226 backend) -----------------------------------
// `hypr input` owns pointer/keyboard feel: sensitivity, accel
// profile, key repeat, touchpad natural-scroll and tap-to-click.
// Same contract as `hypr windows`: read live via `hyprctl
// getoption`, apply via `hyprctl keyword`, persist as a key=value
// state token so `restore` re-applies after a compositor restart.
// The config repo keeps owning the input.conf defaults; this is
// the user-level live/persist layer on top. On non-Hyprland
// compositors status reports the persisted values with the
// compositor marked unavailable — nothing is faked.

pub struct InputSettings {
pub mut:
	sensitivity    f64    = 0.0
	accel_profile  string = 'flat'
	repeat_rate    int    = 50
	repeat_delay   int    = 300
	natural_scroll bool   = true
	tap_to_click   bool   = true
}

pub struct InputApplyOptions {
pub:
	settings  InputSettings
	dry_run   bool
	yes       bool
	ephemeral bool
}

pub fn resolve_hypr_input_state_file() string {
	env := os.getenv('HORNERO_HYPR_INPUT_STATE_FILE')
	if env.len > 0 {
		return env
	}
	return os.join_path(hypr_state_base(), 'hornero', 'hypr', 'input', 'current')
}

pub fn input_settings_valid(s InputSettings) bool {
	return s.sensitivity >= -1.0 && s.sensitivity <= 1.0
		&& s.accel_profile in ['adaptive', 'flat'] && s.repeat_rate >= 1
		&& s.repeat_rate <= 100 && s.repeat_delay >= 100 && s.repeat_delay <= 2000
}

pub fn input_keyword_pairs(s InputSettings) [][]string {
	return [
		['input:sensitivity', '${s.sensitivity:.2f}'.trim_right('0').trim_right('.')],
		['input:accel_profile', s.accel_profile],
		['input:repeat_rate', s.repeat_rate.str()],
		['input:repeat_delay', s.repeat_delay.str()],
		['input:touchpad:natural_scroll', s.natural_scroll.str()],
		['input:touchpad:tap-to-click', s.tap_to_click.str()],
	]
}

pub fn input_persisted() InputSettings {
	mut s := InputSettings{}
	raw := os.read_file(resolve_hypr_input_state_file()) or { return s }
	for tok in raw.split(' ') {
		kv := tok.trim_space().split('=')
		if kv.len != 2 {
			continue
		}
		match kv[0] {
			'sensitivity' { s.sensitivity = kv[1].f64() }
			'accel_profile' { s.accel_profile = kv[1] }
			'repeat_rate' { s.repeat_rate = kv[1].int() }
			'repeat_delay' { s.repeat_delay = kv[1].int() }
			'natural_scroll' { s.natural_scroll = kv[1] == 'true' }
			'tap_to_click' { s.tap_to_click = kv[1] == 'true' }
			else {}
		}
	}
	if !input_settings_valid(s) {
		return InputSettings{}
	}
	return s
}

fn input_live_str(bin string, key string) string {
	rep := run_exec(ExecSpec{
		prog: bin
		args: ['getoption', key, '-j']
	})
	if !rep.ok {
		return ''
	}
	return rep.output
}

fn input_live(bin string) InputSettings {
	mut s := input_persisted()
	if bin.len == 0 {
		return s
	}
	raw_input_sensitivity := input_live_str(bin, 'input:sensitivity')
	if raw_input_sensitivity.len > 0 {
		m := json2_decode_map(raw_input_sensitivity)
		if 'float' in m {
			s.sensitivity = json2_f64(m, 'float')
		}
	}
	raw_input_accel_profile := input_live_str(bin, 'input:accel_profile')
	if raw_input_accel_profile.len > 0 {
		m := json2_decode_map(raw_input_accel_profile)
		v := json2_str(m, 'str')
		if v.len > 0 {
			s.accel_profile = v
		}
	}
	raw_input_repeat_rate := input_live_str(bin, 'input:repeat_rate')
	if raw_input_repeat_rate.len > 0 {
		m := json2_decode_map(raw_input_repeat_rate)
		if 'int' in m {
			s.repeat_rate = int(json2_f64(m, 'int'))
		}
	}
	raw_input_repeat_delay := input_live_str(bin, 'input:repeat_delay')
	if raw_input_repeat_delay.len > 0 {
		m := json2_decode_map(raw_input_repeat_delay)
		if 'int' in m {
			s.repeat_delay = int(json2_f64(m, 'int'))
		}
	}
	raw_input_touchpad_natural_scroll := input_live_str(bin, 'input:touchpad:natural_scroll')
	if raw_input_touchpad_natural_scroll.len > 0 {
		m := json2_decode_map(raw_input_touchpad_natural_scroll)
		if 'int' in m {
			s.natural_scroll = json2_f64(m, 'int') != 0
		}
	}
	raw_input_touchpad_tap_to_click := input_live_str(bin, 'input:touchpad:tap-to-click')
	if raw_input_touchpad_tap_to_click.len > 0 {
		m := json2_decode_map(raw_input_touchpad_tap_to_click)
		if 'int' in m {
			s.tap_to_click = json2_f64(m, 'int') != 0
		}
	}
	return s
}

fn input_data(s InputSettings) map[string]string {
	pairs := input_keyword_pairs(s)
	return {
		'sensitivity':    pairs[0][1]
		'accel_profile':  s.accel_profile
		'repeat_rate':    s.repeat_rate.str()
		'repeat_delay':   s.repeat_delay.str()
		'natural_scroll': s.natural_scroll.str()
		'tap_to_click':   s.tap_to_click.str()
	}
}

pub fn input_status_report() CommandResult {
	bin := resolve_hyprctl_bin()
	live := input_live(bin)
	saved := input_persisted()
	compositor := if bin.len > 0 { 'hyprland' } else { 'unavailable' }
	mut lines := []string{}
	lines << 'sensitivity: ${input_data(live)['sensitivity']}'
	lines << 'accel_profile: ${live.accel_profile}'
	lines << 'repeat_rate: ${live.repeat_rate}'
	lines << 'repeat_delay: ${live.repeat_delay}'
	lines << 'natural_scroll: ${live.natural_scroll}'
	lines << 'tap_to_click: ${live.tap_to_click}'
	lines << 'persisted: sensitivity=${input_data(saved)['sensitivity']} accel=${saved.accel_profile} repeat=${saved.repeat_rate}/${saved.repeat_delay}'
	lines << 'compositor: ${compositor}'
	mut data := input_data(live)
	data['compositor'] = compositor
	data['hyprctl'] = describe_bin(bin)
	return ok_result('hypr input status', lines.join('\n'), data)
}

pub fn input_apply_report(opts InputApplyOptions) CommandResult {
	if !input_settings_valid(opts.settings) {
		return fail_result('hypr input set', 'input settings out of bounds (sensitivity -1.0..1.0, accel adaptive|flat, repeat_rate 1-100, repeat_delay 100-2000).\nExample: horneroctl hypr input set --sensitivity 0.2 --dry-run')
	}
	if !opts.yes && !opts.dry_run {
		return fail_result('hypr input set', 'refusing to change input settings without --yes (preview with --dry-run).\nExample: horneroctl hypr input set --sensitivity 0.2 --dry-run')
	}
	bin := hyprctl_or_fail('input set', opts.dry_run) or {
		return fail_result('hypr input set', err.msg())
	}
	s := opts.settings
	pairs := input_keyword_pairs(s)
	mut previews := []string{}
	for pr in pairs {
		previews << command_line(bin, ['keyword', pr[0], pr[1]])
	}
	if opts.dry_run {
		mut lines := ['would apply input settings:']
		for pv in previews {
			lines << 'would run: ${pv}'
		}
		mut data := input_data(s)
		data['command_line'] = previews.join('; ')
		data['dry_run'] = 'true'
		return ok_result('hypr input set', lines.join('\n'), data)
	}
	for pr in pairs {
		rep := run_exec(ExecSpec{
			prog: bin
			args: ['keyword', pr[0], pr[1]]
		})
		if !rep.ok {
			return fail_result('hypr input set', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
		}
	}
	if !opts.ephemeral {
		write_state_token(resolve_hypr_input_state_file(), 'sensitivity=${input_data(s)['sensitivity']} accel_profile=${s.accel_profile} repeat_rate=${s.repeat_rate} repeat_delay=${s.repeat_delay} natural_scroll=${s.natural_scroll} tap_to_click=${s.tap_to_click}') or {
			return fail_result('hypr input set', err.msg())
		}
	}
	mut data := input_data(s)
	data['command_line'] = previews.join('; ')
	return ok_result('hypr input set', 'applied input settings sensitivity=${input_data(s)['sensitivity']} accel=${s.accel_profile} repeat=${s.repeat_rate}/${s.repeat_delay} natural_scroll=${s.natural_scroll} tap_to_click=${s.tap_to_click}',
		data)
}

pub fn input_current_value() InputSettings {
	return input_live(resolve_hyprctl_bin())
}

pub fn input_restore_value() InputSettings {
	return input_persisted()
}

pub fn input_restore_report(dry_run bool, yes bool) CommandResult {
	saved := input_persisted()
	return input_apply_report(InputApplyOptions{
		settings: saved
		dry_run:  dry_run
		yes:      yes
	})
}
