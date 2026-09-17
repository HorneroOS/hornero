module hornero_core

import os

// Default-application setter: `config default-apps set` over the
// xdg-mime backend, ported from the `dots-default-apps --set` verb
// (which never bound its arguments under EasyOptions, so the backend
// moves to xdg-mime directly; handlr stays internal per
// docs/cli-architecture.md section 5).
//
// Only MIME associations are covered (`xdg-mime default <app>
// <mime>`). The terminal emulator stays out: it lives in the exo
// config (`~/.config/xfce4/helpers.rc`), not in MIME.
//
// Mutating: needs --yes; --dry-run only previews.

// resolve_xdg_mime_bin locates xdg-mime. Override with
// HORNERO_XDG_MIME_BIN.
pub fn resolve_xdg_mime_bin() string {
	env := os.getenv('HORNERO_XDG_MIME_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('xdg-mime')
}

fn xdg_mime_or_fail(dry_run bool) !string {
	bin := resolve_xdg_mime_bin()
	if bin.len == 0 {
		if dry_run {
			return 'xdg-mime'
		}
		return error('xdg-mime not found. Install xdg-utils, then retry.\nExample: horneroctl config default-apps set text/plain nvim.desktop --dry-run')
	}
	return bin
}

pub struct DefaultAppsSetOptions {
pub:
	mime    string
	app     string
	dry_run bool
	yes     bool
	helper  string
}

// default_apps_set_report implements `config default-apps set <mime>
// <app>`: validate the pair, then `xdg-mime default <app> <mime>`.
// Mutating: needs --yes; --dry-run only previews.
pub fn default_apps_set_report(opts DefaultAppsSetOptions) CommandResult {
	if opts.mime.len == 0 || opts.app.len == 0 {
		return fail_result('config default-apps set', 'missing MIME type or application.\nExample: horneroctl config default-apps set text/plain nvim.desktop --dry-run')
	}
	if !opts.mime.contains('/') {
		return fail_result('config default-apps set', 'invalid MIME type: ${opts.mime} (expected type/subtype, e.g. text/plain).\nExample: horneroctl config default-apps set text/plain nvim.desktop --dry-run')
	}
	if !opts.app.ends_with('.desktop') {
		return fail_result('config default-apps set', 'invalid application: ${opts.app} (expected a .desktop file, e.g. nvim.desktop).\nExample: horneroctl config default-apps set ${opts.mime} nvim.desktop --dry-run')
	}
	if !opts.yes && !opts.dry_run {
		return fail_result('config default-apps set', 'refusing to set the default app without --yes (preview with --dry-run).\nExample: horneroctl config default-apps set ${opts.mime} ${opts.app} --dry-run')
	}
	bin := if opts.helper.len > 0 { opts.helper } else { xdg_mime_or_fail(opts.dry_run) or {
			return fail_result('config default-apps set', err.msg())} }
	rep := run_exec(ExecSpec{
		prog:    bin
		args:    ['default', opts.app, opts.mime]
		dry_run: opts.dry_run
	})
	if opts.dry_run {
		return ok_result('config default-apps set', 'would run: ${rep.command_line}',
			{
			'command_line': rep.command_line
			'mime':         opts.mime
			'app':          opts.app
			'dry_run':      'true'
		})
	}
	if rep.ok {
		return ok_result('config default-apps set', 'Set ${opts.app} as default for ${opts.mime}',
			{
			'command_line': rep.command_line
			'mime':         opts.mime
			'app':          opts.app
		})
	}
	return fail_result('config default-apps set', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
}
