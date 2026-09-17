module hornero_core

import os
import time
import x.json2

// Native appearance apply pipeline. Ports dots-appearance (theme
// list/show/apply, status, set-*, sync, doctor), dots-hyprlock-theme,
// dots-wal-reload, and the apply-appearance.sh / wallpaper-resolver.sh
// helpers. Quickshell IPC stays the live-shell fast path (external
// `quickshell`/`qs` backend, best-effort with shell fallback); every
// file decision is V.

// resolve_quickshell_bin locates the IPC-capable shell CLI for the
// appearance fast path: HORNERO_QUICKSHELL_BIN, else `quickshell`, else
// `qs` (both external backends).
pub fn resolve_quickshell_bin() string {
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

// wait_appearance_ipc polls isBusy/lastError after an IPC mutation,
// mirroring _wait_appearance_ipc (120 polls, then the last error).
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

// shell_colours_reload_best_effort pings the shell colours target after
// an M3 rewrite; absence/failure only adds a note (the dots-quickshell
// `ipc colours reload` handshake it replaces).
pub fn shell_colours_reload_best_effort() string {
	bin := resolve_quickshell_bin()
	if bin.len == 0 {
		return ''
	}
	rep := strict_exec(bin, ['ipc', 'call', 'colours', 'reload'], false)
	if rep.ok {
		return 'shell colours reloaded via ${bin}'
	}
	return 'note: shell colours reload ping failed (shell will pick up scheme.json on next read)'
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

// PaletteBackends is the test seam for the apply pipeline: every
// external step is injectable so verify/rollback stay hermetic (no wal,
// no M3, no compositor). Production uses default_palette_backends().
pub struct PaletteBackends {
	wal_exec    fn (prog string, args []string, dry_run bool) ExecReport
	m3_exec     fn (image string, output string, flavour string, mode string, accent string, dry_run bool) ExecReport
	gtk_sync    fn (dry_run bool) CommandResult
	gtk_apply   fn (theme string, icon string, policy string, dry_run bool) CommandResult
	hyprlock    fn (wallpaper string, dry_run bool) CommandResult
	hyprctl_run fn (dry_run bool)
}

fn default_wal_exec(prog string, args []string, dry_run bool) ExecReport {
	return strict_exec(prog, args, dry_run)
}

fn default_m3_exec(image string, output string, flavour string, mode string, accent string, dry_run bool) ExecReport {
	return run_m3_synthesis(image, output, flavour, mode, accent, dry_run) or {
		ExecReport{
			command_line: 'm3 ${image} -> ${output}'
			ok:           false
			output:       err.msg()
			exit_code:    1
		}
	}
}

fn default_gtk_sync(dry_run bool) CommandResult {
	return sync_gtk_color_scheme_native(dry_run)
}

fn default_gtk_apply(theme string, icon string, policy string, dry_run bool) CommandResult {
	return apply_gtk_theme_native(theme, icon, policy, dry_run)
}

fn default_hyprlock(wallpaper string, dry_run bool) CommandResult {
	return regenerate_hyprlock_native(wallpaper, dry_run)
}

fn default_hyprctl_run(dry_run bool) {
	if dry_run {
		return
	}
	hc := resolve_hyprctl_bin()
	if hc.len > 0 {
		strict_exec(hc, ['reload'], false)
	}
}

pub fn default_palette_backends() PaletteBackends {
	return PaletteBackends{
		wal_exec:    default_wal_exec
		m3_exec:     default_m3_exec
		gtk_sync:    default_gtk_sync
		gtk_apply:   default_gtk_apply
		hyprlock:    default_hyprlock
		hyprctl_run: default_hyprctl_run
	}
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
	return error('Theme not found: ${id}')
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
// (default name, else first sorted image) — the resolver port.
pub fn resolve_pack_wallpaper(id string, wallpaper_dir string, default_name string, override string) !string {
	if override.len > 0 {
		real := os.real_path(override)
		if os.is_file(real) {
			return real
		}
	}
	pics := os.getenv('DOTS_PICTURES_WALLPAPERS')
	pics_base := if pics.len > 0 {
		pics
	} else {
		os.join_path(os.home_dir(), 'Pictures', 'Wallpapers')
	}
	wall_dirs := resolve_wallpapers_dir()
	wall_fallback := resolve_wallpapers_dir_fallback()
	for base in [os.join_path(pics_base, wallpaper_dir), os.join_path(wall_dirs, wallpaper_dir),
		os.join_path(wall_fallback, wallpaper_dir)] {
		if default_name.len > 0 && os.is_file(os.join_path(base, default_name)) {
			return os.real_path(os.join_path(base, default_name))
		}
	}
	for base in [os.join_path(pics_base, wallpaper_dir), os.join_path(wall_dirs, wallpaper_dir),
		os.join_path(wall_fallback, wallpaper_dir)] {
		entries := os.ls(base) or { continue }
		mut cands := []string{}
		for e in entries {
			lc := e.to_lower()
			if lc.ends_with('.jpg') || lc.ends_with('.jpeg') || lc.ends_with('.png')
				|| lc.ends_with('.webp') || lc.ends_with('.gif') || lc.ends_with('.bmp') {
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

// run_palette_pipeline runs wal + pointer + wal-path-file + M3 + state
// sync + GTK policy sync + hyprlock + hyprctl reload for one wallpaper
// (the _dots_aa_run_palette port).
pub fn run_palette_pipeline(wallpaper string, flavour string, mode string, dry_run bool) CommandResult {
	return run_palette_pipeline_with(wallpaper, flavour, mode, dry_run, default_palette_backends())
}

// run_palette_pipeline_with is the injectable worker behind
// run_palette_pipeline.
pub fn run_palette_pipeline_with(wallpaper string, flavour string, mode string, dry_run bool, deps PaletteBackends) CommandResult {
	wal := backend_or_empty('HORNERO_WAL_BIN', 'wal')
	if wal.len == 0 && !dry_run {
		return fail_result('appearance palette', 'wal not found on PATH. Set HORNERO_WAL_BIN.')
	}
	wal_prog := if wal.len > 0 { wal } else { 'wal' }
	mut wal_args := ['-i', wallpaper, '-q']
	if mode == 'light' {
		wal_args << '-l'
	}
	pointer := resolve_wallpaper_pointer_file()
	wal_path_file := os.join_path(os.home_dir(), '.cache', 'wal', 'wal')
	out := os.join_path(smart_colors_dir(), 'scheme.json')
	accent := read_accent_override()
	if dry_run {
		m3 := run_m3_synthesis(wallpaper, out, flavour, mode, accent, true) or {
			return fail_result('appearance palette', err.msg())
		}
		lines := [
			'would run: ${strict_command_line(wal_prog, wal_args)}',
			'would run: write ${wallpaper} to ${pointer} and ${wal_path_file}',
			'would run: ${m3.command_line}',
			'would run: sync state.json from scheme.json',
			'would run: sync GTK color-scheme policy',
			'would run: regenerate colors-hyprlock.conf',
			'would run: hyprctl reload (when present)',
		]
		return ok_result('appearance palette', lines.join('\n'), {
			'command_line': lines.join('\n')
			'dry_run':      'true'
		})
	}
	if !os.is_file(wallpaper) {
		return fail_result('appearance palette', 'wallpaper not found: ${wallpaper}')
	}
	wal_home := os.join_path(os.home_dir(), '.cache', 'wal')
	os.mkdir_all(wal_home) or {}
	os.rm(os.join_path(wal_home, 'wal')) or {}
	wal_rep := deps.wal_exec(wal_prog, wal_args, false)
	if !wal_rep.ok {
		return fail_result('appearance palette', 'wal failed (exit ${wal_rep.exit_code}):\n${wal_rep.output}')
	}
	os.mkdir_all(os.dir(pointer)) or {
		return fail_result('appearance palette', 'cannot create pointer dir: ${err.msg()}')
	}
	os.write_file(pointer, wallpaper + '\n') or {
		return fail_result('appearance palette', 'cannot write pointer: ${err.msg()}')
	}
	os.rm(wal_path_file) or {}
	os.write_file(wal_path_file, wallpaper + '\n') or {}
	os.mkdir_all(os.dir(out)) or {
		return fail_result('appearance palette', 'cannot create scheme dir: ${err.msg()}')
	}
	m3 := deps.m3_exec(wallpaper, out, flavour, mode, accent, false)
	if !m3.ok {
		return fail_result('appearance palette', 'M3 backend failed (exit ${m3.exit_code}):\n${m3.output}')
	}
	sync_state_from_scheme() or {
		return fail_result('appearance palette', 'palette wrote ${out} but state sync failed: ${err.msg()}')
	}
	gtk := deps.gtk_sync(false)
	if !gtk.ok {
		return fail_result('appearance palette', 'palette applied but GTK sync failed: ${gtk.message}')
	}
	hl := deps.hyprlock('', false)
	deps.hyprctl_run(false)
	mut msg := 'palette applied from ${wallpaper} (flavour ${flavour}, mode ${mode})'
	if !hl.ok {
		msg += '\nWARN: hyprlock refresh failed: ${hl.message}'
	}
	return ok_result('appearance palette', msg, {
		'scheme': out
	})
}

// theme_apply_native applies one theme pack once (no sticky current
// theme): IPC fast path when the shell is up, else the shell pipeline
// (wal + M3 + GTK + kitty + recolor + qt), all natively.
pub fn theme_apply_native(id string, wallpaper_override string, dry_run bool) CommandResult {
	return theme_apply_native_with(id, wallpaper_override, dry_run, default_palette_backends())
}

// theme_apply_native_with is the injectable worker behind
// theme_apply_native.
pub fn theme_apply_native_with(id string, wallpaper_override string, dry_run bool, deps PaletteBackends) CommandResult {
	if id.len == 0 || id.contains('/') || id == '.' || id == '..' {
		return fail_result('appearance theme apply', 'invalid theme id.\nExample: horneroctl appearance theme apply vapor-dreams --dry-run')
	}
	pack := read_pack_map(id) or { return fail_result('appearance theme apply', err.msg()) }
	if !dry_run && shell_running() {
		ipc := ipc_appearance_call(['applyTheme', id, wallpaper_override], false)
		if ipc.ok && !ipc.output.contains('Target not found') {
			wait_appearance_ipc(false) or {
				return fail_result('appearance theme apply', err.msg())
			}
			return ok_result('appearance theme apply', '${id} applied via shell', {
				'id': id
			})
		}
	}
	scheme_type := normalize_scheme_type(pack_str(pack, 'schemeType'))
	dark_raw := pack_str(pack, 'darkMode')
	mode := if dark_raw == 'false' { 'light' } else { 'dark' }
	mut gtk_theme := pack_str(pack, 'gtkTheme')
	if gtk_theme.len == 0 {
		gtk_theme = 'Orchis-Light-Compact'
	}
	mut icon_theme := pack_str(pack, 'iconTheme')
	if icon_theme.len == 0 {
		icon_theme = 'Numix-Circle'
	}
	mut wallpaper_dir := pack_str(pack, 'wallpaperDir')
	if wallpaper_dir.len == 0 {
		wallpaper_dir = id
	}
	wallpaper := resolve_pack_wallpaper(id, wallpaper_dir, pack_str(pack, 'defaultWallpaper'),
		wallpaper_override) or {
		if dry_run {
			'<wallpaper>'
		} else {
			return fail_result('appearance theme apply', err.msg())
		}
	}
	policy := pack_gtk_policy(pack_str(pack, 'gtkColorScheme'), pack_str(pack, 'gtkPreferDark'),
		gtk_theme, mode)
	if dry_run {
		pal := run_palette_pipeline(wallpaper, scheme_type, mode, true)
		lines := [pal.message,
			'would run: apply gtk ${gtk_theme} icons ${icon_theme} policy ${policy}',
			'would run: sync kitty include, gtk recolor, qt6ct palette']
		return ok_result('appearance theme apply', lines.join('\n'), {
			'command_line': lines.join('\n')
			'dry_run':      'true'
			'id':           id
		})
	}
	pal := run_palette_pipeline_with(wallpaper, scheme_type, mode, false, deps)
	if !pal.ok {
		return fail_result('appearance theme apply', pal.message)
	}
	if gtk_theme != 'auto' && gtk_theme.len > 0 {
		gtk := deps.gtk_apply(gtk_theme, icon_theme, policy, false)
		if !gtk.ok {
			return fail_result('appearance theme apply', 'palette applied but GTK apply failed: ${gtk.message}')
		}
	} else {
		pack_gtk := theme_pack_gtk_apply(id, false)
		if !pack_gtk.ok {
			return fail_result('appearance theme apply', 'palette applied but pack GTK failed: ${pack_gtk.message}')
		}
	}
	sync_kitty_include(id)
	sync_gtk_recolor(id)
	sync_qt6ct_palette(id)
	snappy_pack_best_effort(id)
	notify_best_effort('HorneroConfig', '${pack_str(pack, 'name')} theme applied')
	name := pack_str(pack, 'name')
	return ok_result('appearance theme apply', '${if name.len > 0 { name } else { id }} theme applied',
		{
		'id': id
	})
}

// theme_pack_gtk_apply resolves GTK/icons from a pack (wallpaper
// detection when gtkTheme is auto) and applies them.
pub fn theme_pack_gtk_apply(id string, dry_run bool) CommandResult {
	pack := read_pack_map(id) or { return fail_result('appearance gtk pack', err.msg()) }
	gtk_theme := pack_str(pack, 'gtkTheme')
	mut icon_theme := pack_str(pack, 'iconTheme')
	if icon_theme.len == 0 {
		icon_theme = 'Numix-Circle'
	}
	mode := if pack_str(pack, 'darkMode') == 'false' { 'light' } else { 'dark' }
	policy := pack_gtk_policy(pack_str(pack, 'gtkColorScheme'), pack_str(pack, 'gtkPreferDark'),
		gtk_theme, mode)
	if gtk_theme.len == 0 || gtk_theme == 'auto' {
		wall := read_wallpaper_pointer()
		if wall.len > 0 && os.is_file(wall) {
			bg := read_wal_colors_bg()
			detected, _ := detect_gtk_theme(if bg.len > 0 { bg } else { '000000' }, list_names_in_dirs(gtk_theme_search_dirs(),
				false))
			return apply_gtk_theme_native(detected, icon_theme, policy, dry_run)
		}
		fallback := if policy == 'prefer-light' {
			'Orchis-Light-Compact'
		} else {
			'Orchis-Dark-Compact'
		}
		return apply_gtk_theme_native(fallback, icon_theme, policy, dry_run)
	}
	return apply_gtk_theme_native(gtk_theme, icon_theme, policy, dry_run)
}

// read_wal_colors_bg returns the first pywal color (background).
pub fn read_wal_colors_bg() string {
	path := os.getenv('HORNERO_WAL_COLORS_FILE')
	colors := if path.len > 0 {
		path
	} else {
		os.join_path(os.home_dir(), '.cache', 'wal', 'colors')
	}
	raw := os.read_file(colors) or { return '' }
	for line in raw.split_into_lines() {
		t := line.trim_space()
		if t.len > 0 {
			return t
		}
	}
	return ''
}

// sync_kitty_include swaps the kitty.conf include to the theme variant
// and pokes kitty with SIGUSR1 (best-effort, silent skip).
pub fn sync_kitty_include(theme_id string) {
	kitty_dir := os.join_path(gtk_config_home(), 'kitty')
	conf := os.join_path(kitty_dir, 'kitty.conf')
	variant := os.join_path(kitty_dir, theme_id + '.conf')
	if !os.is_file(conf) || !os.is_file(variant) {
		return
	}
	raw := os.read_file(conf) or { return }
	mut out := []string{}
	for line in raw.split_into_lines() {
		if line.starts_with('include ')
			&& (line.ends_with('hornero-dark.conf') || line.ends_with('hornero-light.conf')
			|| line.ends_with('pampa.conf')) {
			out << 'include ${theme_id}.conf'
		} else {
			out << line
		}
	}
	os.write_file(conf, out.join('\n') + '\n') or { return }
	pk := resolve_pkill_bin()
	if pk.len > 0 {
		strict_exec(pk, ['-SIGUSR1', '-x', 'kitty'], false)
	}
}

// sync_gtk_recolor copies the theme's libadwaita recolor.css into place
// (silent no-op when the variant ships none).
pub fn sync_gtk_recolor(theme_id string) {
	tree := match theme_id {
		'hornero-dark' { 'Hornero-Dark' }
		'hornero-light' { 'Hornero-Light' }
		'pampa' { 'Hornero-Pampa' }
		else { return }
	}
	mut data := os.getenv('XDG_DATA_HOME')
	if data.len == 0 {
		data = os.join_path(os.home_dir(), '.local', 'share')
	}
	src := os.join_path(data, 'themes', tree, 'gtk-4.0', 'recolor.css')
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
	bin := find_on_path('dots-snappy-switcher')
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

// regenerate_hyprlock_native rebuilds colors-hyprlock.conf from the live
// scheme.json colours (the dots-hyprlock-theme port).
pub fn regenerate_hyprlock_native(wallpaper_arg string, dry_run bool) CommandResult {
	scheme := color_scheme_file_for_read()
	if !os.is_file(scheme) && !dry_run {
		return fail_result('appearance hyprlock', 'scheme.json not found at ${scheme} — regenerate first.')
	}
	dir := smart_colors_dir()
	out := os.join_path(dir, 'colors-hyprlock.conf')
	if dry_run {
		return ok_result('appearance hyprlock', 'would run: write ${out} from ${scheme}',
			{
			'command_line': 'write ${out}'
			'dry_run':      'true'
		})
	}
	raw := os.read_file(scheme) or {
		return fail_result('appearance hyprlock', 'cannot read ${scheme}: ${err.msg()}')
	}
	parsed := json2.decode[json2.Any](raw) or {
		return fail_result('appearance hyprlock', 'scheme.json is not JSON: ${err.msg()}')
	}
	mut colours := map[string]string{}
	if parsed is map[string]json2.Any {
		cmap := parsed.clone()
		if 'colours' in cmap {
			for k, v in cmap['colours'].as_map() {
				colours[k] = v.str()
			}
		}
	}
	mode := scheme_json_field(scheme, 'mode')
	mut wallpaper := wallpaper_arg
	if wallpaper.len == 0 {
		wallpaper = read_wallpaper_pointer()
	}
	if wallpaper.len > 0 && !os.is_file(wallpaper) {
		wallpaper = ''
	}
	conf := render_hyprlock_conf(HyprlockScheme{
		primary:            colours['primary']
		surface:            colours['surface']
		on_surface:         colours['onSurface']
		background:         colours['background']
		on_surface_variant: colours['onSurfaceVariant']
		outline:            colours['outline']
		secondary:          colours['secondary']
		error:              colours['error']
		light:              mode == 'light'
		wallpaper:          wallpaper
		scheme_source:      scheme
	})
	os.mkdir_all(dir) or {
		return fail_result('appearance hyprlock', 'cannot create ${dir}: ${err.msg()}')
	}
	os.write_file(out, conf) or {
		return fail_result('appearance hyprlock', 'cannot write ${out}: ${err.msg()}')
	}
	return ok_result('appearance hyprlock', 'wrote color overrides to ${out}', {
		'output': out
	})
}

// read_appearance_status_native gathers the live appearance state without
// any backend: wallpaper pointer, scheme state, gtk3 ini, gsettings icon.
pub fn read_appearance_status_native() AppearanceStatus {
	wallpaper := read_wallpaper_pointer()
	st := read_scheme_state()
	gtk_theme, _, _ := read_gtk3_ini()
	icon := current_icon_theme()
	return AppearanceStatus{
		mode:             st.mode
		flavour:          st.flavour
		gtk_theme:        gtk_theme
		icon_theme:       icon
		gtk_color_scheme: st.gtk_color_scheme
		wallpaper:        wallpaper
	}
}

// appearance_status_report implements `appearance status` natively.
pub fn appearance_status_report(json bool) CommandResult {
	st := read_appearance_status_native()
	if json {
		payload := '{"wallpaper":"${st.wallpaper}","mode":"${st.mode}","flavour":"${st.flavour}","gtkTheme":"${st.gtk_theme}","iconTheme":"${st.icon_theme}","gtkColorScheme":"${st.gtk_color_scheme}"}'
		return ok_result('appearance status', payload, {
			'mode':             st.mode
			'flavour':          st.flavour
			'gtk_theme':        st.gtk_theme
			'wallpaper':        st.wallpaper
			'gtk_color_scheme': st.gtk_color_scheme
		})
	}
	lines := ['wallpaper      : ${st.wallpaper}', 'mode           : ${st.mode}',
		'flavour        : ${st.flavour}', 'gtkTheme       : ${st.gtk_theme}',
		'iconTheme      : ${st.icon_theme}', 'gtkColorScheme : ${st.gtk_color_scheme}']
	return ok_result('appearance status', lines.join('\n'), {
		'mode':             st.mode
		'flavour':          st.flavour
		'gtk_theme':        st.gtk_theme
		'wallpaper':        st.wallpaper
		'gtk_color_scheme': st.gtk_color_scheme
	})
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
		icon = 'Numix-Circle'
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

// appearance_set_wallpaper_native validates a wallpaper path and runs
// the wallpaper-only pipeline (live state prefs).
pub fn appearance_set_wallpaper_native(path string, dry_run bool) CommandResult {
	if path.len == 0 {
		return fail_result('appearance set-wallpaper', 'Usage: horneroctl appearance set-wallpaper <path>.\nExample: horneroctl appearance set-wallpaper ~/wall.jpg --dry-run')
	}
	real := os.real_path(path)
	if !os.is_file(real) && !dry_run {
		return fail_result('appearance set-wallpaper', 'wallpaper not found: ${path}')
	}
	st := ensure_scheme_state()
	flavour := normalize_scheme_type(if st.flavour.len > 0 { st.flavour } else { 'tonal-spot' })
	mode := if st.mode == 'light' || st.mode == 'dark' { st.mode } else { 'dark' }
	return run_palette_pipeline(if dry_run { path } else { real }, flavour, mode, dry_run)
}

// appearance_sync_native reloads the shell (when up) and adopts the live
// scheme meta into state.json.
pub fn appearance_sync_native(dry_run bool) CommandResult {
	if !dry_run && shell_running() {
		ipc := ipc_appearance_call(['reload'], false)
		if ipc.ok {
			wait_appearance_ipc(false) or { return fail_result('appearance sync', err.msg()) }
		}
	}
	if dry_run {
		return ok_result('appearance sync', 'would run: sync state.json from scheme.json',
			{
			'dry_run': 'true'
		})
	}
	sync_state_from_scheme() or { return fail_result('appearance sync', err.msg()) }
	return ok_result('appearance sync', 'appearance state synced from scheme.json', {})
}

// appearance_doctor_native checks appearance consistency (the doctor
// port): scheme/state agreement, wallpaper pointer chain, hyprlock
// output, GTK policy, M3 interpreter, and legacy orphans. One-time
// legacy rice pointers are purged like the bash doctor did.
pub fn appearance_doctor_native() CommandResult {
	mut fails := []string{}
	mut warns := []string{}
	mut lines := []string{}
	os.rm(os.join_path(os.home_dir(), '.local', 'share', 'dots', 'rices', '.current_rice')) or {}
	os.rm(os.join_path(os.home_dir(), '.cache', 'dots', 'current_rice')) or {}
	os.rm(os.join_path(os.home_dir(), '.local', 'state', 'dots', 'rice', 'current')) or {}
	os.rmdir(os.join_path(os.home_dir(), '.local', 'state', 'dots', 'rice')) or {}
	scheme := color_scheme_file_for_read()
	state := scheme_state_file_for_read()
	scheme_flavour := scheme_json_field(scheme, 'flavour')
	state_flavour := scheme_json_field(state, 'flavour')
	scheme_mode := scheme_json_field(scheme, 'mode')
	state_mode := scheme_json_field(state, 'mode')
	lines << 'scheme.flavour : ${if scheme_flavour.len > 0 { scheme_flavour } else { '(missing)' }}'
	lines << 'state.flavour  : ${if state_flavour.len > 0 { state_flavour } else { '(missing)' }}'
	lines << 'scheme.mode    : ${if scheme_mode.len > 0 { scheme_mode } else { '(missing)' }}'
	lines << 'state.mode     : ${if state_mode.len > 0 { state_mode } else { '(missing)' }}'
	pointer_val := read_wallpaper_pointer()
	resolved := read_wallpaper_pointer()
	lines << 'wallpaper.ptr  : ${if pointer_val.len > 0 { pointer_val } else { '(missing)' }}'
	lines << 'wallpaper.res  : ${if resolved.len > 0 { resolved } else { '(missing)' }}'
	wal_file := os.join_path(os.home_dir(), '.cache', 'wal', 'wal')
	mut wal_target := ''
	if os.is_link(wal_file) {
		wal_target = os.real_path(wal_file)
	} else if os.is_file(wal_file) {
		first := (os.read_file(wal_file) or { '' }).split_into_lines()
		if first.len > 0 {
			wal_target = os.real_path(first[0])
		}
	}
	lines << 'wal.target     : ${if wal_target.len > 0 { wal_target } else { '(missing)' }}'
	hl_conf := os.join_path(smart_colors_dir(), 'colors-hyprlock.conf')
	mut hl_bytes := 0
	if os.is_file(hl_conf) {
		hl_bytes = (os.read_file(hl_conf) or { '' }).len
	} else {
		fb := os.join_path(smart_colors_dir_fallback(), 'colors-hyprlock.conf')
		if os.is_file(fb) {
			hl_bytes = (os.read_file(fb) or { '' }).len
		}
	}
	lines << 'hyprlock.conf  : ${hl_bytes} bytes'
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
	policy := read_scheme_state().gtk_color_scheme
	lines << 'gtk.theme.ini  : ${if gtk_theme.len > 0 { gtk_theme } else { '(missing)' }}'
	lines << 'gtk.preferDark : ${if gtk_prefer.len > 0 { gtk_prefer } else { '(missing)' }}'
	lines << 'gtk.colorPolicy: ${policy}'
	lines << 'gtk.colorScheme: ${if gtk_scheme.len > 0 { gtk_scheme } else { '(missing)' }}'
	if os.is_file(os.join_path(os.home_dir(), '.local', 'share', 'dots', 'rices', '.current_rice'))
		|| os.is_file(os.join_path(os.home_dir(), '.cache', 'dots', 'current_rice')) {
		fails << 'legacy rice pointer still present'
	}
	if scheme_flavour.len > 0 && state_flavour.len > 0 && scheme_flavour != state_flavour {
		fails << 'scheme flavour != state flavour (${scheme_flavour} vs ${state_flavour})'
	}
	if scheme_mode.len > 0 && state_mode.len > 0 && scheme_mode != state_mode {
		fails << 'scheme mode != state mode (${scheme_mode} vs ${state_mode})'
	}
	if pointer_val.len == 0 {
		fails << 'wallpaper pointer missing'
	} else if !os.is_file(pointer_val) && os.real_path(pointer_val).len == 0 {
		fails << 'wallpaper pointer does not exist: ${pointer_val}'
	}
	if pointer_val.len > 0 && os.is_file(pointer_val) {
		if wal_target.len == 0 {
			fails << '~/.cache/wal/wal missing or broken'
		} else if os.real_path(pointer_val) != wal_target {
			fails << 'wal target != wallpaper pointer (${wal_target} vs ${os.real_path(pointer_val)})'
		}
	}
	if hl_bytes == 0 {
		fails << 'colors-hyprlock.conf missing or empty'
	}
	m3py := resolve_m3_python(false) or { '' }
	lines << 'm3.python      : ${if m3py.len > 0 { m3py } else { '(missing)' }}'
	if m3py.len == 0 {
		fails << 'no Python with materialyoucolor (install python-materialyoucolor; pyenv shims alone are not enough)'
	}
	if os.is_file(os.join_path(os.home_dir(), '.local', 'state', 'dots', 'wallpaper',
		'path.txt'))
	{
		fails << 'orphan wallpaper/path.txt present (use wallpaper/path)'
	}
	if os.is_file(os.join_path(os.home_dir(), '.cache', 'dots', 'smart-colors', 'wallpaper')) {
		fails << 'orphan smart-colors/wallpaper cache present'
	}
	if policy == 'follow' {
		if state_mode == 'dark' && gtk_prefer == 'false' {
			warns << 'GTK prefer-dark=false while follow-policy mode is dark'
		} else if state_mode == 'light' && gtk_prefer == 'true' {
			warns << 'GTK prefer-dark=true while follow-policy mode is light'
		}
		if state_mode == 'dark' && gtk_scheme.len > 0 && gtk_scheme != 'prefer-dark' {
			warns << 'gsettings color-scheme=${gtk_scheme} while follow-policy mode is dark'
		} else if state_mode == 'light' && gtk_scheme.len > 0 && gtk_scheme != 'prefer-light' {
			warns << 'gsettings color-scheme=${gtk_scheme} while follow-policy mode is light'
		}
	}
	if wal_target.len > 0 && os.is_file(wal_target) {
		fb := find_on_path('file')
		if fb.len > 0 {
			mime := strict_exec(fb, ['-b', '--mime-type', wal_target], false)
			if mime.ok && !mime.output.starts_with('image/') {
				warns << 'wal target is not an image: ${wal_target}'
			}
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

// wallpaper_reload_native re-applies the wallpaper color pipeline: shell
// IPC reload when the shell is up (Hyprland sessions briefly wait for
// IPC first), else the direct fallback (wal -R + M3 + GTK + hyprlock).
pub fn wallpaper_reload_native(dry_run bool) CommandResult {
	if !dry_run && os.getenv('HYPRLAND_INSTANCE_SIGNATURE').len > 0 {
		for _ in 0 .. 30 {
			if shell_running() && ipc_appearance_call(['isBusy'], false).ok {
				break
			}
			time.sleep(500 * time.millisecond)
		}
	}
	if !dry_run && shell_running() {
		ipc := ipc_appearance_call(['reload'], false)
		if ipc.ok {
			wait_appearance_ipc(false) or { return fail_result('wallpaper reload', err.msg()) }
			last := ipc_appearance_call(['lastError'], false)
			if last.ok && last.output.len > 0 {
				return fail_result('wallpaper reload', 'appearance reload failed: ${last.output}')
			}
			return ok_result('wallpaper reload', 'wallpaper pipeline reloaded via shell',
				{})
		}
	}
	wallpaper := read_wallpaper_pointer()
	if wallpaper.len == 0 {
		return fail_result('wallpaper reload', 'no wallpaper pointer; set one first.')
	}
	wal := backend_or_empty('HORNERO_WAL_BIN', 'wal')
	mut lines := []string{}
	if wal.len > 0 || dry_run {
		rep := strict_exec(if wal.len > 0 { wal } else { 'wal' }, ['-R', '-q'], dry_run)
		lines << rep.command_line
	}
	wal_path_file := os.join_path(os.home_dir(), '.cache', 'wal', 'wal')
	lines << 'write ${wallpaper} to ${wal_path_file} (text path file)'
	st := read_scheme_state()
	flavour := normalize_scheme_type(if st.flavour.len > 0 { st.flavour } else { 'tonal-spot' })
	mode := if st.mode == 'light' || st.mode == 'dark' { st.mode } else { 'dark' }
	out := os.join_path(smart_colors_dir(), 'scheme.json')
	accent := read_accent_override()
	m3 := run_m3_synthesis(wallpaper, out, flavour, mode, accent, dry_run) or {
		return fail_result('wallpaper reload', err.msg())
	}
	lines << m3.command_line
	lines << 'sync state.json from scheme.json'
	lines << 'sync GTK color-scheme policy'
	lines << 'regenerate colors-hyprlock.conf'
	if dry_run {
		return ok_result('wallpaper reload', 'would run:\n' + lines.join('\n'), {
			'command_line': lines.join('\n')
			'dry_run':      'true'
		})
	}
	os.mkdir_all(os.join_path(os.home_dir(), '.cache', 'wal')) or {}
	os.rm(wal_path_file) or {}
	os.write_file(wal_path_file, wallpaper + '\n') or {}
	m3real := run_m3_synthesis(wallpaper, out, flavour, mode, accent, false) or {
		return fail_result('wallpaper reload', err.msg())
	}
	if !m3real.ok {
		return fail_result('wallpaper reload', 'M3 backend failed (exit ${m3real.exit_code}):\n${m3real.output}')
	}
	sync_state_from_scheme() or {}
	sync_gtk_color_scheme_native(false)
	regenerate_hyprlock_native('', false)
	return ok_result('wallpaper reload', 'wallpaper pipeline reloaded from ${wallpaper}',
		{
		'wallpaper': wallpaper
	})
}

// smart_file_outputs lists every file `colors generate` writes.
pub fn smart_file_outputs(dir string) map[string]string {
	return {
		'colors-eww.scss':      os.join_path(dir, 'colors-eww.scss')
		'colors.sh':            os.join_path(dir, 'colors.sh')
		'colors.env':           os.join_path(dir, 'colors.env')
		'colors-waybar.css':    os.join_path(dir, 'colors-waybar.css')
		'colors-mako.conf':     os.join_path(dir, 'colors-mako.conf')
		'colors-hyprland.conf': os.join_path(dir, 'colors-hyprland.conf')
		'colors-wlogout.css':   os.join_path(dir, 'colors-wlogout.css')
		'colors-copyq.ini':     os.join_path(dir, 'colors-copyq.ini')
		'colors-hyprlock.env':  os.join_path(dir, 'colors-hyprlock.env')
		'current.env':          os.join_path(dir, 'current.env')
		'colors-kitty.conf':    os.join_path(dir, 'colors-kitty.conf')
		'colors.css':           os.join_path(dir, 'colors.css')
	}
}

// colors_generate_native reads the xrdb palette and writes every
// smart-color file, plus M3 scheme.json with --m3.
pub fn colors_generate_native(with_m3 bool, dry_run bool) CommandResult {
	xrdb := backend_or_empty('HORNERO_XRDB_BIN', 'xrdb')
	if xrdb.len == 0 && !dry_run {
		return fail_result('appearance colors generate', 'xrdb not found on PATH. Set HORNERO_XRDB_BIN.')
	}
	dir := smart_colors_dir()
	if dry_run {
		xr_line := strict_command_line(if xrdb.len > 0 { xrdb } else { 'xrdb' }, [
			'-query',
		])
		mut lines := ['would run: ${xr_line}', 'would run: write 12 smart-color files to ${dir}']
		if with_m3 {
			m3 := run_m3_synthesis('<wallpaper>', os.join_path(dir, 'scheme.json'), 'tonal-spot',
				'dark', read_accent_override(), true) or {
				return fail_result('appearance colors generate', err.msg())
			}
			lines << 'would run: ${m3.command_line}'
		}
		return ok_result('appearance colors generate', lines.join('\n'), {
			'command_line': lines.join('\n')
			'dry_run':      'true'
		})
	}
	query := strict_exec(xrdb, ['-query'], false)
	if !query.ok {
		return fail_result('appearance colors generate', 'xrdb -query failed (exit ${query.exit_code}):\n${query.output}')
	}
	pal := parse_xrdb_query(query.output)
	wallpaper := read_wallpaper_pointer()
	sp := derive_palette(pal, if wallpaper.len > 0 { wallpaper } else { '' })
	os.mkdir_all(dir) or {
		return fail_result('appearance colors generate', 'cannot create ${dir}: ${err.msg()}')
	}
	env_path := os.join_path(dir, 'colors.env')
	hypr_env := render_hyprlock_env(sp)
	contents := {
		'colors-eww.scss':      render_scss(sp)
		'colors.sh':            render_shell_colors(sp)
		'colors.env':           render_env_colors(sp, env_path)
		'colors-waybar.css':    render_waybar(sp)
		'colors-mako.conf':     render_mako(sp)
		'colors-hyprland.conf': render_hyprland(sp)
		'colors-wlogout.css':   render_wlogout(sp)
		'colors-copyq.ini':     render_copyq(sp)
		'colors-hyprlock.env':  hypr_env
		'current.env':          hypr_env
		'colors-kitty.conf':    render_kitty(sp)
		'colors.css':           render_css_vars(sp)
	}
	for name, body in contents {
		os.write_file(os.join_path(dir, name), body) or {
			return fail_result('appearance colors generate', 'cannot write ${name}: ${err.msg()}')
		}
	}
	link_copyq_theme(os.join_path(dir, 'colors-copyq.ini'))
	mut msg := 'Smart color files generated in ${dir}'
	if with_m3 {
		if wallpaper.len == 0 || !os.is_file(wallpaper) {
			return fail_result('appearance colors generate', 'smart files written but M3 needs a wallpaper (none found).')
		}
		st := ensure_scheme_state()
		flavour := normalize_scheme_type(if st.flavour.len > 0 { st.flavour } else { 'tonal-spot' })
		mode := if st.mode == 'light' || st.mode == 'dark' { st.mode } else { 'dark' }
		m3 := run_m3_synthesis(wallpaper, os.join_path(dir, 'scheme.json'), flavour, mode,
			read_accent_override(), false) or {
			return fail_result('appearance colors generate', err.msg())
		}
		if !m3.ok {
			return fail_result('appearance colors generate', 'smart files written but M3 failed (exit ${m3.exit_code}):\n${m3.output}')
		}
		msg += '\nM3 scheme.json generated'
	}
	return ok_result('appearance colors generate', msg, {
		'dir': dir
	})
}

// link_copyq_theme symlinks the generated CopyQ theme into place.
fn link_copyq_theme(theme_file string) {
	mut cfg := os.getenv('XDG_CONFIG_HOME')
	if cfg.len == 0 {
		cfg = os.join_path(os.home_dir(), '.config')
	}
	themes := os.join_path(cfg, 'copyq', 'themes')
	os.mkdir_all(themes) or { return }
	link := os.join_path(themes, 'hornero-smart-colors.ini')
	if os.is_link(link) && os.real_path(link) == os.real_path(theme_file) {
		return
	}
	os.rm(link) or {}
	os.symlink(theme_file, link) or {}
}

// colors_status_native prints the smart-colors preview from the xrdb
// palette (read-only).
pub fn colors_status_native() CommandResult {
	xrdb := backend_or_empty('HORNERO_XRDB_BIN', 'xrdb')
	if xrdb.len == 0 {
		return fail_result('appearance colors status', 'xrdb not found on PATH. Set HORNERO_XRDB_BIN.')
	}
	query := strict_exec(xrdb, ['-query'], false)
	if !query.ok {
		return fail_result('appearance colors status', 'xrdb -query failed (exit ${query.exit_code}):\n${query.output}')
	}
	pal := parse_xrdb_query(query.output)
	bg := palette_get(pal, 'background', '#000000')
	theme := if is_light_hex(bg) { 'Light' } else { 'Dark' }
	mut lines := ['Smart Colors Preview:', 'Theme: ${theme}', '']
	for concept in ['background', 'foreground', 'background-alt', 'foreground-alt'] {
		lines << '${concept}: ${smart_color_for(concept, pal) or { '?' }}'
	}
	lines << ''
	lines << 'Semantic:'
	for concept in ['error', 'warning', 'success', 'info', 'accent'] {
		lines << '${concept}: ${smart_color_for(concept, pal) or { '?' }}'
	}
	return ok_result('appearance colors status', lines.join('\n'), {
		'theme': theme
	})
}

// colors_concept_native resolves one --concept value (hex out).
pub fn colors_concept_native(concept string) CommandResult {
	xrdb := backend_or_empty('HORNERO_XRDB_BIN', 'xrdb')
	if xrdb.len == 0 {
		return fail_result('appearance colors concept', 'xrdb not found on PATH. Set HORNERO_XRDB_BIN.')
	}
	if !valid_smart_concept(concept) {
		return fail_result('appearance colors concept', 'unknown concept: ${concept}')
	}
	query := strict_exec(xrdb, ['-query'], false)
	if !query.ok {
		return fail_result('appearance colors concept', 'xrdb -query failed.')
	}
	color := smart_color_for(concept, parse_xrdb_query(query.output)) or {
		return fail_result('appearance colors concept', err.msg())
	}
	return ok_result('appearance colors concept', color, {
		'concept': concept
		'color':   color
	})
}

// colors_export_native prints shell export lines for every concept.
pub fn colors_export_native() CommandResult {
	xrdb := backend_or_empty('HORNERO_XRDB_BIN', 'xrdb')
	if xrdb.len == 0 {
		return fail_result('appearance colors export', 'xrdb not found on PATH. Set HORNERO_XRDB_BIN.')
	}
	query := strict_exec(xrdb, ['-query'], false)
	if !query.ok {
		return fail_result('appearance colors export', 'xrdb -query failed.')
	}
	pal := parse_xrdb_query(query.output)
	mut lines := [
		'# Smart color variables generated by horneroctl appearance colors export',
		'',
	]
	lines << '# Background and foreground variants'
	for concept in ['background', 'background-alt', 'foreground', 'foreground-alt'] {
		color := smart_color_for(concept, pal) or { '' }
		lines << "export COLOR_${concept.to_upper().replace('-', '_')}='${color}'"
	}
	lines << ''
	lines << '# Semantic colors'
	for concept in ['error', 'warning', 'success', 'info', 'accent'] {
		color := smart_color_for(concept, pal) or { '' }
		lines << "export COLOR_${concept.to_upper()}='${color}'"
	}
	lines << ''
	lines << '# Basic colors'
	for concept in ['red', 'green', 'blue', 'yellow', 'cyan', 'magenta', 'orange', 'pink', 'brown',
		'white', 'black', 'gray'] {
		color := smart_color_for(concept, pal) or { '' }
		lines << "export COLOR_${concept.to_upper()}='${color}'"
	}
	return ok_result('appearance colors export', lines.join('\n'), {})
}

// colors_m3_passthrough_native runs the M3 backend with caller args.
pub fn colors_m3_passthrough_native(args []string, dry_run bool) CommandResult {
	if args.len == 0 {
		return fail_result('appearance colors m3', 'nothing to pass through.\nExample: horneroctl appearance colors m3 --dry-run -- --help')
	}
	script := resolve_m3_script()
	if !dry_run && !os.is_file(script) {
		return fail_result('appearance colors m3', 'M3 script not found: ${script} (set HORNERO_M3_SCRIPT).')
	}
	py := resolve_m3_python(dry_run) or { return fail_result('appearance colors m3', err.msg()) }
	mut full := [script]
	full << args
	rep := strict_exec(py, full, dry_run)
	if rep.was_dry_run {
		return ok_result('appearance colors m3', 'would run: ${rep.command_line}', {
			'command_line': rep.command_line
			'dry_run':      'true'
		})
	}
	if rep.ok {
		return ok_result('appearance colors m3', rep.output, {
			'command_line': rep.command_line
		})
	}
	return fail_result('appearance colors m3', 'M3 backend failed (exit ${rep.exit_code}):\n${rep.output}')
}
