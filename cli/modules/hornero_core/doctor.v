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
	if choice == 'Invalid shell.json' {
		checks << DoctorCheck{
			name:   'shell-terminal'
			ok:     false
			detail: 'Hornero Shell configuration is invalid: shell.json could not be parsed; repair the file before selecting a terminal'
		}
		return checks
	}
	available_label := if available.len > 0 { available.join(', ') } else { 'none installed' }
	checks << DoctorCheck{
		name:   'shell-terminal'
		ok:     choice in available
		detail: if choice in available {
			'${choice} is installed and selected'
		} else if choice !in supported_terminal_defaults {
			'${choice} is selected but unsupported; installed supported choices: ${available_label}'
		} else {
			'${choice} is selected but not installed; available: ${available_label}'
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
	// warn marks a check that passes but needs the person's attention or
	// reports an optional capability that is absent. It never counts as a
	// failure and is reported as "warn" so UIs do not draw it as a pass.
	warn bool
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
		// No user shell.json is a supported state, not a failure: the shell
		// runs on its built-in defaults until the user changes a setting.
		checks << DoctorCheck{
			name:   'shell-config'
			ok:     true
			detail: '${cfg} not found; shell will use built-in defaults'
		}
	}
	checks << appearance_doctor_checks()
	checks << grub_boot_menu_doctor_checks('/usr/lib/modules', '/boot', '/boot/grub/grub.cfg')
	return checks
}

// grub_boot_menu_doctor_checks detects a stale GRUB menu where an installed
// Arch kernel package (/usr/lib/modules/<ver>/pkgbase with a matching
// /boot/vmlinuz-<pkgbase>) is absent from grub.cfg (hornero#465).
// Returns no checks on systems without GRUB (e.g., systemd-boot, Limine, containers).
pub fn grub_boot_menu_doctor_checks(modules_dir string, boot_dir string, grub_cfg string) []DoctorCheck {
	if !os.is_file(grub_cfg) {
		return []DoctorCheck{}
	}
	cfg_content := os.read_file(grub_cfg) or {
		return [
			DoctorCheck{
				name:   'grub-boot-menu'
				ok:     true
				warn:   true
				detail: '${grub_cfg} exists but is not readable (${err.msg()}); verify installed kernels are listed in the GRUB menu'
			},
		]
	}
	if !os.is_dir(modules_dir) {
		return []DoctorCheck{}
	}
	entries := os.ls(modules_dir) or { return []DoctorCheck{} }
	mut installed := []string{}
	for entry in entries {
		pkgbase_path := os.join_path(modules_dir, entry, 'pkgbase')
		if !os.is_file(pkgbase_path) {
			continue
		}
		pkgbase := (os.read_file(pkgbase_path) or { continue }).trim_space()
		if pkgbase.len == 0 {
			continue
		}
		img := 'vmlinuz-${pkgbase}'
		if os.is_file(os.join_path(boot_dir, img)) && img !in installed {
			installed << img
		}
	}
	installed.sort()
	if installed.len == 0 {
		return []DoctorCheck{}
	}
	mut listed := map[string]bool{}
	for raw_line in cfg_content.split_into_lines() {
		line := raw_line.trim_space()
		if line.starts_with('#') {
			continue
		}
		if !line.starts_with('linux ') && !line.starts_with('linux\t')
			&& !line.starts_with('linuxefi ') && !line.starts_with('linuxefi\t') {
			continue
		}
		fields := line.fields()
		if fields.len < 2 {
			continue
		}
		kernel_path := fields[1]
		base := os.base(kernel_path)
		if base.starts_with('vmlinuz-') {
			listed[base] = true
		}
	}
	mut missing := []string{}
	for img in installed {
		if img !in listed {
			missing << img
		}
	}
	if missing.len > 0 {
		return [
			DoctorCheck{
				name:   'grub-boot-menu'
				ok:     true
				warn:   true
				detail: 'installed kernel(s) missing from ${grub_cfg}: ${missing.join(', ')} — run: sudo grub-mkconfig -o ${grub_cfg}'
			},
		]
	}
	return [
		DoctorCheck{
			name:   'grub-boot-menu'
			ok:     true
			detail: 'all ${installed.len} installed kernel(s) present in ${grub_cfg} (${installed.join(', ')})'
		},
	]
}

// doctor_result renders checks for display. Every detail passes through
// redact_secrets first, so credential-like KEY=VALUE text (tokens, keys,
// passwords) never reaches human or --json output verbatim.
pub fn doctor_result(checks []DoctorCheck) CommandResult {
	mut lines := []string{}
	mut failed := 0
	mut data := map[string]string{}
	for c in checks {
		mark := if !c.ok {
			'FAIL'
		} else if c.warn {
			'warn'
		} else {
			'ok'
		}
		if !c.ok {
			failed++
		}
		lines << '${mark}  ${c.name}: ${redact_secrets(c.detail)}'
		data[c.name] = if !c.ok {
			'fail'
		} else if c.warn {
			'warn'
		} else {
			'ok'
		}
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
