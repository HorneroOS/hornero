module hornero_core

import os

// Appearance-plus: status surfaces and generation delegation for the
// appearance backend family (dots-smart-colors, dots-m3-colors,
// dots-night-mode, dots-accent-override).
//
// Reads and generation stay delegated: the smart-colors GENERATION engine
// (xrdb palette analysis, semantic harmonization, M3 scheme synthesis) is
// NOT reimplemented here. V resolves the backend (HORNERO_*_BIN overrides,
// else the dots-* program on PATH) and invokes it; --dry-run only previews.
// Mutating verbs require --yes.
//
// Every backend invocation runs under HORNEROCTL_DELEGATED=1 (see
// delegated_run) so delegating dots-* shims run their legacy body instead
// of calling back into horneroctl.

// delegated_run executes prog with args exactly like run_exec (same
// command_line preview shape), except the child runs under
// HORNEROCTL_DELEGATED=1 (via env(1)) so delegating dots-* shims run their
// legacy body instead of calling back into horneroctl. The executed line
// strictly single-quotes every word with wallpaper_shell_quote: backend
// args are caller-controlled (accent seeds, m3 passthrough), and the shared
// quote_arg only covers spaces/quotes, so a value like `#8839ef` would
// otherwise become a shell comment. Dry-run previews never execute.
fn delegated_run(spec ExecSpec) ExecReport {
	line := command_line(spec.prog, spec.args)
	if spec.dry_run {
		return ExecReport{
			command_line: line
			ok:           true
			output:       '(dry-run: not executed)'
			exit_code:    0
			was_dry_run:  true
		}
	}
	mut words := ['env', 'HORNEROCTL_DELEGATED=1', spec.prog]
	for a in spec.args {
		words << a
	}
	mut quoted := []string{}
	for w in words {
		quoted << wallpaper_shell_quote(w)
	}
	r := os.execute(quoted.join(' '))
	return ExecReport{
		command_line: line
		ok:           r.exit_code == 0
		output:       r.output.trim_space()
		exit_code:    r.exit_code
		was_dry_run:  false
	}
}

// resolve_smart_colors_bin locates the dots-smart-colors backend (palette
// generation engine). Override with HORNERO_SMART_COLORS_BIN.
pub fn resolve_smart_colors_bin() string {
	env := os.getenv('HORNERO_SMART_COLORS_BIN')
	if env.len > 0 {
		return env
	}
	home_helper := os.join_path(os.home_dir(), '.local', 'bin', 'dots-smart-colors')
	if os.is_file(home_helper) {
		return home_helper
	}
	return find_on_path('dots-smart-colors')
}

// resolve_m3_colors_bin locates the dots-m3-colors backend (M3 scheme
// synthesis passthrough). Override with HORNERO_M3_COLORS_BIN.
pub fn resolve_m3_colors_bin() string {
	env := os.getenv('HORNERO_M3_COLORS_BIN')
	if env.len > 0 {
		return env
	}
	home_helper := os.join_path(os.home_dir(), '.local', 'bin', 'dots-m3-colors')
	if os.is_file(home_helper) {
		return home_helper
	}
	return find_on_path('dots-m3-colors')
}

// resolve_night_mode_bin locates the dots-night-mode backend.
// Override with HORNERO_NIGHT_MODE_BIN.
pub fn resolve_night_mode_bin() string {
	env := os.getenv('HORNERO_NIGHT_MODE_BIN')
	if env.len > 0 {
		return env
	}
	home_helper := os.join_path(os.home_dir(), '.local', 'bin', 'dots-night-mode')
	if os.is_file(home_helper) {
		return home_helper
	}
	return find_on_path('dots-night-mode')
}

// resolve_accent_override_bin locates the dots-accent-override backend.
// Override with HORNERO_ACCENT_OVERRIDE_BIN.
pub fn resolve_accent_override_bin() string {
	env := os.getenv('HORNERO_ACCENT_OVERRIDE_BIN')
	if env.len > 0 {
		return env
	}
	home_helper := os.join_path(os.home_dir(), '.local', 'bin', 'dots-accent-override')
	if os.is_file(home_helper) {
		return home_helper
	}
	return find_on_path('dots-accent-override')
}

// plus_backend resolves one appearance-plus backend to an executable path,
// or the bare program name for dry-run previews when nothing is installed.
fn plus_backend(helper string, resolve fn () string, prog string, dry_run bool) !string {
	bin := if helper.len > 0 { helper } else { resolve() }
	if bin.len == 0 {
		if dry_run {
			return prog
		}
		return error('${prog} backend not found.')
	}
	return bin
}

// plus_ok wraps a successful backend run (or its dry-run preview) in the
// shared `would run:` / verbatim-output shape.
fn plus_ok(command string, rep ExecReport) CommandResult {
	if rep.was_dry_run {
		return ok_result(command, 'would run: ${rep.command_line}', {
			'command_line': rep.command_line
			'dry_run':      'true'
		})
	}
	if rep.ok {
		return ok_result(command, rep.output, {
			'command_line': rep.command_line
		})
	}
	return fail_result(command, 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
}

pub struct ColorsOptions {
pub:
	action    string // status | generate | m3
	m3        bool
	call      []string
	dry_run   bool
	yes       bool
	helper    string
	m3_helper string
}

// colors_report implements `appearance colors ...`. `status` previews the
// generated palette (read-only); `generate` rewrites the smart-color files
// (needs --yes, --m3 also refreshes scheme.json); `m3 -- <args>` passes
// through to dots-m3-colors (needs --yes). --dry-run only previews.
pub fn colors_report(opts ColorsOptions) CommandResult {
	match opts.action {
		'status' {
			bin := plus_backend(opts.helper, resolve_smart_colors_bin, 'dots-smart-colors',
				opts.dry_run) or {
				return fail_result('appearance colors status', err.msg() +
					'\nExample: horneroctl appearance colors status --dry-run')
			}
			return plus_ok('appearance colors status', delegated_run(ExecSpec{
				prog:    bin
				args:    []
				dry_run: opts.dry_run
			}))
		}
		'generate' {
			if !opts.yes && !opts.dry_run {
				return fail_result('appearance colors generate', 'refusing to generate without --yes (preview with --dry-run).\nExample: horneroctl appearance colors generate --dry-run')
			}
			bin := plus_backend(opts.helper, resolve_smart_colors_bin, 'dots-smart-colors',
				opts.dry_run) or {
				return fail_result('appearance colors generate', err.msg() +
					'\nExample: horneroctl appearance colors generate --dry-run')
			}
			mut args := ['--generate']
			if opts.m3 {
				args << '--m3'
			}
			return plus_ok('appearance colors generate', delegated_run(ExecSpec{
				prog:    bin
				args:    args
				dry_run: opts.dry_run
			}))
		}
		'm3' {
			if opts.call.len == 0 {
				return fail_result('appearance colors m3', 'nothing to pass through.\nExample: horneroctl appearance colors m3 --dry-run -- --help')
			}
			if !opts.yes && !opts.dry_run {
				return fail_result('appearance colors m3', 'refusing to run without --yes (preview with --dry-run).\nExample: horneroctl appearance colors m3 --dry-run -- --help')
			}
			bin := plus_backend(opts.m3_helper, resolve_m3_colors_bin, 'dots-m3-colors',
				opts.dry_run) or {
				return fail_result('appearance colors m3', err.msg() +
					'\nExample: horneroctl appearance colors m3 --dry-run -- --help')
			}
			return plus_ok('appearance colors m3', delegated_run(ExecSpec{
				prog:    bin
				args:    opts.call.clone()
				dry_run: opts.dry_run
			}))
		}
		else {
			return fail_result('appearance colors', 'unknown action: ${opts.action}.\nRun: horneroctl appearance colors --help')
		}
	}
}

pub struct AccentOptions {
pub:
	action  string // show | set | clear
	value   string
	dry_run bool
	yes     bool
	helper  string
}

const hex_digits = '0123456789abcdefABCDEF'

// accent_is_hex validates a hex seed the way dots-accent-override does:
// six hex digits with an optional leading `#`.
fn accent_is_hex(s string) bool {
	mut c := s
	if c.starts_with('#') {
		c = c[1..]
	}
	if c.len != 6 {
		return false
	}
	for i in 0 .. c.len {
		if !hex_digits.contains(c[i].ascii_str()) {
			return false
		}
	}
	return true
}

// accent_report implements `appearance accent ...`. `show` prints the
// current override (read-only); `set`/`clear` mutate it and trigger a
// scheme regenerate downstream (need --yes). --dry-run only previews.
pub fn accent_report(opts AccentOptions) CommandResult {
	match opts.action {
		'show' {
			bin := plus_backend(opts.helper, resolve_accent_override_bin, 'dots-accent-override',
				opts.dry_run) or {
				return fail_result('appearance accent show', err.msg() +
					'\nExample: horneroctl appearance accent show --dry-run')
			}
			return plus_ok('appearance accent show', delegated_run(ExecSpec{
				prog:    bin
				args:    ['--show']
				dry_run: opts.dry_run
			}))
		}
		'set' {
			if !accent_is_hex(opts.value) {
				return fail_result('appearance accent set', 'invalid hex color: ${opts.value} (want #RRGGBB).\nExample: horneroctl appearance accent set "#8839ef" --dry-run')
			}
			if !opts.yes && !opts.dry_run {
				return fail_result('appearance accent set', 'refusing to set without --yes (preview with --dry-run).\nExample: horneroctl appearance accent set "${opts.value}" --dry-run')
			}
			bin := plus_backend(opts.helper, resolve_accent_override_bin, 'dots-accent-override',
				opts.dry_run) or {
				return fail_result('appearance accent set', err.msg() +
					'\nExample: horneroctl appearance accent set "${opts.value}" --dry-run')
			}
			return plus_ok('appearance accent set', delegated_run(ExecSpec{
				prog:    bin
				args:    [opts.value]
				dry_run: opts.dry_run
			}))
		}
		'clear' {
			if !opts.yes && !opts.dry_run {
				return fail_result('appearance accent clear', 'refusing to clear without --yes (preview with --dry-run).\nExample: horneroctl appearance accent clear --dry-run')
			}
			bin := plus_backend(opts.helper, resolve_accent_override_bin, 'dots-accent-override',
				opts.dry_run) or {
				return fail_result('appearance accent clear', err.msg() +
					'\nExample: horneroctl appearance accent clear --dry-run')
			}
			return plus_ok('appearance accent clear', delegated_run(ExecSpec{
				prog:    bin
				args:    ['--clear']
				dry_run: opts.dry_run
			}))
		}
		else {
			return fail_result('appearance accent', 'unknown action: ${opts.action}.\nRun: horneroctl appearance accent --help')
		}
	}
}

pub struct NightModeOptions {
pub:
	action  string // status
	dry_run bool
	yes     bool
	helper  string
}

// night_mode_report implements `appearance night-mode status` (read-only):
// whether the display temperature backend is active. Toggles stay in
// dots-night-mode (no verified portable surface yet); --dry-run previews.
pub fn night_mode_report(opts NightModeOptions) CommandResult {
	if opts.action != 'status' {
		return fail_result('appearance night-mode', 'unknown action: ${opts.action}.\nRun: horneroctl appearance night-mode --help')
	}
	bin := plus_backend(opts.helper, resolve_night_mode_bin, 'dots-night-mode', opts.dry_run) or {
		return fail_result('appearance night-mode status', err.msg() +
			'\nExample: horneroctl appearance night-mode status --dry-run')
	}
	return plus_ok('appearance night-mode status', delegated_run(ExecSpec{
		prog:    bin
		args:    ['status']
		dry_run: opts.dry_run
	}))
}
