module hornero_core

import os

// DoctorCheck is one read-only health probe. doctor never changes anything.
pub struct DoctorCheck {
pub:
	name   string
	ok     bool
	detail string
}

fn bin_check(name string, prog string) DoctorCheck {
	found := find_on_path(prog)
	if found.len > 0 {
		return DoctorCheck{
			name: name
			ok: true
			detail: found
		}
	}
	return DoctorCheck{
		name: name
		ok: false
		detail: '${prog} not found on PATH'
	}
}

fn env_check(name string, key string) DoctorCheck {
	v := os.getenv(key)
	if v.len > 0 {
		return DoctorCheck{
			name: name
			ok: true
			detail: '${key} is set'
		}
	}
	return DoctorCheck{
		name: name
		ok: false
		detail: '${key} is not set'
	}
}

// run_doctor executes all probes. Missing pieces are reported, not fatal to
// the tool itself: doctor always succeeds as a command; per-check ok flags
// carry the verdict (exit code follows the worst check).
pub fn run_doctor() []DoctorCheck {
	p := resolve_paths()
	mut checks := []DoctorCheck{}
	checks << env_check('wayland-session', 'WAYLAND_DISPLAY')
	checks << env_check('hyprland-instance', 'HYPRLAND_INSTANCE_SIGNATURE')
	checks << bin_check('quickshell-cli', 'qs')
	checks << bin_check('hyprland-ctl', 'hyprctl')
	cfg := shell_config_file(p)
	if os.is_file(cfg) {
		checks << DoctorCheck{
			name: 'shell-config'
			ok: true
			detail: cfg
		}
	} else {
		checks << DoctorCheck{
			name: 'shell-config'
			ok: false
			detail: '${cfg} not found (shell will use built-in defaults)'
		}
	}
	return checks
}

pub fn doctor_result(checks []DoctorCheck) CommandResult {
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
		lines << 'doctor: all ${checks.len} checks passed'
	} else {
		lines << 'doctor: ${failed}/${checks.len} checks failed'
	}
	return CommandResult{
		command: 'doctor'
		ok: failed == 0
		message: lines.join('\n')
		data: data
	}
}
