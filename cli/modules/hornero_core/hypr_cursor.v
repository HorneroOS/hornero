module hornero_core

import os

// Cursor size (shell#221): Hyprland exposes no cursor size option to
// read back; the live lever is `hyprctl setcursor <theme> <size>`.
// Theme comes from XCURSOR_THEME (the session value), size from the
// persisted token, else XCURSOR_SIZE, else 24. Status reports which
// source the size came from instead of pretending a live read.

pub fn resolve_cursor_state_file() string {
	env := os.getenv('HORNERO_CURSOR_STATE_FILE')
	if env.len > 0 {
		return env
	}
	return os.join_path(hypr_state_base(), 'hornero', 'hypr', 'cursor', 'current')
}

fn cursor_theme() string {
	theme := os.getenv('XCURSOR_THEME')
	if theme.len > 0 {
		return theme
	}
	return 'default'
}

fn cursor_persisted() (int, string) {
	raw := os.read_file(resolve_cursor_state_file()) or { return 0, '' }
	mut size := 0
	mut theme := ''
	for part in raw.trim_space().split(' ') {
		if part.starts_with('size=') {
			size = part[5..].int()
		} else if part.starts_with('theme=') {
			theme = part[6..]
		}
	}
	return size, theme
}

// cursor_effective_size returns (size, source) with source in
// persisted|env|default.
fn cursor_effective_size() (int, string) {
	size, _ := cursor_persisted()
	if size >= 8 && size <= 96 {
		return size, 'persisted'
	}
	env := os.getenv('XCURSOR_SIZE')
	if env.len > 0 && env.int() >= 8 && env.int() <= 96 {
		return env.int(), 'env'
	}
	return 24, 'default'
}

pub fn cursor_status_report() CommandResult {
	size, source := cursor_effective_size()
	theme := cursor_theme()
	return ok_result('hypr cursor status', 'cursor: theme=${theme} size=${size} (source: ${source})', {
		'theme':       theme
		'size':        size.str()
		'size_source': source
		'hyprctl':     describe_bin(resolve_hyprctl_bin())
	})
}

fn apply_cursor(theme string, size int, dry_run bool) CommandResult {
	bin := resolve_hyprctl_bin()
	if bin.len == 0 {
		if dry_run {
			return ok_result('hypr cursor set', 'would run: hyprctl setcursor ${theme} ${size}', {
				'dry_run': 'true'
				'size':    size.str()
			})
		}
		return fail_result('hypr cursor set', 'hyprctl not found on PATH. Set HORNERO_HYPRCTL_BIN.')
	}
	if dry_run {
		return ok_result('hypr cursor set', 'would run: ${command_line(bin, [
			'setcursor',
			theme,
			size.str(),
		])}', {
			'dry_run': 'true'
			'size':    size.str()
			'theme':   theme
		})
	}
	rep := run_exec(ExecSpec{
		prog: bin
		args: ['setcursor', theme, size.str()]
	})
	if !rep.ok {
		return fail_result('hypr cursor set', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
	}
	write_state_token(resolve_cursor_state_file(), 'size=${size} theme=${theme}') or {
		return fail_result('hypr cursor set', 'Cursor applied live but could not persist: ${err.msg()}')
	}
	return ok_result('hypr cursor set', 'Cursor size set to ${size} (theme ${theme}); applies to the Hyprland cursor now and at login via restore.', {
		'size':  size.str()
		'theme': theme
	})
}

pub fn cursor_set_report(size int, dry_run bool, yes bool) CommandResult {
	if size < 8 || size > 96 {
		return fail_result('hypr cursor set', 'Cursor size must be 8-96. Example: horneroctl hypr cursor set --size 32 --yes')
	}
	if !dry_run && !yes {
		return fail_result('hypr cursor set', 'Changing the cursor size needs --yes (preview with --dry-run).')
	}
	return apply_cursor(cursor_theme(), size, dry_run)
}

// cursor_restore_report re-applies the persisted size at login;
// without a token it is a successful no-op.
pub fn cursor_restore_report(dry_run bool, yes bool) CommandResult {
	size, theme := cursor_persisted()
	if size < 8 || size > 96 {
		return ok_result('hypr cursor restore', 'No persisted cursor size; session default applies.', {
			'restored': 'false'
		})
	}
	if !dry_run && !yes {
		return fail_result('hypr cursor restore', 'Restore changes the live cursor. Re-run with --yes (or --dry-run to preview).')
	}
	t := if theme.len > 0 { theme } else { cursor_theme() }
	rep := apply_cursor(t, size, dry_run)
	if !rep.ok {
		return rep
	}
	mut data := rep.data.clone()
	data['restored'] = 'true'
	return ok_result('hypr cursor restore', 'Restored cursor size ${size} (theme ${t}).', data)
}
