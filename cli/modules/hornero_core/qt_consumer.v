module hornero_core

import os
import strconv
import time

// Qt consumer of the appearance pipeline (hornero#439).
//
// Qt5/Qt6 Widgets apps (Dolphin, CopyQ, ...) read their palette from the
// qt6ct/qt5ct platform-theme plugins. The plugin reads ONE config file, the
// first that exists: ~/.config/qt6ct/qt6ct.conf shadows the packaged
// /etc/xdg/qt6ct/qt6ct.conf entirely, so a pre-Signal user file left Qt apps
// light next to dark GTK. This consumer renders the live Signal/Chromatic
// scheme into an owned colour-scheme file and manages exactly two keys of the
// user's [Appearance] group.
//
// Ownership: the keys `custom_palette` and `color_scheme_path` of
// [Appearance], and the file <config>/<toolkit>/colors/hornero-signal.conf.
// The durable marker is the value of color_scheme_path (qt6ct rewrites its
// config through QSettings and drops comments, so a comment marker is only a
// courtesy). Everything else in the user's file is preserved byte-for-byte.
//
// Per-toolkit policy (state.json, written by `appearance set-qt`):
//   follow  default: manage the keys unless the user points at their own palette
//   force   always manage the keys, even over the user's own palette
//   off     never touch this toolkit's files

pub const qt_toolkits = ['qt6ct', 'qt5ct']
// qt_consumer_names are the opt-out units of `appearance set-qt`.
pub const qt_consumer_names = ['qt6ct', 'qt5ct', 'kde']
pub const qt_scheme_name = 'hornero-signal.conf'
const qt_marker = '; hornero-managed: custom_palette, color_scheme_path (horneroctl appearance set-qt <toolkit>=off to opt out)'

// Retired / packaged scheme names that identify a stale pre-Signal Hornero
// config, safe to migrate (with a backup).
const qt_stale_scheme_stems = ['hornero-dark', 'hornero-light', 'hornero-199x', 'pampa']

pub struct QtSyncReport {
pub:
	toolkit string
	status  string // synced | unchanged | off | not-installed | user-palette | no-scheme | error
	detail  string
	changed bool
	backup  string
}

// qt_policy reads the persisted per-toolkit policy (default follow).
pub fn qt_policy(toolkit string) string {
	v := scheme_json_field(scheme_state_file(), '${toolkit}Consumer')
	return if v in ['follow', 'force', 'off'] { v } else { 'follow' }
}

fn qt_config_dir(toolkit string) string {
	return os.join_path(gtk_config_home(), toolkit)
}

fn qt_conf_file(toolkit string) string {
	return os.join_path(qt_config_dir(toolkit), '${toolkit}.conf')
}

pub fn qt_scheme_file(toolkit string) string {
	return os.join_path(qt_config_dir(toolkit), 'colors', qt_scheme_name)
}

fn qt_backup_dir(toolkit string) string {
	base := xdg_or_home('XDG_STATE_HOME', '.local/state')
	return os.join_path(base, 'hornero', 'qt', 'backups', toolkit)
}

// qt_plugin_dirs lists where the platform-theme plugin may live.
// HORNERO_QT_PLUGIN_DIRS (colon separated) overrides for tests.
fn qt_plugin_dirs(toolkit string) []string {
	override := os.getenv('HORNERO_QT_PLUGIN_DIRS')
	if override.len > 0 {
		return override.split(':').filter(it.len > 0)
	}
	if toolkit == 'qt6ct' {
		return ['/usr/lib/qt6/plugins/platformthemes', '/usr/lib64/qt6/plugins/platformthemes']
	}
	return ['/usr/lib/qt/plugins/platformthemes', '/usr/lib64/qt5/plugins/platformthemes',
		'/usr/lib/qt5/plugins/platformthemes']
}

pub fn qt_plugin_installed(toolkit string) bool {
	for d in qt_plugin_dirs(toolkit) {
		if os.is_file(os.join_path(d, 'lib${toolkit}.so')) {
			return true
		}
	}
	return false
}

// qt_toolkit_present: manage a toolkit when its plugin is installed or the
// user already has its config directory.
fn qt_toolkit_present(toolkit string) bool {
	return qt_plugin_installed(toolkit) || os.is_dir(qt_config_dir(toolkit))
}

fn qt_hex_rgb(hex string) (int, int, int) {
	v := int(strconv.parse_uint(hex.trim_left('#'), 16, 32) or { 0 })
	return (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff
}

// mix_half blends two #RRGGBB colours 50/50 with round-half-to-even per
// channel, matching the Python generator (signal_theme.mix) byte for byte.
fn mix_half(a string, b string) string {
	ar, ag, ab := qt_hex_rgb(a)
	br, bg, bb := qt_hex_rgb(b)
	half := fn (x int, y int) int {
		s := x + y
		q := s / 2
		return if s % 2 == 1 && q % 2 == 1 { q + 1 } else { q }
	}
	return '#${half(ar, br):02X}${half(ag, bg):02X}${half(ab, bb):02X}'
}

fn qt_argb(hex string) string {
	return '#ff' + hex.trim_left('#').to_lower()
}

// render_qt_scheme renders the qt6ct/qt5ct [ColorScheme] for a live scheme.
// Roles follow QPalette::ColorRole order; Qt5 has no Accent role (21 entries),
// Qt6 has 22. Selection is the celeste cue, Accent the amber signal.
pub fn render_qt_scheme(t SignalTheme, toolkit string) string {
	dark := t.mode == 'dark'
	mut active := [
		t.role('ink'),
		t.role('raised'),
		t.role('lifted'),
		mix_half(t.role('raised'), t.role('lifted')),
		t.role('sunken'),
		t.role('ruleStrong'),
		t.role('ink'),
		if dark { '#FFFFFF' } else { '#000000' },
		t.role('ink'),
		t.role('sunken'),
		t.role('base'),
		t.role('shadow'),
		t.role('cue'),
		t.role('onCue'),
		t.role('cue'),
		t.role('inkMuted'),
		t.role('panel'),
		'#000000',
		t.role('lifted'),
		t.role('ink'),
		t.role('inkMuted'),
	]
	mut disabled := active.clone()
	for i in [0, 6, 8, 13, 20] {
		disabled[i] = t.role('inkFaint')
	}
	disabled[12] = t.role('cueWell')
	if toolkit == 'qt6ct' {
		active << t.role('signal')
		disabled << t.role('signalWell')
	}
	row := fn (cols []string) string {
		return cols.map(qt_argb(it)).join(', ')
	}
	return '; Hornero Signal ${toolkit} colour scheme for ${t.id} (${t.mode}) - GENERATED by horneroctl; do not hand-edit.\n' +
		'; Re-rendered on every theme apply. Roles follow QPalette::ColorRole order.\n' +
		'[ColorScheme]\nactive_colors=${row(active)}\ninactive_colors=${row(active)}\ndisabled_colors=${row(disabled)}\n'
}

// qt_ini_value reads key from one group of INI text ('' when absent).
fn qt_ini_value(text string, group string, key string) string {
	mut in_group := false
	for line in text.split_into_lines() {
		s := line.trim_space()
		if s.starts_with('[') {
			in_group = s == '[${group}]'
		} else if in_group && s.starts_with('${key}=') {
			return s.all_after('=').trim_space()
		}
	}
	return ''
}

// qt_set_managed_keys edits only custom_palette and color_scheme_path in
// [Appearance]; every other line, group and comment is preserved.
fn qt_set_managed_keys(text string, scheme_path string) string {
	mut out := []string{}
	mut in_app := false
	mut seen_palette := false
	mut seen_path := false
	mut has_marker := false
	for line in text.split_into_lines() {
		s := line.trim_space()
		mut next := line
		if s == qt_marker {
			has_marker = true
		}
		if s.starts_with('[') {
			in_app = s == '[Appearance]'
		} else if in_app && s.starts_with('custom_palette=') {
			next = 'custom_palette=true'
			seen_palette = true
		} else if in_app && s.starts_with('color_scheme_path=') {
			next = 'color_scheme_path=${scheme_path}'
			seen_path = true
		}
		out << next
	}
	if !seen_palette || !seen_path {
		mut extra := []string{}
		if !seen_palette {
			extra << 'custom_palette=true'
		}
		if !seen_path {
			extra << 'color_scheme_path=${scheme_path}'
		}
		idx := out.index('[Appearance]')
		if idx >= 0 {
			for i, e in extra {
				out.insert(idx + 1 + i, e)
			}
		} else {
			mut head := ['[Appearance]']
			head << extra
			head << ''
			head << out
			out = head.clone()
		}
	}
	if !has_marker {
		out.insert(0, qt_marker)
	}
	return out.join('\n') + '\n'
}

// qt_conf_class classifies an existing config: managed | stale | user-palette.
fn qt_conf_class(text string, our_scheme string) string {
	palette := qt_ini_value(text, 'Appearance', 'custom_palette')
	path := qt_ini_value(text, 'Appearance', 'color_scheme_path')
	if palette == 'true' && path == our_scheme {
		return 'managed'
	}
	if palette != 'true' || path.len == 0 {
		return 'stale'
	}
	stem := os.file_name(path).all_before_last('.')
	if stem in qt_stale_scheme_stems || stem.starts_with('hornero-') || path.starts_with('/etc/xdg/')
		|| path.starts_with('/usr/share/') {
		return 'stale'
	}
	return 'user-palette'
}

// qt_base_conf is the starting point for a fresh install: the packaged
// factory file when present, else a minimal Fusion config.
fn qt_base_conf(toolkit string) string {
	raw_dirs := os.getenv('XDG_CONFIG_DIRS')
	dirs := if raw_dirs.len > 0 { raw_dirs.split(':').filter(it.len > 0) } else { ['/etc/xdg'] }
	for d in dirs {
		raw := os.read_file(os.join_path(d, toolkit, '${toolkit}.conf')) or { continue }
		return raw
	}
	return '[Appearance]\nstyle=Fusion\nstandard_dialogs=default\n'
}

fn qt_backup(toolkit string, conf string) !string {
	dir := qt_backup_dir(toolkit)
	os.mkdir_all(dir) or { return error('cannot create ${dir}: ${err.msg()}') }
	stamp := time.now().custom_format('YYYYMMDD-HHmmss')
	dest := os.join_path(dir, '${stamp}-${toolkit}.conf')
	os.cp(conf, dest) or { return error('cannot back up ${conf}: ${err.msg()}') }
	return dest
}

// qt_sync_toolkit renders and installs the scheme for one toolkit.
pub fn qt_sync_toolkit(toolkit string, theme SignalTheme, dry_run bool) QtSyncReport {
	policy := qt_policy(toolkit)
	if policy == 'off' {
		return QtSyncReport{
			toolkit: toolkit
			status:  'off'
			detail:  'opted out (${toolkit}Consumer=off); files untouched'
		}
	}
	if !qt_toolkit_present(toolkit) {
		return QtSyncReport{
			toolkit: toolkit
			status:  'not-installed'
			detail:  '${toolkit} is not installed; nothing to theme'
		}
	}
	conf := qt_conf_file(toolkit)
	scheme_path := qt_scheme_file(toolkit)
	rendered := render_qt_scheme(theme, toolkit)
	existing := os.read_file(conf) or { '' }
	has_conf := os.is_file(conf)
	class := if has_conf { qt_conf_class(existing, scheme_path) } else { 'fresh' }
	if class == 'user-palette' && policy != 'force' {
		return QtSyncReport{
			toolkit: toolkit
			status:  'user-palette'
			detail:  'your own palette (${qt_ini_value(existing, 'Appearance', 'color_scheme_path')}) is in use; left alone. Take over with: horneroctl appearance set-qt ${toolkit}=force --yes'
		}
	}
	base := if has_conf { existing } else { qt_base_conf(toolkit) }
	next_conf := qt_set_managed_keys(base, scheme_path)
	scheme_changed := (os.read_file(scheme_path) or { '' }) != rendered
	conf_changed := next_conf != existing
	if !scheme_changed && !conf_changed {
		return QtSyncReport{
			toolkit: toolkit
			status:  'unchanged'
			detail:  '${theme.id} (${theme.mode}) already applied to ${toolkit}'
		}
	}
	if dry_run {
		return QtSyncReport{
			toolkit: toolkit
			status:  'synced'
			detail:  'would write ${scheme_path}' +
				if conf_changed { ' and update ${conf} (${class})' } else { '' }
			changed: true
		}
	}
	mut backup := ''
	if has_conf && conf_changed {
		backup = qt_backup(toolkit, conf) or {
			return QtSyncReport{
				toolkit: toolkit
				status:  'error'
				detail:  err.msg()
			}
		}
	}
	write_file_atomic(scheme_path, rendered) or {
		return QtSyncReport{
			toolkit: toolkit
			status:  'error'
			detail:  err.msg()
		}
	}
	// Always rewrite the config (even when only the scheme changed) so the
	// platform theme's file watcher reloads running apps.
	write_file_atomic(conf, next_conf) or {
		return QtSyncReport{
			toolkit: toolkit
			status:  'error'
			detail:  err.msg()
		}
	}
	return QtSyncReport{
		toolkit: toolkit
		status:  'synced'
		detail:  '${theme.id} (${theme.mode}) written to ${scheme_path}'
		changed: true
		backup:  backup
	}
}

// qt_sync_all themes every enabled toolkit from the live scheme.
pub fn qt_sync_all(dry_run bool) []QtSyncReport {
	theme := read_signal_scheme() or {
		return qt_consumer_names.map(QtSyncReport{
			toolkit: it
			status:  'no-scheme'
			detail:  err.msg()
		})
	}
	mut reports := qt_toolkits.map(qt_sync_toolkit(it, theme, dry_run))
	reports << kde_sync(theme, dry_run)
	return reports
}

// sync_qt6ct_palette keeps the historical hook name used by theme apply and
// Chromatic: it now syncs every Qt toolkit from the live scheme.
pub fn sync_qt6ct_palette(_ string) {
	qt_sync_all(false)
}

fn qt_reports_text(reports []QtSyncReport) string {
	mut lines := []string{}
	for r in reports {
		mut l := '${r.toolkit}: ${r.status} - ${r.detail}'
		if r.backup.len > 0 {
			l += ' (backup: ${r.backup})'
		}
		lines << l
	}
	return lines.join('\n')
}

// appearance_sync_qt_native implements `appearance sync-qt`.
pub fn appearance_sync_qt_native(dry_run bool) CommandResult {
	reports := qt_sync_all(dry_run)
	mut data := map[string]string{}
	mut failed := false
	for r in reports {
		data[r.toolkit] = r.status
		if r.status in ['error', 'no-scheme'] {
			failed = true
		}
	}
	text := qt_reports_text(reports)
	if failed {
		return fail_result('appearance sync-qt', text)
	}
	return ok_result('appearance sync-qt', text, data)
}

// appearance_set_qt_native implements `appearance set-qt <toolkit>=<policy>`
// (persist the policy, then apply it).
pub fn appearance_set_qt_native(spec string, dry_run bool) CommandResult {
	toolkit := spec.all_before('=')
	policy := spec.all_after('=')
	if toolkit !in qt_consumer_names || policy !in ['follow', 'force', 'off'] || !spec.contains('=') {
		return fail_result('appearance set-qt', 'Usage: horneroctl appearance set-qt <qt6ct|qt5ct|kde>=<follow|force|off>.\nExample: horneroctl appearance set-qt qt6ct=off --dry-run')
	}
	if dry_run {
		return ok_result('appearance set-qt', 'would persist ${toolkit}Consumer=${policy} in ${scheme_state_file()} and re-sync',
			{
				'toolkit': toolkit
				'policy':  policy
			})
	}
	update_state_json_fields({
		'${toolkit}Consumer': policy
	}, map[string]string{}) or { return fail_result('appearance set-qt', err.msg()) }
	reports := qt_sync_all(false)
	return ok_result('appearance set-qt', '${toolkit} policy: ${policy}\n' + qt_reports_text(reports), {
		'toolkit': toolkit
		'policy':  policy
	})
}

// qt_doctor_checks reports the Qt consumer state honestly and read-only.
pub fn qt_doctor_checks() []DoctorCheck {
	mut checks := []DoctorCheck{}
	live := read_signal_scheme() or { SignalTheme{} }
	for toolkit in qt_toolkits {
		name := 'qt-${toolkit}'
		policy := qt_policy(toolkit)
		if policy == 'off' {
			checks << DoctorCheck{
				name:   name
				ok:     true
				detail: 'opted out (${toolkit}Consumer=off); Hornero never touches ${toolkit} files'
			}
			continue
		}
		if !qt_toolkit_present(toolkit) {
			checks << DoctorCheck{
				name:   name
				ok:     true
				warn:   toolkit == 'qt6ct'
				detail: '${toolkit} not installed; ${if toolkit == 'qt6ct' {
					'Qt6 apps keep their default palette (install qt6ct)'
				} else {
					'no Qt5 theming needed unless Qt5 apps are used (install qt5ct)'
				}}'
			}
			continue
		}
		conf := qt_conf_file(toolkit)
		scheme := qt_scheme_file(toolkit)
		if !os.is_file(conf) {
			checks << DoctorCheck{
				name:   name
				ok:     false
				detail: '${conf} missing; ${toolkit} apps are unthemed. Run: horneroctl appearance sync-qt --yes'
			}
			continue
		}
		text := os.read_file(conf) or { '' }
		class := qt_conf_class(text, scheme)
		if class == 'user-palette' {
			checks << DoctorCheck{
				name:   name
				ok:     true
				warn:   true
				detail: 'your own palette is in use (${qt_ini_value(text, 'Appearance', 'color_scheme_path')}); not following Hornero. Take over: horneroctl appearance set-qt ${toolkit}=force --yes'
			}
			continue
		}
		if class == 'stale' {
			checks << DoctorCheck{
				name:   name
				ok:     false
				detail: '${conf} has no Hornero palette (custom_palette!=true or stale scheme); apps render with the default palette. Run: horneroctl appearance sync-qt --yes'
			}
			continue
		}
		if live.id.len == 0 {
			checks << DoctorCheck{
				name:   name
				ok:     false
				detail: 'cannot verify: live Signal scheme unreadable'
			}
			continue
		}
		have := os.read_file(scheme) or { '' }
		if have != render_qt_scheme(live, toolkit) {
			checks << DoctorCheck{
				name:   name
				ok:     false
				detail: '${scheme} does not match the live theme ${live.id}; run: horneroctl appearance sync-qt --yes'
			}
			continue
		}
		checks << DoctorCheck{
			name:   name
			ok:     true
			detail: '${live.id} (${live.mode}) applied via ${scheme}'
		}
	}
	checks << kde_doctor_check(live)
	env := os.getenv('QT_QPA_PLATFORMTHEME')
	if env.len > 0 {
		missing := qt_toolkits.filter(qt_toolkit_present(it) && qt_policy(it) != 'off'
			&& it !in env.split(':'))
		checks << DoctorCheck{
			name:   'qt-platformtheme'
			ok:     true
			warn:   missing.len > 0
			detail: if missing.len == 0 {
				'QT_QPA_PLATFORMTHEME=${env}'
			} else {
				'QT_QPA_PLATFORMTHEME=${env} lacks ${missing.join(', ')}; ${missing.join(', ')} apps ignore the palette. Use qt6ct:qt5ct in the Hyprland env block'
			}
		}
	} else {
		checks << DoctorCheck{
			name:   'qt-platformtheme'
			ok:     true
			warn:   true
			detail: 'QT_QPA_PLATFORMTHEME unset in this shell (a Hornero session sets it from the Hyprland env block); Qt apps started from here ignore the palette'
		}
	}
	for toolkit in qt_toolkits {
		text := os.read_file(qt_conf_file(toolkit)) or { continue }
		style := qt_ini_value(text, 'Appearance', 'style').to_lower()
		if style.starts_with('kvantum') {
			checks << DoctorCheck{
				name:   'qt-kvantum'
				ok:     true
				warn:   true
				detail: '${toolkit} style=${style}: Kvantum draws its own theme and bypasses the Signal palette; Hornero does not manage Kvantum (use style=Fusion for Signal colours)'
			}
		}
	}
	return checks
}
