module hornero_core

import os

const supported_terminal_defaults = [3]string['kitty', 'alacritty', 'ghostty']

fn terminal_desktop_id(app string) string {
	return match app {
		'kitty' { 'kitty.desktop' }
		'alacritty' { 'Alacritty.desktop' }
		'ghostty' { 'com.mitchellh.ghostty.desktop' }
		else { '' }
	}
}

fn terminal_helper_path() string {
	mut config_home := os.getenv('XDG_CONFIG_HOME')
	if config_home.len == 0 {
		config_home = os.join_path(os.home_dir(), '.config')
	}
	return os.join_path(config_home, 'xfce4', 'helpers.rc')
}

fn xdg_terminal_preference_path() string {
	mut config_home := os.getenv('XDG_CONFIG_HOME')
	if config_home.len == 0 {
		config_home = os.join_path(os.home_dir(), '.config')
	}
	return os.join_path(config_home, 'xdg-terminals.list')
}

fn terminal_preference_is_control_line(trimmed string) bool {
	return trimmed == '' || trimmed.starts_with('#') || trimmed.starts_with('+')
		|| trimmed.starts_with('-') || trimmed.starts_with('/')
}

fn terminal_preference_content(existing string, selected_id string) string {
	mut lines := []string{}
	for line in existing.split_into_lines() {
		trimmed := line.trim_space()
		if terminal_preference_is_control_line(trimmed) {
			lines << line
			continue
		}
		entry_id := trimmed.split(':')[0]
		if entry_id != selected_id {
			lines << line
		}
	}
	mut selected := 0
	for i, line in lines {
		trimmed := line.trim_space()
		if !terminal_preference_is_control_line(trimmed) {
			selected = i
			break
		}
	}
	lines.insert(selected, selected_id)
	return lines.join('\n') + '\n'
}

fn terminal_write_private_config(path string, updated string) ! {
	dir := os.dir(path)
	os.mkdir_all(dir) or { return error('cannot create ${dir}: ${err.msg()}') }
	tmp_path := '${path}.hornero-tmp'
	if os.exists(tmp_path) || os.is_link(tmp_path) {
		return error('temporary file already exists: ${tmp_path}; remove it after verifying it is not in use, then retry')
	}
	os.write_file(tmp_path, updated) or { return error('cannot write ${tmp_path}: ${err.msg()}') }
	os.chmod(tmp_path, 0o600) or {
		os.rm(tmp_path) or {}
		return error('cannot secure ${tmp_path}: ${err.msg()}')
	}
	os.rename(tmp_path, path) or {
		os.rm(tmp_path) or {}
		return error('cannot replace ${path}: ${err.msg()}')
	}
}

fn terminal_stale_temp(path string) string {
	tmp_path := '${path}.hornero-tmp'
	if os.exists(tmp_path) || os.is_link(tmp_path) {
		return tmp_path
	}
	return ''
}

// default_terminal_set_report updates Exo's compatibility helper and the XDG
// default-terminal preference list. The latter is consumed by
// xdg-terminal-exec when installed; keeping both choices aligned means older
// Exo-based launch paths and XDG-aware applications follow the same terminal.
fn default_terminal_set_report(app string, dry_run bool, yes bool) CommandResult {
	if app !in supported_terminal_defaults {
		return fail_result('config default-apps set', 'unsupported terminal: ${app} (choose kitty, alacritty, or ghostty).\nExample: horneroctl config default-apps set terminal ghostty --dry-run')
	}
	if !yes && !dry_run {
		return fail_result('config default-apps set', 'refusing to change the default terminal without --yes (preview with --dry-run).\nExample: horneroctl config default-apps set terminal ghostty --dry-run')
	}
	exo_path := terminal_helper_path()
	xdg_path := xdg_terminal_preference_path()
	if dry_run {
		return ok_result('config default-apps set', 'would set ${app} in Exo and the XDG terminal preference list', {
			'category': 'terminal'
			'app':      app
			'path':     exo_path
			'exo_path': exo_path
			'xdg_path': xdg_path
			'dry_run':  'true'
		})
	}
	if find_on_path(app).len == 0 {
		return fail_result('config default-apps set', '${app} is not installed or not available on PATH. Install it before selecting it.\nExample: horneroctl config default-apps set terminal ghostty --dry-run')
	}
	for path in [exo_path, xdg_path] {
		stale := terminal_stale_temp(path)
		if stale.len > 0 {
			return fail_result('config default-apps set', 'temporary file already exists: ${stale}; remove it after verifying it is not in use, then retry')
		}
	}
	mut exo_content := ''
	if os.exists(exo_path) {
		exo_content = os.read_file(exo_path) or {
			return fail_result('config default-apps set', 'cannot read ${exo_path}: ${err.msg()}')
		}
	}
	mut exo_lines := []string{}
	for line in exo_content.split_into_lines() {
		if !line.starts_with('TerminalEmulator=') {
			exo_lines << line
		}
	}
	exo_lines << 'TerminalEmulator=${app}'
	exo_updated := exo_lines.join('\n') + '\n'
	mut xdg_content := ''
	if os.exists(xdg_path) {
		xdg_content = os.read_file(xdg_path) or {
			return fail_result('config default-apps set', 'cannot read ${xdg_path}: ${err.msg()}')
		}
	}
	xdg_updated := terminal_preference_content(xdg_content, terminal_desktop_id(app))
	terminal_write_private_config(exo_path, exo_updated) or {
		return fail_result('config default-apps set', err.msg())
	}
	terminal_write_private_config(xdg_path, xdg_updated) or {
		return fail_result('config default-apps set', 'updated ${exo_path}, but ${err.msg()}')
	}
	return ok_result('config default-apps set', 'Set ${app} as the default terminal in Exo and xdg-terminal-exec preferences', {
		'category': 'terminal'
		'app':      app
		'path':     exo_path
		'exo_path': exo_path
		'xdg_path': xdg_path
	})
}
