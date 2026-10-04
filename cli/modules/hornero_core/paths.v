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

// Runtime paths are owned by Hornero and follow XDG. User data overrides
// read-only package catalogues; the same canonical paths are used for writes.

// system_data_dirs lists package-owned data roots in XDG precedence order.
pub fn system_data_dirs() []string {
	raw := os.getenv('XDG_DATA_DIRS')
	spec := if raw.len > 0 { raw } else { '/usr/local/share:/usr/share' }
	mut out := []string{}
	for d in spec.split(':') {
		if d.len > 0 && d !in out { out << d }
	}
	return out
}

fn append_system_catalogues(mut dirs []string, rel string) {
	for base in system_data_dirs() {
		dir := os.join_path(base, rel)
		if os.is_dir(dir) && dir !in dirs { dirs << dir }
	}
}

pub fn resolve_wallpapers_dir() string {
	env := os.getenv('HORNERO_WALLPAPERS_DIR')
	if env.len > 0 { return env }
	base := xdg_or_home('XDG_DATA_HOME', '.local/share')
	return os.join_path(base, 'hornero', 'wallpapers')
}

pub fn resolve_wallpapers_dirs_for_read() []string {
	override := os.getenv('HORNERO_WALLPAPERS_DIR')
	if override.len > 0 { return [override] }
	mut dirs := []string{}
	user := resolve_wallpapers_dir()
	if os.is_dir(user) { dirs << user }
	append_system_catalogues(mut dirs, os.join_path('hornero', 'wallpapers'))
	return dirs
}

pub fn resolve_pictures_wallpapers_dir() string {
	value := os.getenv('HORNERO_PICTURES_WALLPAPERS')
	if value.len > 0 { return value }
	return os.join_path(os.home_dir(), 'Pictures', 'Wallpapers')
}

pub fn resolve_wallpaper_pointer_file() string {
	env := os.getenv('HORNERO_WALLPAPER_POINTER_FILE')
	if env.len > 0 { return env }
	base := xdg_or_home('XDG_STATE_HOME', '.local/state')
	return os.join_path(base, 'hornero', 'wallpaper', 'path')
}

pub fn read_wallpaper_pointer() string {
	return os.read_file(resolve_wallpaper_pointer_file()) or { '' }.trim_space()
}

pub fn resolve_notifs_file() string {
	env := os.getenv('HORNERO_NOTIFS_FILE')
	if env.len > 0 { return env }
	base := xdg_or_home('XDG_STATE_HOME', '.local/state')
	return os.join_path(base, 'hornero', 'notifs.json')
}

pub fn resolve_image_cache_dir() string {
	env := os.getenv('HORNERO_IMAGE_CACHE_DIR')
	if env.len > 0 { return env }
	base := xdg_or_home('XDG_CACHE_HOME', '.cache')
	return os.join_path(base, 'hornero', 'imagecache')
}

pub fn resolve_notif_image_cache_dir() string {
	return os.join_path(resolve_image_cache_dir(), 'notifs')
}
