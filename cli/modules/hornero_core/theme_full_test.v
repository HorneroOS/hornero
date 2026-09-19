module hornero_core

import os
import x.json2

// Theme --full fixtures: everything lives under /tmp, env overrides
// isolate resolution, and each test restores what it sets (no network,
// no compositor, no HOME mutation).

const theme_full_root = '/tmp/hx-theme-full-test'

const theme_full_a_json = '{"schemaVersion":1,"id":"pack-a","name":"Pack A","description":"first","tags":["dark","cozy"],"darkMode":true,"schemeType":"tonal-spot","gtkTheme":"Orchis-Dark-Compact","iconTheme":"Papirus-Dark","gtkPreferDark":true,"defaultWallpaper":"a.jpg","wallpaperDir":"hx-full-a","colorOnly":false}'

const theme_full_b_json = '{"id":"pack-b","name":"Pack B"}'

fn theme_full_write(path string, content string) {
	os.mkdir_all(os.dir(path)) or { assert false, 'mkdir ${os.dir(path)}' }
	os.write_file(path, content) or { assert false, 'write ${path}' }
}

fn theme_full_isolate() (string, string) {
	old_themes := os.getenv('HORNERO_THEMES_DIR')
	old_walls := os.getenv('HORNERO_WALLPAPERS_DIR')
	os.setenv('HORNERO_THEMES_DIR', theme_full_root + '/themes', true)
	os.setenv('HORNERO_WALLPAPERS_DIR', theme_full_root + '/walls', true)
	os.rmdir_all(theme_full_root) or {}
	theme_full_write(theme_full_root + '/themes/pack-a/theme.json', theme_full_a_json)
	theme_full_write(theme_full_root + '/themes/pack-a/preview.jpg', 'fake')
	theme_full_write(theme_full_root + '/themes/pack-b/theme.json', theme_full_b_json)
	theme_full_write(theme_full_root + '/walls/hx-full-a/a.jpg', 'fake')
	theme_full_write(theme_full_root + '/walls/hx-full-a/b.png', 'fake')
	theme_full_write(theme_full_root + '/walls/hx-full-a/notes.txt', 'not-an-image')
	return old_themes, old_walls
}

fn theme_full_restore(old_themes string, old_walls string) {
	os.setenv('HORNERO_THEMES_DIR', old_themes, true)
	os.setenv('HORNERO_WALLPAPERS_DIR', old_walls, true)
	os.rmdir_all(theme_full_root) or {}
}

fn test_theme_list_full_is_manifest_array() {
	old_themes, old_walls := theme_full_isolate()
	r := theme_list_full_report()
	assert r.ok
	assert r.data['format'] == 'full'
	arr := json2.decode[[]json2.Any](r.message) or {
		assert false, 'full message is a JSON array: ${err}'
		[]json2.Any{}
	}
	assert arr.len == 2
	a := arr[0].as_map()
	assert a['id'].str() == 'pack-a'
	assert a['name'].str() == 'Pack A'
	assert a['description'].str() == 'first'
	assert a['darkMode'].bool() == true
	assert a['gtkTheme'].str() == 'Orchis-Dark-Compact'
	assert a['gtkPreferDark'].bool() == true
	assert a['gtkColorScheme'].str() == 'prefer-dark'
	assert a['wallpaperDir'].str() == 'hx-full-a'
	assert a['defaultWallpaper'].str() == 'a.jpg'
	assert a['preview'].str().ends_with('pack-a/preview.jpg')
	walls := a['wallpapers'].arr()
	assert walls.len == 2
	assert walls[0].str() == 'a.jpg'
	assert walls[1].str() == 'b.png'
	wall_map := a['wallpaperPaths'].as_map()
	assert wall_map['a.jpg'].str().ends_with('hx-full-a/a.jpg')
	assert a['wallpaperPath'].str().ends_with('hx-full-a/a.jpg')
	b := arr[1].as_map()
	assert b['id'].str() == 'pack-b'
	assert b['schemeType'].str() == 'tonal-spot'
	assert b['iconTheme'].str() == 'Numix-Circle'
	assert b['wallpapers'].arr().len == 0
	assert b['wallpaperPath'].str() == ''
	theme_full_restore(old_themes, old_walls)
}

fn test_theme_list_full_light_gtk_heuristic() {
	old_themes, old_walls := theme_full_isolate()
	theme_full_write(theme_full_root + '/themes/pack-c/theme.json', '{"id":"pack-c","name":"C","gtkTheme":"Orchis-Light-Compact"}')
	r := theme_list_full_report()
	assert r.ok
	arr := json2.decode[[]json2.Any](r.message) or {
		assert false, 'full message is a JSON array: ${err}'
		[]json2.Any{}
	}
	assert arr.len == 3
	c := arr[2].as_map()
	assert c['id'].str() == 'pack-c'
	assert c['gtkPreferDark'].bool() == false
	assert c['gtkColorScheme'].str() == 'prefer-light'
	theme_full_restore(old_themes, old_walls)
}
