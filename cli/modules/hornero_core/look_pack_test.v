module hornero_core

import os
import x.json2

const lp_factory = '{"appearance":{"rounding":{"scale":1},"reducedMotion":false,"anim":{"curveStyle":"smooth"}},"launcher":{"favouriteApps":[],"sizes":{"itemWidth":640}},"general":{"apps":{"terminal":["kitty"]}}}'

fn lp_obj(s string) map[string]json2.Any {
	return (json2.decode[json2.Any](s) or { panic(err) }).as_map()
}

fn test_look_pack_export_lists_only_changes() {
	cur := lp_obj('{"appearance":{"rounding":{"scale":1.6},"reducedMotion":false,"anim":{"curveStyle":"smooth"}},"launcher":{"favouriteApps":["x"],"sizes":{"itemWidth":700}},"general":{"apps":{"terminal":["foot"]}}}')
	text := look_pack_export_text(cur, lp_obj(lp_factory), 'Cozy')
	pack := lp_obj(text)
	assert pack['schema'].str() == look_pack_schema
	assert pack['name'].str() == 'Cozy'
	values := pack['values'].as_map()
	assert values.len == 2
	assert values['appearance.rounding.scale'].f64() == 1.6
	assert values['launcher.sizes.itemWidth'].f64() == 700
}

fn test_look_pack_export_of_factory_is_empty() {
	text := look_pack_export_text(lp_obj(lp_factory), lp_obj(lp_factory), 'x')
	assert lp_obj(text)['values'].as_map().len == 0
}

fn test_look_pack_validate_rejects_and_clamps() {
	pack := lp_obj('{"schema":"hornero/look-pack@1","values":{"appearance.rounding.scale":9999,"appearance.reducedMotion":"yes","launcher.favouriteApps":["x"],"general.apps.terminal":["foot"],"nope.x":1}}')
	v := look_pack_validate(pack, lp_obj(lp_factory)) or { panic(err) }
	assert v.accepted.len == 1
	assert v.accepted['appearance.rounding.scale'].f64() == 10
	assert v.rejected.len == 4
}

fn test_look_pack_validate_rejects_foreign_documents() {
	look_pack_validate(lp_obj('{"schema":"other"}'), lp_obj(lp_factory)) or {
		assert err.msg().contains('not a Hornero look pack')
		return
	}
	assert false, 'expected error'
}

fn test_look_pack_import_round_trip_and_gates() {
	root := os.join_path(os.temp_dir(), 'hx-lookpack-test')
	os.rmdir_all(root) or {}
	os.mkdir_all(root + '/config/hornero') or { assert false }
	os.write_file(root + '/factory.json', lp_factory) or { assert false }
	os.write_file(root + '/config/hornero/shell.json', '{"general":{"apps":{"terminal":["foot"]}}}') or {
		assert false
	}
	os.write_file(root + '/pack.json', '{"schema":"hornero/look-pack@1","values":{"appearance.rounding.scale":1.6}}') or {
		assert false
	}
	old := os.getenv('XDG_CONFIG_HOME')
	os.setenv('XDG_CONFIG_HOME', root + '/config', true)
	defer {
		os.setenv('XDG_CONFIG_HOME', old, true)
		os.rmdir_all(root) or {}
	}
	refused := config_look_import_report(LookPackImportOptions{
		file:    root + '/pack.json'
		factory: root + '/factory.json'
	})
	assert !refused.ok
	dry := config_look_import_report(LookPackImportOptions{
		file:    root + '/pack.json'
		factory: root + '/factory.json'
		dry_run: true
	})
	assert dry.ok
	assert !(os.read_file(root + '/config/hornero/shell.json') or { '' }).contains('rounding')
	done := config_look_import_report(LookPackImportOptions{
		file:    root + '/pack.json'
		factory: root + '/factory.json'
		yes:     true
	})
	assert done.ok
	after := lp_obj(os.read_file(root + '/config/hornero/shell.json') or { '' })
	assert after['appearance'].as_map()['rounding'].as_map()['scale'].f64() == 1.6
	assert after['general'].as_map()['apps'].as_map()['terminal'].as_array()[0].str() == 'foot'
	exported := config_look_export_report(LookPackExportOptions{
		factory: root + '/factory.json'
	})
	assert exported.ok && exported.message.contains('appearance.rounding.scale')
}
