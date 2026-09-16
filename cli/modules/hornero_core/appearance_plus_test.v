module hornero_core

import os

// Appearance-plus fixtures: stub backends under /tmp, env overrides for
// resolver tests, and the helper struct field everywhere else (no network,
// no compositor, no real backends, no HOME mutation).

const ap_root = '/tmp/hx-appearance-plus-test'

fn ap_write(path string, content string) {
	os.mkdir_all(os.dir(path)) or { assert false }
	os.write_file(path, content) or { assert false }
	os.chmod(path, 0o755) or { assert false }
}

// ap_setup_stub installs a fake backend called `name`: every invocation
// appends "$@" to argv.log, fails with exit 9 unless HORNEROCTL_DELEGATED
// is set (proving the re-entrancy guard), prints HX_OUTPUT, exits HX_RC.
fn ap_setup_stub(name string) {
	ap_write('${ap_root}/bin/${name}', '#!/bin/sh\n' + 'echo "\$@" >> "' + ap_root +
		'/argv.log"\n' +
		'if [ -z "\$HORNEROCTL_DELEGATED" ]; then echo "missing delegation guard" >&2; exit 9; fi\n' +
		'printf "%s\\n" "\$HX_OUTPUT"\n' + 'exit "\${HX_RC:-0}"\n')
	os.setenv('HX_OUTPUT', 'stub-output', true)
	os.setenv('HX_RC', '0', true)
	os.rm('${ap_root}/argv.log') or {}
}

fn ap_teardown() {
	os.unsetenv('HX_OUTPUT')
	os.unsetenv('HX_RC')
	os.unsetenv('HORNERO_SMART_COLORS_BIN')
	os.unsetenv('HORNERO_M3_COLORS_BIN')
	os.unsetenv('HORNERO_NIGHT_MODE_BIN')
	os.unsetenv('HORNERO_ACCENT_OVERRIDE_BIN')
}

fn ap_argv_log() string {
	return os.read_file('${ap_root}/argv.log') or { '' }
}

fn test_plus_resolvers_prefer_env() {
	os.setenv('HORNERO_SMART_COLORS_BIN', '/override/dots-smart-colors', true)
	assert resolve_smart_colors_bin() == '/override/dots-smart-colors'
	os.setenv('HORNERO_M3_COLORS_BIN', '/override/dots-m3-colors', true)
	assert resolve_m3_colors_bin() == '/override/dots-m3-colors'
	os.setenv('HORNERO_NIGHT_MODE_BIN', '/override/dots-night-mode', true)
	assert resolve_night_mode_bin() == '/override/dots-night-mode'
	os.setenv('HORNERO_ACCENT_OVERRIDE_BIN', '/override/dots-accent-override', true)
	assert resolve_accent_override_bin() == '/override/dots-accent-override'
	ap_teardown()
}

fn ap_clear_log() {
	os.rm('${ap_root}/argv.log') or {}
}

fn test_colors_status_dry_run_needs_no_backend() {
	ap_clear_log()
	r := colors_report(ColorsOptions{
		action:  'status'
		helper:  '/nonexistent-colors-hornero-test'
		dry_run: true
	})
	assert r.ok, r.message
	assert r.command == 'appearance colors status'
	assert r.data['dry_run'] == 'true'
	assert r.message.contains('/nonexistent-colors-hornero-test')
	assert ap_argv_log() == ''
}

fn test_colors_generate_needs_yes() {
	ap_clear_log()
	refused := colors_report(ColorsOptions{
		action: 'generate'
		helper: '/nonexistent-colors-hornero-test'
	})
	assert !refused.ok
	assert refused.message.contains('--yes')
	assert ap_argv_log() == ''
}

fn test_colors_generate_dry_run_carries_m3() {
	ap_clear_log()
	r := colors_report(ColorsOptions{
		action:  'generate'
		m3:      true
		helper:  '/nonexistent-colors-hornero-test'
		dry_run: true
	})
	assert r.ok, r.message
	assert r.message.contains('--generate')
	assert r.message.contains('--m3')
	assert ap_argv_log() == ''
}

fn test_colors_m3_needs_call_and_yes() {
	ap_clear_log()
	empty := colors_report(ColorsOptions{
		action:    'm3'
		m3_helper: '/nonexistent-m3-hornero-test'
		yes:       true
	})
	assert !empty.ok
	assert empty.message.contains('--help')
	refused := colors_report(ColorsOptions{
		action:    'm3'
		call:      ['--help']
		m3_helper: '/nonexistent-m3-hornero-test'
	})
	assert !refused.ok
	assert refused.message.contains('--yes')
	assert ap_argv_log() == ''
}

fn test_colors_unknown_action() {
	r := colors_report(ColorsOptions{
		action: 'bogus'
	})
	assert !r.ok
	assert r.message.contains('unknown action')
}

fn test_accent_show_dry_run_needs_no_backend() {
	ap_clear_log()
	r := accent_report(AccentOptions{
		action:  'show'
		helper:  '/nonexistent-accent-hornero-test'
		dry_run: true
	})
	assert r.ok, r.message
	assert r.command == 'appearance accent show'
	assert r.message.contains('--show')
	assert ap_argv_log() == ''
}

fn test_accent_set_validates_hex() {
	ap_clear_log()
	bad := accent_report(AccentOptions{
		action:  'set'
		value:   'not-a-color'
		helper:  '/nonexistent-accent-hornero-test'
		dry_run: true
	})
	assert !bad.ok
	assert bad.message.contains('#RRGGBB')
	short := accent_report(AccentOptions{
		action:  'set'
		value:   '#12345'
		helper:  '/nonexistent-accent-hornero-test'
		dry_run: true
	})
	assert !short.ok
	ok_hash := accent_report(AccentOptions{
		action:  'set'
		value:   '#8839ef'
		helper:  '/nonexistent-accent-hornero-test'
		dry_run: true
	})
	assert ok_hash.ok, ok_hash.message
	assert ok_hash.message.contains('#8839ef')
	ok_bare := accent_report(AccentOptions{
		action:  'set'
		value:   '8839EF'
		helper:  '/nonexistent-accent-hornero-test'
		dry_run: true
	})
	assert ok_bare.ok, ok_bare.message
	assert ap_argv_log() == ''
}

fn test_accent_set_and_clear_need_yes() {
	ap_clear_log()
	refused_set := accent_report(AccentOptions{
		action: 'set'
		value:  '#8839ef'
		helper: '/nonexistent-accent-hornero-test'
	})
	assert !refused_set.ok
	assert refused_set.message.contains('--yes')
	refused_clear := accent_report(AccentOptions{
		action: 'clear'
		helper: '/nonexistent-accent-hornero-test'
	})
	assert !refused_clear.ok
	assert refused_clear.message.contains('--yes')
	assert ap_argv_log() == ''
}

fn test_accent_unknown_action() {
	r := accent_report(AccentOptions{
		action: 'bogus'
	})
	assert !r.ok
	assert r.message.contains('unknown action')
}

fn test_night_mode_status_dry_run_needs_no_backend() {
	ap_clear_log()
	r := night_mode_report(NightModeOptions{
		action:  'status'
		helper:  '/nonexistent-night-hornero-test'
		dry_run: true
	})
	assert r.ok, r.message
	assert r.command == 'appearance night-mode status'
	assert r.message.contains('status')
	assert ap_argv_log() == ''
}

fn test_night_mode_unknown_action() {
	r := night_mode_report(NightModeOptions{
		action: 'toggle'
	})
	assert !r.ok
	assert r.message.contains('unknown action')
}

fn test_delegated_run_sets_guard_and_passes_output() {
	ap_setup_stub('dots-smart-colors')
	r := colors_report(ColorsOptions{
		action: 'status'
		helper: '${ap_root}/bin/dots-smart-colors'
	})
	assert r.ok, r.message
	assert r.message.contains('stub-output')
	ap_teardown()
}

fn test_delegated_run_reports_backend_failure() {
	ap_setup_stub('dots-night-mode')
	os.setenv('HX_OUTPUT', 'boom', true)
	os.setenv('HX_RC', '3', true)
	r := night_mode_report(NightModeOptions{
		action: 'status'
		helper: '${ap_root}/bin/dots-night-mode'
	})
	assert !r.ok
	assert r.message.contains('backend failed (exit 3)')
	assert r.message.contains('boom')
	ap_teardown()
}

fn test_accent_set_real_run_passes_value() {
	ap_setup_stub('dots-accent-override')
	r := accent_report(AccentOptions{
		action: 'set'
		value:  '#8839ef'
		helper: '${ap_root}/bin/dots-accent-override'
		yes:    true
	})
	assert r.ok, r.message
	assert ap_argv_log().contains('#8839ef')
	ap_teardown()
}

fn test_colors_generate_real_run_passes_flags() {
	ap_setup_stub('dots-smart-colors')
	r := colors_report(ColorsOptions{
		action: 'generate'
		m3:     true
		helper: '${ap_root}/bin/dots-smart-colors'
		yes:    true
	})
	assert r.ok, r.message
	log := ap_argv_log()
	assert log.contains('--generate')
	assert log.contains('--m3')
	ap_teardown()
}
