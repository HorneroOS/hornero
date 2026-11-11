module hornero_core

import os

fn test_assistant_workspace_list_report_exposes_ids() {
	saved := os.getenv('HORNERO_ASSISTANT_WORKSPACES_FILE')
	path := '/tmp/hx-assistant-workspaces-list-test.json'
	os.setenv('HORNERO_ASSISTANT_WORKSPACES_FILE', path, true)
	os.rm(path) or {}
	report := assistant_workspace_list_report()
	assert report.ok
	assert report.data['count'] == '1'
	assert report.data['active'] == 'default'
	assert report.data['ids'] == 'default'
	assert report.message.contains('default')
	os.rm(path) or {}
	if saved.len == 0 {
		os.unsetenv('HORNERO_ASSISTANT_WORKSPACES_FILE')
	} else {
		os.setenv('HORNERO_ASSISTANT_WORKSPACES_FILE', saved, true)
	}
}

fn test_assistant_workspace_valid_id_rejects_traversal() {
	assert assistant_workspace_valid_id('default')
	assert assistant_workspace_valid_id('ws-abc123')
	assert !assistant_workspace_valid_id('')
	assert !assistant_workspace_valid_id('../escape')
	assert !assistant_workspace_valid_id('a/b')
	assert !assistant_workspace_valid_id('a b')
}
