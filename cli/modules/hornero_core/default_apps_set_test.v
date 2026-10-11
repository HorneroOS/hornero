module hornero_core

import os

fn default_apps_set_test_save_env(keys []string) map[string]string {
	mut saved := map[string]string{}
	for k in keys {
		saved[k] = os.getenv(k)
	}
	return saved
}

fn default_apps_set_test_restore_env(saved map[string]string) {
	for k, v in saved {
		if v.len == 0 {
			os.unsetenv(k)
		} else {
			os.setenv(k, v, true)
		}
	}
}

fn test_default_apps_set_needs_args() {
	r := default_apps_set_report(DefaultAppsSetOptions{
		dry_run: true
	})
	assert !r.ok
	assert r.message.contains('missing MIME type')
}

fn test_default_apps_set_rejects_bad_mime() {
	r := default_apps_set_report(DefaultAppsSetOptions{
		mime:    'not-a-mime'
		app:     'nvim.desktop'
		dry_run: true
	})
	assert !r.ok
	assert r.message.contains('invalid MIME type')
}

fn test_default_apps_set_rejects_bad_app() {
	r := default_apps_set_report(DefaultAppsSetOptions{
		mime:    'text/plain'
		app:     'nvim'
		dry_run: true
	})
	assert !r.ok
	assert r.message.contains('invalid application')
}

fn test_default_apps_set_needs_yes() {
	r := default_apps_set_report(DefaultAppsSetOptions{
		mime: 'text/plain'
		app:  'nvim.desktop'
	})
	assert !r.ok
	assert r.message.contains('--yes')
}

fn test_default_apps_set_dry_run_needs_no_backend() {
	// Hermetic: nonexistent backend; dry-run still previews.
	saved := default_apps_set_test_save_env(['HORNERO_XDG_MIME_BIN'])
	os.setenv('HORNERO_XDG_MIME_BIN', '/nonexistent-xdg-mime-hornero-test', true)
	r := default_apps_set_report(DefaultAppsSetOptions{
		mime:    'text/plain'
		app:     'nvim.desktop'
		dry_run: true
	})
	assert r.ok
	assert r.message.contains('would run:')
	assert r.message.contains('default nvim.desktop text/plain')
	default_apps_set_test_restore_env(saved)
}

fn test_default_apps_set_missing_backend() {
	// Hermetic: no override and an empty PATH, so nothing resolves and
	// the command fails with guidance instead of executing.
	saved := default_apps_set_test_save_env(['HORNERO_XDG_MIME_BIN', 'PATH'])
	os.unsetenv('HORNERO_XDG_MIME_BIN')
	os.setenv('PATH', '/nonexistent-hx-path-test', true)
	r := default_apps_set_report(DefaultAppsSetOptions{
		mime: 'text/plain'
		app:  'nvim.desktop'
		yes:  true
	})
	assert !r.ok
	assert r.message.contains('xdg-mime not found')
	default_apps_set_test_restore_env(saved)
}

fn test_default_apps_set_live() {
	// Live set through a fixture xdg-mime (the horneroctl config default-apps
	// delegation path): validates the pair, then runs xdg-mime.
	saved := default_apps_set_test_save_env(['HORNERO_XDG_MIME_BIN'])
	os.mkdir_all('/tmp/hx-default-apps-set-test/bin') or { assert false }
	os.write_file('/tmp/hx-default-apps-set-test/bin/xdg-mime', '#!/bin/sh\necho "xdg-mime \$*"\nexit 0\n') or {
		assert false
	}
	os.chmod('/tmp/hx-default-apps-set-test/bin/xdg-mime', 0o755) or { assert false }
	os.setenv('HORNERO_XDG_MIME_BIN', '/tmp/hx-default-apps-set-test/bin/xdg-mime', true)
	r := default_apps_set_report(DefaultAppsSetOptions{
		mime: 'text/plain'
		app:  'nvim.desktop'
		yes:  true
	})
	assert r.ok
	assert r.message.contains('Set nvim.desktop as default for text/plain')
	default_apps_set_test_restore_env(saved)
}

fn test_default_terminal_set_dry_run_is_read_only() {
	saved := default_apps_set_test_save_env(['HOME', 'XDG_CONFIG_HOME'])
	root := '/tmp/hx-terminal-default-dry-test'
	os.mkdir_all(root) or { assert false }
	os.setenv('XDG_CONFIG_HOME', root, true)
	r := default_apps_set_report(DefaultAppsSetOptions{
		mime:    'terminal'
		app:     'ghostty'
		dry_run: true
	})
	assert r.ok
	assert r.data['path'] == '${root}/xfce4/helpers.rc'
	assert r.data['exo_path'] == '${root}/xfce4/helpers.rc'
	assert r.data['xdg_path'] == '${root}/xdg-terminals.list'
	assert !os.exists('${root}/xfce4/helpers.rc')
	assert !os.exists('${root}/xdg-terminals.list')
	os.rmdir_all(root) or {}
	default_apps_set_test_restore_env(saved)
}

fn test_default_terminal_set_requires_yes() {
	r := default_apps_set_report(DefaultAppsSetOptions{
		mime: 'terminal'
		app:  'kitty'
	})
	assert !r.ok
	assert r.message.contains('--yes')
}

fn test_default_terminal_set_updates_exo_and_xdg_preferences() {
	saved := default_apps_set_test_save_env(['HOME', 'XDG_CONFIG_HOME', 'PATH'])
	root := '/tmp/hx-terminal-default-live-test'
	bin_dir := '${root}/bin'
	config_dir := '${root}/config/xfce4'
	os.mkdir_all(bin_dir) or { assert false }
	os.mkdir_all(config_dir) or { assert false }
	os.write_file('${bin_dir}/ghostty', '#!/bin/sh\nexit 0\n') or { assert false }
	os.chmod('${bin_dir}/ghostty', 0o755) or { assert false }
	os.write_file('${config_dir}/helpers.rc', '# Keep this helper\nTerminalEmulator=kitty\nOtherHelper=filemanager\nTerminalEmulator=alacritty\n') or {
		assert false
	}
	os.write_file('${root}/config/xdg-terminals.list', '# Preferred terminal\nkitty.desktop\nAlacritty.desktop\n') or {
		assert false
	}
	os.setenv('XDG_CONFIG_HOME', '${root}/config', true)
	os.setenv('PATH', bin_dir, true)
	r := default_apps_set_report(DefaultAppsSetOptions{
		mime: 'terminal'
		app:  'ghostty'
		yes:  true
	})
	assert r.ok
	updated := os.read_file('${config_dir}/helpers.rc') or { '' }
	assert updated.contains('# Keep this helper')
	assert updated.contains('OtherHelper=filemanager')
	assert updated.contains('TerminalEmulator=ghostty')
	assert updated.count('TerminalEmulator=') == 1
	xdg_updated := os.read_file('${root}/config/xdg-terminals.list') or { '' }
	assert xdg_updated == '# Preferred terminal\ncom.mitchellh.ghostty.desktop\nkitty.desktop\nAlacritty.desktop\n'
	os.rmdir_all(root) or {}
	default_apps_set_test_restore_env(saved)
}

fn test_terminal_preference_content_moves_selected_entry_to_front_and_keeps_fallbacks() {
	updated := terminal_preference_content('# terminals\nkitty.desktop\nAlacritty.desktop\ncom.mitchellh.ghostty.desktop:NewWindow\n',
		'com.mitchellh.ghostty.desktop')
	assert updated == '# terminals\ncom.mitchellh.ghostty.desktop\nkitty.desktop\nAlacritty.desktop\n'
}

fn test_terminal_preference_content_creates_a_single_default_entry() {
	assert terminal_preference_content('', 'kitty.desktop') == 'kitty.desktop\n'
}

fn test_terminal_preference_content_keeps_xdg_directives_before_terminal_choices() {
	existing := '# terminals\n/execarg_compat\n+kitty.desktop\nAlacritty.desktop\n'
	updated := terminal_preference_content(existing, 'com.mitchellh.ghostty.desktop')
	assert updated == '# terminals\n/execarg_compat\n+kitty.desktop\ncom.mitchellh.ghostty.desktop\nAlacritty.desktop\n'
}

fn test_default_xdg_terminal_id_skips_comments_and_blank_lines() {
	saved := default_apps_set_test_save_env(['HOME', 'XDG_CONFIG_HOME'])
	root := '/tmp/hx-xdg-terminal-list-test'
	os.mkdir_all(root) or { assert false }
	os.write_file('${root}/xdg-terminals.list', '# comment\n\n/compat\n+kitty.desktop\n-ghostty.desktop\nAlacritty.desktop\n') or {
		assert false
	}
	os.setenv('XDG_CONFIG_HOME', root, true)
	assert default_xdg_terminal_id() == 'Alacritty.desktop'
	os.rmdir_all(root) or {}
	default_apps_set_test_restore_env(saved)
}

fn test_default_terminal_set_rejects_missing_program() {
	saved := default_apps_set_test_save_env(['PATH'])
	os.setenv('PATH', '/nonexistent-hx-terminal-test', true)
	r := default_apps_set_report(DefaultAppsSetOptions{
		mime: 'terminal'
		app:  'kitty'
		yes:  true
	})
	assert !r.ok
	assert r.message.contains('not installed')
	default_apps_set_test_restore_env(saved)
}

fn test_default_terminal_set_refuses_stale_temp_file() {
	saved := default_apps_set_test_save_env(['HOME', 'XDG_CONFIG_HOME', 'PATH'])
	root := '/tmp/hx-terminal-default-stale-temp-test'
	os.rmdir_all(root) or {}
	config_dir := '${root}/config/xfce4'
	bin_dir := '${root}/bin'
	os.mkdir_all(config_dir) or { assert false }
	os.mkdir_all(bin_dir) or { assert false }
	os.write_file('${bin_dir}/ghostty', '') or { assert false }
	os.chmod('${bin_dir}/ghostty', 0o755) or { assert false }
	os.symlink('${root}/untrusted-target', '${config_dir}/helpers.rc.hornero-tmp') or { assert false }
	os.setenv('XDG_CONFIG_HOME', '${root}/config', true)
	os.setenv('PATH', bin_dir, true)
	r := default_apps_set_report(DefaultAppsSetOptions{
		mime: 'terminal'
		app:  'ghostty'
		yes:  true
	})
	assert !r.ok
	assert r.message.contains('temporary file already exists')
	assert os.is_link('${config_dir}/helpers.rc.hornero-tmp')
	assert !os.exists('${root}/config/xdg-terminals.list')
	assert !os.exists('${root}/untrusted-target')
	os.rmdir_all(root) or {}
	default_apps_set_test_restore_env(saved)
}
