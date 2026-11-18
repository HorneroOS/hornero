module hornero_core

import os

fn test_assistant_log_line_scrubs_secrets_and_controls() {
	detail := 'api_' + 'key=' + 'hun' + 'ter2 now'
	line := assistant_log_line('2026-10-21T10:00:00', 'approve', 'run_1', detail, 'recorded')
	assert !line.contains('hunter2')
	assert line.count('\t') == 4 // five TSV fields, detail tabs flattened
	assert line.contains('run_1')
	assert line.contains('recorded')
}

fn test_assistant_log_rotate_keeps_newest_within_cap() {
	mut content := ''
	for i in 0 .. 100 {
		content += 'line-${i:03d}-padding-padding-padding\n'
	}
	rotated := assistant_log_rotate_text(content, 200)
	assert rotated.len <= 200
	assert rotated.contains('line-099')
	assert !rotated.contains('line-000\n')
	// Chronological order survives rotation (oldest kept line first).
	kept := rotated.trim_right('\n').split('\n')
	assert kept.last().starts_with('line-099')
	for i in 1 .. kept.len {
		assert kept[i - 1] < kept[i]
	}
	// Under the cap the content is untouched.
	assert assistant_log_rotate_text('a\nb\n', 200) == 'a\nb\n'
}

fn test_assistant_log_filter_lines_matches_case_insensitive() {
	lines := ['a DENY here', 'b ok', 'c deny too']
	assert assistant_log_filter_lines(lines, 'deny').len == 2
	assert assistant_log_filter_lines(lines, '').len == 3
	assert assistant_log_filter_lines(lines, 'missing').len == 0
	assert assistant_log_filter_lines(lines, ' OK ').len == 1
}

fn test_assistant_log_append_report_roundtrip_and_perms() {
	tmp := os.join_path(os.temp_dir(), 'hornero-log-test-${os.getpid()}')
	os.mkdir_all(tmp) or { panic(err) }
	defer { os.rmdir_all(tmp) or {} }
	path := os.join_path(tmp, 'assistant.log')
	old := os.getenv('HORNERO_ASSISTANT_LOG_FILE')
	os.setenv('HORNERO_ASSISTANT_LOG_FILE', path, true)
	defer { os.setenv('HORNERO_ASSISTANT_LOG_FILE', old, true) }

	assistant_log_append('ask', 'run_1', 'finished', 'ok')
	assistant_log_append('approve', 'run_1', 'choice once', 'recorded')
	report := assistant_log_report()
	assert report.ok
	assert report.data['entries'] == '2'
	assert report.data['matched'] == '2'
	filtered := assistant_log_report_filtered('APPROVE')
	assert filtered.data['matched'] == '1'
	assert filtered.message.contains('choice once')
	no_match := assistant_log_report_filtered('no-such-thing')
	assert no_match.data['matched'] == '0'
	assert no_match.message.contains('No assistant activity matches')
	assert report.message.contains('run_1')
	assert report.message.contains('choice once')
	st := os.stat(path) or { panic(err) }
	assert st.mode & 0o077 == 0
}

fn test_assistant_log_append_concurrent_writers_lose_no_lines() {
	// K6: the old read-modify-write dropped lines under concurrency.
	tmp := os.join_path(os.temp_dir(), 'hornero-log-conc-${os.getpid()}')
	os.mkdir_all(tmp) or { panic(err) }
	defer { os.rmdir_all(tmp) or {} }
	path := os.join_path(tmp, 'assistant.log')
	old := os.getenv('HORNERO_ASSISTANT_LOG_FILE')
	os.setenv('HORNERO_ASSISTANT_LOG_FILE', path, true)
	defer { os.setenv('HORNERO_ASSISTANT_LOG_FILE', old, true) }
	mut threads := []thread{}
	for w in 0 .. 8 {
		threads << spawn fn (w int) {
			for i in 0 .. 25 {
				assistant_log_append('ask', 'run_w${w}', 'entry ${i}', 'ok')
			}
		}(w)
	}
	threads.wait()
	lines := (os.read_file(path) or { panic(err) }).split('\n').filter(it.len > 0)
	assert lines.len == 200
	for w in 0 .. 8 {
		for i in 0 .. 25 {
			assert lines.any(it.contains('run_w${w}\tentry ${i}\t')), 'missing w${w} i${i}'
		}
	}
	assert lines.all(it.count('\t') == 4)
	st := os.stat(path) or { panic(err) }
	assert st.mode & 0o077 == 0
}

fn test_assistant_log_append_rotates_under_lock_and_keeps_appending() {
	tmp := os.join_path(os.temp_dir(), 'hornero-log-rot-${os.getpid()}')
	os.mkdir_all(tmp) or { panic(err) }
	defer { os.rmdir_all(tmp) or {} }
	path := os.join_path(tmp, 'assistant.log')
	old := os.getenv('HORNERO_ASSISTANT_LOG_FILE')
	os.setenv('HORNERO_ASSISTANT_LOG_FILE', path, true)
	defer { os.setenv('HORNERO_ASSISTANT_LOG_FILE', old, true) }
	// Pre-fill just over the cap, then append: the file is rotated to
	// within half the cap and the new entry is the last line.
	filler := 'x'.repeat(100)
	mut big := ''
	for big.len <= assistant_log_max_bytes {
		big += '2026-01-01T00:00:00\tfill\trun_f\t${filler}\tok\n'
	}
	os.write_file(path, big) or { panic(err) }
	assistant_log_append('approve', 'run_last', 'choice once', 'recorded')
	content := os.read_file(path) or { panic(err) }
	assert content.len <= assistant_log_max_bytes / 2
	assert content.trim_right('\n').split('\n').last().contains('run_last')
	assistant_log_append('stop', 'run_after', '', 'requested')
	after := os.read_file(path) or { panic(err) }
	assert after.contains('run_after') && after.contains('run_last')
	leftovers := os.ls(tmp) or { [] }
	assert leftovers == ['assistant.log']
}
