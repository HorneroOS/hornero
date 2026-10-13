module hornero_core

import os

// terminal_doctor_checks keeps terminal health deterministic and separately
// reports whether a supported choice exists and whether the Shell default can
// actually be launched.
fn terminal_doctor_checks(installed []string, selected string) []DoctorCheck {
	available := installed.filter(it in supported_terminal_defaults)
	mut checks := []DoctorCheck{}
	checks << DoctorCheck{
		name:   'terminal-options'
		ok:     available.len > 0
		detail: if available.len > 0 {
			'available: ${available.join(', ')}'
		} else {
			'none of the supported terminals are installed (kitty, alacritty, ghostty)'
		}
	}
	choice := if selected.len == 0 { 'kitty' } else { selected }
	checks << DoctorCheck{
		name:   'shell-terminal'
		ok:     choice in available
		detail: if choice in available {
			'${choice} is installed and selected'
		} else if choice !in supported_terminal_defaults {
			'${choice} is selected but unsupported; choose an installed terminal (kitty, alacritty, ghostty)'
		} else {
			'${choice} is selected but not installed; available: ${if available.len > 0 {
				available.join(', ')
			} else {
				'none'
			}}'
		}
	}
	return checks
}

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
			name:   name
			ok:     true
			detail: found
		}
	}
	return DoctorCheck{
		name:   name
		ok:     false
		detail: '${prog} not found on PATH'
	}
}

fn env_check(name string, key string) DoctorCheck {
	v := os.getenv(key)
	if v.len > 0 {
		return DoctorCheck{
			name:   name
			ok:     true
			detail: '${key} is set'
		}
	}
	return DoctorCheck{
		name:   name
		ok:     false
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
	compositor := active_compositor()
	if compositor == 'niri' {
		checks << DoctorCheck{
			name:   'niri-session'
			ok:     true
			detail: 'NIRI_SOCKET is set'
		}
		checks << bin_check('niri-ipc', 'niri')
	} else if compositor == 'hyprland' {
		checks << DoctorCheck{
			name:   'hyprland-session'
			ok:     true
			detail: 'HYPRLAND_INSTANCE_SIGNATURE is set'
		}
		checks << bin_check('hyprland-ctl', 'hyprctl')
	} else {
		checks << DoctorCheck{
			name:   'compositor-session'
			ok:     false
			detail: 'No recognized Hornero compositor session is active'
		}
	}
	mut installed_terminals := []string{}
	for terminal in supported_terminal_defaults {
		if find_on_path(terminal).len > 0 {
			installed_terminals << terminal
		}
	}
	checks << terminal_doctor_checks(installed_terminals, shell_terminal_id())
	checks << bin_check('quickshell-cli', 'qs')
	cfg := shell_config_file(p)
	if os.is_file(cfg) {
		checks << DoctorCheck{
			name:   'shell-config'
			ok:     true
			detail: cfg
		}
	} else {
		checks << DoctorCheck{
			name:   'shell-config'
			ok:     false
			detail: '${cfg} not found (shell will use built-in defaults)'
		}
	}
	return checks
}

// doctor_result renders checks for display. Every detail passes through
// redact_secrets first, so credential-like KEY=VALUE text (tokens, keys,
// passwords) never reaches human or --json output verbatim.
pub fn doctor_result(checks []DoctorCheck) CommandResult {
	mut lines := []string{}
	mut failed := 0
	mut data := map[string]string{}
	for c in checks {
		mark := if c.ok { 'ok' } else { 'FAIL' }
		if !c.ok {
			failed++
		}
		lines << '${mark}  ${c.name}: ${redact_secrets(c.detail)}'
		data[c.name] = if c.ok { 'ok' } else { 'fail' }
	}
	if failed == 0 {
		lines << 'doctor: all ${checks.len} checks passed'
	} else {
		lines << 'doctor: ${failed}/${checks.len} checks failed'
	}
	return CommandResult{
		command: 'doctor'
		ok:      failed == 0
		message: lines.join('\n')
		data:    data
	}
}
