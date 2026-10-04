module hornero_core

import os

// Wallpaper control uses the Hornero state pointer and native palette
// pipeline. Only the optional reload hook is an external session action.
// Mutations require --yes; --dry-run only previews.

// resolve_wal_reload_bin locates the horneroctl wallpaper reload backend.
// Override with HORNERO_WAL_RELOAD_BIN.
pub fn resolve_wal_reload_bin() string {
	env := os.getenv('HORNERO_WAL_RELOAD_BIN')
	if env.len > 0 {
		return env
	}
	home_helper := os.join_path(os.home_dir(), '.local', 'bin', 'horneroctl wallpaper reload')
	if os.is_file(home_helper) {
		return home_helper
	}
	return find_on_path('horneroctl wallpaper reload')
}

pub struct WallpaperOptions {
pub:
	action        string // set | current | reload
	path          string // set target, or explicit candidate for current
	dry_run       bool
	yes           bool
	set_helper    string
	reload_helper string
}

// wallpaper_strip_uri drops a file:// prefix, normalizing a file URI.
fn wallpaper_strip_uri(s string) string {
	if s.starts_with('file://') {
		return s[7..]
	}
	return s
}

// resolve_wallpaper_candidate resolves an explicit path to an existing file,
// preferring the canonical path when it resolves.
fn resolve_wallpaper_candidate(candidate string) string {
	c := wallpaper_strip_uri(candidate.trim_space())
	if c.len == 0 {
		return ''
	}
	real := os.real_path(c)
	if real.len > 0 && os.is_file(real) {
		return real
	}
	if os.is_file(c) {
		return c
	}
	return ''
}

// wallpaper_wal_link is the pywal state link (last-resort read candidate).
fn wallpaper_wal_link() string {
	mut base := os.getenv('XDG_CACHE_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.cache')
	}
	return os.join_path(base, 'wal', 'wal')
}

// wallpaper_from_pointer reads one pointer file: a symlink-to-image resolves
// directly, otherwise the first text line names the image (with a
// self-reference guard). Returns '' when
// the pointer yields no existing file.
fn wallpaper_from_pointer(pointer_file string) string {
	if pointer_file.len == 0 {
		return ''
	}
	if os.is_link(pointer_file) {
		resolved := resolve_wallpaper_candidate(pointer_file)
		if resolved.len > 0 {
			return resolved
		}
	}
	if os.is_file(pointer_file) && !os.is_link(pointer_file) {
		raw := os.read_file(pointer_file) or { return '' }
		lines := raw.split_into_lines()
		if lines.len == 0 {
			return ''
		}
		line := wallpaper_strip_uri(lines[0].trim_space())
		if line.len == 0 || line == pointer_file {
			return ''
		}
		ptr_real := os.real_path(pointer_file)
		from_line := os.real_path(line)
		if ptr_real.len > 0 && from_line.len > 0 && from_line == ptr_real {
			return ''
		}
		if from_line.len > 0 && os.is_file(from_line) {
			return from_line
		}
		if os.is_file(line) {
			return line
		}
	}
	return ''
}

// current_wallpaper resolves the live wallpaper: an explicit path wins,
// then the canonical Hornero pointer, then the optional pywal
// link. Returns '' when nothing resolves to an existing file.
pub fn current_wallpaper(explicit string) string {
	if explicit.len > 0 {
		resolved := resolve_wallpaper_candidate(explicit)
		if resolved.len > 0 {
			return resolved
		}
	}
	candidates := [resolve_wallpaper_pointer_file(), wallpaper_wal_link()]
	for c in candidates {
		resolved := wallpaper_from_pointer(c)
		if resolved.len > 0 {
			return resolved
		}
	}
	return ''
}

// wallpaper_backend_or_placeholder resolves one wallpaper backend, or the
// bare program name for dry-run previews when nothing is installed.
fn wallpaper_backend_or_placeholder(helper string, resolve fn () string, prog string, dry_run bool) !string {
	bin := if helper.len > 0 { helper } else { resolve() }
	if bin.len == 0 {
		if dry_run {
			return prog
		}
		return error('wallpaper backend not found (${prog}). Set the HORNERO_*_BIN override.')
	}
	return bin
}

// wallpaper_shell_quote single-quotes one argv word for the shell hop
// below. A wallpaper path is an arbitrary filename, so every word is
// quoted (the shared quote_arg only covers spaces/quotes): without this,
// a name like `wall.jpg;id` would run `id` as a second command.
fn wallpaper_shell_quote(s string) string {
	return "'" + s.replace("'", '\'"\'"\'') + "'"
}

// wallpaper_run_backend invokes the optional reload action with strict
// argument quoting; dry-run previews never execute it.
fn wallpaper_run_backend(bin string, args []string, dry_run bool) ExecReport {
	mut words := ['env', bin]
	for a in args {
		words << a
	}
	mut quoted := []string{}
	for w in words {
		quoted << wallpaper_shell_quote(w)
	}
	line := quoted.join(' ')
	if dry_run {
		return ExecReport{
			command_line: line
			ok:           true
			output:       '(dry-run: not executed)'
			exit_code:    0
			was_dry_run:  true
		}
	}
	r := os.execute(line)
	return ExecReport{
		command_line: line
		ok:           r.exit_code == 0
		output:       r.output.trim_space()
		exit_code:    r.exit_code
		was_dry_run:  false
	}
}

// wallpaper_report implements the wallpaper subcommands. `current` reads the
// pointer and set palette natively; reload uses the optional session hook.
// Mutating verbs require --yes; --dry-run only previews.
// wallpaper_set_native applies one wallpaper without the
// horneroctl wallpaper set wrapper (retired): quickshell IPC setWallpaper
// first (when the shell runs), else the wal+M3 palette pipeline for
// the new path — the native wallpaper-only contract. An explicit
// set_helper still delegates (caller override).
fn wallpaper_set_native(path string, dry_run bool) CommandResult {
	if !dry_run && shell_running() {
		ipc := ipc_appearance_call(['setWallpaper', path], false)
		if ipc.ok && !ipc.output.contains('Target not found') {
			wait_appearance_ipc(false) or { return fail_result('wallpaper set', err.msg()) }
			return ok_result('wallpaper set', 'wallpaper applied via shell: ${path}',
				{
					'path':    path
					'backend': 'shell'
				})
		}
	}
	st := read_scheme_state()
	flavour := normalize_scheme_type(if st.flavour.len > 0 { st.flavour } else { 'tonal-spot' })
	mode := if st.mode == 'light' || st.mode == 'dark' { st.mode } else { 'dark' }
	res := run_palette_pipeline_with(path, flavour, mode, dry_run, default_palette_backends())
	if !res.ok {
		return res
	}
	mut data := res.data.clone()
	data['path'] = path
	return ok_result('wallpaper set', res.message, data)
}

pub fn wallpaper_report(opts WallpaperOptions) CommandResult {
	match opts.action {
		'current' {
			path := current_wallpaper(opts.path)
			if path.len == 0 {
				return fail_result('wallpaper current', 'no current wallpaper found.\nExample: horneroctl wallpaper set ~/wall.jpg --dry-run')
			}
			return ok_result('wallpaper current', path, {
				'path': path
			})
		}
		'set' {
			if opts.path.len == 0 {
				return fail_result('wallpaper set', 'missing wallpaper path.\nExample: horneroctl wallpaper set ~/wall.jpg --dry-run')
			}
			resolved := resolve_wallpaper_candidate(opts.path)
			if resolved.len == 0 {
				return fail_result('wallpaper set', 'wallpaper file not found: ${opts.path}')
			}
			if !opts.yes && !opts.dry_run {
				return fail_result('wallpaper set', 'refusing to apply without --yes (preview with --dry-run).\nExample: horneroctl wallpaper set ~/wall.jpg --dry-run')
			}
			if opts.set_helper.len > 0 {
				bin := opts.set_helper
				rep := wallpaper_run_backend(bin, [opts.path], opts.dry_run)
				if opts.dry_run {
					return ok_result('wallpaper set', 'would run: ${rep.command_line}',
						{
							'command_line': rep.command_line
							'dry_run':      'true'
							'path':         resolved
						})
				}
				if rep.ok {
					return ok_result('wallpaper set', rep.output, {
						'command_line': rep.command_line
						'path':         resolved
					})
				}
				return fail_result('wallpaper set', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
			}
			return wallpaper_set_native(resolved, opts.dry_run)
		}
		'reload' {
			if !opts.yes && !opts.dry_run {
				return fail_result('wallpaper reload', 'refusing to reload without --yes (preview with --dry-run).\nExample: horneroctl wallpaper reload --dry-run')
			}
			// A configured backend (explicit helper or the
			// HORNERO_WAL_RELOAD_BIN-aware resolver) owns reload;
			// with nothing configured the native pipeline runs.
			helper := if opts.reload_helper.len > 0 {
				opts.reload_helper
			} else {
				resolve_wal_reload_bin()
			}
			if helper.len == 0 {
				return wallpaper_reload_native(opts.dry_run)
			}
			rep := wallpaper_run_backend(helper, [], opts.dry_run)
			if opts.dry_run {
				return ok_result('wallpaper reload', 'would run: ${rep.command_line}',
					{
						'command_line': rep.command_line
						'dry_run':      'true'
					})
			}
			if rep.ok {
				return ok_result('wallpaper reload', rep.output, {
					'command_line': rep.command_line
				})
			}
			return fail_result('wallpaper reload', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
		}
		else {
			return fail_result('wallpaper', 'unknown action: ${opts.action}.\nRun: horneroctl wallpaper --help')
		}
	}
}
