module hornero_cli

import os

// Apps dispatch fixtures break every backend override; each test sets
// what it needs and restores afterwards. Dry-run previews must pass
// with no backends installed (CI hermeticity).
fn apps_dispatch_setup() {
	os.setenv('HORNERO_FILE_MANAGER_BIN', '/nonexistent-fm-hornero-test', true)
	os.setenv('HORNERO_EXO_OPEN_BIN', '/nonexistent-exo-hornero-test', true)
	os.setenv('HORNERO_HANDLR_BIN', '/nonexistent-handlr-hornero-test', true)
	os.setenv('HORNERO_XDG_OPEN_BIN', '/nonexistent-xdg-open-hornero-test', true)
	os.setenv('HORNERO_DOTS_YAZI_BIN', '/nonexistent-dots-yazi-hornero-test', true)
	os.setenv('HORNERO_YAZI_BIN', '/nonexistent-yazi-hornero-test', true)
	os.setenv('HORNERO_GIT_NOTIFY_BIN', '/nonexistent-git-notify-hornero-test', true)
	os.setenv('HORNERO_SNAPPY_BIN', '/nonexistent-snappy-hornero-test', true)
	os.setenv('HORNERO_POWERPROFILESCTL_BIN', '/nonexistent-ppctl-hornero-test', true)
}

fn apps_dispatch_teardown() {
	os.unsetenv('HORNERO_FILE_MANAGER_BIN')
	os.unsetenv('HORNERO_EXO_OPEN_BIN')
	os.unsetenv('HORNERO_HANDLR_BIN')
	os.unsetenv('HORNERO_XDG_OPEN_BIN')
	os.unsetenv('HORNERO_DOTS_YAZI_BIN')
	os.unsetenv('HORNERO_YAZI_BIN')
	os.unsetenv('HORNERO_GIT_NOTIFY_BIN')
	os.unsetenv('HORNERO_SNAPPY_BIN')
	os.unsetenv('HORNERO_POWERPROFILESCTL_BIN')
}

fn test_dispatch_apps_reads_dry_run() {
	apps_dispatch_setup()
	assert dispatch(['horneroctl', 'apps', 'files', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'apps', 'files', '--info', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'apps', 'terminal-file', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'apps', 'terminal-file', '--cheatsheet', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'apps', 'terminal-file', '--fix-previews', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'apps', 'weather', '--temp', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'apps', 'weather', '--getdata', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'apps', 'git-status', 'jobs', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'apps', 'git-status', 'watch', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'apps', 'git-status', 'stop', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'apps', 'audit', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'apps', 'audit', '--permissions', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'apps', 'audit', '--fix', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'apps', 'audit', '--report', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'apps', 'audit', '--fix']) == 1
	assert dispatch(['horneroctl', 'apps', 'launch', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'apps', 'launch', '--list', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'apps', 'toggle', 'bar', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'apps', 'toggle', 'caffeine', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'apps', 'switcher', 'status', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'apps', 'switcher', 'next', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'apps', 'switcher', 'apply-theme', 'nord.ini', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'apps', 'performance', 'memory', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'apps', 'performance', 'startup', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'apps', 'performance', 'mode', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'apps', 'performance', 'mode', 'set', 'balanced', '--dry-run']) == 0
	apps_dispatch_teardown()
}

fn test_dispatch_apps_files_open_live() {
	apps_dispatch_setup()
	os.mkdir_all('/tmp/hx-apps-dtest/bin') or { assert false }
	os.write_file('/tmp/hx-apps-dtest/bin/exo-open', '#!/bin/sh\necho "exo-open \$*"\nexit 0\n') or {
		assert false
	}
	os.chmod('/tmp/hx-apps-dtest/bin/exo-open', 0o755) or { assert false }
	os.setenv('HORNERO_EXO_OPEN_BIN', '/tmp/hx-apps-dtest/bin/exo-open', true)
	// The exact calls dots-file-manager delegates to (open needs no
	// --yes; the launch itself is the action).
	assert dispatch(['horneroctl', 'apps', 'files']) == 0
	assert dispatch(['horneroctl', 'apps', 'files', '--path', '/tmp']) == 0
	apps_dispatch_teardown()
}

fn test_dispatch_apps_mutations_need_yes() {
	apps_dispatch_setup()
	assert dispatch(['horneroctl', 'apps', 'toggle', 'bar']) == 1
	assert dispatch(['horneroctl', 'apps', 'toggle', 'redshift']) == 1
	assert dispatch(['horneroctl', 'apps', 'switcher', 'next']) == 1
	assert dispatch(['horneroctl', 'apps', 'switcher']) == 1
	assert dispatch(['horneroctl', 'apps', 'git-status', 'watch']) == 1
	assert dispatch(['horneroctl', 'apps', 'git-status', 'stop']) == 1
	assert dispatch(['horneroctl', 'apps', 'performance', 'mode', 'set', 'balanced']) == 1
	apps_dispatch_teardown()
}

fn test_dispatch_apps_usage_errors() {
	apps_dispatch_setup()
	assert dispatch(['horneroctl', 'apps']) == 2
	assert dispatch(['horneroctl', 'apps', 'bogus']) == 2
	assert dispatch(['horneroctl', 'apps', 'files', '--bogus']) == 2
	assert dispatch(['horneroctl', 'apps', 'files', 'extra']) == 2
	assert dispatch(['horneroctl', 'apps', 'weather']) == 2
	assert dispatch(['horneroctl', 'apps', 'weather', '--temp', '--icon']) == 2
	assert dispatch(['horneroctl', 'apps', 'weather', '--bogus']) == 2
	assert dispatch(['horneroctl', 'apps', 'git-status', 'bogus']) == 2
	assert dispatch(['horneroctl', 'apps', 'git-status', 'jobs', '--async']) == 2
	assert dispatch(['horneroctl', 'apps', 'git-status', 'watch', '--interval', 'soon']) == 2
	assert dispatch(['horneroctl', 'apps', 'audit', '--permissions', '--system']) == 2
	assert dispatch(['horneroctl', 'apps', 'audit', '--fix', '--report']) == 2
	assert dispatch(['horneroctl', 'apps', 'launch', '--backend', 'bogus']) == 2
	assert dispatch(['horneroctl', 'apps', 'launch', '--list', '--backend', 'minimal']) == 2
	assert dispatch(['horneroctl', 'apps', 'toggle']) == 2
	assert dispatch(['horneroctl', 'apps', 'toggle', 'bogus']) == 2
	assert dispatch(['horneroctl', 'apps', 'switcher', 'bogus']) == 2
	assert dispatch(['horneroctl', 'apps', 'switcher', 'apply-theme']) == 2
	assert dispatch(['horneroctl', 'apps', 'switcher', 'status', '--yes']) == 2
	assert dispatch(['horneroctl', 'apps', 'performance']) == 2
	assert dispatch(['horneroctl', 'apps', 'performance', 'bogus']) == 2
	assert dispatch(['horneroctl', 'apps', 'performance', 'mode', 'set']) == 2
	assert dispatch(['horneroctl', 'apps', 'performance', 'memory', '--yes']) == 2
	assert dispatch(['horneroctl', 'apps', 'performance', 'mode', '--yes']) == 2
	assert dispatch(['horneroctl', 'apps', '--help']) == 0
	assert dispatch(['horneroctl', 'apps', 'files', '--help']) == 0
	apps_dispatch_teardown()
}

fn test_dispatch_apps_performance_mode_set_live() {
	apps_dispatch_setup()
	os.mkdir_all('/tmp/hx-apps-dtest-ppctl') or { assert false }
	os.write_file('/tmp/hx-apps-dtest-ppctl/powerprofilesctl', '#!/bin/sh\nif [ "$1" = "list" ]; then printf "* balanced:\n    CpuDriver: amd_pstate\n  power-saver:\n    CpuDriver: amd_pstate\n"; exit 0; fi\nif [ "$1" = "get" ]; then echo "balanced"; exit 0; fi\necho "set $*"\nexit 0\n') or {
		assert false
	}
	os.chmod('/tmp/hx-apps-dtest-ppctl/powerprofilesctl', 0o755) or { assert false }
	os.setenv('HORNERO_POWERPROFILESCTL_BIN', '/tmp/hx-apps-dtest-ppctl/powerprofilesctl',
		true)
	// The exact call dots-performance-mode delegates to after a menu pick.
	assert dispatch(['horneroctl', 'apps', 'performance', 'mode', 'set', 'power-saver', '--yes']) == 0
	assert dispatch(['horneroctl', 'apps', 'performance', 'mode', 'set', 'bogus-profile', '--yes']) == 1
	apps_dispatch_teardown()
}

fn test_apps_help_carries_performance_mode_probe() {
	// dots-performance-mode delegates only when `apps --help` contains
	// this usage line; pin it so the probe can never silently break.
	assert command_help('apps').contains('Usage: horneroctl apps')
}

fn test_apps_help_has_examples() {
	for cmd in ['apps', 'apps files', 'apps terminal-file', 'apps weather', 'apps git-status',
		'apps audit', 'apps launch', 'apps toggle', 'apps switcher', 'apps performance'] {
		h := command_help(cmd)
		assert h.contains('Examples:')
	}
}

fn test_dispatch_apps_json_and_quiet_modes() {
	apps_dispatch_setup()
	assert dispatch(['horneroctl', '--json', 'apps', 'audit', '--dry-run']) == 0
	assert dispatch(['horneroctl', '--quiet', 'apps', 'audit', '--dry-run']) == 0
	assert dispatch(['horneroctl', '--json', 'apps', 'switcher', 'status', '--dry-run']) == 0
	assert dispatch(['horneroctl', '--quiet', 'apps', 'toggle', 'bar', '--dry-run']) == 0
	assert dispatch(['horneroctl', '--json', 'apps', 'performance', 'mode', '--dry-run']) == 0
	apps_dispatch_teardown()
}

fn test_dispatch_apps_git_watch_flags_preview() {
	apps_dispatch_setup()
	assert dispatch(['horneroctl', 'apps', 'git-status', 'watch', '--branch', 'origin/main',
		'--interval', '30', '--async', '--verbose', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'apps', 'git-status', '--branch', 'origin/main', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'apps', 'terminal-file', '--path', '/tmp', '--select', '/tmp/x',
		'--last-dir', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'apps', 'files', '--path', '/tmp', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'apps', 'launch', '--backend', 'quickshell', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'apps', 'switcher', 'apply-theme-pack', 'nord', '--dry-run']) == 0
	apps_dispatch_teardown()
}
