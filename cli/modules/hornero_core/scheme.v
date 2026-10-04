module hornero_core

import os
import x.json2

// Scheme backend: materialized color-scheme state files plus the
// `horneroctl appearance` setters for mutation.
//
// Reads are native: `$XDG_CACHE_HOME/hornero/smart-colors/scheme.json` is
// the runtime source of truth and `$XDG_STATE_HOME/hornero/scheme/state.json`
// persists mode, flavour, variant and the independent GTK color policy.
// Mutation (`set-mode`/`set-variant`) delegates to the verified
// `horneroctl appearance set-mode|set-variant` verbs.
//
// Later phases (no verified backend from this repo, so intentionally absent
// here): `device brightness ...` and other hardware/compositor controls.
// The shell documents a `brightness` IPC target today, but horneroctl must
// not drive hardware without a pinned, integration-tested IPC path; those
// leaves land in a later phase per docs/cli-architecture.md section 7.

pub struct SchemeState {
pub:
	mode             string
	flavour          string
	variant          string
	gtk_color_scheme string
	state_file       string
	scheme_file      string
	state_present    bool
	scheme_present   bool
}

// scheme_state_file is the canonical scheme state location
// (docs/PATH_CONTRACT.md row 5) and the WRITE TARGET.
pub fn scheme_state_file() string {
	mut base := os.getenv('XDG_STATE_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.local', 'state')
	}
	return os.join_path(base, 'hornero', 'scheme', 'state.json')
}

// color_scheme_file is the canonical scheme runtime location
// (docs/PATH_CONTRACT.md row 4) and the WRITE TARGET.
pub fn color_scheme_file() string {
	mut base := os.getenv('XDG_CACHE_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.cache')
	}
	return os.join_path(base, 'hornero', 'smart-colors', 'scheme.json')
}

fn scheme_json_field(path string, key string) string {
	raw := os.read_file(path) or { return '' }
	parsed := json2.decode[json2.Any](raw) or { return '' }
	if parsed is map[string]json2.Any {
		if value := parsed[key] {
			return value.str()
		}
	}
	return ''
}

// read_scheme_state loads persisted appearance from canonical Hornero state.
// Scheme metadata supplies mode, flavour, and variant when state is incomplete.
pub fn read_scheme_state() SchemeState {
	state := scheme_state_file()
	scheme := color_scheme_file()
	state_present := os.is_file(state)
	scheme_present := os.is_file(scheme)
	mut mode := scheme_json_field(state, 'mode')
	mut flavour := scheme_json_field(state, 'flavour')
	mut variant := scheme_json_field(state, 'variant')
	if mode.len == 0 { mode = scheme_json_field(scheme, 'mode') }
	if flavour.len == 0 { flavour = scheme_json_field(scheme, 'flavour') }
	if variant.len == 0 { variant = scheme_json_field(scheme, 'variant') }
	policy := scheme_json_field(state, 'gtkColorScheme')
	return SchemeState{
		mode:             mode
		flavour:          flavour
		variant:          variant
		gtk_color_scheme: if policy.len > 0 { policy } else { 'follow' }
		state_file:       state
		scheme_file:      scheme
		state_present:    state_present
		scheme_present:   scheme_present
	}
}

fn or_unknown(v string) string {
	if v.len == 0 {
		return '(unknown)'
	}
	return v
}

// scheme_status_report implements `appearance scheme status` (read-only).
pub fn scheme_status_report() CommandResult {
	s := read_scheme_state()
	lines := [
		'mode: ${or_unknown(s.mode)}',
		'flavour: ${or_unknown(s.flavour)}',
		'variant: ${or_unknown(s.variant)}',
		'gtkColorScheme: ${s.gtk_color_scheme}',
	]
	return ok_result('appearance scheme status', lines.join('\n'), {
		'mode':             s.mode
		'flavour':          s.flavour
		'variant':          s.variant
		'gtk_color_scheme': s.gtk_color_scheme
		'state_file':       s.state_file
	})
}

pub struct SchemeSetOptions {
pub:
	kind    string // mode | variant
	value   string
	dry_run bool
	yes     bool
	helper  string
}

// scheme_set_report implements `appearance scheme set-mode|set-variant`
// natively (persist + M3 regenerate, GTK follow-push for mode).
// Mutating: needs --yes; --dry-run only previews.
pub fn scheme_set_report(opts SchemeSetOptions) CommandResult {
	if opts.kind == 'mode' && opts.value !in ['dark', 'light'] {
		return fail_result('appearance scheme set-mode', 'invalid mode: ${opts.value} (want dark|light).\nExample: horneroctl appearance scheme set-mode dark --dry-run')
	}
	if opts.kind == 'variant' && opts.value.len == 0 {
		return fail_result('appearance scheme set-variant', 'missing variant.\nExample: horneroctl appearance scheme set-variant tonalspot --dry-run')
	}
	if opts.kind !in ['mode', 'variant'] {
		return fail_result('appearance scheme', 'unknown action: ${opts.kind}.\nRun: horneroctl appearance scheme --help')
	}
	if !opts.yes && !opts.dry_run {
		return fail_result('appearance scheme', 'refusing to apply without --yes (preview with --dry-run).\nExample: horneroctl appearance scheme set-${opts.kind} ${opts.value} --dry-run')
	}
	if opts.kind == 'mode' {
		return scheme_set_mode_native(opts.value, opts.dry_run)
	}
	return scheme_set_variant_native(opts.value, opts.dry_run)
}
