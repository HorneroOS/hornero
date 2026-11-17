module hornero_core

import os
import time
import x.json2

// Native Hornero Signal appearance pipeline: theme apply, status, sync,
// doctor, the derived compositor/lock/terminal files, and the smart-color
// files. Colours come only from the selected schema-v2 theme (signal.v);
// the live scheme file is the shell contract, so apply never needs shell
// IPC. Quickshell IPC stays the fast path for GTK/icon setters only.

// resolve_quickshell_bin locates the IPC-capable shell CLI:
// HORNERO_QUICKSHELL_BIN, else `quickshell`, else `qs`.
pub fn resolve_quickshell_bin() string {
	ensure_quickshell_ipc_config()
	env := os.getenv('HORNERO_QUICKSHELL_BIN')
	if env.len > 0 {
		return env
	}
	bin := find_on_path('quickshell')
	if bin.len > 0 {
		return bin
	}
	return find_on_path('qs')
}

// ipc_appearance_call runs `quickshell ipc call appearance ...` once.
fn ipc_appearance_call(args []string, dry_run bool) ExecReport {
	bin := resolve_quickshell_bin()
	if bin.len == 0 {
		return ExecReport{
			command_line: 'quickshell ipc call appearance ' + args.join(' ')
			ok:           false
			output:       'quickshell not found'
			exit_code:    1
		}
	}
	mut full := ['ipc', 'call', 'appearance']
	full << args
	return strict_exec(bin, full, dry_run)
}

// wait_appearance_ipc polls isBusy/lastError after an IPC mutation
// (120 polls, then the last error).
fn wait_appearance_ipc(dry_run bool) !string {
	if dry_run {
		return 'preview'
	}
	mut busy := ''
	for _ in 0 .. 120 {
		rep := ipc_appearance_call(['isBusy'], false)
		if !rep.ok {
			return error('failed to poll appearance isBusy via Quickshell IPC')
		}
		busy = rep.output.replace('\r', '').replace('\n', '')
		if busy != '1' {
			break
		}
		time.sleep(500 * time.millisecond)
	}
	if busy == '1' {
		return error('appearance apply timed out waiting for Quickshell')
	}
	last := ipc_appearance_call(['lastError'], false)
	err_text := last.output.replace('\r', '').replace('\n', '')
	if err_text.len > 0 {
		return error('appearance apply failed: ${err_text}')
	}
	return 'settled'
}

// shell_running reports whether a Quickshell process is visible in /proc.
// HORNERO_SHELL_RUNNING=0/1 forces the answer (hermetic tests and CI
// never depend on the host process table).
pub fn shell_running() bool {
	override := os.getenv('HORNERO_SHELL_RUNNING')
	if override == '0' {
		return false
	}
	if override == '1' {
		return true
	}
	for c in collect_proc_cmdlines() {
		base := c.split(' ').first()
		name := base.all_after_last('/')
		if name == 'quickshell' || name == 'qs' {
			return true
		}
	}
	return false
}

// AppearanceBackends is the test seam for every external side effect of
// a theme apply. Production uses default_appearance_backends().
pub struct AppearanceBackends {
pub:
	gtk_apply   fn (theme string, icon string, policy string, dry_run bool) CommandResult @[required]
	pack_extras fn (id string, gtk_theme string, name string) @[required]
	reload      fn () @[required]
}

fn default_gtk_apply(theme string, icon string, policy string, dry_run bool) CommandResult {
	return apply_gtk_theme_native(theme, icon, policy, dry_run)
}

// default_pack_extras runs the best-effort per-pack integrations.
fn default_pack_extras(id string, gtk_theme string, name string) {
	chromatic_release_outputs()
	sync_kitty_include(id)
	sync_gtk_recolor(gtk_theme)
	sync_qt6ct_palette(id)
	snappy_pack_best_effort(id)
	notify_best_effort('Hornero', '${name} theme applied')
}

// default_reload asks Hyprland and running terminals to re-read colours.
fn default_reload() {
	hc := resolve_hyprctl_bin()
	if hc.len > 0 {
		strict_exec(hc, ['reload'], false)
	}
	pk := resolve_pkill_bin()
	strict_exec(pk, ['-SIGUSR1', '-x', 'kitty'], false)
	reload_ghostty_theme()
}

pub fn default_appearance_backends() AppearanceBackends {
	return AppearanceBackends{
		gtk_apply:   default_gtk_apply
		pack_extras: default_pack_extras
		reload:      default_reload
	}
}

// reload_ghostty_theme asks a running Ghostty to re-read its named theme:
// the documented user service first, else SIGUSR2 through pkill.
fn reload_ghostty_theme() {
	systemctl := find_on_path('systemctl')
	if systemctl.len > 0 {
		active := strict_exec(systemctl, ['--user', 'is-active', '--quiet',
			'app-com.mitchellh.ghostty.service'], false)
		if active.ok {
			reloaded := strict_exec(systemctl, ['--user', 'reload', 'app-com.mitchellh.ghostty.service'], false)
			if reloaded.ok {
				return
			}
		}
	}
	_ = strict_exec(resolve_pkill_bin(), ['-USR2', '-x', 'ghostty'], false)
}

// read_pack_map reads one theme pack's theme.json canonical-first.
pub fn read_pack_map(id string) !map[string]json2.Any {
	for dir in resolve_themes_dirs_for_read() {
		raw := os.read_file(os.join_path(dir, id, 'theme.json')) or { continue }
		parsed := json2.decode[json2.Any](raw) or { continue }
		if parsed is map[string]json2.Any {
			return parsed
		}
	}
	return error('Theme not found: ${id}.\nRun: horneroctl appearance theme list')
}

// pack_str reads one string field from a pack map (bools render true/false).
pub fn pack_str(m map[string]json2.Any, key string) string {
	if key !in m {
		return ''
	}
	return m[key].str()
}

// resolve_pack_wallpaper finds the wallpaper for a pack: the override
// first, then Pictures/Wallpapers, then the installed wallpaper trees
// (default name, else first sorted image).
pub fn resolve_pack_wallpaper(id string, wallpaper_dir string, default_name string, override string) !string {
	if override.len > 0 {
		real := os.real_path(override)
		if os.is_file(real) {
			return real
		}
		return error('wallpaper not found: ${override}')
	}
	pics_base := resolve_pictures_wallpapers_dir()
	wall_roots := resolve_wallpapers_dirs_for_read()
	mut search_dirs := []string{}
	if os.getenv('HORNERO_WALLPAPERS_DIR').len == 0 {
		search_dirs << os.join_path(pics_base, wallpaper_dir)
	}
	for root in wall_roots {
		search_dirs << os.join_path(root, wallpaper_dir)
	}
	for base in search_dirs {
		if default_name.len > 0 && os.is_file(os.join_path(base, default_name)) {
			return os.real_path(os.join_path(base, default_name))
		}
	}
	for base in search_dirs {
		entries := os.ls(base) or { continue }
		mut cands := []string{}
		for e in entries {
			if os.file_ext(e).to_lower().trim_left('.') in theme_image_exts {
				full := os.join_path(base, e)
				if os.is_file(full) {
					cands << os.real_path(full)
				}
			}
		}
		cands.sort()
		if cands.len > 0 {
			return cands[0]
		}
	}
	return error('no wallpaper for theme ${id}')
}

// write_wallpaper_pointer atomically replaces the canonical Hornero pointer
// (the shell watches it). Setting a wallpaper never changes a colour.
fn write_wallpaper_pointer(pointer string, wallpaper string) ! {
	write_file_atomic(pointer, wallpaper + '\n')!
}

// check_typed_theme_id rejects malformed ids and names retired ones with
// their replacement instead of silently rewriting explicit input.
fn check_typed_theme_id(id string) ! {
	if id.len == 0 || id.contains('/') || id == '.' || id == '..' || id.contains('\x00') {
		return error('invalid theme id.\nExample: horneroctl appearance theme apply ${signal_default_theme_id} --dry-run')
	}
	replacement := retired_theme_replacement(id)
	if replacement.len > 0 {
		return error('theme ${id} was removed with Hornero Signal; use ${replacement}.\nExample: horneroctl appearance theme apply ${replacement} --yes')
	}
}

// theme_apply_native applies one schema-v2 theme pack.
pub fn theme_apply_native(id string, wallpaper_override string, dry_run bool) CommandResult {
	return theme_apply_native_with(id, wallpaper_override, dry_run, default_appearance_backends())
}

// theme_apply_native_with is the injectable worker behind
// theme_apply_native: validate the pack, migrate retired selections once,
// write the live scheme and every derived file atomically, persist the
// selection, then apply wallpaper and GTK.
pub fn theme_apply_native_with(id string, wallpaper_override string, dry_run bool, deps AppearanceBackends) CommandResult {
	check_typed_theme_id(id) or { return fail_result('appearance theme apply', err.msg()) }
	pack := read_pack_map(id) or { return fail_result('appearance theme apply', err.msg()) }
	theme := parse_signal_theme(id, pack) or {
		return fail_result('appearance theme apply', 'not a Hornero Signal theme: ${err.msg()}')
	}
	mut gtk_theme := pack_str(pack, 'gtkTheme')
	mut icon_theme := pack_str(pack, 'iconTheme')
	if icon_theme.len == 0 {
		icon_theme = 'Papirus-Dark'
	}
	policy := pack_gtk_policy(pack_str(pack, 'gtkColorScheme'), '', '', theme.mode)
	wallpaper_dir := theme_nonempty_str(pack, 'wallpaperDir', id)
	default_wall := pack_str(pack, 'defaultWallpaper')
	has_wallpaper := wallpaper_override.len > 0 || default_wall.len > 0 || 'wallpaperDir' in pack
	mut wallpaper := ''
	if has_wallpaper {
		wallpaper = resolve_pack_wallpaper(id, wallpaper_dir, default_wall, wallpaper_override) or {
			if wallpaper_override.len > 0 {
				return fail_result('appearance theme apply', err.msg())
			}
			''
		}
	}
	pointer := resolve_wallpaper_pointer_file()
	migration := plan_legacy_migration()
	if dry_run {
		mut lines := []string{}
		for c in migration.changes {
			lines << 'would migrate ${c}'
		}
		lines << signal_output_preview()
		lines << 'would persist theme ${id} in ${scheme_state_file()} and ${shell_config_file(resolve_paths())}'
		if wallpaper.len > 0 {
			lines << 'would atomically write ${wallpaper} to ${pointer}'
		} else {
			lines << 'would keep the current wallpaper'
		}
		gtk_label := if gtk_theme.len == 0 || gtk_theme == 'auto' { 'auto' } else { gtk_theme }
		lines << 'would run: apply gtk ${gtk_label} icons ${icon_theme} policy ${policy}'
		lines << 'would run: sync kitty include, gtk recolor, qt6ct palette; reload Hyprland and terminals'
		return ok_result('appearance theme apply', lines.join('\n'), {
			'command_line': lines.join('\n')
			'dry_run':      'true'
			'id':           id
			'mode':         theme.mode
		})
	}
	migrate_legacy_appearance() or {
		return fail_result('appearance theme apply', 'cannot migrate retired appearance state: ${err.msg()}')
	}
	outputs := write_signal_outputs(theme) or {
		return fail_result('appearance theme apply', err.msg())
	}
	persist_state_theme(id) or {
		return fail_result('appearance theme apply', 'scheme written but state persist failed: ${err.msg()}')
	}
	persist_shell_theme(id) or {
		return fail_result('appearance theme apply', 'scheme written but shell.json update failed: ${err.msg()}')
	}
	if wallpaper.len > 0 {
		write_wallpaper_pointer(pointer, wallpaper) or {
			return fail_result('appearance theme apply', 'scheme written but wallpaper pointer failed: ${err.msg()}')
		}
	}
	if gtk_theme.len == 0 || gtk_theme == 'auto' {
		gtk_theme = gtk_theme_for(theme)
	}
	gtk := deps.gtk_apply(gtk_theme, icon_theme, policy, false)
	if !gtk.ok {
		return fail_result('appearance theme apply', 'scheme written, but GTK apply failed: ${gtk.message}')
	}
	deps.pack_extras(id, gtk_theme, theme.name)
	deps.reload()
	mut msg := '${theme.name} theme applied (${outputs.scheme})'
	if migration.changes.len > 0 {
		msg += '\nmigrated: ' + migration.changes.join('; ')
	}
	return ok_result('appearance theme apply', msg, {
		'id':        id
		'mode':      theme.mode
		'scheme':    outputs.scheme
		'wallpaper': wallpaper
	})
}

// gtk_theme_for picks an installed GTK theme for packs that set gtkTheme
// to auto (or omit it), from the luminance of the theme's ground role.
fn gtk_theme_for(theme SignalTheme) string {
	name, _ := detect_gtk_theme(theme.role('ground'), list_names_in_dirs(gtk_theme_search_dirs(),
		false))
	return name
}

// theme_pack_gtk_apply applies the GTK/icon side of one pack (mode-based
// GTK pick when gtkTheme is auto). An empty id uses the current theme.
pub fn theme_pack_gtk_apply(id_arg string, dry_run bool) CommandResult {
	id := if id_arg.len > 0 { id_arg } else { resolve_signal_selection().id }
	pack := read_pack_map(id) or { return fail_result('appearance gtk theme', err.msg()) }
	theme := parse_signal_theme(id, pack) or {
		return fail_result('appearance gtk theme', 'not a Hornero Signal theme: ${err.msg()}')
	}
	mut gtk_theme := pack_str(pack, 'gtkTheme')
	mut icon_theme := pack_str(pack, 'iconTheme')
	if icon_theme.len == 0 {
		icon_theme = 'Papirus-Dark'
	}
	policy := pack_gtk_policy(pack_str(pack, 'gtkColorScheme'), '', '', theme.mode)
	if gtk_theme.len == 0 || gtk_theme == 'auto' {
		gtk_theme = gtk_theme_for(theme)
	}
	return apply_gtk_theme_native(gtk_theme, icon_theme, policy, dry_run)
}

// sync_kitty_include swaps the single theme `include <id>.conf` line of
// kitty.conf to the applied pack's shipped `<id>.conf` (HorneroOS/config
// ships one per theme). Only includes naming an installed or retired theme
// are touched; a missing kitty.conf or variant skips silently.
pub fn sync_kitty_include(theme_id string) {
	kitty_dir := os.join_path(gtk_config_home(), 'kitty')
	conf := os.join_path(kitty_dir, 'kitty.conf')
	variant := os.join_path(kitty_dir, theme_id + '.conf')
	if !os.is_file(conf) || !os.is_file(variant) {
		return
	}
	raw := os.read_file(conf) or { return }
	mut out := []string{}
	mut changed := false
	for line in raw.split_into_lines() {
		if line.starts_with('include ') && line.ends_with('.conf') {
			name := line.all_after('include ').trim_space().all_before_last('.conf')
			is_theme := name == chromatic_theme_id || retired_theme_replacement(name).len > 0
				|| (read_pack_map(name) or {
					map[string]json2.Any{}
				}).len > 0
			if !name.contains('/') && name != theme_id && is_theme {
				out << 'include ${theme_id}.conf'
				changed = true
				continue
			}
		}
		out << line
	}
	if changed {
		write_file_atomic(conf, out.join('\n') + '\n') or {}
	}
}

// sync_gtk_recolor copies the GTK theme's libadwaita recolor.css into
// place (silent no-op when the theme ships none).
pub fn sync_gtk_recolor(gtk_theme string) {
	if gtk_theme.len == 0 || gtk_theme.contains('/') {
		return
	}
	data := xdg_or_home('XDG_DATA_HOME', '.local/share')
	src := os.join_path(data, 'themes', gtk_theme, 'gtk-4.0', 'recolor.css')
	if !os.is_file(src) {
		return
	}
	dest := os.join_path(gtk_config_home(), 'gtk-4.0', 'gtk.css')
	os.mkdir_all(os.dir(dest)) or { return }
	os.cp(src, dest) or {}
}

// sync_qt6ct_palette points qt6ct at the theme's generated palette with
// a comment-preserving line edit (silent no-op when absent).
pub fn sync_qt6ct_palette(theme_id string) {
	qt_dir := os.join_path(gtk_config_home(), 'qt6ct')
	scheme := os.join_path(qt_dir, 'colors', theme_id + '.conf')
	conf := os.join_path(qt_dir, 'qt6ct.conf')
	if !os.is_file(scheme) || !os.is_file(conf) {
		return
	}
	raw := os.read_file(conf) or { return }
	mut out := []string{}
	mut in_appearance := false
	mut seen_palette := false
	mut seen_path := false
	for line in raw.split_into_lines() {
		stripped := line.trim_space()
		mut next := line
		if stripped.starts_with('[') {
			in_appearance = stripped == '[Appearance]'
		} else if in_appearance {
			if stripped.starts_with('custom_palette') {
				next = 'custom_palette=true'
				seen_palette = true
			} else if stripped.starts_with('color_scheme_path') {
				next = 'color_scheme_path=${scheme}'
				seen_path = true
			}
		}
		out << next
	}
	mut text := out.join('\n')
	if !seen_palette || !seen_path {
		mut extra := ''
		if !seen_palette {
			extra += 'custom_palette=true\n'
		}
		if !seen_path {
			extra += 'color_scheme_path=${scheme}\n'
		}
		if text.contains('[Appearance]\n') {
			text = text.replace('[Appearance]\n', '[Appearance]\n' + extra)
		} else {
			text = text.trim_space() + '\n[Appearance]\n' + extra
		}
		out = text.split_into_lines()
	}
	os.write_file(conf, out.join('\n') + '\n') or {}
}

// snappy_pack_best_effort hands the pack id to the sibling
// snappy-switcher family when installed; never fails.
fn snappy_pack_best_effort(theme_id string) {
	bin := resolve_hornero_snappy_bin()
	if bin.len == 0 {
		return
	}
	strict_exec(bin, ['apply-theme-pack', theme_id], false)
}

// notify_best_effort sends a desktop notice when notify-send exists.
fn notify_best_effort(title string, body string) {
	nb := resolve_notify_bin()
	if nb.len == 0 {
		return
	}
	strict_exec(nb, [title, body], false)
}

// regenerate_hyprlock_native rebuilds colors-hyprlock.conf (hyprlang
// colour variables only) from the live Signal scheme. The wallpaper
// argument is accepted for CLI compatibility; it never affects colours.
pub fn regenerate_hyprlock_native(wallpaper_arg string, dry_run bool) CommandResult {
	out := signal_output_paths().hyprlock_conf
	if dry_run {
		return ok_result('appearance hyprlock', 'would run: write ${out} from ${signal_scheme_file()}',
			{
				'command_line': 'write ${out}'
				'dry_run':      'true'
			})
	}
	theme := read_signal_scheme() or {
		return fail_result('appearance hyprlock', '${err.msg()}.\nRun: horneroctl appearance sync --yes')
	}
	write_file_atomic(out, render_signal_hyprlock_conf(theme)) or {
		return fail_result('appearance hyprlock', err.msg())
	}
	return ok_result('appearance hyprlock', 'wrote lock colour variables to ${out}', {
		'output': out
	})
}

// regenerate_hyprland_native rebuilds colors-hyprland.lua from the live
// Signal scheme. HorneroOS/config's smart-colors.lua loads it on every
// Hyprland config evaluation; the write is atomic so a reload never sees
// a half-written chunk.
pub fn regenerate_hyprland_native(dry_run bool) CommandResult {
	out := signal_output_paths().hyprland_lua
	if dry_run {
		return ok_result('appearance hyprland', 'would run: write ${out} from ${signal_scheme_file()}',
			{
				'command_line': 'write ${out}'
				'dry_run':      'true'
			})
	}
	theme := read_signal_scheme() or {
		return fail_result('appearance hyprland', '${err.msg()}.\nRun: horneroctl appearance sync --yes')
	}
	write_file_atomic(out, render_signal_hyprland_lua(theme)) or {
		return fail_result('appearance hyprland', err.msg())
	}
	return ok_result('appearance hyprland', 'wrote Hyprland border colours to ${out}', {
		'output': out
	})
}

// read_appearance_status_native gathers the live appearance state without
// any backend: selected theme, live scheme, wallpaper, GTK and icons.
pub fn read_appearance_status_native() AppearanceStatus {
	st := read_scheme_state()
	gtk_theme, _, _ := read_gtk3_ini()
	return AppearanceStatus{
		theme:            st.theme
		mode:             st.mode
		gtk_theme:        gtk_theme
		icon_theme:       current_icon_theme()
		gtk_color_scheme: st.gtk_color_scheme
		wallpaper:        read_wallpaper_pointer()
	}
}

// appearance_status_report implements `appearance status` natively.
pub fn appearance_status_report(json bool) CommandResult {
	st := read_appearance_status_native()
	data := {
		'theme':            st.theme
		'mode':             st.mode
		'gtk_theme':        st.gtk_theme
		'icon_theme':       st.icon_theme
		'wallpaper':        st.wallpaper
		'gtk_color_scheme': st.gtk_color_scheme
	}
	if json {
		mut doc := map[string]json2.Any{}
		for k, v in data {
			doc[k] = json2.Any(v)
		}
		return ok_result('appearance status', json2.encode(doc, escape_unicode: true), data)
	}
	lines := ['theme          : ${st.theme}', 'mode           : ${st.mode}',
		'wallpaper      : ${st.wallpaper}', 'gtkTheme       : ${st.gtk_theme}',
		'iconTheme      : ${st.icon_theme}', 'gtkColorScheme : ${st.gtk_color_scheme}']
	return ok_result('appearance status', lines.join('\n'), data)
}

// appearance_set_gtk_native sets the GTK theme: shell IPC first, native
// apply fallback (live policy preserved).
pub fn appearance_set_gtk_native(theme string, dry_run bool) CommandResult {
	if theme.len == 0 {
		return fail_result('appearance set-gtk', 'Usage: horneroctl appearance set-gtk <theme>.\nExample: horneroctl appearance set-gtk Orchis-Dark --dry-run')
	}
	if !dry_run && shell_running() {
		ipc := ipc_appearance_call(['setGtk', theme], false)
		if ipc.ok {
			wait_appearance_ipc(false) or { return fail_result('appearance set-gtk', err.msg()) }
			return ok_result('appearance set-gtk', 'GTK theme set via shell: ${theme}',
				{
					'theme': theme
				})
		}
	}
	mut icon := current_icon_theme()
	if icon.len == 0 {
		icon = 'Papirus-Dark'
	}
	return apply_gtk_theme_native(theme, icon, '', dry_run)
}

// appearance_set_icons_native sets the icon theme: shell IPC first,
// native set-icons fallback.
pub fn appearance_set_icons_native(theme string, dry_run bool) CommandResult {
	if theme.len == 0 {
		return fail_result('appearance set-icons', 'Usage: horneroctl appearance set-icons <theme>.\nExample: horneroctl appearance set-icons Papirus-Dark --dry-run')
	}
	if !dry_run && shell_running() {
		ipc := ipc_appearance_call(['setIcons', theme], false)
		if ipc.ok {
			wait_appearance_ipc(false) or { return fail_result('appearance set-icons', err.msg()) }
			return ok_result('appearance set-icons', 'Icon theme set via shell: ${theme}',
				{
					'theme': theme
				})
		}
	}
	current := current_gtk_theme()
	if current.len == 0 || current == 'Unknown' {
		return fail_result('appearance set-icons', 'cannot read current GTK theme; set one first.')
	}
	return apply_gtk_theme_native(current, theme, '', dry_run)
}

// appearance_set_gtk_policy_native sets the GTK color-scheme policy:
// shell IPC first, native fallback.
pub fn appearance_set_gtk_policy_native(policy string, dry_run bool) CommandResult {
	if policy.len == 0 {
		return fail_result('appearance set-gtk-color-scheme', 'Usage: horneroctl appearance set-gtk-color-scheme <follow|default|prefer-light|prefer-dark>.\nExample: horneroctl appearance set-gtk-color-scheme follow --dry-run')
	}
	if !dry_run && shell_running() {
		ipc := ipc_appearance_call(['setGtkColorScheme', policy], false)
		if ipc.ok {
			wait_appearance_ipc(false) or {
				return fail_result('appearance set-gtk-color-scheme', err.msg())
			}
			return ok_result('appearance set-gtk-color-scheme', 'GTK color-scheme set via shell: ${policy}',
				{
					'policy': policy
				})
		}
	}
	return apply_gtk_color_scheme_native(policy, dry_run)
}

// set_wallpaper_only atomically points the shell at a new wallpaper.
// Colours never change.
pub fn set_wallpaper_only(command string, path string, dry_run bool) CommandResult {
	pointer := resolve_wallpaper_pointer_file()
	if dry_run {
		return ok_result(command, 'would atomically write ${path} to ${pointer}',
			{
				'command_line': 'write ${pointer}'
				'dry_run':      'true'
				'path':         path
			})
	}
	if !os.is_file(path) {
		return fail_result(command, 'wallpaper not found: ${path}')
	}
	write_wallpaper_pointer(pointer, path) or {
		return fail_result(command, 'cannot write wallpaper pointer: ${err.msg()}')
	}
	return ok_result(command, 'wallpaper set: ${path}', {
		'path':    path
		'pointer': pointer
	})
}

// appearance_set_wallpaper_native validates a wallpaper path and sets it
// without touching colours.
pub fn appearance_set_wallpaper_native(path string, dry_run bool) CommandResult {
	if path.len == 0 {
		return fail_result('appearance set-wallpaper', 'Usage: horneroctl appearance set-wallpaper <path>.\nExample: horneroctl appearance set-wallpaper ~/wall.jpg --dry-run')
	}
	real := os.real_path(path)
	if !os.is_file(real) && !dry_run {
		return fail_result('appearance set-wallpaper', 'wallpaper not found: ${path}')
	}
	return set_wallpaper_only('appearance set-wallpaper', if dry_run { path } else { real },
		dry_run)
}

// appearance_sync_native is the repair verb: run the one-shot migration of
// retired selections, then rewrite the live scheme and derived files from
// the selected theme (factory default when none). Wallpaper and GTK stay.
pub fn appearance_sync_native(dry_run bool) CommandResult {
	migration := plan_legacy_migration()
	sel := resolve_signal_selection()
	theme := load_signal_theme(sel.id) or {
		return fail_result('appearance sync', 'selected theme ${sel.id} (${sel.source}) is not usable: ${err.msg()}\nRun: horneroctl appearance theme apply ${signal_default_theme_id} --yes')
	}
	if dry_run {
		mut lines := []string{}
		for c in migration.changes {
			lines << 'would migrate ${c}'
		}
		lines << signal_output_preview()
		return ok_result('appearance sync', lines.join('\n'), {
			'dry_run': 'true'
			'theme':   theme.id
		})
	}
	migrate_legacy_appearance() or { return fail_result('appearance sync', err.msg()) }
	outputs := write_signal_outputs(theme) or {
		return fail_result('appearance sync', err.msg())
	}
	persist_state_theme(theme.id) or { return fail_result('appearance sync', err.msg()) }
	mut msg := 'appearance synced from ${theme.id} (${outputs.scheme})'
	if migration.changes.len > 0 {
		msg += '\nmigrated: ' + migration.changes.join('; ')
	}
	return ok_result('appearance sync', msg, {
		'theme':  theme.id
		'scheme': outputs.scheme
	})
}

// ibm_plex_families are the Signal font files the shell needs
// (package ttf-ibm-plex), matched by file-name prefix.
const ibm_plex_families = {
	'IBM Plex Sans':           'IBMPlexSans-'
	'IBM Plex Mono':           'IBMPlexMono-'
	'IBM Plex Sans Condensed': 'IBMPlexSansCondensed-'
}

// font_search_dirs lists font roots: the user font dirs, then
// `<XDG_DATA_DIRS>/fonts`. HORNERO_FONT_DIRS (colon-separated) overrides.
pub fn font_search_dirs() []string {
	override := os.getenv('HORNERO_FONT_DIRS')
	if override.len > 0 {
		return override.split(':').filter(it.len > 0)
	}
	mut dirs := [os.join_path(xdg_or_home('XDG_DATA_HOME', '.local/share'), 'fonts'),
		os.join_path(os.home_dir(), '.fonts')]
	for d in system_data_dirs() {
		dirs << os.join_path(d, 'fonts')
	}
	return dirs
}

// missing_ibm_plex_families scans font dirs (recursively) and returns the
// Signal families with no installed file.
pub fn missing_ibm_plex_families(dirs []string) []string {
	mut found := map[string]bool{}
	for dir in dirs {
		if !os.is_dir(dir) {
			continue
		}
		mut files := os.walk_ext(dir, '.ttf')
		files << os.walk_ext(dir, '.otf')
		for path in files {
			name := os.file_name(path)
			for family, prefix in ibm_plex_families {
				// Prefixes end in `-`, so IBMPlexSans- never matches
				// IBMPlexSansCondensed- files.
				if name.starts_with(prefix) {
					found[family] = true
				}
			}
		}
	}
	mut missing := []string{}
	for family, _ in ibm_plex_families {
		if family !in found {
			missing << family
		}
	}
	return missing
}

// appearance_doctor_checks gathers the read-only appearance probes shared
// by `appearance doctor` and the top-level `doctor`.
pub fn appearance_doctor_checks() []DoctorCheck {
	mut checks := []DoctorCheck{}
	scheme_path := signal_scheme_file()
	if live := read_signal_scheme() {
		checks << DoctorCheck{
			name:   'signal-scheme'
			ok:     true
			detail: '${live.id} (${live.mode}) at ${scheme_path}'
		}
	} else {
		checks << DoctorCheck{
			name:   'signal-scheme'
			ok:     false
			detail: '${err.msg()}; run: horneroctl appearance sync --yes'
		}
	}
	helper := chromatic_helper_path()
	checks << DoctorCheck{
		name:   'chromatic-helper'
		ok:     helper.len > 0 || !is_chromatic_active()
		detail: if helper.len > 0 {
			helper
		} else {
			'hornero-chromatic not found (optional; run: horneroctl appearance chromatic doctor)'
		}
	}
	missing := missing_ibm_plex_families(font_search_dirs())
	checks << DoctorCheck{
		name:   'signal-fonts'
		ok:     missing.len == 0
		detail: if missing.len == 0 {
			'IBM Plex Sans, Mono and Sans Condensed installed'
		} else {
			'missing ${missing.join(', ')}; install ttf-ibm-plex'
		}
	}
	return checks
}

// appearance_doctor_native checks appearance consistency: live scheme
// validity, Signal fonts, retired selections, derived files, wallpaper
// pointer and GTK policy. It never mutates user state.
pub fn appearance_doctor_native() CommandResult {
	mut fails := []string{}
	mut warns := []string{}
	mut lines := []string{}
	for c in appearance_doctor_checks() {
		lines << '${c.name}: ${c.detail}'
		if !c.ok {
			fails << c.detail
		}
	}
	sel := resolve_signal_selection()
	lines << 'theme          : ${sel.id} (${sel.source})'
	migration := plan_legacy_migration()
	for c in migration.changes {
		warns << 'retired appearance state: ${c}; run: horneroctl appearance sync --yes'
	}
	outputs := signal_output_paths()
	for path in [outputs.hyprland_lua, outputs.hyprlock_conf] {
		size := if os.is_file(path) { os.file_size(path) } else { u64(0) }
		lines << '${os.file_name(path)} : ${size} bytes'
		if size == 0 {
			fails << '${path} missing or empty'
		}
	}
	pointer_val := read_wallpaper_pointer()
	lines << 'wallpaper.ptr  : ${if pointer_val.len > 0 { pointer_val } else { '(missing)' }}'
	if pointer_val.len > 0 && !os.is_file(pointer_val) {
		warns << 'wallpaper file does not exist: ${pointer_val}'
	}
	st := read_scheme_state()
	gtk_theme, _, gtk_prefer := read_gtk3_ini()
	mut gtk_scheme := ''
	gs := resolve_gsettings_bin()
	if gs.len > 0 {
		rep := strict_exec(gs, ['get', 'org.gnome.desktop.interface', 'color-scheme'],
			false)
		if rep.ok {
			gtk_scheme = rep.output.trim("'")
		}
	}
	lines << 'gtk.theme.ini  : ${if gtk_theme.len > 0 { gtk_theme } else { '(missing)' }}'
	lines << 'gtk.preferDark : ${if gtk_prefer.len > 0 { gtk_prefer } else { '(missing)' }}'
	lines << 'gtk.colorPolicy: ${st.gtk_color_scheme}'
	lines << 'gtk.colorScheme: ${if gtk_scheme.len > 0 { gtk_scheme } else { '(missing)' }}'
	if st.gtk_color_scheme == 'follow' && st.mode.len > 0 {
		if st.mode == 'dark' && gtk_prefer == 'false' {
			warns << 'GTK prefer-dark=false while follow-policy mode is dark'
		} else if st.mode == 'light' && gtk_prefer == 'true' {
			warns << 'GTK prefer-dark=true while follow-policy mode is light'
		}
		if st.mode == 'dark' && gtk_scheme.len > 0 && gtk_scheme != 'prefer-dark' {
			warns << 'gsettings color-scheme=${gtk_scheme} while follow-policy mode is dark'
		} else if st.mode == 'light' && gtk_scheme.len > 0 && gtk_scheme != 'prefer-light' {
			warns << 'gsettings color-scheme=${gtk_scheme} while follow-policy mode is light'
		}
	}
	for w in warns {
		lines << 'WARN: ${w}'
	}
	for f in fails {
		lines << 'FAIL: ${f}'
	}
	if fails.len == 0 {
		lines << 'OK: appearance state is consistent'
		return ok_result('appearance doctor', lines.join('\n'), {})
	}
	lines << 'DONE: inconsistencies detected (exit 1)'
	return fail_result('appearance doctor', lines.join('\n'))
}

// smart_file_outputs lists every file `colors generate` writes.
pub fn smart_file_outputs(dir string) map[string]string {
	mut out := map[string]string{}
	for name in smart_file_names {
		out[name] = os.join_path(dir, name)
	}
	return out
}

const smart_file_names = ['colors-eww.scss', 'colors.sh', 'colors.env', 'colors-waybar.css',
	'colors-mako.conf', 'colors-hyprland.conf', 'colors-hyprland.lua', 'colors-wlogout.css',
	'colors-copyq.ini', 'colors-hyprlock.env', 'current.env', 'colors-kitty.conf', 'colors.css']

// colors_generate_native renders every smart-color file from the live
// Signal scheme.
pub fn colors_generate_native(dry_run bool) CommandResult {
	dir := smart_colors_dir()
	if dry_run {
		msg := 'would run: write ${smart_file_names.len} smart-color files to ${dir} from ${signal_scheme_file()}'
		return ok_result('appearance colors generate', msg, {
			'command_line': msg
			'dry_run':      'true'
		})
	}
	theme := read_signal_scheme() or {
		return fail_result('appearance colors generate', '${err.msg()}.\nRun: horneroctl appearance sync --yes')
	}
	sp := signal_smart_palette(theme, read_wallpaper_pointer())
	env_path := os.join_path(dir, 'colors.env')
	hypr_env := render_hyprlock_env(sp)
	contents := {
		'colors-eww.scss':      render_scss(sp)
		'colors.sh':            render_shell_colors(sp)
		'colors.env':           render_env_colors(sp, env_path)
		'colors-waybar.css':    render_waybar(sp)
		'colors-mako.conf':     render_mako(sp)
		'colors-hyprland.conf': render_signal_hyprland_conf(theme)
		'colors-hyprland.lua':  render_signal_hyprland_lua(theme)
		'colors-wlogout.css':   render_wlogout(sp)
		'colors-copyq.ini':     render_copyq(sp)
		'colors-hyprlock.env':  hypr_env
		'current.env':          hypr_env
		'colors-kitty.conf':    render_signal_kitty(theme)
		'colors.css':           render_css_vars(sp)
	}
	for name, body in contents {
		write_file_atomic(os.join_path(dir, name), body) or {
			return fail_result('appearance colors generate', 'cannot write ${name}: ${err.msg()}')
		}
	}
	link_copyq_theme(os.join_path(dir, 'colors-copyq.ini'))
	return ok_result('appearance colors generate', 'Smart color files generated in ${dir} from ${theme.id}',
		{
			'dir':   dir
			'theme': theme.id
		})
}

// link_copyq_theme symlinks the generated CopyQ theme into place.
fn link_copyq_theme(theme_file string) {
	themes := os.join_path(xdg_or_home('XDG_CONFIG_HOME', '.config'), 'copyq', 'themes')
	os.mkdir_all(themes) or { return }
	link := os.join_path(themes, 'hornero-smart-colors.ini')
	if os.is_link(link) && os.real_path(link) == os.real_path(theme_file) {
		return
	}
	os.rm(link) or {}
	os.symlink(theme_file, link) or {}
}

// colors_status_native previews the smart concepts of the live scheme.
pub fn colors_status_native() CommandResult {
	theme := read_signal_scheme() or {
		return fail_result('appearance colors status', '${err.msg()}.\nRun: horneroctl appearance sync --yes')
	}
	mut lines := ['Smart Colors Preview:', 'Theme: ${theme.id} (${theme.mode})', '']
	for concept in ['background', 'foreground', 'background-alt', 'foreground-alt'] {
		lines << '${concept}: ${signal_concept(theme, concept) or { '?' }}'
	}
	lines << ''
	lines << 'Semantic:'
	for concept in ['error', 'warning', 'success', 'info', 'accent'] {
		lines << '${concept}: ${signal_concept(theme, concept) or { '?' }}'
	}
	return ok_result('appearance colors status', lines.join('\n'), {
		'theme': theme.id
		'mode':  theme.mode
	})
}

// colors_concept_native resolves one concept against the live scheme.
pub fn colors_concept_native(concept string) CommandResult {
	if !valid_smart_concept(concept) {
		return fail_result('appearance colors concept', 'unknown concept: ${concept}')
	}
	theme := read_signal_scheme() or {
		return fail_result('appearance colors concept', '${err.msg()}.\nRun: horneroctl appearance sync --yes')
	}
	color := signal_concept(theme, concept) or {
		return fail_result('appearance colors concept', err.msg())
	}
	return ok_result('appearance colors concept', color, {
		'concept': concept
		'color':   color
	})
}

// colors_export_native prints shell export lines for every concept.
pub fn colors_export_native() CommandResult {
	theme := read_signal_scheme() or {
		return fail_result('appearance colors export', '${err.msg()}.\nRun: horneroctl appearance sync --yes')
	}
	mut lines := [
		'# Smart color variables generated by horneroctl appearance colors export',
		'# Source theme: ${theme.id}',
		'',
	]
	lines << '# Background and foreground variants'
	for concept in ['background', 'background-alt', 'foreground', 'foreground-alt'] {
		lines << "export COLOR_${concept.to_upper().replace('-', '_')}='${signal_concept(theme, concept) or { '' }}'"
	}
	lines << ''
	lines << '# Semantic colors'
	for concept in ['error', 'warning', 'success', 'info', 'accent'] {
		lines << "export COLOR_${concept.to_upper()}='${signal_concept(theme, concept) or { '' }}'"
	}
	lines << ''
	lines << '# Basic colors'
	for concept in ['red', 'green', 'blue', 'yellow', 'cyan', 'magenta', 'orange', 'pink', 'brown',
		'white', 'black', 'gray'] {
		lines << "export COLOR_${concept.to_upper()}='${signal_concept(theme, concept) or { '' }}'"
	}
	return ok_result('appearance colors export', lines.join('\n'), {})
}
