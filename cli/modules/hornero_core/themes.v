module hornero_core

import os
import x.json2

// Theme-pack backend: installed `theme.json` recipes.
//
// The packs ship in HorneroOS/config (`profiles/themes/<id>/theme.json`)
// and are installed to `$XDG_DATA_HOME/dots/themes/<id>/theme.json`
// (`DOTS_THEMES_DIR` in the config repo). `dots-appearance theme list/show`
// read the same files; these native readers stay byte-compatible with that
// output for reads. Mutation (`apply`) delegates to `dots-appearance`
// (see theme_apply_report); wallpaper/theme repository splits stay out of
// scope per docs/theme-split-plan.md.

// resolve_themes_dir locates installed theme packs.
// Override with HORNERO_THEMES_DIR.
pub fn resolve_themes_dir() string {
	env := os.getenv('HORNERO_THEMES_DIR')
	if env.len > 0 {
		return env
	}
	mut base := os.getenv('XDG_DATA_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.local', 'share')
	}
	return os.join_path(base, 'dots', 'themes')
}

// resolve_dots_appearance locates the `dots-appearance` backend CLI shipped
// by HorneroOS/config (theme apply, scheme setters).
// Override with HORNERO_DOTS_APPEARANCE_BIN.
pub fn resolve_dots_appearance() string {
	env := os.getenv('HORNERO_DOTS_APPEARANCE_BIN')
	if env.len > 0 {
		return env
	}
	home_helper := os.join_path(os.home_dir(), '.local', 'bin', 'dots-appearance')
	if os.is_file(home_helper) {
		return home_helper
	}
	return find_on_path('dots-appearance')
}

pub struct ThemeEntry {
pub:
	id          string
	name        string
	description string
}

fn theme_str_field(m map[string]json2.Any, key string) string {
	if key !in m {
		return ''
	}
	return m[key].str()
}

// read_theme_pack parses and validates one installed pack directory.
// Required keys and the id == directory invariant follow the
// docs/theme-split-plan.md checker rules.
fn read_theme_pack(dir string, id string) !ThemeEntry {
	raw := os.read_file(os.join_path(dir, id, 'theme.json'))!
	parsed := json2.decode[json2.Any](raw)!
	if parsed is map[string]json2.Any {
		return theme_entry_from_map(id, parsed)
	}
	return error('theme pack is corrupt: ${id} (theme.json is not an object)')
}

// theme_entry_from_map validates required pack keys and the
// id == directory invariant (docs/theme-split-plan.md checker rules).
fn theme_entry_from_map(id string, m map[string]json2.Any) !ThemeEntry {
	for key in ['schemaVersion', 'id', 'name', 'defaultWallpaper', 'wallpaperDir'] {
		if key !in m || m[key].str().len == 0 {
			return error('theme pack is corrupt: ${id} (missing key: ${key})')
		}
	}
	if m['id'].str() != id {
		return error('theme pack is corrupt: ${id} (id != directory name)')
	}
	return ThemeEntry{
		id:          id
		name:        theme_str_field(m, 'name')
		description: theme_str_field(m, 'description')
	}
}

// list_theme_packs returns installed packs sorted by id.
// Unparseable pack directories are skipped (same as the backend lister).
pub fn list_theme_packs() ![]ThemeEntry {
	dir := resolve_themes_dir()
	if !os.is_dir(dir) {
		return error('no themes installed at ${dir}. Set HORNERO_THEMES_DIR.\nExample: horneroctl appearance theme list --json')
	}
	entries := os.ls(dir)!
	mut packs := []ThemeEntry{}
	for id in entries {
		if !os.is_dir(os.join_path(dir, id)) {
			continue
		}
		if pack := read_theme_pack(dir, id) {
			packs << pack
		} else {
			continue
		}
	}
	packs.sort(a.id < b.id)
	return packs
}

// themes_list_report implements `appearance theme list` (read-only).
pub fn themes_list_report() CommandResult {
	packs := list_theme_packs() or { return fail_result('appearance theme list', err.msg()) }
	mut lines := []string{}
	mut ids := []string{}
	for p in packs {
		ids << p.id
		if p.description.len > 0 {
			lines << '${p.id}: ${p.name} - ${p.description}'
		} else {
			lines << '${p.id}: ${p.name}'
		}
	}
	lines << '${packs.len} theme(s)'
	return ok_result('appearance theme list', lines.join('\n'), {
		'count': packs.len.str()
		'ids':   ids.join(',')
	})
}

pub struct ThemeShow {
pub:
	id                string
	name              string
	description       string
	gtk_theme         string
	icon_theme        string
	default_wallpaper string
	wallpaper_dir     string
	raw               string
}

// show_theme_pack returns the full detail of one installed pack.
pub fn show_theme_pack(id string) !ThemeShow {
	if id.len == 0 || id.contains('/') || id == '.' || id == '..' || id.contains('\x00') {
		return error('invalid theme id: ${id}.\nExample: horneroctl appearance theme show vapor-dreams')
	}
	dir := resolve_themes_dir()
	raw := os.read_file(os.join_path(dir, id, 'theme.json')) or {
		return error('Theme not found: ${id}.\nRun: horneroctl appearance theme list')
	}
	parsed := json2.decode[json2.Any](raw) or {
		return error('theme pack is corrupt: ${id} (theme.json does not parse)')
	}
	if parsed is map[string]json2.Any {
		return theme_show_from_map(id, raw, parsed)
	}
	return error('theme pack is corrupt: ${id} (theme.json is not an object)')
}

// theme_show_from_map validates one pack and builds its detail view.
fn theme_show_from_map(id string, raw string, m map[string]json2.Any) !ThemeShow {
	for key in ['schemaVersion', 'id', 'name', 'defaultWallpaper', 'wallpaperDir'] {
		if key !in m || m[key].str().len == 0 {
			return error('theme pack is corrupt: ${id} (missing key: ${key})')
		}
	}
	if m['id'].str() != id {
		return error('theme pack is corrupt: ${id} (id != directory name)')
	}
	return ThemeShow{
		id:                id
		name:              theme_str_field(m, 'name')
		description:       theme_str_field(m, 'description')
		gtk_theme:         theme_str_field(m, 'gtkTheme')
		icon_theme:        theme_str_field(m, 'iconTheme')
		default_wallpaper: theme_str_field(m, 'defaultWallpaper')
		wallpaper_dir:     theme_str_field(m, 'wallpaperDir')
		raw:               raw
	}
}

// theme_show_report implements `appearance theme show <id>` (read-only).
pub fn theme_show_report(id string) CommandResult {
	pack := show_theme_pack(id) or { return fail_result('appearance theme show', err.msg()) }
	mut lines := []string{}
	lines << 'id: ${pack.id}'
	lines << 'name: ${pack.name}'
	if pack.description.len > 0 {
		lines << 'description: ${pack.description}'
	}
	if pack.gtk_theme.len > 0 {
		lines << 'gtk: ${pack.gtk_theme}'
	}
	if pack.icon_theme.len > 0 {
		lines << 'icons: ${pack.icon_theme}'
	}
	lines << 'wallpaper: ${pack.wallpaper_dir}/${pack.default_wallpaper}'
	return ok_result('appearance theme show', lines.join('\n'), {
		'id':        pack.id
		'name':      pack.name
		'gtk_theme': pack.gtk_theme
		'wallpaper': '${pack.wallpaper_dir}/${pack.default_wallpaper}'
	})
}

pub struct ThemeApplyOptions {
pub:
	id        string
	wallpaper string
	dry_run   bool
	yes       bool
	helper    string
}

fn dots_appearance_or_fail(helper string) !string {
	bin := if helper.len > 0 { helper } else { resolve_dots_appearance() }
	if bin.len == 0 {
		return error('dots-appearance backend not found. Set HORNERO_DOTS_APPEARANCE_BIN.\nExample: horneroctl appearance theme apply vapor-dreams --dry-run')
	}
	return bin
}

// theme_apply_report implements `appearance theme apply <id>` by delegating
// to `dots-appearance theme apply` (verified backend verb). Mutating: needs
// --yes; --dry-run only previews.
pub fn theme_apply_report(opts ThemeApplyOptions) CommandResult {
	if opts.id.len == 0 || opts.id.contains('/') || opts.id == '.' || opts.id == '..' {
		return fail_result('appearance theme apply', 'invalid theme id.\nExample: horneroctl appearance theme apply vapor-dreams --dry-run')
	}
	bin := dots_appearance_or_fail(opts.helper) or {
		if opts.dry_run {
			'dots-appearance'
		} else {
			return fail_result('appearance theme apply', err.msg())
		}
	}
	if !opts.yes && !opts.dry_run {
		return fail_result('appearance theme apply', 'refusing to apply without --yes (preview with --dry-run).\nExample: horneroctl appearance theme apply ${opts.id} --dry-run')
	}
	mut args := ['theme', 'apply', opts.id]
	if opts.wallpaper.len > 0 {
		args << '--wallpaper'
		args << opts.wallpaper
	}
	rep := run_exec(ExecSpec{
		prog:    bin
		args:    args
		dry_run: opts.dry_run
	})
	if opts.dry_run {
		return ok_result('appearance theme apply', 'would run: ${rep.command_line}', {
			'command_line': rep.command_line
			'dry_run':      'true'
		})
	}
	if rep.ok {
		return ok_result('appearance theme apply', rep.output, {
			'command_line': rep.command_line
		})
	}
	return fail_result('appearance theme apply', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
}
