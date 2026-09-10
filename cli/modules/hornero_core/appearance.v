module hornero_core

import os

// resolve_appearance_helper locates the appearance backend CLI shipped by
// HorneroOS/config. Override with HORNERO_APPEARANCE_BIN.
pub fn resolve_appearance_helper() string {
	env := os.getenv('HORNERO_APPEARANCE_BIN')
	if env.len > 0 {
		return env
	}
	home_helper := os.join_path(os.home_dir(), '.local', 'bin', 'dots-gtk-theme')
	if os.is_file(home_helper) {
		return home_helper
	}
	return find_on_path('dots-gtk-theme')
}

pub struct AppearanceOptions {
pub:
	action  string // status | sync | call
	call    []string
	dry_run bool
	yes     bool
	helper  string
}

fn helper_or_fail(helper string) !string {
	bin := if helper.len > 0 { helper } else { resolve_appearance_helper() }
	if bin.len == 0 {
		return error('appearance backend not found. Set HORNERO_APPEARANCE_BIN.\nExample: horneroctl appearance status --dry-run')
	}
	return bin
}

// appearance_report implements the appearance subcommands. `status` and
// `sync` map to stable backend verbs; `call -- <args>` passes anything else
// through untouched. Mutating verbs require --yes; --dry-run only previews.
pub fn appearance_report(opts AppearanceOptions) CommandResult {
	bin := helper_or_fail(opts.helper) or { return fail_result('appearance', err.msg()) }
	mut args := []string{}
	match opts.action {
		'status' {
			args = ['current']
		}
		'sync' {
			if !opts.yes && !opts.dry_run {
				return fail_result('appearance sync', 'refusing to apply without --yes (preview with --dry-run).\nExample: horneroctl appearance sync --dry-run')
			}
			args = ['sync-color-scheme']
		}
		'call' {
			if opts.call.len == 0 {
				return fail_result('appearance call', 'nothing to call.\nExample: horneroctl appearance call --dry-run -- theme list')
			}
			args = opts.call.clone()
		}
		else {
			return fail_result('appearance', 'unknown action: ${opts.action}.\nRun: horneroctl appearance --help')
		}
	}
	rep := run_exec(ExecSpec{
		prog:    bin
		args:    args
		dry_run: opts.dry_run
	})
	if opts.dry_run {
		return ok_result('appearance', 'would run: ${rep.command_line}', {
			'command_line': rep.command_line
			'dry_run':      'true'
		})
	}
	if rep.ok {
		return ok_result('appearance', rep.output, {
			'command_line': rep.command_line
		})
	}
	return fail_result('appearance', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
}
