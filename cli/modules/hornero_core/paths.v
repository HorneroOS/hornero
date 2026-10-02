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

// system_data_dirs lists the system data roots from XDG_DATA_DIRS (default
// `/usr/local/share:/usr/share`). Packages install catalogues there; they
// are read-only and always rank below the user's data home.
pub fn system_data_dirs() []string {
	raw := os.getenv('XDG_DATA_DIRS')
	spec := if raw.len > 0 { raw } else { '/usr/local/share:/usr/share' }
	mut out := []string{}
	for d in spec.split(':') {
		if d.len > 0 && d !in out {
			out << d
		}
	}
	return out
}

// append_system_catalogues adds `<data-dir>/<rel>` for every existing system
// data dir not already present, after the user-level directories.
fn append_system_catalogues(mut dirs []string, rel string) {
	for base in system_data_dirs() {
		dir := os.join_path(base, rel)
		if os.is_dir(dir) && dir !in dirs {
			dirs << dir
		}
	}
}

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

// resolve_wallpapers_dirs_for_read returns wallpaper catalogue roots in
// precedence order: explicit override, user canonical, user legacy, then
// read-only system catalogues. It never changes the canonical write target.
pub fn resolve_wallpapers_dirs_for_read() []string {
	override := os.getenv('HORNERO_WALLPAPERS_DIR')
	if override.len > 0 {
		return [override]
	}
	mut dirs := []string{}
	canonical := resolve_wallpapers_dir()
	fallback := resolve_wallpapers_dir_fallback()
	if os.is_dir(canonical) {
		dirs << canonical
	}
	if os.is_dir(fallback) && fallback != canonical {
		dirs << fallback
	}
	append_system_catalogues(mut dirs, os.join_path('hornero', 'wallpapers'))
	append_system_catalogues(mut dirs, os.join_path('dots', 'wallpapers'))
	return dirs
}

// resolve_pictures_wallpapers_dir accepts the Hornero override first. The
// DOTS_* name remains a read-only compatibility fallback for existing users.
pub fn resolve_pictures_wallpapers_dir() string {
	value := os.getenv('HORNERO_PICTURES_WALLPAPERS')
	if value.len > 0 {
		return value
	}
	legacy := os.getenv('DOTS_PICTURES_WALLPAPERS')
	if legacy.len > 0 {
		return legacy
	}
	return os.join_path(os.home_dir(), 'Pictures', 'Wallpapers')
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
