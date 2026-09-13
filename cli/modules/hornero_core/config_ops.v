module hornero_core

import os

// Config operations backend: the remaining `config` leaves beyond
// snapshots (see snapshots.v).
//
// `dots-default-apps` (dotfiles reference, read-only) owns `list`
// (`--list` prints current XDG defaults via handlr); `set` has no
// verified non-interactive verb upstream (`--set` never binds its
// arguments under EasyOptions, so `set` stays a usage-error deferral
// and handlr stays internal). `config gui` delegates to
// `dots-settings-gui` (`--pane=<name>` selects the control-center
// pane, bare invocation opens the hub). `config materialize`
// delegates to the config repo's `scripts/materialize.sh`
// (`--dest <dir> [--dry-run]`, hermetic into a temp HOME for tests).
// Path handling follows docs/PATH_CONTRACT.md: backend locations are
// resolved through the helpers below (explicit override, then the
// installed `~/.local/bin` helper, then PATH) and `--dest` is passed
// through verbatim -- never rewritten to a hardcoded `dots/*` path.

// resolve_default_apps_bin locates the `dots-default-apps` backend CLI.
// Override with HORNERO_DEFAULT_APPS_BIN.
pub fn resolve_default_apps_bin() string {
	env := os.getenv('HORNERO_DEFAULT_APPS_BIN')
	if env.len > 0 {
		return env
	}
	home_helper := os.join_path(os.home_dir(), '.local', 'bin', 'dots-default-apps')
	if os.is_file(home_helper) {
		return home_helper
	}
	return find_on_path('dots-default-apps')
}

// resolve_settings_gui_bin locates the `dots-settings-gui` backend CLI.
// Override with HORNERO_SETTINGS_GUI_BIN.
pub fn resolve_settings_gui_bin() string {
	env := os.getenv('HORNERO_SETTINGS_GUI_BIN')
	if env.len > 0 {
		return env
	}
	home_helper := os.join_path(os.home_dir(), '.local', 'bin', 'dots-settings-gui')
	if os.is_file(home_helper) {
		return home_helper
	}
	return find_on_path('dots-settings-gui')
}

// resolve_materialize_bin locates the config repo's `materialize.sh`.
// Override with HORNERO_MATERIALIZE_BIN. Unlike the `dots-*` helpers
// above there is no installed `~/.local/bin` default: the script lives
// in the config repo checkout (`scripts/`), so resolution is the
// explicit override, then PATH.
pub fn resolve_materialize_bin() string {
	env := os.getenv('HORNERO_MATERIALIZE_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('materialize.sh')
}

fn default_apps_or_fail(helper string, dry_run bool) !string {
	bin := if helper.len > 0 { helper } else { resolve_default_apps_bin() }
	if bin.len == 0 {
		if dry_run {
			return 'dots-default-apps'
		}
		return error('default-apps backend not found. Set HORNERO_DEFAULT_APPS_BIN.\nExample: horneroctl config default-apps list --dry-run')
	}
	return bin
}

fn settings_gui_or_fail(helper string, dry_run bool) !string {
	bin := if helper.len > 0 { helper } else { resolve_settings_gui_bin() }
	if bin.len == 0 {
		if dry_run {
			return 'dots-settings-gui'
		}
		return error('settings-gui backend not found. Set HORNERO_SETTINGS_GUI_BIN.\nExample: horneroctl config gui --dry-run')
	}
	return bin
}

fn materialize_or_fail(helper string, dry_run bool) !string {
	bin := if helper.len > 0 { helper } else { resolve_materialize_bin() }
	if bin.len == 0 {
		if dry_run {
			return 'materialize.sh'
		}
		return error('materialize backend not found. Set HORNERO_MATERIALIZE_BIN.\nExample: horneroctl config materialize --dest /tmp/hx-dest --dry-run')
	}
	return bin
}

pub struct DefaultAppsListOptions {
pub:
	dry_run bool
	helper  string
}

// default_apps_list_report implements `config default-apps list`
// (read-only) by delegating to `dots-default-apps --list` (verified
// backend verb).
pub fn default_apps_list_report(opts DefaultAppsListOptions) CommandResult {
	bin := default_apps_or_fail(opts.helper, opts.dry_run) or {
		return fail_result('config default-apps list', err.msg())
	}
	rep := run_exec(ExecSpec{
		prog:    bin
		args:    ['--list']
		dry_run: opts.dry_run
	})
	if opts.dry_run {
		return ok_result('config default-apps list', 'would run: ${rep.command_line}',
			{
			'command_line': rep.command_line
			'dry_run':      'true'
		})
	}
	if rep.ok {
		return ok_result('config default-apps list', rep.output, {
			'command_line': rep.command_line
		})
	}
	return fail_result('config default-apps list', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
}

pub struct MaterializeOptions {
pub:
	dest    string
	dry_run bool
	yes     bool
	helper  string
}

// materialize_report implements `config materialize --dest <dir>` by
// delegating to `materialize.sh --dest <dir>` (verified backend
// verbs). Mutating: needs --yes; --dry-run only previews (passing
// `--dry-run` through so the backend previews too). The destination
// travels verbatim: callers pass the canonical target explicitly and
// nothing here rewrites it to a legacy `dots/*` path.
pub fn materialize_report(opts MaterializeOptions) CommandResult {
	if opts.dest.len == 0 {
		return fail_result('config materialize', 'missing --dest.\nExample: horneroctl config materialize --dest /tmp/hx-dest --dry-run')
	}
	if !opts.yes && !opts.dry_run {
		return fail_result('config materialize', 'refusing to materialize into ${opts.dest} without --yes (preview with --dry-run).\nExample: horneroctl config materialize --dest ${opts.dest} --dry-run')
	}
	bin := materialize_or_fail(opts.helper, opts.dry_run) or {
		return fail_result('config materialize', err.msg())
	}
	mut args := ['--dest', opts.dest]
	if opts.dry_run {
		args << '--dry-run'
	}
	rep := run_exec(ExecSpec{
		prog:    bin
		args:    args
		dry_run: opts.dry_run
	})
	if opts.dry_run {
		return ok_result('config materialize', 'would run: ${rep.command_line}', {
			'command_line': rep.command_line
			'dry_run':      'true'
		})
	}
	if rep.ok {
		return ok_result('config materialize', rep.output, {
			'command_line': rep.command_line
			'dest':         opts.dest
		})
	}
	return fail_result('config materialize', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
}

// valid_gui_panes are the control-center panes `dots-settings-gui`
// documents (`--pane=NAME`); anything else is a caller-side typo.
const valid_gui_panes = ['network', 'bluetooth', 'audio', 'appearance', 'taskbar', 'launcher',
	'dashboard', 'system']

pub struct SettingsGuiOptions {
pub:
	pane    string
	dry_run bool
	helper  string
}

// settings_gui_report implements `config gui [--pane <name>]` by
// delegating to `dots-settings-gui [--pane=<name>]` (verified backend
// verbs). Launcher semantics (mirroring `shell ipc`): --dry-run
// previews, no --yes needed.
pub fn settings_gui_report(opts SettingsGuiOptions) CommandResult {
	if opts.pane.len > 0 && opts.pane !in valid_gui_panes {
		return fail_result('config gui', 'invalid pane: ${opts.pane} (want network|bluetooth|audio|appearance|taskbar|launcher|dashboard|system).\nExample: horneroctl config gui --pane appearance --dry-run')
	}
	bin := settings_gui_or_fail(opts.helper, opts.dry_run) or {
		return fail_result('config gui', err.msg())
	}
	mut args := []string{}
	if opts.pane.len > 0 {
		args << '--pane=${opts.pane}'
	}
	rep := run_exec(ExecSpec{
		prog:    bin
		args:    args
		dry_run: opts.dry_run
	})
	if opts.dry_run {
		return ok_result('config gui', 'would run: ${rep.command_line}', {
			'command_line': rep.command_line
			'dry_run':      'true'
		})
	}
	if rep.ok {
		return ok_result('config gui', rep.output, {
			'command_line': rep.command_line
		})
	}
	return fail_result('config gui', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
}
