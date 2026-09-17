module hornero_core

// Native appearance top level: status reads the live state, sync adopts
// the live scheme meta, doctor checks consistency, and the set-* verbs
// drive the shell pipeline. No backend delegation remains.

pub struct AppearanceOptions {
pub:
	action  string // status | sync | doctor | set-wallpaper | set-gtk | set-icons | set-gtk-color-scheme
	value   string
	dry_run bool
	yes     bool
}

// appearance_report implements the appearance subcommands. `status` and
// `doctor` are read-only; every mutation needs --yes while --dry-run
// only previews.
pub fn appearance_report(opts AppearanceOptions) CommandResult {
	match opts.action {
		'status' {
			return appearance_status_report(false)
		}
		'sync' {
			if !opts.yes && !opts.dry_run {
				return fail_result('appearance sync', 'refusing to apply without --yes (preview with --dry-run).\nExample: horneroctl appearance sync --dry-run')
			}
			return appearance_sync_native(opts.dry_run)
		}
		'doctor' {
			return appearance_doctor_native()
		}
		'set-wallpaper' {
			if !opts.yes && !opts.dry_run {
				return fail_result('appearance set-wallpaper', 'refusing to apply without --yes (preview with --dry-run).\nExample: horneroctl appearance set-wallpaper ~/wall.jpg --dry-run')
			}
			return appearance_set_wallpaper_native(opts.value, opts.dry_run)
		}
		'set-gtk' {
			if !opts.yes && !opts.dry_run {
				return fail_result('appearance set-gtk', 'refusing to apply without --yes (preview with --dry-run).\nExample: horneroctl appearance set-gtk Orchis-Dark --dry-run')
			}
			return appearance_set_gtk_native(opts.value, opts.dry_run)
		}
		'set-icons' {
			if !opts.yes && !opts.dry_run {
				return fail_result('appearance set-icons', 'refusing to apply without --yes (preview with --dry-run).\nExample: horneroctl appearance set-icons Papirus-Dark --dry-run')
			}
			return appearance_set_icons_native(opts.value, opts.dry_run)
		}
		'set-gtk-color-scheme' {
			if !opts.yes && !opts.dry_run {
				return fail_result('appearance set-gtk-color-scheme', 'refusing to apply without --yes (preview with --dry-run).\nExample: horneroctl appearance set-gtk-color-scheme follow --dry-run')
			}
			return appearance_set_gtk_policy_native(opts.value, opts.dry_run)
		}
		else {
			return fail_result('appearance', 'unknown action: ${opts.action}.\nRun: horneroctl appearance --help')
		}
	}
}
