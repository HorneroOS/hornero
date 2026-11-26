module hornero_core

import os

fn test_validate_app_id_rejects_traversal() {
	bad_ids := ['', '../evil', 'a/b', 'a\\b', 'foo..bar', '.hidden', '-dash', 'bad\0id', 'has space']
	for id in bad_ids {
		if _ := validate_app_id(id) {
			assert false, 'expected validate_app_id to reject "${id}"'
		}
	}
	good := validate_app_id('github-prs_1') or {
		assert false, 'expected valid id, got: ${err}'
		return
	}
	assert good == 'github-prs_1'
}

fn test_webapp_add_list_remove_lifecycle() {
	tmp := os.join_path(os.temp_dir(), 'hornero_webapp_test_${os.getpid()}')
	os.rmdir_all(tmp) or {}
	defer {
		os.rmdir_all(tmp) or {}
	}
	os.setenv('XDG_DATA_HOME', tmp, true)
	defer {
		os.unsetenv('XDG_DATA_HOME')
	}

	entry := webapp_add(WebAppSpec{
		id:      'github'
		name:    'GitHub'
		url:     'https://github.com'
		browser: 'chromium'
		icon:    'web-browser'
	}) or {
		assert false, 'webapp_add failed: ${err}'
		return
	}
	assert entry.id == 'github'
	assert entry.kind == 'webapp'
	assert entry.wm_class == 'hornero-webapp-github'
	assert os.exists(entry.file_path)

	content := os.read_file(entry.file_path) or { '' }
	assert content.contains('StartupWMClass=hornero-webapp-github')
	assert content.contains('Exec=chromium --app=https://github.com')

	listed := webapp_list()
	assert listed.len == 1
	assert listed[0].id == 'github'
	assert listed[0].name == 'GitHub'

	removed := webapp_remove('github') or {
		assert false, 'webapp_remove failed: ${err}'
		return
	}
	assert removed == entry.file_path
	assert !os.exists(entry.file_path)
	assert webapp_list().len == 0
}

fn test_tui_app_add_list_remove_lifecycle() {
	tmp := os.join_path(os.temp_dir(), 'hornero_tui_test_${os.getpid()}')
	os.rmdir_all(tmp) or {}
	defer {
		os.rmdir_all(tmp) or {}
	}
	os.setenv('XDG_DATA_HOME', tmp, true)
	defer {
		os.unsetenv('XDG_DATA_HOME')
	}

	entry := tui_app_add(TuiAppSpec{
		id:       'lazygit'
		name:     'Lazygit'
		command:  'lazygit'
		terminal: 'kitty'
	}) or {
		assert false, 'tui_app_add failed: ${err}'
		return
	}
	assert entry.id == 'lazygit'
	assert entry.kind == 'tui'
	assert entry.wm_class == 'hornero-tui-lazygit'
	assert os.exists(entry.file_path)

	content := os.read_file(entry.file_path) or { '' }
	assert content.contains('StartupWMClass=hornero-tui-lazygit')
	assert content.contains('Exec=kitty --class hornero-tui-lazygit -e lazygit')

	listed := tui_app_list()
	assert listed.len == 1
	assert listed[0].id == 'lazygit'

	tui_app_remove('lazygit') or {
		assert false, 'tui_app_remove failed: ${err}'
		return
	}
	assert tui_app_list().len == 0
}
