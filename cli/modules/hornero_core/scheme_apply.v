module hornero_core

import os
import x.json2

// Native scheme-state operations. Ports dots-color-scheme (state
// read/write, normalize, list/current/set/variant/mode/regenerate/
// sync-state) plus the M3 regeneration orchestration. Only the M3
// synthesizer (python + generate-m3-colors.py) and the optional shell
// reload ping stay backends; every JSON decision is V.

// smart_colors_dir is the canonical smart-colors cache location
// (WRITE TARGET). Override with HORNERO_SMART_COLORS_DIR.
pub fn smart_colors_dir() string {
	env := os.getenv('HORNERO_SMART_COLORS_DIR')
	if env.len > 0 {
		return env
	}
	mut base := os.getenv('XDG_CACHE_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.cache')
	}
	return os.join_path(base, 'hornero', 'smart-colors')
}

// smart_colors_dir_fallback is the legacy `dots/*` location (reads only).
pub fn smart_colors_dir_fallback() string {
	mut base := os.getenv('XDG_CACHE_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.cache')
	}
	return os.join_path(base, 'dots', 'smart-colors')
}

// accent_override_file is the canonical accent seed location
// (WRITE TARGET). Override with HORNERO_ACCENT_OVERRIDE_FILE.
pub fn accent_override_file() string {
	env := os.getenv('HORNERO_ACCENT_OVERRIDE_FILE')
	if env.len > 0 {
		return env
	}
	return os.join_path(smart_colors_dir(), 'accent-override')
}

// accent_override_file_fallback is the legacy `dots/*` location.
pub fn accent_override_file_fallback() string {
	return os.join_path(smart_colors_dir_fallback(), 'accent-override')
}

// read_accent_override returns the accent seed canonical-first.
pub fn read_accent_override() string {
	canon := accent_override_file()
	if os.is_file(canon) {
		return (os.read_file(canon) or { '' }).trim_space()
	}
	fb := accent_override_file_fallback()
	if os.is_file(fb) {
		return (os.read_file(fb) or { '' }).trim_space()
	}
	return ''
}

// write_scheme_state persists name/flavour/mode/variant to the canonical
// state file, preserving keys it does not own (gtkColorScheme).
pub fn write_scheme_state(name string, flavour string, mode string, variant string) !string {
	return update_state_json_fields({
		'name':    name
		'flavour': flavour
		'mode':    mode
		'variant': variant
	}, {
		'name':    'dynamic'
		'flavour': 'tonal-spot'
		'mode':    'dark'
		'variant': 'tonalspot'
	})
}

// ensure_scheme_state creates the canonical state file when missing,
// adopting flavour/mode from scheme.json meta (normalized) like the
// bash ensure_state. Existing files are untouched.
pub fn ensure_scheme_state() SchemeState {
	path := scheme_state_file()
	if !os.is_file(path) {
		scheme := color_scheme_file_for_read()
		mut flavour := 'tonal-spot'
		mut mode := 'dark'
		if os.is_file(scheme) {
			f := normalize_scheme_type(scheme_json_field(scheme, 'flavour'))
			if f.len > 0 {
				flavour = f
			}
			m := scheme_json_field(scheme, 'mode')
			if m == 'light' || m == 'dark' {
				mode = m
			}
		}
		write_scheme_state('dynamic', flavour, mode, normalize_variant(flavour)) or {}
	}
	return read_scheme_state()
}

// scheme_flavours lists the M3 scheme flavours the list verb reports.
pub fn scheme_flavours() []string {
	return ['vibrant', 'tonal-spot', 'expressive', 'fidelity', 'content', 'neutral', 'monochrome']
}

// scheme_list_report implements the scheme `list` verb natively: the
// live colours under every flavour key (the dots-color-scheme list shape).
pub fn scheme_list_report() CommandResult {
	colours := scheme_colours_for_read()
	mut inner := []string{}
	for fl in scheme_flavours() {
		inner << '"${fl}": ${colours}'
	}
	payload := '{"dynamic": {${inner.join(', ')}}}'
	return ok_result('appearance scheme list', payload, {
		'state_file': scheme_state_file_for_read()
	})
}

// scheme_colours_for_read returns the live colours object (or `{}`).
fn scheme_colours_for_read() string {
	path := color_scheme_file_for_read()
	raw := os.read_file(path) or { return '{}' }
	parsed := json2.decode[json2.Any](raw) or { return '{}' }
	if parsed is map[string]json2.Any {
		if colours := parsed['colours'] {
			return json2.encode(colours, escape_unicode: true)
		}
	}
	return '{}'
}

// scheme_current_report implements the scheme `current` verb natively:
// name, flavour, variant (one per line, like cmd_current).
pub fn scheme_current_report() CommandResult {
	st := read_scheme_state()
	name_field := scheme_json_field(color_scheme_file_for_read(), 'name')
	out_name := if name_field.len > 0 { name_field } else { 'dynamic' }
	out_flavour := if st.flavour.len > 0 { st.flavour } else { 'tonal-spot' }
	out_variant := if st.variant.len > 0 { st.variant } else { 'tonalspot' }
	return ok_result('appearance scheme current', '${out_name}\n${out_flavour}\n${out_variant}',
		{
		'name':    out_name
		'flavour': out_flavour
		'variant': out_variant
	})
}

// sync_state_from_scheme adopts scheme.json meta into state.json without
// regenerating (the ThemePipeline post-write handshake). Fails when the
// scheme file is missing.
pub fn sync_state_from_scheme() !string {
	scheme := color_scheme_file_for_read()
	if !os.is_file(scheme) {
		return error('scheme.json missing at ${scheme} — regenerate first.')
	}
	flavour := normalize_scheme_type(scheme_json_field(scheme, 'flavour'))
	mut mode := scheme_json_field(scheme, 'mode')
	if mode != 'light' && mode != 'dark' {
		mode = 'dark'
	}
	mut name := scheme_json_field(scheme, 'name')
	if name.len == 0 {
		name = 'dynamic'
	}
	return write_scheme_state(name, flavour, mode, normalize_variant(flavour))
}

// regenerate_scheme_native rewrites scheme.json from the wallpaper via
// the M3 backend, then refreshes hyprlock + the shell colours target.
// Best-effort steps (hyprlock, shell ping) warn but do not fail.
pub fn regenerate_scheme_native(wallpaper string, dry_run bool) CommandResult {
	st := if dry_run { read_scheme_state() } else { ensure_scheme_state() }
	flavour := normalize_scheme_type(if st.flavour.len > 0 { st.flavour } else { 'tonal-spot' })
	mut mode := st.mode
	if mode != 'light' && mode != 'dark' {
		mode = 'dark'
	}
	if wallpaper.len == 0 {
		return fail_result('appearance scheme regenerate', 'no wallpaper: state pointer is missing or broken.\nExample: horneroctl appearance theme apply hornero-dark --dry-run')
	}
	if !os.is_file(wallpaper) && !dry_run {
		return fail_result('appearance scheme regenerate', 'wallpaper not found: ${wallpaper}')
	}
	out := os.join_path(smart_colors_dir(), 'scheme.json')
	accent := read_accent_override()
	if dry_run {
		rep := run_m3_synthesis(wallpaper, out, flavour, mode, accent, true) or {
			return fail_result('appearance scheme regenerate', err.msg())
		}
		return ok_result('appearance scheme regenerate', 'would run: ${rep.command_line}',
			{
			'command_line': rep.command_line
			'dry_run':      'true'
		})
	}
	os.mkdir_all(os.dir(out)) or {
		return fail_result('appearance scheme regenerate', 'cannot create ${os.dir(out)}: ${err.msg()}')
	}
	rep := run_m3_synthesis(wallpaper, out, flavour, mode, accent, false) or {
		return fail_result('appearance scheme regenerate', err.msg())
	}
	if !rep.ok {
		return fail_result('appearance scheme regenerate', 'M3 backend failed (exit ${rep.exit_code}):\n${rep.output}')
	}
	hl := regenerate_hyprlock_native('', false)
	sync_state_from_scheme() or {
		return fail_result('appearance scheme regenerate', 'M3 wrote ${out} but state sync failed: ${err.msg()}')
	}
	qs_note := shell_colours_reload_best_effort()
	mut msg := 'regenerated ${out} (flavour ${flavour}, mode ${mode})'
	if !hl.ok {
		msg += '\nWARN: hyprlock refresh failed: ${hl.message}'
	}
	if qs_note.len > 0 {
		msg += '\n${qs_note}'
	}
	return ok_result('appearance scheme regenerate', msg, {
		'scheme':  out
		'flavour': flavour
		'mode':    mode
	})
}

// scheme_set_mode_native implements `set-mode`: validate, persist, M3
// regenerate, then push GTK when the policy is follow.
pub fn scheme_set_mode_native(mode string, dry_run bool) CommandResult {
	if mode != 'light' && mode != 'dark' {
		return fail_result('appearance scheme set-mode', 'invalid mode: ${mode} (want dark|light).\nExample: horneroctl appearance scheme set-mode dark --dry-run')
	}
	st := read_scheme_state()
	name := if scheme_json_field(scheme_state_file_for_read(), 'name').len > 0 {
		scheme_json_field(scheme_state_file_for_read(), 'name')
	} else {
		'dynamic'
	}
	flavour := normalize_scheme_type(if st.flavour.len > 0 { st.flavour } else { 'tonal-spot' })
	variant := if st.variant.len > 0 { st.variant } else { 'tonalspot' }
	if dry_run {
		rep := run_m3_synthesis(read_wallpaper_pointer(), os.join_path(smart_colors_dir(),
			'scheme.json'), flavour, mode, read_accent_override(), true) or {
			return fail_result('appearance scheme set-mode', err.msg())
		}
		return ok_result('appearance scheme set-mode', 'would run: ${rep.command_line}',
			{
			'command_line': rep.command_line
			'dry_run':      'true'
			'mode':         mode
		})
	}
	ensure_scheme_state()
	write_scheme_state(name, flavour, mode, variant) or {
		return fail_result('appearance scheme set-mode', 'cannot persist state: ${err.msg()}')
	}
	reg := regenerate_scheme_native(read_wallpaper_pointer(), false)
	if !reg.ok {
		return fail_result('appearance scheme set-mode', 'state set to ${mode} but regenerate failed: ${reg.message}')
	}
	if read_scheme_state().gtk_color_scheme == 'follow' {
		gtk := apply_gtk_color_scheme_native('follow', false)
		if !gtk.ok {
			return fail_result('appearance scheme set-mode', 'mode set but GTK follow-push failed: ${gtk.message}')
		}
	}
	return ok_result('appearance scheme set-mode', 'mode: ${mode} (flavour ${flavour})',
		{
		'mode':    mode
		'flavour': flavour
	})
}

// scheme_set_variant_native implements `set-variant`: normalize, persist
// (variant + derived flavour), M3 regenerate.
pub fn scheme_set_variant_native(variant_in string, dry_run bool) CommandResult {
	if variant_in.len == 0 {
		return fail_result('appearance scheme set-variant', 'missing variant.\nExample: horneroctl appearance scheme set-variant tonalspot --dry-run')
	}
	variant := normalize_variant(variant_in)
	flavour := variant_to_scheme_type(variant)
	st := read_scheme_state()
	name := if scheme_json_field(scheme_state_file_for_read(), 'name').len > 0 {
		scheme_json_field(scheme_state_file_for_read(), 'name')
	} else {
		'dynamic'
	}
	mode := if st.mode == 'light' || st.mode == 'dark' { st.mode } else { 'dark' }
	if dry_run {
		rep := run_m3_synthesis(read_wallpaper_pointer(), os.join_path(smart_colors_dir(),
			'scheme.json'), flavour, mode, read_accent_override(), true) or {
			return fail_result('appearance scheme set-variant', err.msg())
		}
		return ok_result('appearance scheme set-variant', 'would run: ${rep.command_line}',
			{
			'command_line': rep.command_line
			'dry_run':      'true'
			'variant':      variant
			'flavour':      flavour
		})
	}
	ensure_scheme_state()
	write_scheme_state(name, flavour, mode, variant) or {
		return fail_result('appearance scheme set-variant', 'cannot persist state: ${err.msg()}')
	}
	reg := regenerate_scheme_native(read_wallpaper_pointer(), false)
	if !reg.ok {
		return fail_result('appearance scheme set-variant', 'state set to ${variant} but regenerate failed: ${reg.message}')
	}
	return ok_result('appearance scheme set-variant', 'variant: ${variant} (flavour ${flavour})',
		{
		'variant': variant
		'flavour': flavour
	})
}

// accent_report_native implements `appearance accent ...` natively:
// show reads the seed, set/clear mutate it and regenerate.
pub fn accent_report_native(action string, value string, dry_run bool) CommandResult {
	match action {
		'show' {
			seed := read_accent_override()
			msg := if seed.len > 0 { seed } else { '(no accent override)' }
			return ok_result('appearance accent show', msg, {
				'override': seed
			})
		}
		'set' {
			if !accent_is_hex(value) {
				return fail_result('appearance accent set', 'invalid hex color: ${value} (want #RRGGBB).\nExample: horneroctl appearance accent set "#8839ef" --dry-run')
			}
			hex := if value.starts_with('#') { value[1..] } else { value }
			seed := '#' + hex.to_lower()
			if dry_run {
				return ok_result('appearance accent set', 'would run: write ${seed} to ${accent_override_file()}',
					{
					'dry_run':  'true'
					'override': seed
				})
			}
			os.mkdir_all(os.dir(accent_override_file())) or {
				return fail_result('appearance accent set', 'cannot create override dir: ${err.msg()}')
			}
			os.write_file(accent_override_file(), seed + '\n') or {
				return fail_result('appearance accent set', 'cannot write override: ${err.msg()}')
			}
			reg := regenerate_scheme_native(read_wallpaper_pointer(), false)
			if !reg.ok {
				return fail_result('appearance accent set', 'override set to ${seed} but regenerate failed: ${reg.message}')
			}
			return ok_result('appearance accent set', 'Accent override set to ${seed}.',
				{
				'override': seed
			})
		}
		'clear' {
			if dry_run {
				return ok_result('appearance accent clear', 'would run: remove ${accent_override_file()}',
					{
					'dry_run': 'true'
				})
			}
			os.rm(accent_override_file()) or {}
			fb := accent_override_file_fallback()
			if fb != accent_override_file() {
				os.rm(fb) or {}
			}
			reg := regenerate_scheme_native(read_wallpaper_pointer(), false)
			if !reg.ok {
				return fail_result('appearance accent clear', 'override cleared but regenerate failed: ${reg.message}')
			}
			return ok_result('appearance accent clear', 'Accent override cleared.', {})
		}
		else {
			return fail_result('appearance accent', 'unknown action: ${action}.\nRun: horneroctl appearance accent --help')
		}
	}
}
