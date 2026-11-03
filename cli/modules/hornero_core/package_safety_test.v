module hornero_core

import os

fn test_parse_df_available_kb() {
	out := 'Filesystem     1024-blocks    Used Available Capacity Mounted on\n/dev/sda2        102760448 69632000  27852800      72% /\n'
	assert parse_df_available_kb(out) == 27852800
	assert parse_df_available_kb('') == -1
	assert parse_df_available_kb('Filesystem only') == -1
	assert parse_df_available_kb('h\nshort') == -1
}

fn test_update_history_line_is_stable_json() {
	line := update_history_line(1793739291, '2026-11-03T12:00:00Z', 'upgrade', true,
		'pkexec /usr/bin/pacman -Syu')
	assert line == '{"at_unix":1793739291,"at":"2026-11-03T12:00:00Z","action":"upgrade","ok":true,"command":"pkexec /usr/bin/pacman -Syu"}'
	escaped := update_history_line(1, 'x', 'up"grade', false, 'a\\b')
	assert escaped.contains('up\\"grade')
	assert escaped.contains('a\\\\b')
}

fn test_reboot_required_detects_missing_modules() {
	root := os.join_path(os.temp_dir(), 'hornero-reboot-test-${os.getpid()}')
	os.mkdir_all(os.join_path(root, 'modules', '6.12.1-arch1-1'))!
	release_file := os.join_path(root, 'osrelease')
	os.write_file(release_file, '6.12.1-arch1-1\n')!
	os.setenv('HORNERO_KERNEL_RELEASE_FILE', release_file, true)
	os.setenv('HORNERO_MODULES_ROOT', os.join_path(root, 'modules'), true)
	defer {
		os.rmdir_all(root) or {}
	}
	needs, _ := reboot_required()
	assert needs == false
	os.write_file(release_file, '6.11.9-arch1-1\n')!
	needs2, reason := reboot_required()
	assert needs2 == true
	assert reason.contains('6.11.9-arch1-1')
	assert reason.contains('reboot')
}

fn test_upgrade_history_round_trip() {
	root := os.join_path(os.temp_dir(), 'hornero-history-test-${os.getpid()}')
	os.mkdir_all(root)!
	path := os.join_path(root, 'update-history.jsonl')
	os.setenv('HORNERO_UPDATE_HISTORY', path, true)
	defer {
		os.rmdir_all(root) or {}
	}
	report := package_history_report()
	assert report.data['entries'] or { '' } == '0'
	record_update_history('upgrade', true, 'pkexec /usr/bin/pacman -Syu')
	record_update_history('upgrade', false, 'pkexec /usr/bin/pacman -Syu')
	lines := read_update_history(20)
	assert lines.len == 2
	assert lines[0].contains('"ok":false') // newest first
	assert lines[1].contains('"ok":true')
	report2 := package_history_report()
	assert report2.data['entries'] or { '' } == '2'
}

fn test_preflight_blocks_on_pacman_lock() {
	root := os.join_path(os.temp_dir(), 'hornero-preflight-test-${os.getpid()}')
	os.mkdir_all(root)!
	lock_path := os.join_path(root, 'db.lck')
	os.write_file(lock_path, '')!
	os.setenv('HORNERO_PACMAN_LOCK', lock_path, true)
	defer {
		os.rmdir_all(root) or {}
	}
	blocker := upgrade_preflight_blocker()
	assert blocker.contains('pacman database is locked')
	os.rm(lock_path)!
	// No lock: blocker may still trigger on a genuinely full disk in CI,
	// but it must not be the lock reason anymore.
	assert !upgrade_preflight_blocker().contains('locked')
}
