module hornero_core

import os
import x.json2

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
	assert r.data['shell_path'] == '${root}/hornero/shell.json'
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
	os.mkdir_all('${root}/config/hornero') or { assert false }
	os.write_file('${bin_dir}/ghostty', '#!/bin/sh\nexit 0\n') or { assert false }
	os.chmod('${bin_dir}/ghostty', 0o755) or { assert false }
	os.write_file('${config_dir}/helpers.rc', '# Keep this helper\nTerminalEmulator=kitty\nOtherHelper=filemanager\nTerminalEmulator=alacritty\n') or {
		assert false
	}
	os.write_file('${root}/config/xdg-terminals.list', '# Preferred terminal\nkitty.desktop\nAlacritty.desktop\n') or {
		assert false
	}
	os.write_file('${root}/config/hornero/shell.json', '{"appearance":{"theme":"hornero-light"},"general":{"apps":{"audio":["pavucontrol"],"terminal":["kitty"],"explorer":["thunar"]}},"custom":{"keep":true}}') or {
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
	shell_updated := os.read_file('${root}/config/hornero/shell.json') or { '' }
	shell_config := json2.decode[map[string]json2.Any](shell_updated) or { map[string]json2.Any{} }
	appearance := shell_config['appearance'] or { json2.Any('missing') }
	custom := shell_config['custom'] or { json2.Any('missing') }
	assert appearance is map[string]json2.Any
	assert custom is map[string]json2.Any
	general_value := shell_config['general'] or { json2.Any('missing') }
	general := general_value as map[string]json2.Any
	apps_value := general['apps'] or { json2.Any('missing') }
	apps := apps_value as map[string]json2.Any
	terminal_value := apps['terminal'] or { json2.Any('missing') }
	terminal := terminal_value as []json2.Any
	assert terminal.len == 1
	assert terminal[0] == json2.Any('ghostty')
	os.rmdir_all(root) or {}
	default_apps_set_test_restore_env(saved)
}

fn test_shell_config_with_terminal_preserves_other_values_for_each_supported_terminal() {
	for terminal in supported_terminal_defaults {
		updated := shell_config_with_terminal('{"appearance":{"theme":"pampa"},"general":{"apps":{"audio":["pavucontrol"],"terminal":["kitty"]}},"extra":17}', terminal) or {
			assert false
			continue
		}
		config := json2.decode[map[string]json2.Any](updated) or { map[string]json2.Any{} }
		appearance := config['appearance'] or { json2.Any('missing') }
		extra := config['extra'] or { json2.Any('missing') }
		assert appearance is map[string]json2.Any
		assert extra.str() == '17'
		general_value := config['general'] or { json2.Any('missing') }
		general := general_value as map[string]json2.Any
		apps_value := general['apps'] or { json2.Any('missing') }
		apps := apps_value as map[string]json2.Any
		selected_value := apps['terminal'] or { json2.Any('missing') }
		selected := selected_value as []json2.Any
		assert selected == [json2.Any(terminal)]
		audio_value := apps['audio'] or { json2.Any('missing') }
		assert audio_value == json2.Any([json2.Any('pavucontrol')])
	}
}

fn test_invalid_shell_config_does_not_update_other_terminal_defaults() {
	saved := default_apps_set_test_save_env(['HOME', 'XDG_CONFIG_HOME', 'PATH'])
	root := '/tmp/hx-terminal-default-invalid-shell-test'
	os.rmdir_all(root) or {}
	os.mkdir_all('${root}/bin') or { assert false }
	os.mkdir_all('${root}/config/xfce4') or { assert false }
	os.mkdir_all('${root}/config/hornero') or { assert false }
	os.write_file('${root}/bin/ghostty', '#!/bin/sh\nexit 0\n') or { assert false }
	os.chmod('${root}/bin/ghostty', 0o755) or { assert false }
	os.write_file('${root}/config/xfce4/helpers.rc', 'TerminalEmulator=kitty\n') or { assert false }
	os.write_file('${root}/config/hornero/shell.json', '{broken json') or { assert false }
	os.setenv('XDG_CONFIG_HOME', '${root}/config', true)
	os.setenv('PATH', '${root}/bin', true)
	r := default_apps_set_report(DefaultAppsSetOptions{
		mime: 'terminal'
		app:  'ghostty'
		yes:  true
	})
	assert !r.ok
	assert r.message.contains('cannot parse Hornero Shell config JSON')
	assert os.read_file('${root}/config/xfce4/helpers.rc') or { '' } == 'TerminalEmulator=kitty\n'
	assert !os.exists('${root}/config/xdg-terminals.list')
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

fn test_terminal_preference_content_removes_selected_terminal_fallback_exclusion() {
	existing := '-com.mitchellh.ghostty.desktop\nkitty.desktop\n'
	updated := terminal_preference_content(existing, 'com.mitchellh.ghostty.desktop')
	assert updated == 'com.mitchellh.ghostty.desktop\nkitty.desktop\n'
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
