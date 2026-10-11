module hornero_core

import os
import x.json2

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

fn shell_config_path() string {
	mut config_home := os.getenv('XDG_CONFIG_HOME')
	if config_home.len == 0 {
		config_home = os.join_path(os.home_dir(), '.config')
	}
	return os.join_path(config_home, 'hornero', 'shell.json')
}

fn shell_terminal_id() string {
	raw := os.read_file(shell_config_path()) or { return '' }
	parsed := json2.decode[json2.Any](raw) or { return 'Invalid shell.json' }
	if parsed !is map[string]json2.Any {
		return ''
	}
	config := parsed as map[string]json2.Any
	general_value := config['general'] or { return '' }
	if general_value !is map[string]json2.Any {
		return ''
	}
	general := general_value as map[string]json2.Any
	apps_value := general['apps'] or { return '' }
	if apps_value !is map[string]json2.Any {
		return ''
	}
	apps := apps_value as map[string]json2.Any
	terminal_value := apps['terminal'] or { return '' }
	if terminal_value is []json2.Any {
		terminal := terminal_value as []json2.Any
		if terminal.len > 0 && terminal[0] is string {
			return terminal[0] as string
		}
	}
	return ''
}

fn shell_config_with_terminal(existing string, app string) !string {
	mut config := map[string]json2.Any{}
	if existing.trim_space().len > 0 {
		parsed := json2.decode[json2.Any](existing) or {
			return error('cannot parse Hornero Shell config JSON: ${err.msg()}')
		}
		if parsed !is map[string]json2.Any {
			return error('Hornero Shell config must be a JSON object')
		}
		config = parsed.clone()
	}
	mut general := map[string]json2.Any{}
	if 'general' in config {
		if config['general'] !is map[string]json2.Any {
			return error('Hornero Shell config key "general" must be a JSON object')
		}
		general = config['general']
	}
	mut apps := map[string]json2.Any{}
	if 'apps' in general {
		if general['apps'] !is map[string]json2.Any {
			return error('Hornero Shell config key "general.apps" must be a JSON object')
		}
		apps = general['apps']
	}
	apps['terminal'] = json2.Any([json2.Any(app)])
	general['apps'] = json2.Any(apps)
	config['general'] = json2.Any(general)
	return json2.encode(config, escape_unicode: true) + '\n'
}

fn terminal_preference_is_control_line(trimmed string) bool {
	return trimmed == '' || trimmed.starts_with('#') || trimmed.starts_with('+')
		|| trimmed.starts_with('-') || trimmed.starts_with('/')
}

fn terminal_preference_content(existing string, selected_id string) string {
	mut lines := []string{}
	for line in existing.split_into_lines() {
		trimmed := line.trim_space()
		if trimmed.starts_with('-') && trimmed['-'.len..].split(':')[0] == selected_id {
			continue
		}
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

fn terminal_stage_private_config(path string, updated string) !string {
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
	return tmp_path
}

fn terminal_commit_private_config(tmp_path string, path string) ! {
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

// default_terminal_set_report updates Exo's compatibility helper, the XDG
// default-terminal preference list, and Hornero Shell's app2unit launch
// setting. Keeping these choices aligned means Shell shortcuts and
// XDG-aware/Exo-based application launches use the same terminal.
fn default_terminal_set_report(app string, dry_run bool, yes bool) CommandResult {
	if app !in supported_terminal_defaults {
		return fail_result('config default-apps set', 'unsupported terminal: ${app} (choose kitty, alacritty, or ghostty).\nExample: horneroctl config default-apps set terminal ghostty --dry-run')
	}
	if !yes && !dry_run {
		return fail_result('config default-apps set', 'refusing to change the default terminal without --yes (preview with --dry-run).\nExample: horneroctl config default-apps set terminal ghostty --dry-run')
	}
	exo_path := terminal_helper_path()
	xdg_path := xdg_terminal_preference_path()
	shell_path := shell_config_path()
	if dry_run {
		return ok_result('config default-apps set', 'would set ${app} in Exo, XDG terminal preferences, and Hornero Shell', {
			'category':   'terminal'
			'app':        app
			'path':       exo_path
			'exo_path':   exo_path
			'xdg_path':   xdg_path
			'shell_path': shell_path
			'dry_run':    'true'
		})
	}
	if find_on_path(app).len == 0 {
		return fail_result('config default-apps set', '${app} is not installed or not available on PATH. Install it before selecting it.\nExample: horneroctl config default-apps set terminal ghostty --dry-run')
	}
	for path in [exo_path, xdg_path, shell_path] {
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
	mut shell_content := ''
	if os.exists(shell_path) {
		shell_content = os.read_file(shell_path) or {
			return fail_result('config default-apps set', 'cannot read ${shell_path}: ${err.msg()}')
		}
	}
	shell_updated := shell_config_with_terminal(shell_content, app) or {
		return fail_result('config default-apps set', 'cannot update ${shell_path}: ${err.msg()}')
	}
	mut staged := []string{}
	paths := [exo_path, xdg_path, shell_path]
	contents := [exo_updated, xdg_updated, shell_updated]
	for i, path in paths {
		updated := contents[i]
		tmp := terminal_stage_private_config(path, updated) or {
			for staged_path in staged {
				os.rm(staged_path) or {}
			}
			return fail_result('config default-apps set', err.msg())
		}
		staged << tmp
	}
	terminal_commit_private_config(staged[0], exo_path) or {
		os.rm(staged[1]) or {}
		os.rm(staged[2]) or {}
		return fail_result('config default-apps set', err.msg())
	}
	terminal_commit_private_config(staged[1], xdg_path) or {
		os.rm(staged[2]) or {}
		return fail_result('config default-apps set', 'updated ${exo_path}, but ${err.msg()}')
	}
	terminal_commit_private_config(staged[2], shell_path) or {
		return fail_result('config default-apps set', 'updated Exo and XDG terminal preferences, but could not update Hornero Shell: ${err.msg()}. Re-run the command to converge.')
	}
	return ok_result('config default-apps set', 'Set ${app} as the default terminal in Exo, xdg-terminal-exec, and Hornero Shell', {
		'category':   'terminal'
		'app':        app
		'path':       exo_path
		'exo_path':   exo_path
		'xdg_path':   xdg_path
		'shell_path': shell_path
	})
}
