module hornero_core

import os
import x.json2

// Official theme get/set fixtures: everything lives under /tmp, env
// overrides isolate HOME/PATH, and each test unsets what it sets (no
// network, no compositor, no real backends).

const sw_root = '/tmp/hx-theme-switch-test'

fn sw_write(path string, content string) {
	os.mkdir_all(os.dir(path)) or { assert false }
	os.write_file(path, content) or { assert false }
	os.chmod(path, 0o755) or { assert false }
}

fn sw_setup_packs() {
	sw_write('${sw_root}/themes/hornero-dark/theme.json', '{"schemaVersion":1,"id":"hornero-dark","name":"Hornero Dark","description":"Flagship dark","gtkTheme":"Orchis-Dark-Compact","iconTheme":"Papirus-Dark","defaultWallpaper":"hornero-dark-01.jpg","wallpaperDir":"hornero-dark","mode":"dark"}')
	sw_write('${sw_root}/themes/hornero-light/theme.json', '{"schemaVersion":1,"id":"hornero-light","name":"Hornero Light","description":"Flagship light","gtkTheme":"Orchis-Light-Compact","iconTheme":"Numix-Circle","defaultWallpaper":"hornero-light-01.jpg","wallpaperDir":"hornero-light","mode":"light"}')
	sw_write('${sw_root}/themes/legacy-dark/theme.json', '{"schemaVersion":1,"id":"legacy-dark","name":"Legacy Dark","gtkTheme":"Legacy-Dark","iconTheme":"Papirus-Dark","defaultWallpaper":"l.jpg","wallpaperDir":"legacy-dark","darkMode":true}')
	sw_write('${sw_root}/themes/pampa/theme.json', '{"schemaVersion":1,"id":"pampa","name":"Pampa","description":"Flagship grassland-night","gtkTheme":"Hornero-Pampa","iconTheme":"Papirus-Dark","defaultWallpaper":"pampa-01.png","wallpaperDir":"pampa","mode":"dark"}')
	os.setenv('HORNERO_THEMES_DIR', '${sw_root}/themes', true)
}

// sw_setup_state materializes a status payload as live state files: the
// scheme state.json (mode/flavour/gtkColorScheme), the gtk3 ini
// (gtk-theme-name/gtk-icon-theme-name), and the wallpaper pointer.
// Payload keys: wallpaper, mode, flavour, gtkTheme, iconTheme,
// gtkColorScheme. Env is pointed at sw_root; sw_teardown restores it.
// (The old fake-dots-appearance backend this replaced is gone: reads are
// native now, so fixtures are files, not a stub process.)
fn sw_setup_state(payload string) {
	doc := json2.decode[json2.Any](payload) or {
		assert false
		return
	}
	if doc is map[string]json2.Any {
		mode := doc['mode'].str()
		flavour := doc['flavour'].str()
		mut policy := doc['gtkColorScheme'].str()
		if policy.len == 0 {
			policy = 'follow'
		}
		gtk := doc['gtkTheme'].str()
		icon := doc['iconTheme'].str()
		sw_write('${sw_root}/state/hornero/scheme/state.json', '{"mode":"' + mode +
			'","flavour":"' + flavour + '","gtkColorScheme":"' + policy + '"}')
		mut ini := '[Settings]\n'
		if gtk.len > 0 {
			ini += 'gtk-theme-name=' + gtk + '\n'
		}
		if icon.len > 0 {
			ini += 'gtk-icon-theme-name=' + icon + '\n'
		}
		sw_write('${sw_root}/gtk.ini', ini)
		wp := doc['wallpaper'].str()
		if wp.len > 0 {
			sw_write('${sw_root}/state/hornero/wallpaper/path', wp + '\n')
		} else {
			os.rm('${sw_root}/state/hornero/wallpaper/path') or {}
		}
	} else {
		assert false
	}
	os.setenv('XDG_STATE_HOME', '${sw_root}/state', true)
	os.setenv('XDG_CACHE_HOME', '${sw_root}/cache', true)
	os.setenv('HORNERO_GTK3_FILE', '${sw_root}/gtk.ini', true)
}

// sw_materialize_pack_state writes the fixture-pack state for an official
// id (mirrors sw_setup_packs gtk/mode/icon values).
fn sw_materialize_pack_state(id string) {
	match id {
		'hornero-dark' {
			sw_setup_state('{"wallpaper":"w.jpg","mode":"dark","flavour":"vibrant","gtkTheme":"Orchis-Dark-Compact","iconTheme":"Papirus-Dark","gtkColorScheme":"follow"}')
		}
		'hornero-light' {
			sw_setup_state('{"wallpaper":"w.jpg","mode":"light","flavour":"vibrant","gtkTheme":"Orchis-Light-Compact","iconTheme":"Numix-Circle","gtkColorScheme":"follow"}')
		}
		'pampa' {
			sw_setup_state('{"wallpaper":"pampa-01.png","mode":"dark","flavour":"tonal-spot","gtkTheme":"Hornero-Pampa","iconTheme":"Papirus-Dark","gtkColorScheme":"follow"}')
		}
		else {}
	}
}

// Apply recorder for the theme_set_report_with seam, kept in files (not
// globals: the gates run without -enable-globals). sw_apply_reset arms
// behavior: mode 'ok-update' materializes the target pack state,
// 'ok-stale' succeeds without touching files; fail_first forces that
// many leading failures (rollback paths exercise fail-then-ok and
// fail-then-fail). Every invocation appends its id to calls.log.
fn sw_apply_reset(mode string, fail_first int) {
	sw_write('${sw_root}/apply-mode', mode)
	sw_write('${sw_root}/apply-fail-left', '${fail_first}\n')
	os.write_file('${sw_root}/apply-calls.log', '') or { assert false }
}

fn sw_apply_calls() []string {
	raw := os.read_file('${sw_root}/apply-calls.log') or { return []string{} }
	mut out := []string{}
	for line in raw.split_into_lines() {
		if line.len > 0 {
			out << line
		}
	}
	return out
}

fn sw_apply_stub(id string, wallpaper string, dry_run bool) CommandResult {
	os.write_file('${sw_root}/apply-calls.log',
		os.read_file('${sw_root}/apply-calls.log') or { '' } + id + '\n') or { assert false }
	left := (os.read_file('${sw_root}/apply-fail-left') or { '0' }).int()
	if left > 0 {
		os.write_file('${sw_root}/apply-fail-left', '${left - 1}\n') or { assert false }
		return fail_result('appearance theme apply', 'stub apply failed for ${id}')
	}
	mode := (os.read_file('${sw_root}/apply-mode') or { '' }).trim_space()
	if mode == 'ok-update' {
		sw_materialize_pack_state(id)
	}
	return ok_result('appearance theme apply', 'stub applied ${id}', {
		'id': id
	})
}

fn sw_teardown() {
	os.unsetenv('HORNERO_THEMES_DIR')
	os.unsetenv('HORNERO_DOTS_APPEARANCE_BIN')
	os.unsetenv('XDG_STATE_HOME')
	os.unsetenv('XDG_CACHE_HOME')
	os.unsetenv('HORNERO_GTK3_FILE')
}

const sw_dark_status = '{"wallpaper":"w.jpg","mode":"dark","flavour":"vibrant","gtkTheme":"Orchis-Dark-Compact","iconTheme":"Papirus-Dark","gtkColorScheme":"follow"}'
const sw_light_status = '{"wallpaper":"w.jpg","mode":"light","flavour":"vibrant","gtkTheme":"Orchis-Light-Compact","iconTheme":"Numix-Circle","gtkColorScheme":"follow"}'

fn test_official_theme_ids() {
	assert is_official_theme_id('hornero-dark')
	assert is_official_theme_id('hornero-light')
	assert is_official_theme_id('pampa')
	assert !is_official_theme_id('vapor-dreams')
	assert !is_official_theme_id('')
	assert !is_official_theme_id('../escape')
}

fn test_pack_expected_mode_tokens() {
	flagship := json2.decode[json2.Any]('{"mode":"light","darkMode":true}') or {
		assert false
		return
	}
	if flagship is map[string]json2.Any {
		assert pack_expected_mode(flagship) == 'light'
	} else {
		assert false
	}
	legacy := json2.decode[json2.Any]('{"darkMode":false}') or {
		assert false
		return
	}
	if legacy is map[string]json2.Any {
		assert pack_expected_mode(legacy) == 'light'
	} else {
		assert false
	}
	bare := json2.decode[json2.Any]('{"id":"x"}') or {
		assert false
		return
	}
	if bare is map[string]json2.Any {
		assert pack_expected_mode(bare) == ''
	} else {
		assert false
	}
}

fn test_theme_get_matches_official() {
	sw_setup_packs()
	sw_setup_state(sw_dark_status)
	r := theme_get_report(ThemeGetOptions{})
	assert r.ok
	assert r.command == 'appearance theme get'
	assert r.data['id'] == 'hornero-dark'
	assert r.data['mode'] == 'dark'
	assert r.data['gtk_theme'] == 'Orchis-Dark-Compact'
	assert r.message.contains('hornero-dark')
	sw_teardown()
}

const sw_pampa_status = '{"wallpaper":"pampa-01.png","mode":"dark","flavour":"tonal-spot","gtkTheme":"Hornero-Pampa","iconTheme":"Papirus-Dark","gtkColorScheme":"follow"}'

fn test_theme_get_matches_pampa_via_gtk_discriminator() {
	sw_setup_packs()
	// mode=dark is shared with hornero-dark: only the GTK signal picks pampa.
	sw_setup_state(sw_pampa_status)
	r := theme_get_report(ThemeGetOptions{})
	assert r.ok
	assert r.data['id'] == 'pampa'
	assert r.data['mode'] == 'dark'
	assert r.data['gtk_theme'] == 'Hornero-Pampa'
	assert r.message.contains('pampa')
	sw_teardown()
}

fn test_theme_get_mode_only_dark_prefers_first_official() {
	sw_setup_packs()
	// No GTK signal: both dark packs match on mode, first id wins.
	sw_setup_state('{"wallpaper":"","mode":"dark","flavour":"","gtkTheme":"","iconTheme":"","gtkColorScheme":"follow"}')
	r := theme_get_report(ThemeGetOptions{})
	assert r.ok
	assert r.data['id'] == 'hornero-dark'
	sw_teardown()
}

fn test_theme_get_custom_state_stays_ok() {
	sw_setup_packs()
	sw_setup_state('{"wallpaper":"","mode":"dark","flavour":"","gtkTheme":"Foreign-GTK","iconTheme":"","gtkColorScheme":"follow"}')
	r := theme_get_report(ThemeGetOptions{})
	assert r.ok
	assert r.data['id'] == ''
	assert r.data['gtk_theme'] == 'Foreign-GTK'
	assert r.message.contains('(custom)')
	sw_teardown()
}

fn test_theme_get_empty_state_matches_nothing() {
	sw_setup_packs()
	sw_setup_state('{"wallpaper":"","mode":"","flavour":"","gtkTheme":"","iconTheme":"","gtkColorScheme":"follow"}')
	r := theme_get_report(ThemeGetOptions{})
	assert r.ok
	assert r.data['id'] == ''
	sw_teardown()
}

fn test_theme_get_dry_run_needs_no_backend() {
	r := theme_get_report(ThemeGetOptions{
		dry_run: true
	})
	assert r.ok
	assert r.data['dry_run'] == 'true'
	assert r.message.contains('read scheme state')
	sw_teardown()
}

fn test_theme_get_honors_explicit_backend_override() {
	// An explicit HORNERO_DOTS_APPEARANCE_BIN override short-circuits
	// to that backend: dry-run previews it, a broken one fails loudly.
	os.setenv('HORNERO_DOTS_APPEARANCE_BIN', '/nonexistent-appearance-hornero-test', true)
	dry := theme_get_report(ThemeGetOptions{
		dry_run: true
	})
	assert dry.ok
	assert dry.message.contains('/nonexistent-appearance-hornero-test')
	live := theme_get_report(ThemeGetOptions{})
	assert !live.ok
	assert live.message.contains('backend failed')
	sw_teardown()
}

fn test_theme_get_without_state_files_stays_ok() {
	// Reads are native now: with no state files anywhere the status is
	// unknown/custom, but get still succeeds (there is no backend left
	// to fail).
	os.setenv('XDG_STATE_HOME', '/nonexistent-state-hornero-test', true)
	os.setenv('XDG_CACHE_HOME', '/nonexistent-cache-hornero-test', true)
	os.setenv('HORNERO_GTK3_FILE', '/nonexistent-gtk-hornero-test.ini', true)
	r := theme_get_report(ThemeGetOptions{})
	assert r.ok
	assert r.data['id'] == ''
	sw_teardown()
}

fn test_theme_set_rejects_non_official() {
	r := theme_set_report(ThemeSetOptions{
		id:      'vapor-dreams'
		dry_run: true
	})
	assert !r.ok
	assert r.message.contains('hornero-dark|hornero-light|pampa')
	bad := theme_set_report(ThemeSetOptions{
		id:      '../escape'
		dry_run: true
	})
	assert !bad.ok
}

fn test_theme_set_needs_yes() {
	refused := theme_set_report(ThemeSetOptions{
		id: 'hornero-dark'
	})
	assert !refused.ok
	assert refused.message.contains('--yes')
}

fn test_theme_set_dry_run_previews_and_needs_no_backend() {
	sw_setup_packs()
	r := theme_set_report(ThemeSetOptions{
		id:      'hornero-dark'
		dry_run: true
	})
	assert r.ok
	assert r.data['dry_run'] == 'true'
	assert r.data['id'] == 'hornero-dark'
	assert r.message.contains('theme apply hornero-dark')
	assert r.message.contains('verify')
	sw_teardown()
}

fn test_theme_set_missing_pack_fails_before_mutation() {
	os.setenv('HORNERO_THEMES_DIR', '/nonexistent-themes-hornero-test', true)
	sw_apply_reset('ok-update', 0)
	r := theme_set_report_with(ThemeSetOptions{
		id:  'hornero-dark'
		yes: true
	}, sw_apply_stub)
	assert !r.ok
	assert r.message.contains('Theme not found')
	assert sw_apply_calls().len == 0
	sw_teardown()
}

fn test_theme_set_happy_path_verifies() {
	sw_setup_packs()
	sw_setup_state(sw_light_status)
	sw_apply_reset('ok-update', 0)
	r := theme_set_report_with(ThemeSetOptions{
		id:  'hornero-dark'
		yes: true
	}, sw_apply_stub)
	assert r.ok, r.message
	assert r.command == 'appearance theme set'
	assert r.data['id'] == 'hornero-dark'
	assert r.data['mode'] == 'dark'
	assert r.data['gtk_theme'] == 'Orchis-Dark-Compact'
	assert sw_apply_calls() == ['hornero-dark']
	sw_teardown()
}

fn test_theme_set_pampa_happy_path_verifies() {
	sw_setup_packs()
	sw_setup_state(sw_dark_status)
	sw_apply_reset('ok-update', 0)
	r := theme_set_report_with(ThemeSetOptions{
		id:  'pampa'
		yes: true
	}, sw_apply_stub)
	assert r.ok, r.message
	assert r.command == 'appearance theme set'
	assert r.data['id'] == 'pampa'
	assert r.data['mode'] == 'dark'
	assert r.data['gtk_theme'] == 'Hornero-Pampa'
	assert sw_apply_calls() == ['pampa']
	sw_teardown()
}

fn test_theme_set_verify_failure_rolls_back() {
	sw_setup_packs()
	// Apply succeeds but leaves the old GTK behind: a split state.
	sw_setup_state(sw_light_status)
	sw_apply_reset('ok-stale', 0)
	r := theme_set_report_with(ThemeSetOptions{
		id:  'hornero-dark'
		yes: true
	}, sw_apply_stub)
	assert !r.ok
	assert r.message.contains('verify failed')
	assert r.message.contains('gtk is Orchis-Light-Compact (want Orchis-Dark-Compact)')
	assert r.message.contains('rolled back to hornero-light')
	assert sw_apply_calls() == ['hornero-dark', 'hornero-light']
	sw_teardown()
}

fn test_theme_set_apply_failure_rolls_back() {
	sw_setup_packs()
	sw_setup_state(sw_light_status)
	sw_apply_reset('ok-update', 1)
	r := theme_set_report_with(ThemeSetOptions{
		id:  'hornero-dark'
		yes: true
	}, sw_apply_stub)
	assert !r.ok
	assert r.message.contains('backend failed')
	assert r.message.contains('rolled back to hornero-light')
	assert sw_apply_calls() == ['hornero-dark', 'hornero-light']
	sw_teardown()
}

fn test_theme_set_failed_rollback_is_reported() {
	sw_setup_packs()
	sw_setup_state(sw_light_status)
	sw_apply_reset('ok-update', 99)
	r := theme_set_report_with(ThemeSetOptions{
		id:  'hornero-dark'
		yes: true
	}, sw_apply_stub)
	assert !r.ok
	assert r.message.contains('backend failed')
	assert r.message.contains('rollback to hornero-light failed')
	assert sw_apply_calls() == ['hornero-dark', 'hornero-light']
	sw_teardown()
}

fn test_theme_set_verify_failure_without_clean_pre_state() {
	sw_setup_packs()
	// Custom pre-state, apply leaves it untouched: verify fails and
	// there is nothing coherent to roll back to.
	sw_setup_state('{"wallpaper":"","mode":"dark","flavour":"","gtkTheme":"Foreign-GTK","iconTheme":"","gtkColorScheme":"follow"}')
	sw_apply_reset('ok-stale', 0)
	r := theme_set_report_with(ThemeSetOptions{
		id:  'hornero-dark'
		yes: true
	}, sw_apply_stub)
	assert !r.ok
	assert r.message.contains('verify failed')
	assert r.message.contains('Run: horneroctl appearance theme get')
	assert !r.message.contains('rolled back')
	assert sw_apply_calls() == ['hornero-dark']
	sw_teardown()
}

fn test_theme_set_from_custom_pre_state_succeeds_without_rollback() {
	sw_setup_packs()
	sw_setup_state('{"wallpaper":"","mode":"dark","flavour":"","gtkTheme":"Foreign-GTK","iconTheme":"","gtkColorScheme":"follow"}')
	sw_apply_reset('ok-update', 0)
	r := theme_set_report_with(ThemeSetOptions{
		id:  'hornero-dark'
		yes: true
	}, sw_apply_stub)
	assert r.ok, r.message
	assert r.data['id'] == 'hornero-dark'
	assert sw_apply_calls() == ['hornero-dark']
	sw_teardown()
}
