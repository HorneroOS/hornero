module hornero_core

import os
import x.json2

// config_paths_report prints the resolved XDG path contract.
pub fn config_paths_report() CommandResult {
	p := resolve_paths()
	lines := [
		'user config:   ${p.config_dir}',
		'user data:     ${p.data_dir}',
		'user state:    ${p.state_dir}',
		'user cache:    ${p.cache_dir}',
		'system config: ${p.system_config_dir}',
		'shell config:  ${shell_config_file(p)}',
	]
	return ok_result('config paths', lines.join('\n'), {
		'config_dir':   p.config_dir
		'shell_config': shell_config_file(p)
	})
}

pub struct ThemeManifest {
pub mut:
	id   string
	name string
}

// config_validate_report checks the materialized config without changing it.
pub fn config_validate_report() CommandResult {
	p := resolve_paths()
	mut lines := []string{}
	mut failed := 0
	cfg := shell_config_file(p)
	if os.is_file(cfg) {
		lines << 'ok  shell config: ${cfg}'
	} else {
		lines << 'missing shell config: ${cfg} (defaults apply)'
	}
	sys := system_shell_config_file(p)
	if os.is_file(sys) {
		lines << 'ok  system default: ${sys}'
	}
	manifest := os.join_path(p.data_dir, 'hornero', 'themes', 'wallpapers.manifest.json')
	if os.is_file(manifest) {
		raw := os.read_file(manifest) or { '' }
		if parsed := json2.decode[[]ThemeManifest](raw) {
			lines << 'ok  theme manifest: ${manifest} (${parsed.len} entries)'
		} else {
			lines << 'FAIL theme manifest: ${manifest} does not parse'
			failed++
		}
	} else {
		lines << 'missing theme manifest: ${manifest} (optional)'
	}
	if failed == 0 {
		lines << 'config: valid'
	} else {
		lines << 'config: ${failed} problem(s)'
	}
	return CommandResult{
		command: 'config validate'
		ok:      failed == 0
		message: lines.join('\n')
		data:    map[string]string{}
	}
}
