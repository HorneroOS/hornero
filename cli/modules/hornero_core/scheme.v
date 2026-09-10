module hornero_core

import os
import x.json2

// Scheme backend: materialized color-scheme state files plus the
// `dots-appearance` setters for mutation.
//
// Reads are native: `dots-color-scheme` treats
// `$XDG_CACHE_HOME/dots/smart-colors/scheme.json` as the runtime source of
// truth and persists `$XDG_STATE_HOME/dots/scheme/state.json`
// (mode/flavour/variant plus the independent `gtkColorScheme` policy; a
// missing policy key means `follow` for legacy boots per
// docs/cli-architecture.md section 5).
// Mutation (`set-mode`/`set-variant`) delegates to the verified
// `dots-appearance set-mode|set-variant` verbs.
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

fn scheme_state_file() string {
	mut base := os.getenv('XDG_STATE_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.local', 'state')
	}
	return os.join_path(base, 'dots', 'scheme', 'state.json')
}

fn color_scheme_file() string {
	mut base := os.getenv('XDG_CACHE_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.cache')
	}
	return os.join_path(base, 'dots', 'smart-colors', 'scheme.json')
}

fn scheme_json_field(path string, key string) string {
	raw := os.read_file(path) or { return '' }
	parsed := json2.decode[json2.Any](raw) or { return '' }
	if parsed is map[string]json2.Any {
		m := parsed.clone()
		if key !in m {
			return ''
		}
		return m[key].str()
	}
	return ''
}

// read_scheme_state loads mode/flavour/variant from the state file, falling
// back to the scheme.json runtime meta. Never fails: absent files yield
// empty fields and the caller reports them as unknown.
pub fn read_scheme_state() SchemeState {
	state := scheme_state_file()
	scheme := color_scheme_file()
	state_present := os.is_file(state)
	scheme_present := os.is_file(scheme)
	mut mode := scheme_json_field(state, 'mode')
	mut flavour := scheme_json_field(state, 'flavour')
	mut variant := scheme_json_field(state, 'variant')
	if mode.len == 0 {
		mode = scheme_json_field(scheme, 'mode')
	}
	if flavour.len == 0 {
		flavour = scheme_json_field(scheme, 'flavour')
	}
	mut policy := scheme_json_field(state, 'gtkColorScheme')
	if policy.len == 0 {
		policy = 'follow'
	}
	return SchemeState{
		mode:             mode
		flavour:          flavour
		variant:          variant
		gtk_color_scheme: policy
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

// scheme_set_report implements `appearance scheme set-mode|set-variant` by
// delegating to `dots-appearance` (verified backend verbs). Mutating: needs
// --yes; --dry-run only previews.
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
	bin := dots_appearance_or_fail(opts.helper) or {
		if opts.dry_run {
			'dots-appearance'
		} else {
			return fail_result('appearance scheme', err.msg())
		}
	}
	if !opts.yes && !opts.dry_run {
		return fail_result('appearance scheme', 'refusing to apply without --yes (preview with --dry-run).\nExample: horneroctl appearance scheme set-${opts.kind} ${opts.value} --dry-run')
	}
	verb := if opts.kind == 'mode' { 'set-mode' } else { 'set-variant' }
	rep := run_exec(ExecSpec{
		prog:    bin
		args:    [verb, opts.value]
		dry_run: opts.dry_run
	})
	if opts.dry_run {
		return ok_result('appearance scheme', 'would run: ${rep.command_line}', {
			'command_line': rep.command_line
			'dry_run':      'true'
		})
	}
	if rep.ok {
		return ok_result('appearance scheme', rep.output, {
			'command_line': rep.command_line
		})
	}
	return fail_result('appearance scheme', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
}
