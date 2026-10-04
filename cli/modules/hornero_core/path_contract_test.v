module hornero_core

import os

// Path-contract conformance tests (docs/PATH_CONTRACT.md, hornero row).
// Hornero-owned paths are the only read/write contract. Everything lives under /tmp with XDG
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
	// Hermetic system catalogues: never read the host's /usr/share.
	os.setenv('XDG_DATA_DIRS', '${pc_root}/${tag}/sys', true)
	os.unsetenv('HORNERO_THEMES_DIR')
	os.unsetenv('HORNERO_PRESETS_DIR')
	os.unsetenv('HORNERO_PRESET_STATE_FILE')
	os.unsetenv('HORNERO_SNAPSHOTS_DIR')
	os.unsetenv('HORNERO_WALLPAPERS_DIR')
	os.unsetenv('HORNERO_PICTURES_WALLPAPERS')
	os.unsetenv('HORNERO_WALLPAPER_POINTER_FILE')
	os.unsetenv('HORNERO_NOTIFS_FILE')
	os.unsetenv('HORNERO_IMAGE_CACHE_DIR')
}

fn pc_unset_xdg() {
	os.unsetenv('XDG_DATA_HOME')
	os.unsetenv('XDG_DATA_DIRS')
	os.unsetenv('XDG_STATE_HOME')
	os.unsetenv('XDG_CACHE_HOME')
	os.unsetenv('HORNERO_THEMES_DIR')
	os.unsetenv('HORNERO_PRESETS_DIR')
	os.unsetenv('HORNERO_PRESET_STATE_FILE')
	os.unsetenv('HORNERO_SNAPSHOTS_DIR')
	os.unsetenv('HORNERO_WALLPAPERS_DIR')
	os.unsetenv('HORNERO_PICTURES_WALLPAPERS')
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
	assert resolve_snapshots_dir() == '${pc_root}/write-targets/data/hornero/snapshots'
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
		assert p.contains('/hornero/'), 'write target must be Hornero-owned: ${p}'
	}
	pc_unset_xdg()
}

fn test_pc_unsupported_namespace_is_not_resolved() {
	pc_set_xdg('unsupported-namespace')
	os.mkdir_all('${pc_root}/unsupported-namespace/data/retired/themes') or { assert false }
	os.mkdir_all('${pc_root}/unsupported-namespace/cache/retired/snapshots') or { assert false }
	assert resolve_themes_dirs_for_read() == []
	assert resolve_snapshots_dirs_for_read() == []
	assert resolve_wallpapers_dir() == '${pc_root}/unsupported-namespace/data/hornero/wallpapers'
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
	assert resolve_wallpaper_pointer_file() == '/tmp/hx-pc-ov/wallpaper-path'
	assert resolve_notifs_file() == '/tmp/hx-pc-ov/notifs.json'
	assert resolve_image_cache_dir() == '/tmp/hx-pc-ov/imagecache'
	assert resolve_notif_image_cache_dir() == '/tmp/hx-pc-ov/imagecache/notifs'
	assert resolve_wallpapers_dir() == '/tmp/hx-pc-ov/wallpapers'
	assert resolve_wallpapers_dirs_for_read() == ['/tmp/hx-pc-ov/wallpapers']
	pc_unset_xdg()
}

fn test_pc_system_wallpaper_catalogue_is_read_only_fallback() {
	pc_set_xdg('system-wallpapers')
	system_root := '${pc_root}/system-wallpapers/sys/hornero/wallpapers'
	empty_pictures := '${pc_root}/system-wallpapers/pictures-empty'
	os.setenv('HORNERO_PICTURES_WALLPAPERS', empty_pictures, true)
	pc_write('${system_root}/pampa/pampa-01.png', 'system-wallpaper')
	pc_write('${pc_root}/system-wallpapers/sys/hornero/themes/pampa/theme.json', '{"schemaVersion":1,"id":"pampa","name":"Pampa","defaultWallpaper":"pampa-01.png","wallpaperDir":"pampa","darkMode":true,"gtkTheme":"Hornero-Pampa","iconTheme":"Papirus-Dark"}')
	assert resolve_wallpapers_dirs_for_read() == [system_root]
	resolved := resolve_pack_wallpaper('pampa', 'pampa', 'pampa-01.png', '') or {
		assert false, err.msg()
		''
	}
	assert resolved == '${system_root}/pampa/pampa-01.png'
	full := theme_list_full_report()
	assert full.ok
	assert full.message.contains('"wallpaperPath":"${system_root}/pampa/pampa-01.png"')
	assert resolve_wallpapers_dir() == '${pc_root}/system-wallpapers/data/hornero/wallpapers'
	pc_write('${pc_root}/system-wallpapers/data/hornero/wallpapers/pampa/pampa-01.png', 'user-wallpaper')
	assert resolve_wallpapers_dirs_for_read() == [resolve_wallpapers_dir(), system_root]
	resolved_user := resolve_pack_wallpaper('pampa', 'pampa', 'pampa-01.png', '') or {
		assert false, err.msg()
		''
	}
	assert resolved_user == '${pc_root}/system-wallpapers/data/hornero/wallpapers/pampa/pampa-01.png'
	pictures := '${pc_root}/system-wallpapers/pictures'
	override := '${pc_root}/system-wallpapers/override'
	pc_write('${pictures}/pampa/pampa-01.png', 'picture-wallpaper')
	pc_write('${override}/pampa/pampa-01.png', 'override-wallpaper')
	os.unsetenv('HORNERO_PICTURES_WALLPAPERS')
	assert resolve_pictures_wallpapers_dir() == os.join_path(os.home_dir(), 'Pictures', 'Wallpapers')
	canonical_pictures := '${pc_root}/system-wallpapers/pictures-canonical'
	os.setenv('HORNERO_PICTURES_WALLPAPERS', canonical_pictures, true)
	assert resolve_pictures_wallpapers_dir() == canonical_pictures
	os.unsetenv('HORNERO_PICTURES_WALLPAPERS')
	os.setenv('HORNERO_WALLPAPERS_DIR', override, true)
	os.setenv('HORNERO_PICTURES_WALLPAPERS', pictures, true)
	resolved_override := resolve_pack_wallpaper('pampa', 'pampa', 'pampa-01.png', '') or {
		assert false, err.msg()
		''
	}
	assert resolved_override == '${override}/pampa/pampa-01.png'
	pc_unset_xdg()
}

fn test_pc_themes_use_only_user_and_system_catalogues() {
	pc_set_xdg('themes-only-current')
	pc_write('${pc_root}/themes-only-current/data/hornero/themes/alpha/theme.json', '{"schemaVersion":1,"id":"alpha","name":"Alpha","defaultWallpaper":"a.jpg","wallpaperDir":"alpha"}')
	pc_write('${pc_root}/themes-only-current/data/retired/themes/beta/theme.json', '{"schemaVersion":1,"id":"beta","name":"Old Beta","defaultWallpaper":"b.jpg","wallpaperDir":"beta"}')
	dirs := resolve_themes_dirs_for_read()
	assert dirs == [resolve_themes_dir()]
	packs := list_theme_packs() or {
		assert false
		return
	}
	assert packs.len == 1
	assert packs[0].id == 'alpha'
	pc_unset_xdg()
}

fn test_pc_themes_do_not_read_old_namespace_only() {
	pc_set_xdg('themes-old-only')
	pc_write('${pc_root}/themes-old-only/data/retired/themes/old/theme.json', '{"schemaVersion":1,"id":"old","name":"Old","defaultWallpaper":"o.jpg","wallpaperDir":"old"}')
	assert resolve_themes_dirs_for_read() == []
	if packs := list_theme_packs() {
		assert packs.len == 0
	} else {
		assert err.msg().contains('no themes installed')
	}
	pc_unset_xdg()
}

fn test_pc_presets_use_canonical_catalogue_and_pointer_only() {
	pc_set_xdg('presets-current-only')
	pc_write('${pc_root}/presets-current-only/data/hornero/shell-presets/one.json', '{"_name":"One","bars":[]}')
	pc_write('${pc_root}/presets-current-only/data/retired/shell-presets/old.json', '{"_name":"Old","bars":[]}')
	pc_write('${pc_root}/presets-current-only/state/retired/current-shell-preset', 'old\n')
	assert current_preset_name() == ''
	presets := list_presets() or {
		assert false
		return
	}
	assert presets.len == 1
	assert presets[0].name == 'one'
	pc_unset_xdg()
}

fn test_pc_scheme_uses_only_canonical_state() {
	pc_set_xdg('scheme-current-only')
	pc_write('${pc_root}/scheme-current-only/state/retired/scheme/state.json', '{"mode":"light","flavour":"old"}')
	pc_write('${pc_root}/scheme-current-only/cache/retired/smart-colors/scheme.json', '{"mode":"light","flavour":"old"}')
	s := read_scheme_state()
	assert s.mode == ''
	assert s.flavour == ''
	assert s.state_file == scheme_state_file()
	assert s.scheme_file == color_scheme_file()
	pc_unset_xdg()
}

fn test_pc_scheme_reads_canonical_runtime_metadata_without_state() {
	pc_set_xdg('scheme-meta-current')
	pc_write('${pc_root}/scheme-meta-current/cache/hornero/smart-colors/scheme.json', '{"mode":"light","flavour":"expressive"}')
	s := read_scheme_state()
	assert s.mode == 'light'
	assert s.flavour == 'expressive'
	assert s.scheme_present
	assert !s.state_present
	assert s.scheme_file == color_scheme_file()
	pc_unset_xdg()
}

fn test_pc_snapshots_ignore_old_namespace() {
	pc_set_xdg('snapshots-current-only')
	pc_write('${pc_root}/snapshots-current-only/cache/retired/snapshots/config_old/metadata.json', '{"id":"config_old","timestamp":"old","hostname":"old"}')
	assert resolve_snapshots_dirs_for_read() == []
	if snaps := list_snapshots() {
		assert snaps.len == 0
	} else {
		assert err.msg().contains('no snapshots')
	}
	pc_unset_xdg()
}

fn test_pc_wallpaper_pointer_ignores_old_namespace() {
	pc_set_xdg('wallpaper-old-only')
	pc_write('${pc_root}/wallpaper-old-only/state/retired/wallpaper/path', '/old/wall.jpg\n')
	assert resolve_wallpaper_pointer_file() == '${pc_root}/wallpaper-old-only/state/hornero/wallpaper/path'
	assert read_wallpaper_pointer() == ''
	pc_unset_xdg()
}

fn test_pc_notifs_and_cache_paths_are_canonical() {
	pc_set_xdg('notifs-cache-current')
	pc_write('${pc_root}/notifs-cache-current/state/retired/notifs.json', '[]')
	assert resolve_notifs_file() == '${pc_root}/notifs-cache-current/state/hornero/notifs.json'
	assert resolve_image_cache_dir() == '${pc_root}/notifs-cache-current/cache/hornero/imagecache'
	// An absent wallpaper pointer reads as empty without creating anything.
	os.setenv('XDG_STATE_HOME', '${pc_root}/notifs-cache-current/empty-state', true)
	assert read_wallpaper_pointer() == ''
	assert !os.exists('${pc_root}/notifs-cache-current/empty-state/hornero/wallpaper/path')
	pc_unset_xdg()
}

fn test_pc_manifest_object_shape_validates() {
	// Contract row 8: the shipped manifest is an object with a `themes`
	// array (HorneroOS/config profiles/themes/wallpapers.manifest.json),
	// never a top-level array.
	pc_set_xdg('manifest-object')
	pc_write('${pc_root}/manifest-object/data/hornero/themes/wallpapers.manifest.json',
		'{"provenance": "t", "note": "n", "themes": [{"id": "a", "wallpaperDir": "a"}, {"id": "b"}]}')
	rep := config_validate_report()
	assert rep.ok, rep.message
	assert rep.message.contains('2 entries'), rep.message
	pc_unset_xdg()
}

fn test_pc_manifest_top_level_array_fails() {
	pc_set_xdg('manifest-array')
	pc_write('${pc_root}/manifest-array/data/hornero/themes/wallpapers.manifest.json',
		'[{"id": "a", "name": "A"}]')
	rep := config_validate_report()
	assert !rep.ok, rep.message
	assert rep.message.contains('does not parse'), rep.message
	pc_unset_xdg()
}

fn test_pc_manifest_missing_is_optional() {
	pc_set_xdg('manifest-missing')
	rep := config_validate_report()
	assert rep.ok, rep.message
	assert rep.message.contains('missing theme manifest'), rep.message
	pc_unset_xdg()
}

// hornero#96: package installs ship catalogues under XDG_DATA_DIRS only.
fn test_pc_system_catalogues_package_only_install() {
	pc_set_xdg('sys-only')
	pc_write('${pc_root}/sys-only/sys/hornero/shell-presets/cockpit-clear.json', '{"_name":"Cockpit Clear","bar":{"position":"top"}}')
	pc_write('${pc_root}/sys-only/sys/hornero/themes/hornero-dark/theme.json', '{"schemaVersion":1,"id":"hornero-dark","name":"Hornero Dark","defaultWallpaper":"d.jpg","wallpaperDir":"hornero-dark"}')
	assert resolve_presets_dirs_for_read() == ['${pc_root}/sys-only/sys/hornero/shell-presets']
	assert resolve_themes_dirs_for_read() == ['${pc_root}/sys-only/sys/hornero/themes']
	presets := list_presets() or {
		assert false, err.msg()
		return
	}
	assert presets.map(it.name) == ['cockpit-clear']
	packs := list_theme_packs() or {
		assert false, err.msg()
		return
	}
	assert packs.map(it.id) == ['hornero-dark']
	// Reads never materialize the user side.
	assert !os.exists(resolve_presets_dir())
	assert !os.exists(resolve_themes_dir())
	pc_unset_xdg()
}

fn test_pc_system_catalogues_rank_below_user() {
	pc_set_xdg('sys-rank')
	pc_write('${pc_root}/sys-rank/data/hornero/shell-presets/shared.json', '{"_name":"User Shared","bar":{"position":"left"}}')
	pc_write('${pc_root}/sys-rank/sys/hornero/shell-presets/shared.json', '{"_name":"System Shared","bar":{"position":"top"}}')
	pc_write('${pc_root}/sys-rank/sys/hornero/shell-presets/sys-only.json', '{"_name":"System Only","bar":{"position":"bottom"}}')
	dirs := resolve_presets_dirs_for_read()
	assert dirs == [resolve_presets_dir(), '${pc_root}/sys-rank/sys/hornero/shell-presets']
	presets := list_presets() or {
		assert false, err.msg()
		return
	}
	assert presets.map(it.name) == ['shared', 'sys-only']
	assert presets[0].display == 'User Shared'
	pc_unset_xdg()
}

fn test_pc_system_data_dirs_default_and_dedup() {
	inherited := os.getenv_opt('XDG_DATA_DIRS')
	defer {
		if v := inherited {
			os.setenv('XDG_DATA_DIRS', v, true)
		} else {
			os.unsetenv('XDG_DATA_DIRS')
		}
	}
	os.unsetenv('XDG_DATA_DIRS')
	assert system_data_dirs() == ['/usr/local/share', '/usr/share']
	os.setenv('XDG_DATA_DIRS', '/a::/b:/a', true)
	assert system_data_dirs() == ['/a', '/b']
}

fn test_pc_m3_script_user_then_system() {
	pc_set_xdg('m3')
	old_home := os.getenv('HOME')
	os.setenv('HOME', '${pc_root}/m3/home', true)
	os.unsetenv('HORNERO_M3_SCRIPT')
	user := '${pc_root}/m3/home/.local/lib/hornero/generate-m3-colors.py'
	sys := '${pc_root}/m3/sys/hornero/lib/hornero/generate-m3-colors.py'
	// Nothing installed: the documented user path is named.
	assert resolve_m3_script() == user
	pc_write(sys, '# packaged\n')
	assert resolve_m3_script() == sys
	pc_write(user, '# user\n')
	assert resolve_m3_script() == user
	os.setenv('HOME', old_home, true)
	pc_unset_xdg()
}
