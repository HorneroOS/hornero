module hornero_core

import os

fn test_scheme_json_colour_reads_material_background_role() {
	base := os.join_path(os.temp_dir(), 'hornero-scheme-colour-test')
	os.rmdir_all(base) or {}
	os.mkdir_all(os.join_path(base, 'cache')) or { assert false }
	os.setenv('XDG_CACHE_HOME', os.join_path(base, 'cache'), true)
	defer {
		os.unsetenv('XDG_CACHE_HOME')
		os.rmdir_all(base) or {}
	}
	path := color_scheme_file()
	os.mkdir_all(os.dir(path)) or { assert false }
	os.write_file(path, '{"mode":"dark","colours":{"background":"#17212c","primary":"#80b8ff"}}') or {
		assert false
	}
	assert scheme_json_colour('background') == '#17212c'
	assert scheme_json_colour('primary') == '#80b8ff'
	assert scheme_json_colour('missing') == ''
}
