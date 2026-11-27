module hornero_core

import os
import x.json2

// Theme --full fixtures: everything lives under /tmp, env overrides
// isolate resolution, and each test restores what it sets (no network,
// no compositor, no HOME mutation).

const theme_full_root = '/tmp/hx-theme-full-test'

// theme_full_pack builds a valid schema-v2 pack from the Signal Night test
// fixture (cli/testdata/signal-themes), overriding id/name and extras.
fn theme_full_pack(id string, extra string) string {
	fixture := os.join_path(os.dir(@FILE), '..', '..', 'testdata', 'signal-themes',
		'hornero-signal-night', 'theme.json')
	raw := os.read_file(fixture) or { panic('missing fixture ${fixture}') }
	mut m := json2.decode[map[string]json2.Any](raw) or { panic(err) }
	m['id'] = json2.Any(id)
	m['name'] = json2.Any(id)
	for key in ['description', 'gtkTheme', 'iconTheme', 'defaultWallpaper', 'wallpaperDir', 'tags',
		'collection', 'collectionOrder'] {
		m.delete(key)
	}
	extras := json2.decode[map[string]json2.Any](extra) or { panic(err) }
	for k, v in extras {
		m[k] = v
	}
	return json2.encode(m)
}

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
	theme_full_write(theme_full_root + '/themes/pack-a/theme.json', theme_full_pack('pack-a', '{"name":"Pack A","description":"first","tags":["dark","cozy"],"gtkTheme":"Orchis-Dark-Compact","iconTheme":"Papirus-Dark","defaultWallpaper":"a.jpg","wallpaperDir":"hx-full-a","collection":"hornero-originals","collectionOrder":3}'))
	theme_full_write(theme_full_root + '/themes/pack-a/preview.jpg', 'fake')
	theme_full_write(theme_full_root + '/themes/pack-b/theme.json', theme_full_pack('pack-b', '{"name":"Pack B"}'))
	// Retired schema-v1 packs are not Signal themes and are never listed.
	theme_full_write(theme_full_root + '/themes/pack-old/theme.json', '{"schemaVersion":1,"id":"pack-old","name":"Old","schemeType":"vibrant"}')
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
	assert a['collection'].str() == 'hornero-originals'
	assert a['collectionOrder'].i64() == 3
	assert a['schemaVersion'].int() == 2
	assert a['mode'].str() == 'dark'
	assert 'schemeType' !in a
	assert 'darkMode' !in a
	assert a['gtkTheme'].str() == 'Orchis-Dark-Compact'
	assert 'gtkPreferDark' !in a
	assert a['colorOnly'].bool() == false
	swatch := a['swatch'].as_map()
	assert swatch.len == 5
	assert swatch['signal'].str() == '#F2AC52'
	assert a['gtkColorScheme'].str() == 'prefer-dark'
	assert a['wallpaperDir'].str() == 'hx-full-a'
	assert a['defaultWallpaper'].str() == 'a.jpg'
	assert a['preview'].str().ends_with('pack-a/preview.jpg')
	walls := a['wallpapers'].as_array()
	assert walls.len == 2
	assert walls[0].str() == 'a.jpg'
	assert walls[1].str() == 'b.png'
	wall_map := a['wallpaperPaths'].as_map()
	assert wall_map['a.jpg'].str().ends_with('hx-full-a/a.jpg')
	assert a['wallpaperPath'].str().ends_with('hx-full-a/a.jpg')
	b := arr[1].as_map()
	assert b['id'].str() == 'pack-b'
	assert b['collection'].str() == ''
	assert b['collectionOrder'].i64() == 0
	assert b['gtkTheme'].str() == 'Hornero-Signal'
	assert b['iconTheme'].str() == 'Papirus-Dark'
	assert b['wallpapers'].as_array().len == 0
	assert b['wallpaperPath'].str() == ''
	theme_full_restore(old_themes, old_walls)
}

fn test_theme_list_full_policy_follows_mode() {
	old_themes, old_walls := theme_full_isolate()
	theme_full_write(theme_full_root + '/themes/pack-c/theme.json', theme_full_pack('pack-c', '{"mode":"light","gtkTheme":"Orchis-Dark"}'))
	r := theme_list_full_report()
	assert r.ok
	arr := json2.decode[[]json2.Any](r.message) or {
		assert false, 'full message is a JSON array: ${err}'
		[]json2.Any{}
	}
	assert arr.len == 3
	c := arr[2].as_map()
	assert c['id'].str() == 'pack-c'
	assert c['mode'].str() == 'light'
	assert c['gtkColorScheme'].str() == 'prefer-light'
	theme_full_restore(old_themes, old_walls)
}

fn test_theme_list_full_does_not_claim_missing_default_wallpaper() {
	old_themes, old_walls := theme_full_isolate()
	theme_full_write(theme_full_root + '/themes/pack-c/theme.json', theme_full_pack('pack-c', '{"defaultWallpaper":"missing.jpg","wallpaperDir":"pack-c"}'))
	r := theme_list_full_report()
	assert r.ok
	arr := json2.decode[[]json2.Any](r.message) or {
		assert false, 'full message is a JSON array: ${err}'
		[]json2.Any{}
	}
	pack := arr[2].as_map()
	assert pack['id'].str() == 'pack-c'
	assert pack['defaultWallpaper'].str() == 'missing.jpg'
	assert pack['wallpaperPath'].str() == ''
	assert pack['wallpapers'].as_array().len == 0
	theme_full_restore(old_themes, old_walls)
}
