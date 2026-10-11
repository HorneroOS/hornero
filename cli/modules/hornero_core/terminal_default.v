module hornero_core

import os

const supported_terminal_defaults = ['kitty', 'alacritty', 'ghostty']

fn terminal_helper_path() string {
	mut config_home := os.getenv('XDG_CONFIG_HOME')
	if config_home.len == 0 {
		config_home = os.join_path(os.home_dir(), '.config')
	}
	return os.join_path(config_home, 'xfce4', 'helpers.rc')
}

// default_terminal_set_report updates only TerminalEmulator in the user-level
// Exo helper file. A same-directory temporary file and rename avoid following
// an existing symlink and keep readers from observing a partial write.
fn default_terminal_set_report(app string, dry_run bool, yes bool) CommandResult {
	if app !in supported_terminal_defaults {
		return fail_result('config default-apps set', 'unsupported terminal: ${app} (choose kitty, alacritty, or ghostty).\nExample: horneroctl config default-apps set terminal ghostty --dry-run')
	}
	if !yes && !dry_run {
		return fail_result('config default-apps set', 'refusing to change the default terminal without --yes (preview with --dry-run).\nExample: horneroctl config default-apps set terminal ghostty --dry-run')
	}
	path := terminal_helper_path()
	if dry_run {
		return ok_result('config default-apps set', 'would set TerminalEmulator=${app} in ${path}', {
			'category': 'terminal'
			'app':      app
			'path':     path
			'dry_run':  'true'
		})
	}
	if find_on_path(app).len == 0 {
		return fail_result('config default-apps set', '${app} is not installed or not available on PATH. Install it before selecting it.\nExample: horneroctl config default-apps set terminal ghostty --dry-run')
	}
	mut content := ''
	if os.exists(path) {
		content = os.read_file(path) or {
			return fail_result('config default-apps set', 'cannot read ${path}: ${err.msg()}')
		}
	}
	mut lines := []string{}
	for line in content.split_into_lines() {
		if !line.starts_with('TerminalEmulator=') {
			lines << line
		}
	}
	lines << 'TerminalEmulator=${app}'
	updated := lines.join('\n') + '\n'
	dir := os.dir(path)
	os.mkdir_all(dir) or {
		return fail_result('config default-apps set', 'cannot create ${dir}: ${err.msg()}')
	}
	tmp_path := '${path}.hornero-tmp'
	if os.exists(tmp_path) || os.is_link(tmp_path) {
		return fail_result('config default-apps set', 'temporary file already exists: ${tmp_path}; remove it after verifying it is not in use, then retry')
	}
	os.write_file(tmp_path, updated) or {
		return fail_result('config default-apps set', 'cannot write ${tmp_path}: ${err.msg()}')
	}
	os.chmod(tmp_path, 0o600) or {
		os.rm(tmp_path) or {}
		return fail_result('config default-apps set', 'cannot secure ${tmp_path}: ${err.msg()}')
	}
	os.rename(tmp_path, path) or {
		os.rm(tmp_path) or {}
		return fail_result('config default-apps set', 'cannot replace ${path}: ${err.msg()}')
	}
	return ok_result('config default-apps set', 'Set ${app} as the default terminal in ${path}', {
		'category': 'terminal'
		'app':      app
		'path':     path
	})
}
