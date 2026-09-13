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
	checks << env_check('hyprland-instance', 'HYPRLAND_INSTANCE_SIGNATURE')
	checks << bin_check('quickshell-cli', 'qs')
	checks << bin_check('hyprland-ctl', 'hyprctl')
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

// LegacyPathState is the detected `dots/*` state for one contract row.
// Read-only: detection stats paths, never writes.
pub struct LegacyPathState {
pub:
	domain  string
	legacy  string
	present bool
	detail  string
}

fn count_theme_packs(dir string) int {
	mut n := 0
	entries := os.ls(dir) or { return 0 }
	for e in entries {
		if os.is_file(os.join_path(dir, e, 'theme.json')) {
			n++
		}
	}
	return n
}

fn count_preset_files(dir string) int {
	mut n := 0
	entries := os.ls(dir) or { return 0 }
	for e in entries {
		if e.ends_with('.json') && os.is_file(os.join_path(dir, e)) {
			n++
		}
	}
	return n
}

fn legacy_wallpaper_target(path string) string {
	raw := os.read_file(path) or { return 'empty pointer' }
	lines := raw.split_into_lines()
	if lines.len == 0 || lines[0].trim_space().len == 0 {
		return 'empty pointer'
	}
	return 'points at ${lines[0].trim_space()}'
}

// detect_legacy_paths lists the detected `dots/*` state per contract row
// for the Hornero-owned migration rows (docs/PATH_CONTRACT.md rows 1-5,
// 9-10: themes, presets, the preset pointer, scheme.json plus scheme
// state, the wallpaper pointer, and notifs). Informational only: legacy
// presence is expected during the migration window, so it never fails
// doctor and never prompts. Quiet by design: plain text, no popups.
pub fn detect_legacy_paths() []LegacyPathState {
	mut states := []LegacyPathState{}
	themes := resolve_themes_dir_fallback()
	if os.is_dir(themes) {
		states << LegacyPathState{
			domain:  'themes'
			legacy:  themes
			present: true
			detail:  '${count_theme_packs(themes)} pack(s)'
		}
	} else {
		states << LegacyPathState{
			domain:  'themes'
			legacy:  themes
			present: false
		}
	}
	presets := resolve_presets_dir_fallback()
	if os.is_dir(presets) {
		states << LegacyPathState{
			domain:  'presets'
			legacy:  presets
			present: true
			detail:  '${count_preset_files(presets)} preset(s)'
		}
	} else {
		states << LegacyPathState{
			domain:  'presets'
			legacy:  presets
			present: false
		}
	}
	pointer := resolve_preset_state_file_fallback()
	states << LegacyPathState{
		domain:  'preset-pointer'
		legacy:  pointer
		present: os.is_file(pointer)
	}
	scheme := color_scheme_file_fallback()
	states << LegacyPathState{
		domain:  'scheme'
		legacy:  scheme
		present: os.is_file(scheme)
	}
	scheme_state := scheme_state_file_fallback()
	states << LegacyPathState{
		domain:  'scheme-state'
		legacy:  scheme_state
		present: os.is_file(scheme_state)
	}
	wallpaper := resolve_wallpaper_pointer_file_fallback()
	if os.is_file(wallpaper) {
		states << LegacyPathState{
			domain:  'wallpaper-pointer'
			legacy:  wallpaper
			present: true
			detail:  legacy_wallpaper_target(wallpaper)
		}
	} else {
		states << LegacyPathState{
			domain:  'wallpaper-pointer'
			legacy:  wallpaper
			present: false
		}
	}
	notifs := resolve_notifs_file_fallback()
	states << LegacyPathState{
		domain:  'notifs'
		legacy:  notifs
		present: os.is_file(notifs)
	}
	return states
}

// doctor_result renders checks for display. Every detail passes through
// redact_secrets first, so credential-like KEY=VALUE text (tokens, keys,
// passwords) never reaches human or --json output verbatim. The trailing
// legacy-paths section lists the detected `dots/*` state per contract row
// (see detect_legacy_paths); when any legacy state exists it carries the
// one-shot migration hint. Legacy presence never changes the verdict.
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
	legacy := detect_legacy_paths()
	mut any_legacy := false
	lines << 'legacy-paths:'
	for l in legacy {
		state := if l.present { 'present' } else { 'absent' }
		if l.present {
			any_legacy = true
		}
		extra := if l.present && l.detail.len > 0 { ' (${l.detail})' } else { '' }
		lines << '  ${l.domain} (${redact_secrets(l.legacy)}): ${state}${extra}'
		data['legacy.${l.domain}'] = state
	}
	if any_legacy {
		lines << 'migration available: horneroctl config migrate --dry-run'
		data['legacy_paths'] = 'detected'
	} else {
		data['legacy_paths'] = 'clean'
	}
	return CommandResult{
		command: 'doctor'
		ok:      failed == 0
		message: lines.join('\n')
		data:    data
	}
}
