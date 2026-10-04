module hornero_core

import os
import x.json2

// Theme-pack backend: installed `theme.json` recipes.
//
// The packs ship in HorneroOS/config (`profiles/themes/<id>/theme.json`)
// and are installed to the user catalogue or the read-only system
// catalogue. Mutation (`apply`) runs the native shell pipeline in
// appearance_apply.v.

// resolve_themes_dir locates installed theme packs: the canonical
// `hornero/*` location (docs/PATH_CONTRACT.md row 1) and the WRITE TARGET.
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
	return os.join_path(base, 'hornero', 'themes')
}

// Return user packs first, followed by package-installed system packs.
pub fn resolve_themes_dirs_for_read() []string {
	env := os.getenv('HORNERO_THEMES_DIR')
	if env.len > 0 { return [env] }
	mut dirs := []string{}
	user := resolve_themes_dir()
	if os.is_dir(user) { dirs << user }
	append_system_catalogues(mut dirs, os.join_path('hornero', 'themes'))
	return dirs
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
// catalogue validation rules.
fn read_theme_pack(dir string, id string) !ThemeEntry {
	raw := os.read_file(os.join_path(dir, id, 'theme.json'))!
	parsed := json2.decode[json2.Any](raw)!
	if parsed is map[string]json2.Any {
		return theme_entry_from_map(id, parsed)
	}
	return error('theme pack is corrupt: ${id} (theme.json is not an object)')
}

// theme_entry_from_map validates required pack keys and the
// id == directory invariant.
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
// User packs override system packs. Unparseable pack
// directories are skipped (same as the backend lister).
pub fn list_theme_packs() ![]ThemeEntry {
	dirs := resolve_themes_dirs_for_read().filter(os.is_dir(it))
	if dirs.len == 0 {
		explicit := resolve_themes_dirs_for_read()
		dir := if explicit.len > 0 { explicit[0] } else { resolve_themes_dir() }
		return error('no themes installed at ${dir}. Set HORNERO_THEMES_DIR.\nExample: horneroctl appearance theme list --json')
	}
	mut seen := map[string]bool{}
	mut packs := []ThemeEntry{}
	for dir in dirs {
		entries := os.ls(dir) or { continue }
		for id in entries {
			if id in seen {
				continue
			}
			if !os.is_dir(os.join_path(dir, id)) {
				continue
			}
			if pack := read_theme_pack(dir, id) {
				packs << pack
				seen[id] = true
			} else {
				continue
			}
		}
	}
	packs.sort(a.id < b.id)
	return packs
}

// theme_image_exts mirrors EXTS in the retired list-themes.py backend:
// recognized wallpaper file suffixes (compared lowercased).
const theme_image_exts = ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp']

// theme_pictures_root preserves the optional user Pictures library, after
// the explicit Hornero override and before installed catalogue roots.
fn theme_pictures_root() string {
	return resolve_pictures_wallpapers_dir()
}

// theme_wallpaper_roots lists user then read-only installed catalogue
// wallpaper roots. An explicit HORNERO_WALLPAPERS_DIR override wins outright.
fn theme_wallpaper_roots() []string {
	return resolve_wallpapers_dirs_for_read()
}

// theme_wallpaper_index maps wallpaper filename to absolute path for one
// theme, first root winning (Pictures, then Hornero-managed media). Returns
// the sorted filenames plus the path map.
fn theme_wallpaper_index(theme_id string, wallpaper_dir string, roots []string) ([]string, map[string]string) {
	dir_name := if wallpaper_dir.len > 0 { wallpaper_dir } else { theme_id }
	mut found := map[string]string{}
	mut search := []string{}
	if os.getenv('HORNERO_WALLPAPERS_DIR').len == 0 {
		search << theme_pictures_root()
	}
	search << roots
	for root in search {
		d := os.join_path(root, dir_name)
		if !os.is_dir(d) {
			continue
		}
		files := os.ls(d) or { continue }
		for f in files {
			full := os.join_path(d, f)
			if !os.is_file(full) {
				continue
			}
			if os.file_ext(f).to_lower().trim_left('.') !in theme_image_exts {
				continue
			}
			if f in found {
				continue
			}
			found[f] = os.real_path(full)
		}
	}
	mut names := found.keys()
	names.sort()
	return names, found
}

// theme_resolve_wallpaper_file resolves one wallpaper filename from the
// user's gallery or an installed catalogue. An expected path is not an
// available wallpaper: callers use this result to decide whether a recipe
// can apply its default or should preserve the current background.
fn theme_resolve_wallpaper_file(wallpaper_dir string, filename string, roots []string) string {
	override := os.getenv('HORNERO_WALLPAPERS_DIR')
	pics := os.join_path(theme_pictures_root(), wallpaper_dir, filename)
	if override.len == 0 && os.is_file(pics) {
		return pics
	}
	for root in roots {
		candidate := os.join_path(root, wallpaper_dir, filename)
		if os.is_file(candidate) {
			return candidate
		}
	}
	return ''
}

// theme_truthy mirrors Python truthiness for manifest scalars.
fn theme_truthy(v json2.Any) bool {
	if v is bool {
		return v.bool()
	}
	if v is string {
		return v.str().len > 0
	}
	if v is i64 {
		return v.i64() != 0
	}
	if v is f64 {
		return v.f64() != 0
	}
	if v is []json2.Any {
		return v.as_array().len > 0
	}
	if v is map[string]json2.Any {
		return v.as_map().len > 0
	}
	return false
}

// theme_nonempty_str reads an optional non-empty string field.
fn theme_nonempty_str(m map[string]json2.Any, key string, fallback string) string {
	if key in m && m[key] is string && m[key].str().len > 0 {
		return m[key].str()
	}
	return fallback
}

// theme_gtk_prefer_dark resolves the effective dark preference: explicit
// gtkPreferDark first (null falls through), then the GTK name, then the
// pack darkMode. Mirrors the retired lister.
fn theme_gtk_prefer_dark(m map[string]json2.Any, gtk string, dark bool) bool {
	if 'gtkPreferDark' in m {
		raw := m['gtkPreferDark']
		if raw is bool || raw is string || raw is i64 || raw is f64 {
			return theme_truthy(raw)
		}
	}
	lower := gtk.to_lower()
	if lower.contains('light') {
		return false
	}
	if lower.contains('dark') {
		return true
	}
	return dark
}

// theme_gtk_color_scheme normalizes the persisted color-scheme policy.
// Mirrors the retired lister exactly.
fn theme_gtk_color_scheme(m map[string]json2.Any, prefer_dark bool) string {
	raw := theme_nonempty_str(m, 'gtkColorScheme', '').trim_space().to_lower().replace('_',
		'-')
	if raw in ['follow', 'default', 'prefer-light', 'prefer-dark'] {
		return raw
	}
	if raw == 'light' {
		return 'prefer-light'
	}
	if raw == 'dark' {
		return 'prefer-dark'
	}
	if raw in ['auto', 'apps'] {
		return 'default'
	}
	if prefer_dark {
		return 'prefer-dark'
	}
	return 'prefer-light'
}

// theme_load_full_entry builds one `--full` entry from a pack directory.
// Lenient like the retired lister: unparseable manifests are skipped by
// the caller, ids default to the directory name, every display field has
// a fallback. Returns the entry with its resolved id.
fn theme_load_full_entry(themes_dir string, dirname string, roots []string) !map[string]json2.Any {
	raw := os.read_file(os.join_path(themes_dir, dirname, 'theme.json'))!
	parsed := json2.decode[json2.Any](raw)!
	parsed_ok := parsed is map[string]json2.Any
	if !parsed_ok {
		return error('not an object')
	}
	m := parsed.as_map()
	theme_id := theme_nonempty_str(m, 'id', dirname)
	name := theme_nonempty_str(m, 'name', theme_id)
	description := theme_str_field(m, 'description')
	mut dark := true
	if 'darkMode' in m {
		dark = theme_truthy(m['darkMode'])
	}
	mut color_only := false
	if 'colorOnly' in m {
		color_only = theme_truthy(m['colorOnly'])
	}
	scheme := theme_nonempty_str(m, 'schemeType', 'tonal-spot')
	gtk := theme_nonempty_str(m, 'gtkTheme', 'Orchis-Light-Compact')
	icons := theme_nonempty_str(m, 'iconTheme', 'Numix-Circle')
	// Heuristics read the raw manifest value (missing counts as empty),
	// not the display default above — mirroring the retired lister.
	mut raw_gtk := ''
	if 'gtkTheme' in m && m['gtkTheme'] is string {
		raw_gtk = m['gtkTheme'].str()
	}
	prefer_dark := theme_gtk_prefer_dark(m, raw_gtk, dark)
	policy := theme_gtk_color_scheme(m, prefer_dark)
	wallpaper_dir := theme_nonempty_str(m, 'wallpaperDir', theme_id)
	walls, paths := theme_wallpaper_index(theme_id, wallpaper_dir, roots)
	mut preview := ''
	for candidate in ['preview.jpg', 'preview.webp', 'preview.png'] {
		p := os.join_path(themes_dir, dirname, candidate)
		if os.is_file(p) {
			preview = p
			break
		}
	}
	mut default_wall := theme_nonempty_str(m, 'defaultWallpaper', '')
	if default_wall.len == 0 && walls.len > 0 {
		default_wall = walls[0]
	}
	mut wallpaper_path := ''
	if default_wall.len > 0 {
		if default_wall in paths {
			wallpaper_path = paths[default_wall]
		} else {
			wallpaper_path = theme_resolve_wallpaper_file(wallpaper_dir, default_wall,
				roots)
		}
	}
	mut tags := []json2.Any{}
	if 'tags' in m && m['tags'] is []json2.Any {
		tags = m['tags'].as_array()
	}
	mut wall_list := []json2.Any{}
	for w in walls {
		wall_list << json2.Any(w)
	}
	mut wall_map := map[string]json2.Any{}
	mut path_names := paths.keys()
	path_names.sort()
	for n in path_names {
		wall_map[n] = json2.Any(paths[n])
	}
	collection := theme_str_field(m, 'collection')
	mut collection_order := 0
	if 'collectionOrder' in m {
		order := m['collectionOrder']
		if order is i64 {
			collection_order = int(order.i64())
		} else if order is f64 {
			collection_order = int(order.f64())
		}
	}
	model := if theme_str_field(m, 'family').len > 0 { 'semantic' } else { 'recipe' }
	return {
		'id':               json2.Any(theme_id)
		'name':             json2.Any(name)
		'colorOnly':        json2.Any(color_only)
		'description':      json2.Any(description)
		'tags':             json2.Any(tags)
		'collection':       json2.Any(collection)
		'collectionOrder':  json2.Any(collection_order)
		'model':            json2.Any(model)
		'darkMode':         json2.Any(dark)
		'schemeType':       json2.Any(scheme)
		'gtkTheme':         json2.Any(gtk)
		'iconTheme':        json2.Any(icons)
		'gtkPreferDark':    json2.Any(prefer_dark)
		'gtkColorScheme':   json2.Any(policy)
		'defaultWallpaper': json2.Any(default_wall)
		'wallpaperDir':     json2.Any(wallpaper_dir)
		'wallpapers':       json2.Any(wall_list)
		'wallpaperPaths':   json2.Any(wall_map)
		'preview':          json2.Any(preview)
		'wallpaperPath':    json2.Any(wallpaper_path)
	}
}

// theme_list_full_report implements `appearance theme list --full`
// (read-only). The message is every pack manifest as a JSON array — same
// shape as the retired list-themes.py backend the launcher consumes.
pub fn theme_list_full_report() CommandResult {
	dirs := resolve_themes_dirs_for_read().filter(os.is_dir(it))
	if dirs.len == 0 {
		explicit := resolve_themes_dirs_for_read()
		dir := if explicit.len > 0 { explicit[0] } else { resolve_themes_dir() }
		return fail_result('appearance theme list', 'no themes installed at ${dir}. Set HORNERO_THEMES_DIR.\nExample: horneroctl appearance theme list --json')
	}
	roots := theme_wallpaper_roots()
	mut seen := map[string]bool{}
	mut order := []string{}
	mut items := map[string]map[string]json2.Any{}
	for dir in dirs {
		children := os.ls(dir) or { continue }
		mut sorted := children.clone()
		sorted.sort()
		for child in sorted {
			if !os.is_dir(os.join_path(dir, child)) {
				continue
			}
			entry := theme_load_full_entry(dir, child, roots) or { continue }
			id := entry['id'].str()
			if id in seen {
				continue
			}
			seen[id] = true
			order << id
			items[id] = entry
		}
	}
	order.sort()
	mut arr := []json2.Any{}
	for id in order {
		arr << json2.Any(items[id])
	}
	return ok_result('appearance theme list', json2.encode(arr, escape_unicode: true), {
		'count':  order.len.str()
		'format': 'full'
	})
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
// Canonical-first: the canonical copy wins when both locations hold the id.
pub fn show_theme_pack(id string) !ThemeShow {
	if id.len == 0 || id.contains('/') || id == '.' || id == '..' || id.contains('\x00') {
		return error('invalid theme id: ${id}.\nExample: horneroctl appearance theme show vapor-dreams')
	}
	dirs := resolve_themes_dirs_for_read()
	if dirs.len == 0 {
		return error('Theme not found: ${id}.\nRun: horneroctl appearance theme list')
	}
	mut raw := ''
	mut found := false
	for dir in dirs {
		raw = os.read_file(os.join_path(dir, id, 'theme.json')) or { continue }
		found = true
		break
	}
	if !found {
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

// theme_apply_report implements `appearance theme apply <id>` natively
// (shell IPC fast path, else the wal + M3 + GTK pipeline). Mutating:
// needs --yes; --dry-run only previews.
pub fn theme_apply_report(opts ThemeApplyOptions) CommandResult {
	if opts.id.len == 0 || opts.id.contains('/') || opts.id == '.' || opts.id == '..' {
		return fail_result('appearance theme apply', 'invalid theme id.\nExample: horneroctl appearance theme apply vapor-dreams --dry-run')
	}
	if !opts.yes && !opts.dry_run {
		return fail_result('appearance theme apply', 'refusing to apply without --yes (preview with --dry-run).\nExample: horneroctl appearance theme apply ${opts.id} --dry-run')
	}
	return theme_apply_native(opts.id, opts.wallpaper, opts.dry_run)
}
