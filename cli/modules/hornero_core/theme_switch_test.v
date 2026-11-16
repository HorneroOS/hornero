module hornero_core

import os

// Built-in theme get/set: the Signal fixture catalogue
// (cli/testdata/signal-themes), XDG under /tmp, and a stub apply_fn so
// verify/rollback stay hermetic (no GTK, no shell, no compositor).

const sw_root = '/tmp/hx-theme-switch-test'

fn sw_setup() {
	os.rmdir_all(sw_root) or {}
	os.setenv('HORNERO_THEMES_DIR', os.join_path(os.dir(@FILE), '..', '..', 'testdata',
		'signal-themes'), true)
	os.setenv('XDG_STATE_HOME', '${sw_root}/state', true)
	os.setenv('XDG_CACHE_HOME', '${sw_root}/cache', true)
	os.setenv('XDG_CONFIG_HOME', '${sw_root}/config', true)
	os.setenv('HORNERO_GTK3_FILE', '${sw_root}/gtk.ini', true)
	os.setenv('HORNERO_GSETTINGS_BIN', '/nonexistent-gsettings', true)
}

fn sw_teardown() {
	for name in ['HORNERO_THEMES_DIR', 'XDG_STATE_HOME', 'XDG_CACHE_HOME', 'XDG_CONFIG_HOME',
		'HORNERO_GTK3_FILE', 'HORNERO_GSETTINGS_BIN'] {
		os.unsetenv(name)
	}
	os.rmdir_all(sw_root) or {}
}

fn sw_write(path string, content string) {
	os.mkdir_all(os.dir(path)) or { panic(err) }
	os.write_file(path, content) or { panic(err) }
}

// sw_live writes the live scheme and GTK ini as a real apply would.
fn sw_live(id string, gtk string) {
	m := read_pack_map(id) or { panic(err) }
	t := parse_signal_theme(id, m) or { panic(err) }
	write_signal_scheme(t) or { panic(err) }
	persist_state_theme(id) or { panic(err) }
	sw_write('${sw_root}/gtk.ini', '[Settings]\ngtk-theme-name=${gtk}\n')
}

fn sw_pack_gtk(id string) string {
	m := read_pack_map(id) or { panic(err) }
	return pack_str(m, 'gtkTheme')
}

// sw_good_apply mirrors a successful native apply.
fn sw_good_apply(id string, wallpaper string, dry_run bool) CommandResult {
	sw_live(id, sw_pack_gtk(id))
	return ok_result('appearance theme apply', 'ok', {})
}

fn test_official_theme_ids() {
	assert official_theme_ids() == ['hornero-signal-night', 'hornero-signal-day',
		'hornero-signal-contrast']
	assert is_official_theme_id('hornero-signal-contrast')
	assert !is_official_theme_id('hornero-dark')
	assert !is_official_theme_id('pampa')
}

fn test_theme_get_defaults_to_signal_night() {
	sw_setup()
	r := theme_get_report(ThemeGetOptions{})
	assert r.ok
	assert r.data['id'] == 'hornero-signal-night'
	assert r.data['source'] == 'default'
	assert r.data['official'] == 'true'
	sw_teardown()
}

fn test_theme_get_reports_migration_without_writing() {
	sw_setup()
	state := '${sw_root}/state/hornero/scheme/state.json'
	sw_write(state, '{"name":"hornero-light","flavour":"vibrant"}')
	r := theme_get_report(ThemeGetOptions{})
	assert r.ok
	assert r.data['id'] == 'hornero-signal-day'
	assert r.data['migrated_from'] == 'hornero-light'
	assert r.message.contains('appearance sync --yes')
	assert (os.read_file(state) or { '' }).contains('hornero-light')
	sw_teardown()
}

fn test_theme_get_reads_live_scheme() {
	sw_setup()
	sw_live('hornero-signal-contrast', 'Hornero-Signal-Night')
	r := theme_get_report(ThemeGetOptions{})
	assert r.data['id'] == 'hornero-signal-contrast'
	assert r.data['source'] == 'scheme'
	assert r.data['mode'] == 'dark'
	assert r.data['gtk_theme'] == 'Hornero-Signal-Night'
	sw_teardown()
}

fn test_theme_get_dry_run_needs_no_backend() {
	r := theme_get_report(ThemeGetOptions{
		dry_run: true
	})
	assert r.ok
	assert r.data['dry_run'] == 'true'
}

fn test_theme_set_rejects_non_official_and_retired() {
	for id in ['hornero-dark', 'hornero-light', 'pampa', ''] {
		r := theme_set_report(ThemeSetOptions{
			id:  id
			yes: true
		})
		assert !r.ok
		assert r.message.contains('unknown official theme')
		assert r.message.contains('hornero-signal-night|hornero-signal-day|hornero-signal-contrast')
	}
}

fn test_theme_set_needs_yes() {
	r := theme_set_report(ThemeSetOptions{
		id: 'hornero-signal-day'
	})
	assert !r.ok
	assert r.message.contains('--yes')
}

fn test_theme_set_dry_run_previews() {
	sw_setup()
	r := theme_set_report_with(ThemeSetOptions{
		id:      'hornero-signal-day'
		dry_run: true
	}, fn (id string, w string, d bool) CommandResult {
		panic('dry-run must not apply')
	})
	assert r.ok
	assert r.message.contains('verify mode=light gtk=Hornero-Signal-Day')
	assert !os.exists(signal_scheme_file())
	sw_teardown()
}

fn test_theme_set_happy_path_verifies() {
	sw_setup()
	r := theme_set_report_with(ThemeSetOptions{
		id:  'hornero-signal-day'
		yes: true
	}, sw_good_apply)
	assert r.ok, r.message
	assert r.data['id'] == 'hornero-signal-day'
	assert r.data['mode'] == 'light'
	assert r.data['gtk_theme'] == 'Hornero-Signal-Day'
	sw_teardown()
}

fn test_theme_set_verify_failure_rolls_back() {
	sw_setup()
	sw_live('hornero-signal-night', 'Hornero-Signal-Night')

	log := '${sw_root}/calls.log'
	r := theme_set_report_with(ThemeSetOptions{
		id:  'hornero-signal-day'
		yes: true
	}, fn [log] (id string, w string, d bool) CommandResult {
		mut f := os.open_append(log) or { panic(err) }
		f.writeln(id) or {}
		f.close()
		if id == 'hornero-signal-day' {
			// Split state: the scheme switched but GTK did not.
			sw_live(id, 'Hornero-Signal-Night')
			return ok_result('appearance theme apply', 'ok', {})
		}
		return sw_good_apply(id, w, d)
	})
	calls := (os.read_file(log) or { '' }).split_into_lines()
	assert !r.ok
	assert r.message.contains('gtk is Hornero-Signal-Night (want Hornero-Signal-Day)')
	assert r.message.contains('rolled back to hornero-signal-night')
	assert calls == ['hornero-signal-day', 'hornero-signal-night']
	live := read_signal_scheme() or { panic(err) }
	assert live.id == 'hornero-signal-night'
	sw_teardown()
}

fn test_theme_set_apply_failure_without_clean_pre_state() {
	sw_setup()
	r := theme_set_report_with(ThemeSetOptions{
		id:  'hornero-signal-contrast'
		yes: true
	}, fn (id string, w string, d bool) CommandResult {
		return fail_result('appearance theme apply', 'boom')
	})
	assert !r.ok
	assert r.message.contains('backend failed')
	assert !r.message.contains('rolled back')
	sw_teardown()
}

fn test_theme_set_verify_rejects_wrong_selected_theme() {
	sw_setup()
	r := theme_set_report_with(ThemeSetOptions{
		id:  'hornero-signal-contrast'
		yes: true
	}, fn (id string, w string, d bool) CommandResult {
		// Reports success but leaves Night live.
		sw_live('hornero-signal-night', 'Hornero-Signal-Night')
		return ok_result('appearance theme apply', 'ok', {})
	})
	assert !r.ok
	assert r.message.contains('selected theme is hornero-signal-night')
	sw_teardown()
}
