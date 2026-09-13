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

// Path-contract runtime helpers (docs/PATH_CONTRACT.md rows 9-11).
//
// Every `resolve_*` below is the canonical `hornero/*` location and the
// WRITE TARGET for new code. Each has a `*_fallback` twin pointing at the
// legacy `dots/*` location, which is READ-ONLY: nothing new is ever written
// there. `*_for_read` helpers resolve canonical-first, falling back to the
// legacy path only when the canonical one is absent.

// resolve_wallpapers_dir locates installed wallpaper binaries (row 11).
// Override with HORNERO_WALLPAPERS_DIR.
pub fn resolve_wallpapers_dir() string {
	env := os.getenv('HORNERO_WALLPAPERS_DIR')
	if env.len > 0 {
		return env
	}
	mut base := os.getenv('XDG_DATA_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.local', 'share')
	}
	return os.join_path(base, 'hornero', 'wallpapers')
}

// resolve_wallpapers_dir_fallback is the legacy read-only location (row 11).
pub fn resolve_wallpapers_dir_fallback() string {
	mut base := os.getenv('XDG_DATA_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.local', 'share')
	}
	return os.join_path(base, 'dots', 'wallpapers')
}

// resolve_wallpaper_pointer_file locates the wallpaper pointer (row 9).
// Override with HORNERO_WALLPAPER_POINTER_FILE.
pub fn resolve_wallpaper_pointer_file() string {
	env := os.getenv('HORNERO_WALLPAPER_POINTER_FILE')
	if env.len > 0 {
		return env
	}
	mut base := os.getenv('XDG_STATE_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.local', 'state')
	}
	return os.join_path(base, 'hornero', 'wallpaper', 'path')
}

// resolve_wallpaper_pointer_file_fallback is the legacy read-only location.
pub fn resolve_wallpaper_pointer_file_fallback() string {
	mut base := os.getenv('XDG_STATE_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.local', 'state')
	}
	return os.join_path(base, 'dots', 'wallpaper', 'path')
}

// resolve_wallpaper_pointer_file_for_read picks the pointer actually read:
// the explicit override, else canonical-first with legacy fallback.
pub fn resolve_wallpaper_pointer_file_for_read() string {
	env := os.getenv('HORNERO_WALLPAPER_POINTER_FILE')
	if env.len > 0 {
		return env
	}
	canonical := resolve_wallpaper_pointer_file()
	if os.is_file(canonical) {
		return canonical
	}
	fallback := resolve_wallpaper_pointer_file_fallback()
	if os.is_file(fallback) {
		return fallback
	}
	return canonical
}

// read_wallpaper_pointer returns the trimmed first line of the pointer file,
// or '' when neither the canonical nor the legacy location exists.
pub fn read_wallpaper_pointer() string {
	raw := os.read_file(resolve_wallpaper_pointer_file_for_read()) or { return '' }
	return raw.trim_space()
}

// resolve_notifs_file locates the notifications runtime state (row 10).
// Override with HORNERO_NOTIFS_FILE.
pub fn resolve_notifs_file() string {
	env := os.getenv('HORNERO_NOTIFS_FILE')
	if env.len > 0 {
		return env
	}
	mut base := os.getenv('XDG_STATE_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.local', 'state')
	}
	return os.join_path(base, 'hornero', 'notifs.json')
}

// resolve_notifs_file_fallback is the legacy read-only location.
pub fn resolve_notifs_file_fallback() string {
	mut base := os.getenv('XDG_STATE_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.local', 'state')
	}
	return os.join_path(base, 'dots', 'notifs.json')
}

// resolve_notifs_file_for_read picks the notifs file actually read:
// the explicit override, else canonical-first with legacy fallback.
pub fn resolve_notifs_file_for_read() string {
	env := os.getenv('HORNERO_NOTIFS_FILE')
	if env.len > 0 {
		return env
	}
	canonical := resolve_notifs_file()
	if os.is_file(canonical) {
		return canonical
	}
	fallback := resolve_notifs_file_fallback()
	if os.is_file(fallback) {
		return fallback
	}
	return canonical
}

// resolve_image_cache_dir locates the image cache (row 10).
// Override with HORNERO_IMAGE_CACHE_DIR.
pub fn resolve_image_cache_dir() string {
	env := os.getenv('HORNERO_IMAGE_CACHE_DIR')
	if env.len > 0 {
		return env
	}
	mut base := os.getenv('XDG_CACHE_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.cache')
	}
	return os.join_path(base, 'hornero', 'imagecache')
}

// resolve_image_cache_dir_fallback is the legacy read-only location.
pub fn resolve_image_cache_dir_fallback() string {
	mut base := os.getenv('XDG_CACHE_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.cache')
	}
	return os.join_path(base, 'dots', 'imagecache')
}

// resolve_notif_image_cache_dir locates the notification image cache.
pub fn resolve_notif_image_cache_dir() string {
	return os.join_path(resolve_image_cache_dir(), 'notifs')
}

// resolve_notif_image_cache_dir_fallback is the legacy read-only location.
pub fn resolve_notif_image_cache_dir_fallback() string {
	return os.join_path(resolve_image_cache_dir_fallback(), 'notifs')
}
