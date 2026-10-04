module hornero_core

import os

// Wallpaper control uses the Hornero state pointer and native palette
// pipeline for both live-shell and headless operations.
// Mutations require --yes; --dry-run only previews.

pub struct WallpaperOptions {
pub:
	action  string // set | current | reload
	path    string // set target, or explicit candidate for current
	dry_run bool
	yes     bool
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
// then the canonical Hornero pointer. Returns '' when nothing resolves to an existing file.
pub fn current_wallpaper(explicit string) string {
	if explicit.len > 0 {
		resolved := resolve_wallpaper_candidate(explicit)
		if resolved.len > 0 {
			return resolved
		}
	}
	candidates := [resolve_wallpaper_pointer_file()]
	for c in candidates {
		resolved := wallpaper_from_pointer(c)
		if resolved.len > 0 {
			return resolved
		}
	}
	return ''
}

// wallpaper_report implements the wallpaper subcommands. `current` reads the
// pointer; set and reload use the native palette pipeline.
// Mutating verbs require --yes; --dry-run only previews.
// wallpaper_set_native applies one wallpaper without the
// horneroctl wallpaper set wrapper (retired): quickshell IPC setWallpaper
// first (when the shell runs), else the Hornero M3 palette pipeline for
// the new path — the native wallpaper-only contract. An explicit

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
			return wallpaper_set_native(resolved, opts.dry_run)
		}
		'reload' {
			if !opts.yes && !opts.dry_run {
				return fail_result('wallpaper reload', 'refusing to reload without --yes (preview with --dry-run).\nExample: horneroctl wallpaper reload --dry-run')
			}
			return wallpaper_reload_native(opts.dry_run)
		}
		else {
			return fail_result('wallpaper', 'unknown action: ${opts.action}.\nRun: horneroctl wallpaper --help')
		}
	}
}
