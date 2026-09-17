module hornero_core

import os

// Appearance-plus: smart-color generation, accent seeds, and night-mode
// control, all native V. The dots-smart-colors palette engine, the
// dots-accent-override seed file, and the dots-night-mode backend
// orchestration live here; only genuinely external programs stay
// backends (xrdb, the M3 python synthesizer, redshift/gammastep/
// wlsunset/xrandr, gsettings) with HORNERO_*_BIN overrides. No dots-*
// delegation remains.

pub struct ColorsOptions {
pub:
	action  string // status | generate | m3 | concept | export
	value   string // concept name for `concept`
	m3      bool
	call    []string
	dry_run bool
	yes     bool
}

// colors_report implements `appearance colors ...` natively. `status`
// previews the palette (read-only); `generate` rewrites the smart-color
// files (needs --yes, --m3 also refreshes scheme.json); `m3 -- <args>`
// passes through to the M3 synthesizer (needs --yes); `concept <name>`
// resolves one semantic color; `export` prints shell variables.
// --dry-run only previews.
pub fn colors_report(opts ColorsOptions) CommandResult {
	match opts.action {
		'status' {
			if opts.dry_run {
				return ok_result('appearance colors status', 'would run: read xrdb palette and preview smart colors', {
					'dry_run': 'true'
				})
			}
			// An explicit override short-circuits to that backend
			// (opaque passthrough, fails when broken); unset means
			// fully native with zero dots-* calls.
			override := os.getenv('HORNERO_SMART_COLORS_BIN')
			if override.len > 0 {
				rep := strict_exec(override, [], false)
				if rep.ok {
					return ok_result('appearance colors status', rep.output, {
						'command_line': rep.command_line
					})
				}
				return fail_result('appearance colors status', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
			}
			return colors_status_native()
		}
		'generate' {
			if !opts.yes && !opts.dry_run {
				return fail_result('appearance colors generate', 'refusing to generate without --yes (preview with --dry-run).\nExample: horneroctl appearance colors generate --dry-run')
			}
			return colors_generate_native(opts.m3, opts.dry_run)
		}
		'm3' {
			if opts.call.len == 0 {
				return fail_result('appearance colors m3', 'nothing to pass through.\nExample: horneroctl appearance colors m3 --dry-run -- --help')
			}
			if !opts.yes && !opts.dry_run {
				return fail_result('appearance colors m3', 'refusing to run without --yes (preview with --dry-run).\nExample: horneroctl appearance colors m3 --dry-run -- --help')
			}
			return colors_m3_passthrough_native(opts.call, opts.dry_run)
		}
		'concept' {
			if opts.value.len == 0 {
				return fail_result('appearance colors concept', 'missing concept.\nExample: horneroctl appearance colors concept error')
			}
			return colors_concept_native(opts.value)
		}
		'export' {
			return colors_export_native()
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
}

const hex_digits = '0123456789abcdefABCDEF'

// accent_is_hex validates a hex seed the way dots-accent-override did:
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

// accent_report implements `appearance accent ...` natively (seed file +
// regenerate). `show` is read-only; `set`/`clear` need --yes.
pub fn accent_report(opts AccentOptions) CommandResult {
	match opts.action {
		'show' {
			return accent_report_native('show', '', opts.dry_run)
		}
		'set' {
			if !accent_is_hex(opts.value) {
				return fail_result('appearance accent set', 'invalid hex color: ${opts.value} (want #RRGGBB).\nExample: horneroctl appearance accent set "#8839ef" --dry-run')
			}
			if !opts.yes && !opts.dry_run {
				return fail_result('appearance accent set', 'refusing to set without --yes (preview with --dry-run).\nExample: horneroctl appearance accent set "${opts.value}" --dry-run')
			}
			return accent_report_native('set', opts.value, opts.dry_run)
		}
		'clear' {
			if !opts.yes && !opts.dry_run {
				return fail_result('appearance accent clear', 'refusing to clear without --yes (preview with --dry-run).\nExample: horneroctl appearance accent clear --dry-run')
			}
			return accent_report_native('clear', '', opts.dry_run)
		}
		else {
			return fail_result('appearance accent', 'unknown action: ${opts.action}.\nRun: horneroctl appearance accent --help')
		}
	}
}

pub struct NightModeOptions {
pub:
	action  string // status | toggle | on | off | status-icon | status-text | backends
	dry_run bool
	yes     bool
}

// night_mode_report implements `appearance night-mode ...` natively.
pub fn night_mode_report(opts NightModeOptions) CommandResult {
	return night_mode_run(NightModeCmd{
		verb:    opts.action
		dry_run: opts.dry_run
		yes:     opts.yes
	})
}
