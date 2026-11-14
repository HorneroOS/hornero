module hornero_core

import os

// Hyprland entrypoint refresh (HorneroOS/config#124): existing users
// keep a skel-seeded ~/.config/hypr/hyprland.lua, so packaged factory
// dofile additions (e.g. monitors-user.lua) never reach them and their
// personal *-user.lua overrides are silently ignored. The additive
// refresh helper ships with hornero-config in lib/hornero; this
// command is the discoverable front door to it.
//
// Behaviour: preview (helper dry-run, writes nothing) with --dry-run;
// apply with --yes (helper writes atomically and keeps a .pre-refresh
// backup). The helper is additive-only and refuses restructured
// files; this wrapper never edits the entrypoint itself and never
// touches *-user.lua. Paths are overridable for tests.

pub struct ConfigRefreshHyprOptions {
pub:
	dry_run bool
	yes     bool
}

// resolve_refresh_hypr_helper locates the installed helper: user
// scope first, then the packaged system copy. Override with
// HORNERO_REFRESH_HYPR_HELPER.
pub fn resolve_refresh_hypr_helper() string {
	env := os.getenv('HORNERO_REFRESH_HYPR_HELPER')
	if env.len > 0 {
		return env
	}
	user := os.join_path(os.home_dir(), '.local', 'lib', 'hornero', 'refresh-hypr-entrypoint.py')
	if os.is_file(user) {
		return user
	}
	system := os.join_path('/usr', 'share', 'hornero', 'lib', 'hornero', 'refresh-hypr-entrypoint.py')
	if os.is_file(system) {
		return system
	}
	return ''
}

fn refresh_hypr_factory_path() string {
	env := os.getenv('HORNERO_HYPR_FACTORY')
	if env.len > 0 {
		return env
	}
	mut dirs := os.getenv('XDG_CONFIG_DIRS')
	if dirs.len == 0 {
		dirs = '/etc/xdg'
	}
	for dir in dirs.split(':') {
		p := os.join_path(dir.trim_space(), 'hypr', 'hyprland.lua')
		if os.is_file(p) {
			return p
		}
	}
	return os.join_path('/etc', 'xdg', 'hypr', 'hyprland.lua')
}

fn refresh_hypr_target_path() string {
	env := os.getenv('HORNERO_HYPR_TARGET')
	if env.len > 0 {
		return env
	}
	mut base := os.getenv('XDG_CONFIG_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.config')
	}
	return os.join_path(base, 'hypr', 'hyprland.lua')
}

// config_refresh_hypr_report implements `config refresh-hypr`.
pub fn config_refresh_hypr_report(opts ConfigRefreshHyprOptions) CommandResult {
	leaf := 'config refresh-hypr'
	if !opts.yes && !opts.dry_run {
		return fail_result(leaf, 'refusing to refresh the Hyprland entrypoint without --yes (preview with --dry-run).\nExample: horneroctl config refresh-hypr --dry-run')
	}
	helper := resolve_refresh_hypr_helper()
	if helper.len == 0 {
		return fail_result(leaf, 'refresh helper not installed (looked in ~/.local/lib/hornero and /usr/share/hornero/lib/hornero). Install a hornero-config build that ships lib/hornero/refresh-hypr-entrypoint.py (HorneroOS/config#124).')
	}
	factory := refresh_hypr_factory_path()
	target := refresh_hypr_target_path()
	if !os.is_file(factory) {
		return fail_result(leaf, 'factory entrypoint not found: ${factory}. Is hornero-config installed?')
	}
	if !os.is_file(target) {
		return fail_result(leaf, 'no user Hyprland entrypoint at ${target}; nothing to refresh (fresh installs seed from the packaged entrypoint directly).')
	}
	py := find_on_path('python3')
	if py.len == 0 {
		return fail_result(leaf, 'python3 not found on PATH; the refresh helper needs it.')
	}
	mut args := [helper, '--factory', factory, '--target', target]
	if opts.yes {
		args << '--apply'
	}
	rep := run_exec(ExecSpec{
		prog:        py
		args:        args
		timeout_sec: 30
	})
	if !rep.ok {
		return fail_result(leaf, 'refresh helper failed: ${rep.output.trim_space()}')
	}
	mode_note := if opts.yes {
		'applied (backup kept next to the entrypoint)'
	} else {
		'preview only; re-run with --yes to apply'
	}
	return ok_result(leaf, '${rep.output.trim_space()}\n${mode_note}', {
		'helper':  helper
		'factory': factory
		'target':  target
		'applied': opts.yes.str()
	})
}
