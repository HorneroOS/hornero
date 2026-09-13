module hornero_core

import os

// Path-contract conformance tests (docs/PATH_CONTRACT.md, hornero row).
// Canonical `hornero/*` locations are the write targets; legacy `dots/*`
// locations are read-only fallbacks. Everything lives under /tmp with XDG
// overrides, and each test unsets what it sets (no network, no compositor).

const pc_root = '/tmp/hx-pathcontract-test'

fn pc_write(path string, content string) {
	os.mkdir_all(os.dir(path)) or { assert false }
	os.write_file(path, content) or { assert false }
}

fn pc_set_xdg(tag string) {
	// Hermetic per test (and across reruns): drop stale fixtures first.
	if os.exists('${pc_root}/${tag}') {
		os.rmdir_all('${pc_root}/${tag}') or {}
	}
	os.setenv('XDG_DATA_HOME', '${pc_root}/${tag}/data', true)
	os.setenv('XDG_STATE_HOME', '${pc_root}/${tag}/state', true)
	os.setenv('XDG_CACHE_HOME', '${pc_root}/${tag}/cache', true)
	os.unsetenv('HORNERO_THEMES_DIR')
	os.unsetenv('HORNERO_PRESETS_DIR')
	os.unsetenv('HORNERO_PRESET_STATE_FILE')
	os.unsetenv('HORNERO_SNAPSHOTS_DIR')
	os.unsetenv('HORNERO_WALLPAPERS_DIR')
	os.unsetenv('HORNERO_WALLPAPER_POINTER_FILE')
	os.unsetenv('HORNERO_NOTIFS_FILE')
	os.unsetenv('HORNERO_IMAGE_CACHE_DIR')
}

fn pc_unset_xdg() {
	os.unsetenv('XDG_DATA_HOME')
	os.unsetenv('XDG_STATE_HOME')
	os.unsetenv('XDG_CACHE_HOME')
	os.unsetenv('HORNERO_THEMES_DIR')
	os.unsetenv('HORNERO_PRESETS_DIR')
	os.unsetenv('HORNERO_PRESET_STATE_FILE')
	os.unsetenv('HORNERO_SNAPSHOTS_DIR')
	os.unsetenv('HORNERO_WALLPAPERS_DIR')
	os.unsetenv('HORNERO_WALLPAPER_POINTER_FILE')
	os.unsetenv('HORNERO_NOTIFS_FILE')
	os.unsetenv('HORNERO_IMAGE_CACHE_DIR')
}

fn test_pc_canonical_resolvers_are_write_targets() {
	pc_set_xdg('write-targets')
	assert resolve_themes_dir() == '${pc_root}/write-targets/data/hornero/themes'
	assert resolve_presets_dir() == '${pc_root}/write-targets/data/hornero/shell-presets'
	assert resolve_preset_state_file() == '${pc_root}/write-targets/state/hornero/current-shell-preset'
	assert scheme_state_file() == '${pc_root}/write-targets/state/hornero/scheme/state.json'
	assert color_scheme_file() == '${pc_root}/write-targets/cache/hornero/smart-colors/scheme.json'
	assert resolve_snapshots_dir() == '${pc_root}/write-targets/cache/hornero/snapshots'
	assert resolve_wallpapers_dir() == '${pc_root}/write-targets/data/hornero/wallpapers'
	assert resolve_wallpaper_pointer_file() == '${pc_root}/write-targets/state/hornero/wallpaper/path'
	assert resolve_notifs_file() == '${pc_root}/write-targets/state/hornero/notifs.json'
	assert resolve_image_cache_dir() == '${pc_root}/write-targets/cache/hornero/imagecache'
	assert resolve_notif_image_cache_dir() == '${pc_root}/write-targets/cache/hornero/imagecache/notifs'
	targets := [resolve_themes_dir(), resolve_presets_dir(), resolve_preset_state_file(),
		scheme_state_file(), color_scheme_file(), resolve_snapshots_dir(), resolve_wallpapers_dir(),
		resolve_wallpaper_pointer_file(), resolve_notifs_file(), resolve_image_cache_dir()]
	for p in targets {
		assert p.contains('/hornero/'), 'write target must be hornero/*: ${p}'
		assert !p.contains('/dots/'), 'write target must never be dots/*: ${p}'
	}
	pc_unset_xdg()
}

fn test_pc_fallback_resolvers_target_legacy_dots() {
	pc_set_xdg('fallbacks')
	assert resolve_themes_dir_fallback() == '${pc_root}/fallbacks/data/dots/themes'
	assert resolve_presets_dir_fallback() == '${pc_root}/fallbacks/data/dots/shell-presets'
	assert resolve_preset_state_file_fallback() == '${pc_root}/fallbacks/state/dots/current-shell-preset'
	assert scheme_state_file_fallback() == '${pc_root}/fallbacks/state/dots/scheme/state.json'
	assert color_scheme_file_fallback() == '${pc_root}/fallbacks/cache/dots/smart-colors/scheme.json'
	assert resolve_snapshots_dir_fallback() == '${pc_root}/fallbacks/cache/dots/snapshots'
	assert resolve_wallpapers_dir_fallback() == '${pc_root}/fallbacks/data/dots/wallpapers'
	assert resolve_wallpaper_pointer_file_fallback() == '${pc_root}/fallbacks/state/dots/wallpaper/path'
	assert resolve_notifs_file_fallback() == '${pc_root}/fallbacks/state/dots/notifs.json'
	assert resolve_image_cache_dir_fallback() == '${pc_root}/fallbacks/cache/dots/imagecache'
	assert resolve_notif_image_cache_dir_fallback() == '${pc_root}/fallbacks/cache/dots/imagecache/notifs'
	pc_unset_xdg()
}

fn test_pc_explicit_overrides_win() {
	pc_set_xdg('overrides')
	os.setenv('HORNERO_THEMES_DIR', '/tmp/hx-pc-ov/themes', true)
	os.setenv('HORNERO_PRESETS_DIR', '/tmp/hx-pc-ov/presets', true)
	os.setenv('HORNERO_PRESET_STATE_FILE', '/tmp/hx-pc-ov/preset-current', true)
	os.setenv('HORNERO_SNAPSHOTS_DIR', '/tmp/hx-pc-ov/snapshots', true)
	os.setenv('HORNERO_WALLPAPER_POINTER_FILE', '/tmp/hx-pc-ov/wallpaper-path', true)
	os.setenv('HORNERO_NOTIFS_FILE', '/tmp/hx-pc-ov/notifs.json', true)
	os.setenv('HORNERO_IMAGE_CACHE_DIR', '/tmp/hx-pc-ov/imagecache', true)
	os.setenv('HORNERO_WALLPAPERS_DIR', '/tmp/hx-pc-ov/wallpapers', true)
	assert resolve_themes_dir() == '/tmp/hx-pc-ov/themes'
	assert resolve_themes_dirs_for_read() == ['/tmp/hx-pc-ov/themes']
	assert resolve_presets_dir() == '/tmp/hx-pc-ov/presets'
	assert resolve_preset_state_file() == '/tmp/hx-pc-ov/preset-current'
	assert resolve_preset_state_file_for_read() == '/tmp/hx-pc-ov/preset-current'
	assert resolve_snapshots_dir() == '/tmp/hx-pc-ov/snapshots'
	assert resolve_wallpaper_pointer_file() == '/tmp/hx-pc-ov/wallpaper-path'
	assert resolve_wallpaper_pointer_file_for_read() == '/tmp/hx-pc-ov/wallpaper-path'
	assert resolve_notifs_file() == '/tmp/hx-pc-ov/notifs.json'
	assert resolve_image_cache_dir() == '/tmp/hx-pc-ov/imagecache'
	assert resolve_notif_image_cache_dir() == '/tmp/hx-pc-ov/imagecache/notifs'
	assert resolve_wallpapers_dir() == '/tmp/hx-pc-ov/wallpapers'
	pc_unset_xdg()
}

fn test_pc_themes_canonical_first() {
	pc_set_xdg('themes-both')
	pc_write('${pc_root}/themes-both/data/hornero/themes/alpha/theme.json', '{"schemaVersion":1,"id":"alpha","name":"Canonical Alpha","defaultWallpaper":"a.jpg","wallpaperDir":"alpha"}')
	pc_write('${pc_root}/themes-both/data/dots/themes/alpha/theme.json', '{"schemaVersion":1,"id":"alpha","name":"Legacy Alpha","defaultWallpaper":"a.jpg","wallpaperDir":"alpha"}')
	pc_write('${pc_root}/themes-both/data/dots/themes/beta/theme.json', '{"schemaVersion":1,"id":"beta","name":"Legacy Beta","defaultWallpaper":"b.jpg","wallpaperDir":"beta"}')
	dirs := resolve_themes_dirs_for_read()
	assert dirs.len == 2
	assert dirs[0] == resolve_themes_dir()
	assert dirs[1] == resolve_themes_dir_fallback()
	packs := list_theme_packs() or {
		assert false
		return
	}
	assert packs.len == 2
	assert packs[0].id == 'alpha'
	assert packs[0].name == 'Canonical Alpha'
	assert packs[1].id == 'beta'
	show := show_theme_pack('alpha') or {
		assert false
		return
	}
	assert show.name == 'Canonical Alpha'
	pc_unset_xdg()
}

fn test_pc_themes_fallback_only() {
	pc_set_xdg('themes-legacy')
	pc_write('${pc_root}/themes-legacy/data/dots/themes/legacy-only/theme.json', '{"schemaVersion":1,"id":"legacy-only","name":"Legacy Only","defaultWallpaper":"l.jpg","wallpaperDir":"legacy-only"}')
	dirs := resolve_themes_dirs_for_read()
	assert dirs == [resolve_themes_dir_fallback()]
	packs := list_theme_packs() or {
		assert false
		return
	}
	assert packs.len == 1
	assert packs[0].id == 'legacy-only'
	// Reads never materialize the canonical side.
	assert !os.exists(resolve_themes_dir())
	pc_unset_xdg()
}

fn test_pc_presets_merge_and_pointer_fallback() {
	pc_set_xdg('presets-both')
	pc_write('${pc_root}/presets-both/data/hornero/shell-presets/shared.json', '{"_name":"Canonical Shared","bar":{"position":"left"}}')
	pc_write('${pc_root}/presets-both/data/hornero/shell-presets/canon-only.json', '{"_name":"Canon Only","bar":{"position":"top"}}')
	pc_write('${pc_root}/presets-both/data/dots/shell-presets/shared.json', '{"_name":"Legacy Shared","bar":{"position":"bottom"}}')
	pc_write('${pc_root}/presets-both/data/dots/shell-presets/legacy-only.json', '{"_name":"Legacy Only","bar":{"position":"right"}}')
	pc_write('${pc_root}/presets-both/state/hornero/current-shell-preset', 'canon-only\n')
	assert current_preset_name() == 'canon-only'
	assert resolve_preset_state_file_for_read() == resolve_preset_state_file()
	presets := list_presets() or {
		assert false
		return
	}
	assert presets.len == 3
	assert presets[0].name == 'canon-only'
	assert presets[1].name == 'legacy-only'
	assert presets[2].name == 'shared'
	assert presets[2].display == 'Canonical Shared'
	assert presets[0].active
	// Drop the canonical pointer: the legacy one takes over.
	os.rm(resolve_preset_state_file()) or { assert false }
	pc_write('${pc_root}/presets-both/state/dots/current-shell-preset', 'legacy-only\n')
	assert resolve_preset_state_file_for_read() == resolve_preset_state_file_fallback()
	assert current_preset_name() == 'legacy-only'
	pc_unset_xdg()
}

fn test_pc_scheme_canonical_first() {
	pc_set_xdg('scheme-both')
	pc_write('${pc_root}/scheme-both/state/hornero/scheme/state.json', '{"mode":"dark","flavour":"t-spot","variant":"tonalspot","gtkColorScheme":"prefer-dark"}')
	pc_write('${pc_root}/scheme-both/state/dots/scheme/state.json', '{"mode":"light","flavour":"l-spot","variant":"expressive"}')
	pc_write('${pc_root}/scheme-both/cache/dots/smart-colors/scheme.json', '{"mode":"light","flavour":"legacy"}')
	s := read_scheme_state()
	assert s.mode == 'dark'
	assert s.flavour == 't-spot'
	assert s.variant == 'tonalspot'
	assert s.gtk_color_scheme == 'prefer-dark'
	assert s.state_file == scheme_state_file()
	// Drop the canonical state file: legacy values take over.
	os.rm(scheme_state_file()) or { assert false }
	s2 := read_scheme_state()
	assert s2.mode == 'light'
	assert s2.flavour == 'l-spot'
	assert s2.state_file == scheme_state_file_fallback()
	pc_unset_xdg()
}

fn test_pc_scheme_meta_fallback_without_state() {
	pc_set_xdg('scheme-meta')
	pc_write('${pc_root}/scheme-meta/cache/dots/smart-colors/scheme.json', '{"mode":"light","flavour":"meta-legacy"}')
	s := read_scheme_state()
	assert s.mode == 'light'
	assert s.flavour == 'meta-legacy'
	assert s.scheme_present
	assert !s.state_present
	assert s.scheme_file == color_scheme_file_fallback()
	pc_unset_xdg()
}

fn test_pc_snapshots_merge_canonical_first() {
	pc_set_xdg('snapshots-both')
	pc_write('${pc_root}/snapshots-both/cache/hornero/snapshots/config_20260301_020000/metadata.json', '{"id":"config_20260301_020000","timestamp":"2026-03-01T02:00:00","hostname":"canon","dotfiles_commit":"aaa"}')
	pc_write('${pc_root}/snapshots-both/cache/dots/snapshots/config_20260301_020000/metadata.json', '{"id":"config_20260301_020000","timestamp":"2026-03-01T02:00:00","hostname":"legacy","dotfiles_commit":"bbb"}')
	pc_write('${pc_root}/snapshots-both/cache/dots/snapshots/config_20260401_020000/metadata.json', '{"id":"config_20260401_020000","timestamp":"2026-04-01T02:00:00","hostname":"legacy","dotfiles_commit":"ccc"}')
	snaps := list_snapshots() or {
		assert false
		return
	}
	assert snaps.len == 2
	assert snaps[0].id == 'config_20260301_020000'
	assert snaps[0].hostname == 'canon'
	assert snaps[1].hostname == 'legacy'
	pc_unset_xdg()
}

fn test_pc_wallpaper_pointer_canonical_first() {
	pc_set_xdg('wallpaper-both')
	pc_write('${pc_root}/wallpaper-both/state/hornero/wallpaper/path', '/canon/wall.jpg\n')
	pc_write('${pc_root}/wallpaper-both/state/dots/wallpaper/path', '/legacy/wall.jpg\n')
	assert resolve_wallpaper_pointer_file_for_read() == resolve_wallpaper_pointer_file()
	assert read_wallpaper_pointer() == '/canon/wall.jpg'
	os.rm(resolve_wallpaper_pointer_file()) or { assert false }
	assert resolve_wallpaper_pointer_file_for_read() == resolve_wallpaper_pointer_file_fallback()
	assert read_wallpaper_pointer() == '/legacy/wall.jpg'
	pc_unset_xdg()
}

fn test_pc_notifs_and_cache_paths() {
	pc_set_xdg('notifs-cache')
	pc_write('${pc_root}/notifs-cache/state/dots/notifs.json', '[]')
	assert resolve_notifs_file_for_read() == resolve_notifs_file_fallback()
	pc_write('${pc_root}/notifs-cache/state/hornero/notifs.json', '[]')
	assert resolve_notifs_file_for_read() == resolve_notifs_file()
	assert resolve_image_cache_dir() == '${pc_root}/notifs-cache/cache/hornero/imagecache'
	assert resolve_image_cache_dir_fallback() == '${pc_root}/notifs-cache/cache/dots/imagecache'
	// Absent pointer reads as empty without creating anything.
	os.setenv('XDG_STATE_HOME', '${pc_root}/notifs-cache/empty-state', true)
	assert read_wallpaper_pointer() == ''
	assert !os.exists('${pc_root}/notifs-cache/empty-state/hornero/wallpaper/path')
	pc_unset_xdg()
}
