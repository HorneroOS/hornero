module hornero_core

// Appearance-plus: smart-color files rendered from the live Hornero Signal
// scheme, and night-mode control. Only genuinely external programs stay
// backends (redshift/gammastep/wlsunset/xrandr, gsettings) with
// HORNERO_*_BIN overrides.

pub struct ColorsOptions {
pub:
	action  string // status | generate | concept | export
	value   string // concept name for `concept`
	dry_run bool
	yes     bool
}

// colors_report implements `appearance colors ...` natively. `status`
// previews the smart concepts (read-only); `generate` rewrites the
// smart-color files from the live scheme (needs --yes); `concept <name>`
// resolves one concept; `export` prints shell variables.
// --dry-run only previews.
pub fn colors_report(opts ColorsOptions) CommandResult {
	match opts.action {
		'status' {
			if opts.dry_run {
				return ok_result('appearance colors status', 'would run: read ${signal_scheme_file()} and preview smart colors',
					{
						'dry_run': 'true'
					})
			}
			return colors_status_native()
		}
		'generate' {
			if !opts.yes && !opts.dry_run {
				return fail_result('appearance colors generate', 'refusing to generate without --yes (preview with --dry-run).\nExample: horneroctl appearance colors generate --dry-run')
			}
			return colors_generate_native(opts.dry_run)
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

pub struct NightModeOptions {
pub:
	action      string // status | toggle | on | off | set | schedule | status-icon | status-text | backends
	dry_run     bool
	yes         bool
	temperature int
	schedule    string
	from_min    int = -1
	to_min      int = -1
}

// night_mode_report implements `appearance night-mode ...` natively.
pub fn night_mode_report(opts NightModeOptions) CommandResult {
	return night_mode_run(NightModeCmd{
		verb:        opts.action
		dry_run:     opts.dry_run
		yes:         opts.yes
		temperature: opts.temperature
		schedule:    opts.schedule
		from_min:    opts.from_min
		to_min:      opts.to_min
	})
}
