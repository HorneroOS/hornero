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

// sw_setup_stub installs a fake dots-appearance. `before` is the
// `status --json` payload until `theme apply` runs, `after` the payload
// once it has (empty `after` keeps `before`). HX_APPLY_RC fails the first
// apply, HX_ROLLBACK_RC the rollback re-apply, HX_STATUS_RC the status
// read; every invocation appends to argv.log.
fn sw_setup_stub(before string, after string) {
	sw_write('${sw_root}/bin/dots-appearance', '#!/bin/sh\n' + 'echo "\$@" >> "' + sw_root +
		'/argv.log"\n' + 'if [ "\$1" = "status" ] && [ "\$2" = "--json" ]; then\n' +
		'  if grep -q "theme apply" "' + sw_root +
		'/argv.log" 2>/dev/null && [ -n "\$HX_STATUS_AFTER" ]; then\n' +
		'    printf "%s\\n" "\$HX_STATUS_AFTER"\n' + '  else\n' +
		'    printf "%s\\n" "\$HX_STATUS_BEFORE"\n' + '  fi\n' + '  exit "\${HX_STATUS_RC:-0}"\n' +
		'fi\n' + 'if [ "\$1" = "theme" ] && [ "\$2" = "apply" ]; then\n' +
		'  printf "%s\\n" "applied \$3"\n' + '  n=\$(grep -c "theme apply" "' + sw_root +
		'/argv.log")\n' + '  if [ "\$n" -le 1 ]; then exit "\${HX_APPLY_RC:-0}"; fi\n' +
		'  exit "\${HX_ROLLBACK_RC:-0}"\n' + 'fi\n' + 'echo "stub: unknown: \$@" >&2\n' + 'exit 1\n')
	os.setenv('HORNERO_DOTS_APPEARANCE_BIN', '${sw_root}/bin/dots-appearance', true)
	os.setenv('HX_STATUS_BEFORE', before, true)
	os.setenv('HX_STATUS_AFTER', after, true)
	os.setenv('HX_STATUS_RC', '0', true)
	os.setenv('HX_APPLY_RC', '0', true)
	os.setenv('HX_ROLLBACK_RC', '0', true)
	os.rm('${sw_root}/argv.log') or {}
}

fn sw_teardown() {
	os.unsetenv('HORNERO_THEMES_DIR')
	os.unsetenv('HORNERO_DOTS_APPEARANCE_BIN')
	os.unsetenv('HX_STATUS_BEFORE')
	os.unsetenv('HX_STATUS_AFTER')
	os.unsetenv('HX_STATUS_RC')
	os.unsetenv('HX_APPLY_RC')
	os.unsetenv('HX_ROLLBACK_RC')
}

fn sw_argv_log() string {
	return os.read_file('${sw_root}/argv.log') or { '' }
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
	sw_setup_stub(sw_dark_status, '')
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
	sw_setup_stub(sw_pampa_status, '')
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
	sw_setup_stub('{"wallpaper":"","mode":"dark","flavour":"","gtkTheme":"","iconTheme":"","gtkColorScheme":"follow"}',
		'')
	r := theme_get_report(ThemeGetOptions{})
	assert r.ok
	assert r.data['id'] == 'hornero-dark'
	sw_teardown()
}

fn test_theme_get_custom_state_stays_ok() {
	sw_setup_packs()
	sw_setup_stub('{"wallpaper":"","mode":"dark","flavour":"","gtkTheme":"Foreign-GTK","iconTheme":"","gtkColorScheme":"follow"}',
		'')
	r := theme_get_report(ThemeGetOptions{})
	assert r.ok
	assert r.data['id'] == ''
	assert r.data['gtk_theme'] == 'Foreign-GTK'
	assert r.message.contains('(custom)')
	sw_teardown()
}

fn test_theme_get_empty_state_matches_nothing() {
	sw_setup_packs()
	sw_setup_stub('{"wallpaper":"","mode":"","flavour":"","gtkTheme":"","iconTheme":"","gtkColorScheme":"follow"}',
		'')
	r := theme_get_report(ThemeGetOptions{})
	assert r.ok
	assert r.data['id'] == ''
	sw_teardown()
}

fn test_theme_get_dry_run_needs_no_backend() {
	os.setenv('HORNERO_DOTS_APPEARANCE_BIN', '/nonexistent-appearance-hornero-test', true)
	r := theme_get_report(ThemeGetOptions{
		dry_run: true
	})
	assert r.ok
	assert r.data['dry_run'] == 'true'
	assert r.message.contains('status --json')
	os.unsetenv('HORNERO_DOTS_APPEARANCE_BIN')
}

fn test_theme_get_backend_failure() {
	sw_setup_packs()
	sw_setup_stub(sw_dark_status, '')
	os.setenv('HX_STATUS_RC', '3', true)
	r := theme_get_report(ThemeGetOptions{})
	assert !r.ok
	assert r.message.contains('backend failed')
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
		id:     'hornero-dark'
		helper: '/nonexistent-helper-hornero-test'
	})
	assert !refused.ok
	assert refused.message.contains('--yes')
}

fn test_theme_set_dry_run_previews_and_needs_no_backend() {
	sw_setup_packs()
	os.setenv('HORNERO_DOTS_APPEARANCE_BIN', '/nonexistent-appearance-hornero-test', true)
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
	sw_setup_stub(sw_light_status, sw_dark_status)
	r := theme_set_report(ThemeSetOptions{
		id:  'hornero-dark'
		yes: true
	})
	assert !r.ok
	assert r.message.contains('Theme not found')
	assert !sw_argv_log().contains('theme apply')
	sw_teardown()
}

fn test_theme_set_happy_path_verifies() {
	sw_setup_packs()
	sw_setup_stub(sw_light_status, sw_dark_status)
	r := theme_set_report(ThemeSetOptions{
		id:  'hornero-dark'
		yes: true
	})
	assert r.ok, r.message
	assert r.command == 'appearance theme set'
	assert r.data['id'] == 'hornero-dark'
	assert r.data['mode'] == 'dark'
	assert r.data['gtk_theme'] == 'Orchis-Dark-Compact'
	assert sw_argv_log().contains('theme apply hornero-dark')
	sw_teardown()
}

fn test_theme_set_pampa_happy_path_verifies() {
	sw_setup_packs()
	sw_setup_stub(sw_dark_status, sw_pampa_status)
	r := theme_set_report(ThemeSetOptions{
		id:  'pampa'
		yes: true
	})
	assert r.ok, r.message
	assert r.command == 'appearance theme set'
	assert r.data['id'] == 'pampa'
	assert r.data['mode'] == 'dark'
	assert r.data['gtk_theme'] == 'Hornero-Pampa'
	assert sw_argv_log().contains('theme apply pampa')
	sw_teardown()
}

fn test_theme_set_verify_failure_rolls_back() {
	sw_setup_packs()
	// Backend applies but leaves the old GTK behind: a split state.
	sw_setup_stub(sw_light_status, '{"wallpaper":"","mode":"dark","flavour":"","gtkTheme":"Orchis-Light-Compact","iconTheme":"","gtkColorScheme":"follow"}')
	r := theme_set_report(ThemeSetOptions{
		id:  'hornero-dark'
		yes: true
	})
	assert !r.ok
	assert r.message.contains('verify failed')
	assert r.message.contains('gtk is Orchis-Light-Compact (want Orchis-Dark-Compact)')
	assert r.message.contains('rolled back to hornero-light')
	log := sw_argv_log()
	assert log.contains('theme apply hornero-dark')
	assert log.contains('theme apply hornero-light')
	sw_teardown()
}

fn test_theme_set_apply_failure_rolls_back() {
	sw_setup_packs()
	sw_setup_stub(sw_light_status, sw_dark_status)
	os.setenv('HX_APPLY_RC', '1', true)
	r := theme_set_report(ThemeSetOptions{
		id:  'hornero-dark'
		yes: true
	})
	assert !r.ok
	assert r.message.contains('backend failed')
	assert r.message.contains('rolled back to hornero-light')
	sw_teardown()
}

fn test_theme_set_failed_rollback_is_reported() {
	sw_setup_packs()
	sw_setup_stub(sw_light_status, sw_dark_status)
	os.setenv('HX_APPLY_RC', '1', true)
	os.setenv('HX_ROLLBACK_RC', '1', true)
	r := theme_set_report(ThemeSetOptions{
		id:  'hornero-dark'
		yes: true
	})
	assert !r.ok
	assert r.message.contains('backend failed')
	assert r.message.contains('rollback to hornero-light failed')
	sw_teardown()
}

fn test_theme_set_verify_failure_without_clean_pre_state() {
	sw_setup_packs()
	// Custom pre-state, backend leaves it untouched: verify fails and
	// there is nothing coherent to roll back to.
	sw_setup_stub('{"wallpaper":"","mode":"dark","flavour":"","gtkTheme":"Foreign-GTK","iconTheme":"","gtkColorScheme":"follow"}',
		'{"wallpaper":"","mode":"dark","flavour":"","gtkTheme":"Foreign-GTK","iconTheme":"","gtkColorScheme":"follow"}')
	r := theme_set_report(ThemeSetOptions{
		id:  'hornero-dark'
		yes: true
	})
	assert !r.ok
	assert r.message.contains('verify failed')
	assert r.message.contains('Run: horneroctl appearance theme get')
	assert !r.message.contains('rolled back')
	assert !sw_argv_log().contains('theme apply hornero-light')
	sw_teardown()
}

fn test_theme_set_from_custom_pre_state_succeeds_without_rollback() {
	sw_setup_packs()
	sw_setup_stub('{"wallpaper":"","mode":"dark","flavour":"","gtkTheme":"Foreign-GTK","iconTheme":"","gtkColorScheme":"follow"}',
		sw_dark_status)
	r := theme_set_report(ThemeSetOptions{
		id:  'hornero-dark'
		yes: true
	})
	assert r.ok, r.message
	assert r.data['id'] == 'hornero-dark'
	assert !sw_argv_log().contains('theme apply hornero-light')
	sw_teardown()
}
