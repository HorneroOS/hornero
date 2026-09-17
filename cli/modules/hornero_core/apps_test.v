module hornero_core

import os
import time

fn apps_test_save_env(keys []string) map[string]string {
	mut saved := map[string]string{}
	for k in keys {
		saved[k] = os.getenv(k)
	}
	return saved
}

fn apps_test_restore_env(saved map[string]string) {
	for k, v in saved {
		if v.len == 0 {
			os.unsetenv(k)
		} else {
			os.setenv(k, v, true)
		}
	}
}

const apps_test_keys = ['HORNERO_FILE_MANAGER_BIN', 'HORNERO_EXO_OPEN_BIN', 'HORNERO_HANDLR_BIN',
	'HORNERO_XDG_OPEN_BIN', 'HORNERO_DOTS_YAZI_BIN', 'HORNERO_YAZI_BIN', 'HORNERO_GIT_NOTIFY_BIN',
	'HORNERO_SECURITY_AUDIT_BIN', 'HORNERO_SNAPPY_BIN', 'HORNERO_PIDOF_BIN', 'HORNERO_KILLALL_BIN',
	'HORNERO_PKILL_BIN', 'HORNERO_QUICKSHELL_BIN', 'HORNERO_REDSHIFT_BIN', 'HORNERO_CAFFEINE_BIN',
	'HORNERO_WEATHER_CACHE_DIR', 'HORNERO_WEATHER_GEO_URL', 'HORNERO_WEATHER_API_URL', 'WEATHER_API_KEY',
	'XDG_CONFIG_HOME', 'DOTS_BYPASS_QUICKSHELL', 'HORNERO_POWERPROFILESCTL_BIN']

fn apps_test_break_backends() {
	os.setenv('HORNERO_FILE_MANAGER_BIN', '/nonexistent-fm-hornero-test', true)
	os.setenv('HORNERO_EXO_OPEN_BIN', '/nonexistent-exo-hornero-test', true)
	os.setenv('HORNERO_HANDLR_BIN', '/nonexistent-handlr-hornero-test', true)
	os.setenv('HORNERO_XDG_OPEN_BIN', '/nonexistent-xdg-open-hornero-test', true)
	os.setenv('HORNERO_DOTS_YAZI_BIN', '/nonexistent-dots-yazi-hornero-test', true)
	os.setenv('HORNERO_YAZI_BIN', '/nonexistent-yazi-hornero-test', true)
	os.setenv('HORNERO_GIT_NOTIFY_BIN', '/nonexistent-git-notify-hornero-test', true)
	os.setenv('HORNERO_SECURITY_AUDIT_BIN', '/nonexistent-audit-hornero-test', true)
	os.setenv('HORNERO_SNAPPY_BIN', '/nonexistent-snappy-hornero-test', true)
	os.setenv('HORNERO_POWERPROFILESCTL_BIN', '/nonexistent-ppctl-hornero-test', true)
}

fn test_apps_dry_run_needs_no_backend() {
	saved := apps_test_save_env(apps_test_keys)
	apps_test_break_backends()
	assert files_report(FilesOptions{ dry_run: true }).ok
	assert files_report(FilesOptions{ info: true, dry_run: true }).ok
	assert terminal_file_report(TerminalFileOptions{ dry_run: true }).ok
	assert terminal_file_report(TerminalFileOptions{ cheatsheet: true, dry_run: true }).ok
	assert terminal_file_report(TerminalFileOptions{ fix_previews: true, dry_run: true }).ok
	assert weather_report(WeatherOptions{ field: 'temp', dry_run: true }).ok
	assert weather_report(WeatherOptions{ field: 'getdata', dry_run: true }).ok
	assert git_status_report(GitStatusOptions{ leaf: 'jobs', dry_run: true }).ok
	assert git_status_report(GitStatusOptions{ leaf: 'watch', dry_run: true }).ok
	assert git_status_report(GitStatusOptions{ leaf: 'stop', dry_run: true }).ok
	assert audit_report(AuditOptions{ check: 'full', dry_run: true }).ok
	assert audit_report(AuditOptions{ check: 'permissions', dry_run: true }).ok
	assert launch_report(LaunchOptions{ dry_run: true }).ok
	assert launch_report(LaunchOptions{ list: true, dry_run: true }).ok
	assert toggle_report(ToggleOptions{ component: 'bar', dry_run: true }).ok
	assert toggle_report(ToggleOptions{ component: 'caffeine', dry_run: true }).ok
	assert switcher_report(SwitcherOptions{ leaf: 'status', dry_run: true }).ok
	assert switcher_report(SwitcherOptions{ leaf: 'next', dry_run: true }).ok
	assert switcher_report(SwitcherOptions{
		leaf:    'apply-theme'
		arg:     'nord.ini'
		dry_run: true
	}).ok
	assert performance_report(PerformanceOptions{ leaf: 'memory', dry_run: true }).ok
	assert performance_report(PerformanceOptions{ leaf: 'mode', dry_run: true }).ok
	assert performance_report(PerformanceOptions{
		leaf:    'mode'
		sub:     'set'
		profile: 'balanced'
		dry_run: true
	}).ok
	apps_test_restore_env(saved)
}

fn test_terminal_cheatsheet_native_needs_no_backend() {
	// Native port: cheatsheet and fix-previews no longer shell out to
	// dots-yazi; they must work with every backend broken.
	saved := apps_test_save_env(apps_test_keys)
	apps_test_break_backends()
	c := terminal_file_report(TerminalFileOptions{ cheatsheet: true })
	assert c.ok
	assert c.message.contains('YAZI CHEATSHEET')
	p := terminal_file_report(TerminalFileOptions{ fix_previews: true })
	assert p.ok
	assert p.message.contains('Yazi Preview Diagnostics')
	apps_test_restore_env(saved)
}

fn test_apps_toggle_native_daemon_stop() {
	// Native port: a running daemon (pidof=true fixture) stops via the
	// pkill/killall seams; dots-toggle is never consulted.
	saved := apps_test_save_env(apps_test_keys)
	apps_test_break_backends()
	os.setenv('HORNERO_PIDOF_BIN', '/bin/true', true)
	os.setenv('HORNERO_PKILL_BIN', '/bin/true', true)
	os.setenv('HORNERO_KILLALL_BIN', '/bin/true', true)
	r := toggle_report(ToggleOptions{ component: 'redshift', yes: true })
	assert r.ok
	assert r.message.contains('stopped redshift')
	r2 := toggle_report(ToggleOptions{ component: 'caffeine', yes: true })
	assert r2.ok
	assert r2.message.contains('stopped caffeine')
	apps_test_restore_env(saved)
}

fn test_apps_toggle_native_daemon_start() {
	// Stopped daemon (pidof=false fixture) starts detached via the leaf
	// seam; /bin/true keeps the start harmless. Detached spawn mirrors
	// bash `&` (launch reports ok; failures are async), so the
	// missing-leaf branch only triggers when nothing resolves.
	saved := apps_test_save_env(apps_test_keys)
	apps_test_break_backends()
	os.setenv('HORNERO_PIDOF_BIN', '/bin/false', true)
	os.setenv('HORNERO_REDSHIFT_BIN', '/bin/true', true)
	r := toggle_report(ToggleOptions{ component: 'redshift', yes: true })
	assert r.ok
	assert r.message.contains('started redshift')
	apps_test_restore_env(saved)
}

fn test_apps_toggle_native_quickshell_fails_closed() {
	// Quickshell branch with an unresolvable quickshell binary fails
	// closed without touching dots-toggle.
	saved := apps_test_save_env(apps_test_keys)
	apps_test_break_backends()
	os.setenv('HORNERO_QUICKSHELL_BIN', '/nonexistent-qs-hornero-test', true)
	r := toggle_report(ToggleOptions{ component: 'bar', yes: true })
	assert !r.ok
	apps_test_restore_env(saved)
}

fn test_apps_launch_native_list() {
	// Native port: --list always ends with minimal and keeps priority
	// order; no dots-launcher involved.
	saved := apps_test_save_env(apps_test_keys)
	apps_test_break_backends()
	os.setenv('HORNERO_QUICKSHELL_BIN', '/bin/true', true)
	r := launch_report(LaunchOptions{ list: true })
	assert r.ok
	assert r.message.contains('minimal')
	qi := r.message.index('quickshell') or { -1 }
	mi := r.message.index('minimal') or { -1 }
	assert qi >= 0 && qi < mi
	apps_test_restore_env(saved)
}

fn test_apps_launch_native_quickshell_bypass_fails_closed() {
	// DOTS_BYPASS_QUICKSHELL=1 skips the quickshell attempt hermetically:
	// explicit quickshell fails closed, never touching stdin.
	saved := apps_test_save_env(apps_test_keys)
	apps_test_break_backends()
	os.setenv('DOTS_BYPASS_QUICKSHELL', '1', true)
	r := launch_report(LaunchOptions{ backend: 'quickshell' })
	assert !r.ok
	assert r.message.contains('not running')
	os.unsetenv('DOTS_BYPASS_QUICKSHELL')
	apps_test_restore_env(saved)
}

fn test_apps_weather_native_fields_from_seeded_cache() {
	// Native port: field reads serve seeded cache files directly —
	// no wrapper, no key, no network.
	saved := apps_test_save_env(apps_test_keys)
	apps_test_break_backends()
	dir := '/tmp/hx-weather-test-seed'
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { assert false }
	os.setenv('HORNERO_WEATHER_CACHE_DIR', dir, true)
	os.setenv('WEATHER_API_KEY', '', true)
	os.write_file(dir + '/weather-degree', '21°C') or { assert false }
	os.write_file(dir + '/weather-icon', 'ICON') or { assert false }
	os.write_file(dir + '/weather-stat', 'Clear Sky') or { assert false }
	os.write_file(dir + '/weather-location', 'Lima, Lima, Peru') or { assert false }
	os.write_file(dir + '/weather-hex', '#ffd86b') or { assert false }
	os.write_file(dir + '/weather-quote', 'line one\nline two') or { assert false }
	assert weather_report(WeatherOptions{ field: 'temp' }).message == '21°C'
	assert weather_report(WeatherOptions{ field: 'icon' }).message == 'ICON'
	assert weather_report(WeatherOptions{ field: 'stat' }).message == 'Clear Sky'
	assert weather_report(WeatherOptions{ field: 'loc' }).message == 'Lima, Lima, Peru'
	assert weather_report(WeatherOptions{ field: 'hex' }).message == '#ffd86b'
	assert weather_report(WeatherOptions{ field: 'quote' }).message == 'line one'
	assert weather_report(WeatherOptions{ field: 'quote2' }).message == 'line two'
	os.rmdir_all(dir) or {}
	apps_test_restore_env(saved)
}

fn test_apps_weather_native_getdata_serves_fresh_cache() {
	// Fresh cache (current timestamp) is served without any key.
	saved := apps_test_save_env(apps_test_keys)
	apps_test_break_backends()
	dir := '/tmp/hx-weather-test-fresh'
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { assert false }
	os.setenv('HORNERO_WEATHER_CACHE_DIR', dir, true)
	os.setenv('WEATHER_API_KEY', '', true)
	raw := '{"main":{"temp":18.2}}'
	os.write_file(dir + '/weather-raw', raw) or { assert false }
	os.write_file(dir + '/weather-timestamp', '${time.now().unix()}') or { assert false }
	r := weather_report(WeatherOptions{ field: 'getdata' })
	assert r.ok
	assert r.message == raw
	os.rmdir_all(dir) or {}
	apps_test_restore_env(saved)
}

fn test_apps_weather_native_getdata_stale_needs_key() {
	// Stale cache without a key fails closed naming WEATHER_API_KEY.
	saved := apps_test_save_env(apps_test_keys)
	apps_test_break_backends()
	dir := '/tmp/hx-weather-test-stale'
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { assert false }
	os.setenv('HORNERO_WEATHER_CACHE_DIR', dir, true)
	os.setenv('WEATHER_API_KEY', '', true)
	os.setenv('XDG_CONFIG_HOME', '/nonexistent-xdg-hornero-test', true)
	os.write_file(dir + '/weather-raw', '{"stale":true}') or { assert false }
	os.write_file(dir + '/weather-timestamp', '1') or { assert false }
	r := weather_report(WeatherOptions{ field: 'getdata' })
	assert !r.ok
	assert r.message.contains('WEATHER_API_KEY')
	os.rmdir_all(dir) or {}
	apps_test_restore_env(saved)
}

fn test_apps_weather_native_refresh_writes_cache() {
	// Full refresh against fixture files (file:// seam, no network):
	// geo + api JSON flow into the cache files exactly like the script
	// (temp cut, title case, quote lines, location).
	saved := apps_test_save_env(apps_test_keys)
	apps_test_break_backends()
	fix := '/tmp/hx-weather-test-fix'
	os.rmdir_all(fix) or {}
	os.mkdir_all(fix) or { assert false }
	os.write_file(fix + '/geo.json', '{"lat":10.5,"lon":-20.25,"city":"Lima","regionName":"Lima","country":"Peru"}') or {
		assert false
	}
	os.write_file(fix + '/api.json', '{"main":{"temp":21.7},"weather":[{"icon":"01d","description":"clear sky"}]}') or {
		assert false
	}
	dir := '/tmp/hx-weather-test-refresh'
	os.rmdir_all(dir) or {}
	os.setenv('HORNERO_WEATHER_CACHE_DIR', dir, true)
	os.setenv('WEATHER_API_KEY', 'test-key', true)
	os.setenv('HORNERO_WEATHER_GEO_URL', 'file://${fix}/geo.json', true)
	os.setenv('HORNERO_WEATHER_API_URL', 'file://${fix}/api.json', true)
	r := weather_report(WeatherOptions{ field: 'getdata' })
	assert r.ok
	assert r.message.contains('"temp":21.7')
	degree := os.read_file(dir + '/weather-degree') or { '' }
	assert degree == '21°C'
	stat := os.read_file(dir + '/weather-stat') or { '' }
	assert stat == 'Clear Sky'
	loc := os.read_file(dir + '/weather-location') or { '' }
	assert loc == 'Lima, Lima, Peru'
	hex := os.read_file(dir + '/weather-hex') or { '' }
	assert hex == '#ffd86b'
	quote_raw := os.read_file(dir + '/weather-quote') or { '' }
	assert quote_raw.split_into_lines()[0] == "It's a sunny day, gonna be fun! "
	assert weather_report(WeatherOptions{ field: 'quote2' }).message == "Don't go wandering all by yourself though..."
	os.rmdir_all(dir) or {}
	os.rmdir_all(fix) or {}
	apps_test_restore_env(saved)
}

fn test_apps_dry_run_carries_delegation_guard() {
	saved := apps_test_save_env(apps_test_keys)
	apps_test_break_backends()
	r := audit_report(AuditOptions{ check: 'full', dry_run: true })
	assert r.ok
	assert r.message.contains('HORNEROCTL_DELEGATED=1')
	assert r.message.contains('--audit')
	r2 := toggle_report(ToggleOptions{ component: 'redshift', dry_run: true })
	assert r2.ok
	assert r2.message.contains('--redshift')
	assert r2.message.contains('--toggle')
	r3 := switcher_report(SwitcherOptions{
		leaf:    'apply-theme'
		arg:     'nord.ini'
		dry_run: true
	})
	assert r3.ok
	// Strict quoting: the theme file is single-quoted in the preview.
	assert r3.message.contains("'nord.ini'")
	apps_test_restore_env(saved)
}

fn test_apps_mutations_need_yes() {
	saved := apps_test_save_env(apps_test_keys)
	apps_test_break_backends()
	// Reads and view-opens refuse nothing, but real runs fail without
	// backends; mutations without --yes fail closed instead.
	assert !toggle_report(ToggleOptions{ component: 'bar' }).ok
	assert toggle_report(ToggleOptions{ component: 'bar' }).message.contains('--yes')
	assert !switcher_report(SwitcherOptions{ leaf: 'next' }).ok
	assert !git_status_report(GitStatusOptions{ leaf: 'watch' }).ok
	assert !git_status_report(GitStatusOptions{ leaf: 'stop' }).ok
	assert !performance_report(PerformanceOptions{
		leaf:    'mode'
		sub:     'set'
		profile: 'balanced'
	}).ok
	apps_test_restore_env(saved)
}

fn test_apps_invalid_inputs_fail() {
	saved := apps_test_save_env(apps_test_keys)
	apps_test_break_backends()
	assert !weather_report(WeatherOptions{ field: 'bogus', dry_run: true }).ok
	assert !git_status_report(GitStatusOptions{ leaf: 'bogus', dry_run: true }).ok
	assert !audit_report(AuditOptions{ check: 'bogus', dry_run: true }).ok
	assert !launch_report(LaunchOptions{ backend: 'bogus', dry_run: true }).ok
	assert !toggle_report(ToggleOptions{ component: 'bogus', dry_run: true }).ok
	assert !switcher_report(SwitcherOptions{ leaf: 'bogus', dry_run: true }).ok
	assert !switcher_report(SwitcherOptions{ leaf: 'apply-theme', dry_run: true }).ok
	assert !performance_report(PerformanceOptions{ leaf: 'bogus', dry_run: true }).ok
	assert !performance_report(PerformanceOptions{
		leaf:    'mode'
		sub:     'bogus'
		dry_run: true
	}).ok
	assert !performance_report(PerformanceOptions{
		leaf:    'mode'
		sub:     'set'
		dry_run: true
	}).ok
	apps_test_restore_env(saved)
}

fn test_apps_real_run_without_backend_fails() {
	saved := apps_test_save_env(apps_test_keys)
	apps_test_break_backends()
	assert !files_report(FilesOptions{}).ok
	assert !audit_report(AuditOptions{ check: 'full' }).ok
	assert launch_report(LaunchOptions{ list: true }).ok
	// Mode show is a never-fail status read: a missing backend reports
	// unknown instead of failing.
	mode_show := performance_report(PerformanceOptions{ leaf: 'mode' })
	assert mode_show.ok
	assert mode_show.message.contains('unknown')
	apps_test_restore_env(saved)
}

fn test_apps_files_open_chain_prefers_exo() {
	saved := apps_test_save_env(apps_test_keys)
	base := '/tmp/hx-apps-test/bin'
	os.mkdir_all(base) or { assert false }
	os.write_file(base + '/exo-open', '#!/bin/sh\necho "opened \$*"\nexit 0\n') or { assert false }
	os.chmod(base + '/exo-open', 0o755) or { assert false }
	os.setenv('HORNERO_EXO_OPEN_BIN', base + '/exo-open', true)
	os.setenv('HORNERO_HANDLR_BIN', '/nonexistent-handlr-hornero-test', true)
	os.setenv('HORNERO_XDG_OPEN_BIN', '/nonexistent-xdg-open-hornero-test', true)
	r := files_report(FilesOptions{ path: '/tmp', dry_run: true })
	assert r.ok
	assert r.message.contains('exo-open')
	assert r.message.contains('FileManager')
	r2 := files_report(FilesOptions{ path: '/tmp' })
	assert r2.ok
	assert r2.message.contains('opened')
	apps_test_restore_env(saved)
}

fn test_files_info_native_needs_no_dots_backend() {
	// Native port: --info reads handlr + .desktop files directly; the
	// legacy dots-file-manager backend is gone (a fake desktop id proves
	// it: no .desktop file exists for it, and the id is reported).
	saved := apps_test_save_env(apps_test_keys)
	apps_test_break_backends()
	base := '/tmp/hx-apps-info-test/bin'
	os.mkdir_all(base) or { assert false }
	os.write_file(base + '/handlr', '#!/bin/sh\necho "hx-test-fm-12345.desktop"\nexit 0\n') or {
		assert false
	}
	os.chmod(base + '/handlr', 0o755) or { assert false }
	os.setenv('HORNERO_HANDLR_BIN', base + '/handlr', true)
	r := files_report(FilesOptions{ info: true })
	assert r.ok
	assert r.message.contains('File Manager Configuration')
	assert r.message.contains('hx-test-fm-12345.desktop')
	assert r.data['default'] == 'hx-test-fm-12345.desktop'
	apps_test_restore_env(saved)
}

fn test_apps_delegated_success_path() {
	saved := apps_test_save_env(apps_test_keys)
	base := '/tmp/hx-apps-test/bin2'
	os.mkdir_all(base) or { assert false }
	os.write_file(base + '/dots-security-audit', '#!/bin/sh\n[ -n "' + '$' +
		'{HORNEROCTL_DELEGATED}' +
		'" ] || { echo missing delegation guard >&2; exit 3; }\necho "audit ok"\nexit 0\n') or {
		assert false
	}
	os.chmod(base + '/dots-security-audit', 0o755) or { assert false }
	os.setenv('HORNERO_SECURITY_AUDIT_BIN', base + '/dots-security-audit', true)
	r := audit_report(AuditOptions{ check: 'system' })
	assert r.ok
	assert r.message.contains('audit ok')
	assert r.data['command_line'].contains('HORNEROCTL_DELEGATED=1')
	apps_test_restore_env(saved)
}

fn test_apps_performance_mode_set_validates_profile() {
	saved := apps_test_save_env(apps_test_keys)
	base := '/tmp/hx-apps-test/bin3'
	os.mkdir_all(base) or { assert false }
	os.write_file(base + '/powerprofilesctl', '#!/bin/sh\nif [ "\$1" = "list" ]; then printf "* balanced:\\n    CpuDriver: amd_pstate\\n  power-saver:\\n    CpuDriver: amd_pstate\\n"; exit 0; fi\nif [ "\$1" = "get" ]; then echo "balanced"; exit 0; fi\necho "set \$*"\nexit 0\n') or {
		assert false
	}
	os.chmod(base + '/powerprofilesctl', 0o755) or { assert false }
	os.setenv('HORNERO_POWERPROFILESCTL_BIN', base + '/powerprofilesctl', true)
	show := performance_report(PerformanceOptions{ leaf: 'mode' })
	assert show.ok
	assert show.message.contains('balanced')
	assert show.data['available'] == 'balanced,power-saver'
	// Detail rows (CpuDriver: ...) are not profiles.
	assert !show.message.contains('CpuDriver')
	bad := performance_report(PerformanceOptions{
		leaf:    'mode'
		sub:     'set'
		profile: 'bogus-profile'
		yes:     true
	})
	assert !bad.ok
	assert bad.message.contains('unknown profile')
	preview := performance_report(PerformanceOptions{
		leaf:    'mode'
		sub:     'set'
		profile: 'power-saver'
		dry_run: true
	})
	assert preview.ok
	assert preview.message.contains('powerprofilesctl')
	apps_test_restore_env(saved)
}

fn test_apps_resolvers_prefer_env() {
	saved := apps_test_save_env(apps_test_keys)
	os.setenv('HORNERO_SNAPPY_BIN', '/tmp/custom-snappy', true)
	assert resolve_dots_snappy_bin() == '/tmp/custom-snappy'
	os.setenv('HORNERO_POWERPROFILESCTL_BIN', '/tmp/custom-ppctl', true)
	assert resolve_powerprofilesctl_bin() == '/tmp/custom-ppctl'
	apps_test_restore_env(saved)
}
