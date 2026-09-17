module hornero_core

import os
import x.json2

// Native GTK theme operations. Ports dots-gtk-theme plus
// gtk-theme-manager.sh: theme/icon listing, current reads, apply,
// color-scheme policy persistence, wallpaper-based detection, and
// theme-pack GTK resolution. Only gsettings stays a backend
// (HORNERO_GSETTINGS_BIN); every INI edit and policy decision is V.

// resolve_gtk2_file locates ~/.gtkrc-2.0. Override with HORNERO_GTK2_FILE.
pub fn resolve_gtk2_file() string {
	env := os.getenv('HORNERO_GTK2_FILE')
	if env.len > 0 {
		return env
	}
	return os.join_path(os.home_dir(), '.gtkrc-2.0')
}

// config_home returns XDG_CONFIG_HOME (or ~/.config).
fn gtk_config_home() string {
	base := os.getenv('XDG_CONFIG_HOME')
	if base.len > 0 {
		return base
	}
	return os.join_path(os.home_dir(), '.config')
}

// resolve_gtk3_file locates gtk-3.0/settings.ini. Override with HORNERO_GTK3_FILE.
pub fn resolve_gtk3_file() string {
	env := os.getenv('HORNERO_GTK3_FILE')
	if env.len > 0 {
		return env
	}
	return os.join_path(gtk_config_home(), 'gtk-3.0', 'settings.ini')
}

// resolve_gtk4_file locates gtk-4.0/settings.ini. Override with HORNERO_GTK4_FILE.
pub fn resolve_gtk4_file() string {
	env := os.getenv('HORNERO_GTK4_FILE')
	if env.len > 0 {
		return env
	}
	return os.join_path(gtk_config_home(), 'gtk-4.0', 'settings.ini')
}

// gtk_ini_get returns the first `key=value` line value in an INI file.
pub fn gtk_ini_get(path string, key string) string {
	raw := os.read_file(path) or { return '' }
	for line in raw.split_into_lines() {
		if line.starts_with(key + '=') {
			return line[key.len + 1..]
		}
	}
	return ''
}

// gtk_ini_set upserts one `key=value` line, creating the file (with a
// [Settings] header) when missing — the _gtk_ini_set port.
pub fn gtk_ini_set(path string, key string, value string) ! {
	os.mkdir_all(os.dir(path)) or { return error('cannot create ${os.dir(path)}: ${err.msg()}') }
	mut lines := []string{}
	if os.is_file(path) {
		lines = (os.read_file(path) or { '' }).split_into_lines()
	} else {
		lines = ['[Settings]']
	}
	mut done := false
	mut has_settings := false
	for i, line in lines {
		if line.trim_space() == '[Settings]' {
			has_settings = true
		}
		if !done && line.starts_with(key + '=') {
			lines[i] = '${key}=${value}'
			done = true
		}
	}
	if !done {
		if !has_settings {
			lines << '[Settings]'
		}
		lines << '${key}=${value}'
	}
	os.write_file(path, lines.join('\n') + '\n') or {
		return error('cannot write ${path}: ${err.msg()}')
	}
}

// read_gtk3_ini reads theme, icon, and prefer-dark from settings.ini.
pub fn read_gtk3_ini() (string, string, string) {
	path := resolve_gtk3_file()
	return gtk_ini_get(path, 'gtk-theme-name'), gtk_ini_get(path, 'gtk-icon-theme-name'), gtk_ini_get(path,
		'gtk-application-prefer-dark-theme')
}

// gtk_theme_search_dirs lists the directories scanned for GTK themes.
pub fn gtk_theme_search_dirs() []string {
	mut home_share := os.join_path(os.home_dir(), '.local', 'share', 'themes')
	base := os.getenv('XDG_DATA_HOME')
	if base.len > 0 {
		home_share = os.join_path(base, 'themes')
	}
	return ['/usr/share/themes', '/usr/local/share/themes', os.join_path(os.home_dir(),
		'.themes'),
		home_share]
}

// gtk_icon_search_dirs lists the directories scanned for icon themes.
pub fn gtk_icon_search_dirs() []string {
	mut home_share := os.join_path(os.home_dir(), '.local', 'share', 'icons')
	base := os.getenv('XDG_DATA_HOME')
	if base.len > 0 {
		home_share = os.join_path(base, 'icons')
	}
	return ['/usr/share/icons', '/usr/local/share/icons', os.join_path(os.home_dir(), '.icons'),
		home_share]
}

// list_names_in_dirs returns sorted unique subdirectory names. When
// require_index is set, only entries containing an index.theme file
// count (icon themes); otherwise entries with a gtk-2.0/gtk-3.0 child
// count (GTK themes). default/hicolor are always skipped for icons.
pub fn list_names_in_dirs(dirs []string, require_index bool) []string {
	mut seen := map[string]bool{}
	for dir in dirs {
		entries := os.ls(dir) or { continue }
		for name in entries {
			if require_index {
				if name == 'default' || name == 'hicolor' {
					continue
				}
				if !os.is_file(os.join_path(dir, name, 'index.theme')) {
					continue
				}
			} else {
				if !(os.is_dir(os.join_path(dir, name, 'gtk-2.0'))
					|| os.is_dir(os.join_path(dir, name, 'gtk-3.0'))) {
					continue
				}
			}
			seen[name] = true
		}
	}
	mut out := seen.keys()
	out.sort()
	return out
}

// detect_gtk_theme picks (theme, prefer_dark) from a pywal background hex
// and the installed themes, mirroring detect_optimal_gtk_theme: dark
// backgrounds (r+g+b below 384) prefer the dark list.
pub fn detect_gtk_theme(pywal_bg string, installed []string) (string, string) {
	r, g, b := parse_hex6(pywal_bg) or { return 'Orchis-Light', 'false' }
	present := fn [installed] (name string) bool {
		return name in installed
	}
	if r + g + b < 384 {
		for t in ['Orchis-Dark-Compact', 'Arc-Dark', 'elementary-dark', 'Breeze-Dark'] {
			if present(t) {
				return t, 'true'
			}
		}
		return 'Orchis-Light', 'false'
	}
	for t in ['Orchis-Light', 'Arc', 'elementary', 'Breeze'] {
		if present(t) {
			return t, 'false'
		}
	}
	return 'Orchis-Light', 'false'
}

// gsettings_maybe runs one gsettings set best-effort (failures ignored,
// like the `|| true` bash callsites): the preview line is always
// recorded; execution happens only on real runs with gsettings present.
fn gsettings_maybe(bin string, args []string, dry_run bool, mut lines []string) {
	lines << strict_command_line(if bin.len > 0 { bin } else { 'gsettings' }, args)
	if dry_run || bin.len == 0 {
		return
	}
	strict_exec(bin, args, false)
}

// update_state_json_fields merges string fields into the canonical state
// file (WRITE TARGET), seeding defaults for absent keys without ever
// touching keys it was not asked to write.
pub fn update_state_json_fields(fields map[string]string, defaults map[string]string) !string {
	path := scheme_state_file()
	raw := os.read_file(path) or { '{}' }
	mut m := json2.decode[map[string]json2.Any](raw) or {
		map[string]json2.Any{}
	}
	for k, v in defaults {
		if k !in m {
			m[k] = json2.Any(v)
		}
	}
	for k, v in fields {
		m[k] = json2.Any(v)
	}
	os.mkdir_all(os.dir(path)) or { return error('cannot create ${os.dir(path)}: ${err.msg()}') }
	tmp := os.join_path(os.dir(path), '.state.json.tmp')
	os.write_file(tmp, json2.encode(m, escape_unicode: true) + '\n') or {
		return error('cannot write ${tmp}: ${err.msg()}')
	}
	os.mv(tmp, path) or { return error('cannot move ${tmp} to ${path}: ${err.msg()}') }
	return path
}

// apply_gtk_color_scheme_native sets the persisted gtkColorScheme policy
// and applies its effective mapping to the INI files (+ gsettings when
// present). It never writes the shell `mode`.
pub fn apply_gtk_color_scheme_native(requested string, dry_run bool) CommandResult {
	policy := normalize_gtk_color_scheme(requested)
	if policy == 'invalid' || requested.len == 0 {
		return fail_result('appearance gtk color-scheme', 'Policy must be follow|default|prefer-light|prefer-dark|light|dark.\nExample: horneroctl appearance gtk color-scheme prefer-light --dry-run')
	}
	st := read_scheme_state()
	effective := effective_gtk_policy(policy, st.mode)
	prefer_dark, color_scheme := policy_prefer_dark_and_scheme(effective)
	mut lines := []string{}
	lines << 'persist gtkColorScheme=${policy} in ${scheme_state_file()}'
	lines << 'write gtk-application-prefer-dark-theme=${prefer_dark} (gtk3 + gtk4)'
	gs := resolve_gsettings_bin()
	gsettings_maybe(gs, ['set', 'org.gnome.desktop.interface', 'gtk-application-prefer-dark-theme',
		prefer_dark], dry_run, mut lines)
	gsettings_maybe(gs, ['set', 'org.gnome.desktop.interface', 'color-scheme', color_scheme],
		dry_run, mut lines)
	if dry_run {
		return ok_result('appearance gtk color-scheme', 'would run:\n' + lines.join('\n'),
			{
			'command_line': lines.join('\n')
			'dry_run':      'true'
			'policy':       policy
			'effective':    effective
		})
	}
	update_state_json_fields({
		'gtkColorScheme': policy
	}, {
		'name':    'dynamic'
		'flavour': 'tonal-spot'
		'variant': 'tonalspot'
	}) or {
		return fail_result('appearance gtk color-scheme', 'cannot persist policy: ${err.msg()}')
	}
	gtk_ini_set(resolve_gtk3_file(), 'gtk-application-prefer-dark-theme', prefer_dark) or {
		return fail_result('appearance gtk color-scheme', 'cannot write gtk3 settings: ${err.msg()}')
	}
	gtk_ini_set(resolve_gtk4_file(), 'gtk-application-prefer-dark-theme', prefer_dark) or {
		return fail_result('appearance gtk color-scheme', 'cannot write gtk4 settings: ${err.msg()}')
	}
	return ok_result('appearance gtk color-scheme', 'GTK color-scheme policy: ${policy} (effective ${effective})',
		{
		'policy':    policy
		'effective': effective
	})
}

// sync_gtk_color_scheme_native re-applies the persisted policy (follow
// resolves from the current shell mode).
pub fn sync_gtk_color_scheme_native(dry_run bool) CommandResult {
	return apply_gtk_color_scheme_native(read_scheme_state().gtk_color_scheme, dry_run)
}

const gtk_theme_fallbacks = ['Orchis-Light', 'elementary', 'Arc-Dark', 'Arc', 'Breeze', 'oxygen-gtk']
const gtk_icon_fallbacks = ['Numix-Circle', 'elementary', 'hicolor']

// resolve_gtk_theme_with_fallbacks validates a theme against the
// installed set, walking the fallback list like apply_gtk_theme.
pub fn resolve_gtk_theme_with_fallbacks(wanted string, installed []string) !string {
	if wanted in installed {
		return wanted
	}
	for fb in gtk_theme_fallbacks {
		if fb in installed {
			return fb
		}
	}
	return error("GTK theme '${wanted}' not found and no fallback installed")
}

// resolve_icon_with_fallbacks validates an icon theme; unlike GTK themes
// a missing icon set keeps the requested name (bash behavior).
pub fn resolve_icon_with_fallbacks(wanted string, installed []string) string {
	if wanted in installed {
		return wanted
	}
	for fb in gtk_icon_fallbacks {
		if fb in installed {
			return fb
		}
	}
	return wanted
}

const gtk2_config_template = '# DO NOT EDIT! This file will be overwritten by LXAppearance.\n# Any customization should be done in ~/.gtkrc-2.0.mine instead.\n\ninclude "/home/\$USER/.gtkrc-2.0.mine"\n'

const gtk3_config_template = '[Settings]\n'

// patch_gtk2_config rewrites theme/icon lines in an existing gtkrc, or
// renders the created-file template. Pure: takes file content, returns
// new content plus whether the theme changed.
pub fn patch_gtk2_config(existing string, theme string, icon string) string {
	if existing.len == 0 {
		return gtk2_config_template + 'gtk-theme-name="${theme}"\n' +
			'gtk-icon-theme-name="${icon}"\n' + 'gtk-font-name="sans 11"\n' +
			'gtk-cursor-theme-name="elementary"\n' + 'gtk-cursor-theme-size=24\n' +
			'gtk-toolbar-style=GTK_TOOLBAR_ICONS\n' +
			'gtk-toolbar-icon-size=GTK_ICON_SIZE_SMALL_TOOLBAR\n' + 'gtk-button-images=1\n' +
			'gtk-menu-images=1\n' + 'gtk-enable-event-sounds=1\n' +
			'gtk-enable-input-feedback-sounds=0\n' + 'gtk-xft-antialias=1\n' +
			'gtk-xft-hinting=1\n' + 'gtk-xft-hintstyle="hintslight"\n' + 'gtk-xft-rgba="rgb"\n'
	}
	mut out := []string{}
	for line in existing.split_into_lines() {
		if line.starts_with('gtk-theme-name=') {
			out << 'gtk-theme-name="${theme}"'
		} else if line.starts_with('gtk-icon-theme-name=') {
			out << 'gtk-icon-theme-name="${icon}"'
		} else {
			out << line
		}
	}
	return out.join('\n')
}

// apply_gtk_theme_native applies a GTK + icon theme end to end: INI
// files, gsettings, gtk4 mirror, then the color-scheme policy (explicit
// third arg wins, otherwise the live policy is re-applied so a theme
// rename cannot clobber it).
pub fn apply_gtk_theme_native(theme string, icon string, policy_arg string, dry_run bool) CommandResult {
	if theme.len == 0 {
		return fail_result('appearance gtk apply', 'Theme name required.\nExample: horneroctl appearance gtk apply Orchis-Dark --dry-run')
	}
	installed := list_names_in_dirs(gtk_theme_search_dirs(), false)
	resolved := resolve_gtk_theme_with_fallbacks(theme, installed) or {
		return fail_result('appearance gtk apply', err.msg())
	}
	icons := list_names_in_dirs(gtk_icon_search_dirs(), true)
	icon_name := if icon.len > 0 { icon } else { current_icon_theme() }
	resolved_icon := resolve_icon_with_fallbacks(if icon_name.len > 0 {
		icon_name
	} else {
		'Numix-Circle'
	}, icons)
	mut lines := []string{}
	lines << 'write gtk2/gtk3/gtk4 theme=${resolved} icons=${resolved_icon}'
	gs := resolve_gsettings_bin()
	gsettings_maybe(gs, ['set', 'org.gnome.desktop.interface', 'gtk-theme', resolved],
		dry_run, mut lines)
	gsettings_maybe(gs, ['set', 'org.gnome.desktop.interface', 'icon-theme', resolved_icon],
		dry_run, mut lines)
	mut policy := if policy_arg.len > 0 { normalize_gtk_color_scheme(policy_arg) } else { '' }
	if policy == 'invalid' {
		policy = ''
	}
	if dry_run {
		tail := if policy.len > 0 {
			'apply policy ${policy}'
		} else {
			're-apply live policy ${read_scheme_state().gtk_color_scheme}'
		}
		lines << tail
		return ok_result('appearance gtk apply', 'would run:\n' + lines.join('\n'), {
			'command_line': lines.join('\n')
			'dry_run':      'true'
			'theme':        resolved
			'icons':        resolved_icon
		})
	}
	gtk2_path := resolve_gtk2_file()
	gtk2_existing := os.read_file(gtk2_path) or { '' }
	os.mkdir_all(os.dir(gtk2_path)) or {}
	os.write_file(gtk2_path, patch_gtk2_config(gtk2_existing, resolved, resolved_icon)) or {
		return fail_result('appearance gtk apply', 'cannot write gtk2 config: ${err.msg()}')
	}
	gtk3_path := resolve_gtk3_file()
	if !os.is_file(gtk3_path) {
		os.mkdir_all(os.dir(gtk3_path)) or {}
		os.write_file(gtk3_path, gtk3_config_template) or {
			return fail_result('appearance gtk apply', 'cannot write gtk3 config: ${err.msg()}')
		}
	}
	gtk_ini_set(gtk3_path, 'gtk-theme-name', resolved) or {
		return fail_result('appearance gtk apply', 'cannot write gtk3 config: ${err.msg()}')
	}
	gtk_ini_set(gtk3_path, 'gtk-icon-theme-name', resolved_icon) or {
		return fail_result('appearance gtk apply', 'cannot write gtk3 config: ${err.msg()}')
	}
	gtk_ini_set(resolve_gtk4_file(), 'gtk-theme-name', resolved) or {
		return fail_result('appearance gtk apply', 'cannot write gtk4 config: ${err.msg()}')
	}
	gtk_ini_set(resolve_gtk4_file(), 'gtk-icon-theme-name', resolved_icon) or {
		return fail_result('appearance gtk apply', 'cannot write gtk4 config: ${err.msg()}')
	}
	policy_rep := if policy.len > 0 {
		apply_gtk_color_scheme_native(policy, false)
	} else {
		sync_gtk_color_scheme_native(false)
	}
	if !policy_rep.ok {
		return fail_result('appearance gtk apply', 'theme applied but policy sync failed: ${policy_rep.message}')
	}
	return ok_result('appearance gtk apply', 'Theme applied successfully: ${resolved}',
		{
		'theme':  resolved
		'icons':  resolved_icon
		'policy': policy_rep.data['policy']
	})
}

// gtk_list_report implements `appearance gtk list|icons` (read-only).
pub fn gtk_list_report(icons bool) CommandResult {
	names := list_names_in_dirs(if icons { gtk_icon_search_dirs() } else { gtk_theme_search_dirs() },
		icons)
	verb := if icons { 'icons' } else { 'list' }
	if names.len == 0 {
		return fail_result('appearance gtk ' + verb, 'No ${verb} found.')
	}
	return ok_result('appearance gtk ' + verb, names.join('\n'), {
		'count': '${names.len}'
	})
}

// gtk_current_report implements `appearance gtk current` (read-only).
pub fn gtk_current_report() CommandResult {
	theme := current_gtk_theme()
	return ok_result('appearance gtk current', theme, {
		'theme': theme
	})
}

// gtk_current_icon_report implements `appearance gtk current-icon`.
pub fn gtk_current_icon_report() CommandResult {
	mut icon := current_icon_theme()
	if icon.len == 0 {
		icon = 'Unknown'
	}
	return ok_result('appearance gtk current-icon', icon, {
		'icon': icon
	})
}

// gtk_current_policy_report implements `appearance gtk
// current-color-scheme` (read-only).
pub fn gtk_current_policy_report() CommandResult {
	policy := read_scheme_state().gtk_color_scheme
	return ok_result('appearance gtk current-color-scheme', policy, {
		'policy': policy
	})
}

// gtk_detect_report implements `appearance gtk detect [wallpaper]`
// (read-only suggestion, never applies).
pub fn gtk_detect_report(wallpaper string) CommandResult {
	wall := if wallpaper.len > 0 { wallpaper } else { read_wallpaper_pointer() }
	if wall.len == 0 || !os.is_file(wall) {
		return fail_result('appearance gtk detect', 'No wallpaper specified and no current wallpaper found.')
	}
	bg := read_wal_colors_bg()
	theme, prefer_dark := detect_gtk_theme(if bg.len > 0 { bg } else { '000000' }, list_names_in_dirs(gtk_theme_search_dirs(),
		false))
	return ok_result('appearance gtk detect', 'Detected optimal theme: ${theme}\nDark preference: ${prefer_dark}',
		{
		'theme':       theme
		'prefer_dark': prefer_dark
		'wallpaper':   wall
	})
}

// gtk_info_report implements `appearance gtk info <name>` (read-only).
pub fn gtk_info_report(name string) CommandResult {
	mut home_share := os.join_path(os.home_dir(), '.local', 'share', 'themes')
	xdg_data := os.getenv('XDG_DATA_HOME')
	if xdg_data.len > 0 {
		home_share = os.join_path(xdg_data, 'themes')
	}
	dirs := ['/usr/share/themes', '/usr/local/share/themes', os.join_path(os.home_dir(),
		'.themes'),
		home_share]
	mut found := ''
	for dir in dirs {
		if os.is_dir(os.join_path(dir, name)) {
			found = os.join_path(dir, name)
			break
		}
	}
	if found.len == 0 {
		return fail_result('appearance gtk info', 'Theme not found: ${name}')
	}
	mut lines := ['Theme Information: ${name}', '', 'Location: ${found}', '', 'Available Components:']
	for comp in ['gtk-2.0', 'gtk-3.0', 'gtk-4.0'] {
		mark := if os.is_dir(os.join_path(found, comp)) { 'yes' } else { 'no' }
		lines << '  ${comp}: ${mark}'
	}
	meta := os.join_path(found, 'index.theme')
	if os.is_file(meta) {
		lines << ''
		lines << 'Theme Metadata:'
		for line in (os.read_file(meta) or { '' }).split_into_lines() {
			if line.starts_with('Name=') {
				lines << '  Name: ${line[5..]}'
			} else if line.starts_with('Comment=') {
				lines << '  Description: ${line[8..]}'
			}
		}
	}
	return ok_result('appearance gtk info', lines.join('\n'), {
		'name': name
		'path': found
	})
}

// current_gtk_theme reads the live GTK theme (gtk3 ini, then gtk2, then
// gsettings), like get_current_gtk_theme.
pub fn current_gtk_theme() string {
	theme, _, _ := read_gtk3_ini()
	if theme.len > 0 {
		return theme
	}
	raw := os.read_file(resolve_gtk2_file()) or { '' }
	for line in raw.split_into_lines() {
		if line.starts_with('gtk-theme-name=') {
			return line.all_after_first('gtk-theme-name=').trim('"')
		}
	}
	gs := resolve_gsettings_bin()
	if gs.len > 0 {
		rep := strict_exec(gs, ['get', 'org.gnome.desktop.interface', 'gtk-theme'], false)
		if rep.ok && rep.output.len > 0 {
			return rep.output.trim("'")
		}
	}
	return 'Unknown'
}

// current_icon_theme reads the live icon theme (gtk3 ini, then
// gsettings, then gtk2), like get_current_icon_theme.
pub fn current_icon_theme() string {
	_, icon, _ := read_gtk3_ini()
	if icon.len > 0 {
		return icon
	}
	gs := resolve_gsettings_bin()
	if gs.len > 0 {
		rep := strict_exec(gs, ['get', 'org.gnome.desktop.interface', 'icon-theme'], false)
		if rep.ok && rep.output.len > 0 {
			return rep.output.trim("'")
		}
	}
	raw := os.read_file(resolve_gtk2_file()) or { '' }
	for line in raw.split_into_lines() {
		if line.starts_with('gtk-icon-theme-name=') {
			return line.all_after_first('gtk-icon-theme-name=').trim('"')
		}
	}
	return ''
}

pub struct GtkSelectOptions {
pub:
	dry_run bool
	yes     bool
}

// select_theme_by_index maps a 1-based menu choice to a 0-based index.
// Empty choice means cancelled (handled by the caller as a clean ok).
pub fn select_theme_by_index(names []string, choice string) !int {
	t := choice.trim_space()
	mut digits := t.len > 0
	for ch in t {
		if !ch.is_digit() {
			digits = false
		}
	}
	n := t.int()
	if !digits || n < 1 || n > names.len {
		return error('invalid selection `${t}` (want 1-${names.len}).\nExample: horneroctl appearance gtk select --dry-run')
	}
	return n - 1
}

// gtk_select_menu renders the numbered theme menu (read-only helper).
pub fn gtk_select_menu(names []string) string {
	mut lines := ['GTK themes:']
	for i, name in names {
		lines << '${i + 1}) ${name}'
	}
	lines << 'Select theme [1-${names.len}, empty to cancel]:'
	return lines.join('\n')
}

// gtk_stdin_choice is the production stdin reader for gtk select.
pub fn gtk_stdin_choice() string {
	return os.get_line()
}

// gtk_select_report implements `appearance gtk select`, the native
// dots-theme-selector: with quickshell up it opens the control center
// via shell IPC; otherwise it shows a numbered menu and applies the
// chosen theme natively. Needs --yes; --dry-run only previews.
// read_choice is the stdin seam (tests inject it).
pub fn gtk_select_report(opts GtkSelectOptions, read_choice fn () string) CommandResult {
	names := list_names_in_dirs(gtk_theme_search_dirs(), false)
	return gtk_select_report_with(opts, names, read_choice)
}

// gtk_select_report_with is the testable select core over an explicit
// theme list (read_choice is the stdin seam).
pub fn gtk_select_report_with(opts GtkSelectOptions, names []string, read_choice fn () string) CommandResult {
	if names.len == 0 {
		return fail_result('appearance gtk select', 'No GTK themes found.')
	}
	if shell_running() {
		return ipc_report(IpcOptions{
			passthrough: ['utilities', 'toggle']
			dry_run:     opts.dry_run
		})
	}
	menu := gtk_select_menu(names)
	if opts.dry_run {
		return ok_result('appearance gtk select', menu + '\nwould run: apply chosen theme natively',
			{
			'command_line': 'appearance gtk select'
			'dry_run':      'true'
			'count':        '${names.len}'
		})
	}
	if !opts.yes {
		return fail_result('appearance gtk select', 'refusing to apply without --yes (preview with --dry-run).\nExample: horneroctl appearance gtk select --dry-run')
	}
	choice := read_choice()
	if choice.trim_space().len == 0 {
		return ok_result('appearance gtk select', 'selection cancelled.', {
			'cancelled': 'true'
		})
	}
	idx := select_theme_by_index(names, choice) or {
		return fail_result('appearance gtk select', err.msg())
	}
	return apply_gtk_theme_native(names[idx], '', '', false)
}
