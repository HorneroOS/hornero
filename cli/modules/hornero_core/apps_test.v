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
	'HORNERO_XDG_OPEN_BIN', 'HORNERO_YAZI_HELPER_BIN', 'HORNERO_YAZI_BIN', 'HORNERO_GIT_NOTIFY_BIN',
	'HORNERO_SNAPPY_BIN', 'HORNERO_SNAPPY_SWITCHER_BIN', 'HORNERO_PIDOF_BIN', 'HORNERO_PGREP_BIN',
	'HORNERO_KILLALL_BIN', 'HORNERO_PKILL_BIN', 'HORNERO_QUICKSHELL_BIN', 'HORNERO_REDSHIFT_BIN',
	'HORNERO_CAFFEINE_BIN', 'XDG_CONFIG_HOME', 'HORNERO_BYPASS_QUICKSHELL', 'PATH',
	'HORNERO_POWERPROFILESCTL_BIN']

fn apps_test_break_backends() {
	os.setenv('HORNERO_FILE_MANAGER_BIN', '/nonexistent-fm-hornero-test', true)
	os.setenv('HORNERO_EXO_OPEN_BIN', '/nonexistent-exo-hornero-test', true)
	os.setenv('HORNERO_HANDLR_BIN', '/nonexistent-handlr-hornero-test', true)
	os.setenv('HORNERO_XDG_OPEN_BIN', '/nonexistent-xdg-open-hornero-test', true)
	os.setenv('HORNERO_YAZI_HELPER_BIN', '/nonexistent-hornero-yazi-hornero-test', true)
	os.setenv('HORNERO_YAZI_BIN', '/nonexistent-yazi-hornero-test', true)
	os.setenv('HORNERO_GIT_NOTIFY_BIN', '/nonexistent-git-notify-hornero-test', true)
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
	// hornero-yazi; they must work with every backend broken.
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
	// pkill/killall seams; horneroctl apps toggle is never consulted.
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
	// closed without touching horneroctl apps toggle.
	saved := apps_test_save_env(apps_test_keys)
	apps_test_break_backends()
	os.setenv('HORNERO_QUICKSHELL_BIN', '/nonexistent-qs-hornero-test', true)
	r := toggle_report(ToggleOptions{ component: 'bar', yes: true })
	assert !r.ok
	apps_test_restore_env(saved)
}

fn test_apps_launch_native_list() {
	// Native port: --list always ends with minimal and keeps priority
	// order; no horneroctl apps launch involved.
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
	// HORNERO_BYPASS_QUICKSHELL=1 skips the quickshell attempt hermetically:
	// explicit quickshell fails closed, never touching stdin.
	saved := apps_test_save_env(apps_test_keys)
	apps_test_break_backends()
	os.setenv('HORNERO_BYPASS_QUICKSHELL', '1', true)
	r := launch_report(LaunchOptions{ backend: 'quickshell' })
	assert !r.ok
	assert r.message.contains('not running')
	os.unsetenv('HORNERO_BYPASS_QUICKSHELL')
	apps_test_restore_env(saved)
}

fn test_apps_switcher_status_native() {
	// Native port: status answers from the pgrep seam alone.
	saved := apps_test_save_env(apps_test_keys)
	apps_test_break_backends()
	os.setenv('HORNERO_PGREP_BIN', '/bin/false', true)
	r := switcher_report(SwitcherOptions{ leaf: 'status' })
	assert r.ok
	assert r.message.contains('not running')
	os.setenv('HORNERO_PGREP_BIN', '/bin/true', true)
	r2 := switcher_report(SwitcherOptions{ leaf: 'status' })
	assert r2.ok
	assert r2.message.contains('snappy-switcher daemon: running')
	apps_test_restore_env(saved)
}

fn test_apps_switcher_control_native() {
	// Native port: control verbs run the snappy-switcher binary
	// directly; missing binary fails closed with the install hint.
	saved := apps_test_save_env(apps_test_keys)
	apps_test_break_backends()
	os.setenv('HORNERO_SNAPPY_SWITCHER_BIN', '/nonexistent-snappy-hornero-test', true)
	r := switcher_report(SwitcherOptions{ leaf: 'next', yes: true })
	assert !r.ok
	assert r.message.contains('not installed')
	os.setenv('HORNERO_SNAPPY_SWITCHER_BIN', '/bin/true', true)
	r2 := switcher_report(SwitcherOptions{ leaf: 'toggle', yes: true })
	assert r2.ok
	apps_test_restore_env(saved)
}

fn test_apps_dry_run_uses_native_contract() {
	saved := apps_test_save_env(apps_test_keys)
	apps_test_break_backends()
	r := audit_report(AuditOptions{ check: 'full', dry_run: true })
	assert r.ok
	assert !r.message.contains('HORNEROCTL_INTERNAL_CALL')
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

fn test_files_info_native_needs_no_external_helper() {
	// Native port: --info reads handlr + .desktop files directly; the
	// The file-information command reads installed desktop metadata (a fake desktop id proves
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

fn test_apps_audit_dry_run_keeps_delegation_preview() {
	// Dry-run previews the optional helper but must never execute it.
	saved := apps_test_save_env(apps_test_keys)
	base := '/tmp/hx-apps-test/bin2'
	os.mkdir_all(base) or { assert false }
	marker := base + '/audit-ran'
	helper := base + '/hornero-security-audit'
	os.write_file(helper, '#!/bin/sh\nprintf ran > ' + marker + '\nexit 0\n') or { assert false }
	os.chmod(helper, 0o755) or { assert false }
	os.setenv('PATH', base, true)
	r := audit_report(AuditOptions{ check: 'system', dry_run: true })
	assert r.ok
	assert r.message.contains('hornero-security-audit')
	assert r.message.contains('--system')
	assert !os.exists(marker)
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
	// Live set through the fixture backend (the horneroctl apps performance mode
	// delegation path): validates the profile, then runs powerprofilesctl.
	set := performance_report(PerformanceOptions{
		leaf:    'mode'
		sub:     'set'
		profile: 'power-saver'
		yes:     true
	})
	assert set.ok
	assert set.data['profile'] == 'power-saver'
	apps_test_restore_env(saved)
}

fn test_apps_resolvers_prefer_env() {
	saved := apps_test_save_env(apps_test_keys)
	os.setenv('HORNERO_SNAPPY_BIN', '/tmp/custom-snappy', true)
	assert resolve_hornero_snappy_bin() == '/tmp/custom-snappy'
	os.setenv('HORNERO_POWERPROFILESCTL_BIN', '/tmp/custom-ppctl', true)
	assert resolve_powerprofilesctl_bin() == '/tmp/custom-ppctl'
	apps_test_restore_env(saved)
}
