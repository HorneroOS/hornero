module hornero_core

import os

// HorneroPaths is the XDG path contract shared by shell and config.
// User config lives under $XDG_CONFIG_HOME/hornero (shell.json included);
// system defaults under /etc/xdg/hornero; state/data/cache follow XDG.
pub struct HorneroPaths {
pub:
	config_dir        string
	data_dir          string
	state_dir         string
	cache_dir         string
	system_config_dir string
}

fn xdg_or_home(env_key string, fallback_under_home string) string {
	v := os.getenv(env_key)
	if v.len > 0 {
		return v
	}
	return os.join_path(os.home_dir(), fallback_under_home)
}

pub fn resolve_paths() HorneroPaths {
	return HorneroPaths{
		config_dir:        xdg_or_home('XDG_CONFIG_HOME', '.config')
		data_dir:          xdg_or_home('XDG_DATA_HOME', '.local/share')
		state_dir:         xdg_or_home('XDG_STATE_HOME', '.local/state')
		cache_dir:         xdg_or_home('XDG_CACHE_HOME', '.cache')
		system_config_dir: '/etc/xdg'
	}
}

// shell_config_file is the single runtime settings file the shell reads.
pub fn shell_config_file(p HorneroPaths) string {
	return os.join_path(p.config_dir, 'hornero', 'shell.json')
}

// system_shell_config_file is the shipped system-wide default.
pub fn system_shell_config_file(p HorneroPaths) string {
	return os.join_path(p.system_config_dir, 'hornero', 'shell.json')
}

// quickshell_config_dir is where the compositor-adjacent shell config lives.
pub fn quickshell_config_dir(p HorneroPaths) string {
	return os.join_path(p.config_dir, 'quickshell')
}
