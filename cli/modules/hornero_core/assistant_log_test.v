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
	// Under the cap the content is untouched.
	assert assistant_log_rotate_text('a\nb\n', 200) == 'a\nb\n'
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
	assert report.message.contains('run_1')
	assert report.message.contains('choice once')
	st := os.stat(path) or { panic(err) }
	assert st.mode & 0o077 == 0
}
