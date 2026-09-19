module hornero_core

import os
import x.json2

// Preset apply fixtures: everything lives under /tmp, env overrides
// isolate resolution, and each test restores what it sets (no network,
// no compositor, no HOME mutation).

const preset_root = '/tmp/hx-preset-test'

const preset_valid_json = '{"_name":"Test Left","_description":"fixture","_icon":"🏠","_iconMaterial":"dock_to_left","bar":{"position":"left","style":"attached","floatingMargin":14,"persistent":true,"showOnHover":true,"sizes":{"innerWidth":40},"entries":[{"id":"workspaces","enabled":true},{"id":"clock","enabled":true}]},"border":{"frameEnabled":true},"appearance":{"rounding":{"scale":1.0},"padding":{"scale":1.0},"spacing":{"scale":1.0}}}'

const preset_bad_position_json = '{"_name":"Bad","bar":{"position":"diagonal","style":"attached","floatingMargin":14,"showOnHover":true,"sizes":{"innerWidth":40},"entries":[{"id":"workspaces","enabled":true}]}}'

fn preset_test_write(path string, content string) {
	os.mkdir_all(os.dir(path)) or { assert false, 'mkdir ${os.dir(path)}' }
	os.write_file(path, content) or { assert false, 'write ${path}' }
}

fn preset_test_isolate() (string, string, string) {
	old_presets := os.getenv('HORNERO_PRESETS_DIR')
	old_marker := os.getenv('HORNERO_PRESET_STATE_FILE')
	old_xdg := os.getenv('XDG_CONFIG_HOME')
	os.setenv('HORNERO_PRESETS_DIR', preset_root + '/presets', true)
	os.setenv('HORNERO_PRESET_STATE_FILE', preset_root + '/state/current-shell-preset', true)
	os.setenv('XDG_CONFIG_HOME', preset_root + '/config', true)
	os.rmdir_all(preset_root) or {}
	preset_test_write(preset_root + '/presets/test-left.json', preset_valid_json)
	preset_test_write(preset_root + '/presets/bad.json', preset_bad_position_json)
	return old_presets, old_marker, old_xdg
}

fn preset_test_restore(old_presets string, old_marker string, old_xdg string) {
	os.setenv('HORNERO_PRESETS_DIR', old_presets, true)
	os.setenv('HORNERO_PRESET_STATE_FILE', old_marker, true)
	os.setenv('XDG_CONFIG_HOME', old_xdg, true)
	os.rmdir_all(preset_root) or {}
}

fn test_preset_apply_needs_yes() {
	old_presets, old_marker, old_xdg := preset_test_isolate()
	r := preset_apply_report(PresetApplyOptions{
		name: 'test-left'
	})
	assert !r.ok
	assert r.command == 'shell preset apply'
	assert r.message.contains('--yes')
	preset_test_restore(old_presets, old_marker, old_xdg)
}

fn test_preset_apply_missing_name() {
	old_presets, old_marker, old_xdg := preset_test_isolate()
	r := preset_apply_report(PresetApplyOptions{
		name: ''
		yes:  true
	})
	assert !r.ok
	assert r.message.contains('Example: horneroctl shell preset apply')
	preset_test_restore(old_presets, old_marker, old_xdg)
}

fn test_preset_apply_rejects_traversal_name() {
	old_presets, old_marker, old_xdg := preset_test_isolate()
	r := preset_apply_report(PresetApplyOptions{
		name: '../shared'
		yes:  true
	})
	assert !r.ok
	assert r.message.contains('invalid preset name')
	preset_test_restore(old_presets, old_marker, old_xdg)
}

fn test_preset_apply_unknown_name_lists_available() {
	old_presets, old_marker, old_xdg := preset_test_isolate()
	r := preset_apply_report(PresetApplyOptions{
		name: 'nope'
		yes:  true
	})
	assert !r.ok
	assert r.message.contains('preset not found: nope')
	assert r.message.contains('test-left')
	preset_test_restore(old_presets, old_marker, old_xdg)
}

fn test_preset_apply_rejects_invalid() {
	old_presets, old_marker, old_xdg := preset_test_isolate()
	r := preset_apply_report(PresetApplyOptions{
		name: 'bad'
		yes:  true
	})
	assert !r.ok
	assert r.message.contains('bar.position')
	preset_test_restore(old_presets, old_marker, old_xdg)
}

fn test_preset_apply_dry_run_writes_nothing() {
	old_presets, old_marker, old_xdg := preset_test_isolate()
	conf := preset_root + '/config/hornero/shell.json'
	marker := preset_root + '/state/current-shell-preset'
	r := preset_apply_report(PresetApplyOptions{
		name:    'test-left'
		dry_run: true
	})
	assert r.ok
	assert r.data['dry_run'] == 'true'
	assert r.message.contains('would run')
	assert !os.is_file(conf)
	assert !os.is_file(marker)
	preset_test_restore(old_presets, old_marker, old_xdg)
}

fn test_preset_apply_merges_and_marks() {
	old_presets, old_marker, old_xdg := preset_test_isolate()
	conf := preset_root + '/config/hornero/shell.json'
	marker := preset_root + '/state/current-shell-preset'
	preset_test_write(conf, '{"custom":"keep","bar":{"position":"right"}}')
	r := preset_apply_report(PresetApplyOptions{
		name: 'test-left'
		yes:  true
	})
	assert r.ok
	assert r.message.contains('test-left')
	raw := os.read_file(conf) or { assert false, 'shell.json written' }
	merged := json2.decode[map[string]json2.Any](raw) or {
		assert false, 'shell.json is a JSON object'
		map[string]json2.Any{}
	}
	assert merged['custom'].str() == 'keep'
	assert merged['bar'].as_map()['position'].str() == 'left'
	assert 'border' in merged
	assert '_name' !in merged
	assert '_description' !in merged
	pointer := os.read_file(marker) or { assert false, 'marker written' }
	assert pointer.trim_space() == 'test-left'
	assert current_preset_name() == 'test-left'
	preset_test_restore(old_presets, old_marker, old_xdg)
}

fn test_preset_apply_resets_stale_owned_keys() {
	old_presets, old_marker, old_xdg := preset_test_isolate()
	conf := preset_root + '/config/hornero/shell.json'
	// A previous preset left floatingMargin 200; the new preset says 14.
	preset_test_write(conf, '{"bar":{"position":"right","floatingMargin":200}}')
	r := preset_apply_report(PresetApplyOptions{
		name: 'test-left'
		yes:  true
	})
	assert r.ok
	raw := os.read_file(conf) or { assert false, 'shell.json written' }
	merged := json2.decode[map[string]json2.Any](raw) or {
		assert false, 'shell.json is a JSON object'
		map[string]json2.Any{}
	}
	assert merged['bar'].as_map()['floatingMargin'].i64() == 14
	preset_test_restore(old_presets, old_marker, old_xdg)
}

fn test_preset_list_full_is_json_array() {
	old_presets, old_marker, old_xdg := preset_test_isolate()
	r := preset_list_full_report()
	assert r.ok
	assert r.data['format'] == 'full'
	arr := json2.decode[[]json2.Any](r.message) or {
		assert false, 'full list message is a JSON array: ${err}'
		[]json2.Any{}
	}
	assert arr.len == 2
	mut seen := map[string]bool{}
	for item in arr {
		m := item.as_map()
		assert 'name' in m
		assert 'display' in m
		assert 'iconMaterial' in m
		assert 'position' in m
		assert 'style' in m
		assert 'active' in m
		seen[m['name'].str()] = true
	}
	assert seen['test-left']
	assert seen['bad']
	preset_test_restore(old_presets, old_marker, old_xdg)
}
