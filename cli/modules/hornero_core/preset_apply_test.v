module hornero_core

import os
import x.json2

// Preset apply fixtures: everything lives under /tmp, env overrides
// isolate resolution, and each test restores what it sets (no network,
// no compositor, no HOME mutation).

const preset_root = '/tmp/hx-preset-test'

const preset_valid_json = '{"_name":"Test Left","_description":"fixture","_icon":"🏠","_iconMaterial":"dock_to_left","bar":{"position":"left","style":"attached","floatingMargin":14,"persistent":true,"showOnHover":true,"sizes":{"innerWidth":40},"entries":[{"id":"workspaces","enabled":true},{"id":"clock","enabled":true}]},"border":{"frameEnabled":true},"appearance":{"rounding":{"scale":1.0},"padding":{"scale":1.0},"spacing":{"scale":1.0}}}'

const preset_bad_position_json = '{"_name":"Bad","bar":{"position":"diagonal","style":"attached","floatingMargin":14,"showOnHover":true,"sizes":{"innerWidth":40},"entries":[{"id":"workspaces","enabled":true}]}}'

const preset_default_json = '{"_name":"Hornero Left","_description":"default fallback","_icon":"🏠","_iconMaterial":"dock_to_left","bar":{"position":"left","style":"attached","floatingMargin":14,"persistent":true,"showOnHover":true,"sizes":{"innerWidth":40},"entries":[{"id":"workspaces","enabled":true},{"id":"clock","enabled":true}]},"border":{"frameEnabled":true},"appearance":{"rounding":{"scale":1.0},"padding":{"scale":1.0},"spacing":{"scale":1.0}}}'

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
	preset_test_write(preset_root + '/presets/broken.json', '{oops not json')
	preset_test_write(preset_root + '/presets/hornero-left.json', preset_default_json)
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

// shell#46: an unknown name resolves to the default preset instead of
// failing, with the substitution stated in the message.
fn test_preset_apply_unknown_name_resolves_to_default() {
	old_presets, old_marker, old_xdg := preset_test_isolate()
	conf := preset_root + '/config/hornero/shell.json'
	marker := preset_root + '/state/current-shell-preset'
	r := preset_apply_report(PresetApplyOptions{
		name: 'nope'
		yes:  true
	})
	assert r.ok
	assert r.message.contains("unknown preset 'nope'")
	assert r.message.contains('hornero-left')
	assert r.data['preset'] == 'hornero-left'
	raw := os.read_file(conf) or { assert false, 'shell.json written' }
	merged := json2.decode[map[string]json2.Any](raw) or {
		assert false, 'shell.json is a JSON object'
		map[string]json2.Any{}
	}
	assert merged['bar'].as_map()['position'].str() == 'left'
	pointer := os.read_file(marker) or { assert false, 'marker written' }
	assert pointer.trim_space() == 'hornero-left'
	preset_test_restore(old_presets, old_marker, old_xdg)
}

// Only a missing default itself still fails, listing the catalogue.
fn test_preset_apply_unknown_name_fails_without_default() {
	old_presets, old_marker, old_xdg := preset_test_isolate()
	os.rm(preset_root + '/presets/hornero-left.json') or { assert false, 'rm default' }
	r := preset_apply_report(PresetApplyOptions{
		name: 'nope'
		yes:  true
	})
	assert !r.ok
	assert r.message.contains('preset not found: nope')
	assert r.message.contains('test-left')
	preset_test_restore(old_presets, old_marker, old_xdg)
}

// shell#46: a preset that fails validation falls back to the minimal safe
// layout (owned-defaults reset, no preset merge) so the bar survives.
// The pointer keeps the requested name as the intent record.
fn test_preset_apply_invalid_falls_back_to_safe_layout() {
	old_presets, old_marker, old_xdg := preset_test_isolate()
	conf := preset_root + '/config/hornero/shell.json'
	marker := preset_root + '/state/current-shell-preset'
	preset_test_write(conf, '{"custom":"keep","bar":{"position":"right"}}')
	r := preset_apply_report(PresetApplyOptions{
		name: 'bad'
		yes:  true
	})
	assert r.ok
	assert r.message.contains('safe layout')
	assert r.message.contains('bar.position')
	assert r.data['fallback'] == 'safe-reset'
	raw := os.read_file(conf) or { assert false, 'shell.json written' }
	merged := json2.decode[map[string]json2.Any](raw) or {
		assert false, 'shell.json is a JSON object'
		map[string]json2.Any{}
	}
	assert merged['custom'].str() == 'keep'
	assert merged['bar'].as_map()['position'].str() == 'left'
	pointer := os.read_file(marker) or { assert false, 'marker written' }
	assert pointer.trim_space() == 'bad'
	preset_test_restore(old_presets, old_marker, old_xdg)
}

// Unparseable JSON takes the same safe-layout path.
fn test_preset_apply_unparseable_falls_back_to_safe_layout() {
	old_presets, old_marker, old_xdg := preset_test_isolate()
	r := preset_apply_report(PresetApplyOptions{
		name: 'broken'
		yes:  true
	})
	assert r.ok
	assert r.message.contains('safe layout')
	assert r.message.contains('invalid JSON')
	assert r.data['fallback'] == 'safe-reset'
	preset_test_restore(old_presets, old_marker, old_xdg)
}

fn test_preset_apply_dry_run_unknown_reports_default() {
	old_presets, old_marker, old_xdg := preset_test_isolate()
	conf := preset_root + '/config/hornero/shell.json'
	marker := preset_root + '/state/current-shell-preset'
	r := preset_apply_report(PresetApplyOptions{
		name:    'nope'
		dry_run: true
	})
	assert r.ok
	assert r.message.contains('would run')
	assert r.message.contains('hornero-left')
	assert !os.is_file(conf)
	assert !os.is_file(marker)
	preset_test_restore(old_presets, old_marker, old_xdg)
}

fn test_preset_apply_dry_run_broken_reports_safe_reset() {
	old_presets, old_marker, old_xdg := preset_test_isolate()
	conf := preset_root + '/config/hornero/shell.json'
	marker := preset_root + '/state/current-shell-preset'
	r := preset_apply_report(PresetApplyOptions{
		name:    'bad'
		dry_run: true
	})
	assert r.ok
	assert r.message.contains('would run')
	assert r.message.contains('safe reset')
	assert !os.is_file(conf)
	assert !os.is_file(marker)
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
	assert arr.len == 3
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
	assert seen['hornero-left']
	preset_test_restore(old_presets, old_marker, old_xdg)
}

fn preset_summary_of(raw string) []json2.Any {
	bar := json2.decode[map[string]json2.Any](raw) or { return []json2.Any{} }
	return preset_bars_summary(bar)
}

fn test_preset_bars_summary_v2_dedupes_and_counts() {
	s := preset_summary_of('{"position":"top","style":"attached","bars":[{"edge":"top","style":"inset","groups":{"start":[{"id":"logo","enabled":true},{"id":"clock","enabled":false}],"center":[{"id":"clock"}],"end":[]}},{"edge":"top","style":"dock"},{"edge":"diagonal"},{"edge":"bottom","style":"weird","backdrop":"clear","groups":{"start":[{"id":"workspaces"}]}}]}')
	assert s.len == 2
	top := s[0].as_map()
	assert top['edge'].str() == 'top'
	assert top['style'].str() == 'inset'
	assert top['backdrop'].str() == 'solid'
	assert top['reserve'].str() == 'true'
	g := top['groups'].as_map()
	assert g['start'].int() == 1
	assert g['center'].int() == 1
	assert g['end'].int() == 0
	bottom := s[1].as_map()
	assert bottom['style'].str() == 'attached'
	assert bottom['backdrop'].str() == 'clear'
	assert bottom['reserve'].str() == 'true' // invalid style -> attached reserves
}

fn test_preset_bars_summary_v1_splits_at_spacers() {
	s := preset_summary_of('{"position":"left","style":"floating","bars":[],"entries":[{"id":"logo"},{"id":"workspaces"},{"id":"spacer"},{"id":"clock"},{"id":"spacer","enabled":false},{"id":"spacer"},{"id":"power"},{"id":"tray","enabled":false}]}')
	assert s.len == 1
	m := s[0].as_map()
	assert m['edge'].str() == 'left'
	assert m['style'].str() == 'floating'
	assert m['reserve'].str() == 'false'
	g := m['groups'].as_map()
	assert g['start'].int() == 2
	assert g['center'].int() == 1
	assert g['end'].int() == 1
}

fn test_preset_list_full_carries_bars_and_lineage() {
	old_presets, old_marker, old_xdg := preset_test_isolate()
	r := preset_list_full_report()
	arr := json2.decode[[]json2.Any](r.message) or { []json2.Any{} }
	for item in arr {
		m := item.as_map()
		assert 'lineage' in m
		assert 'bars' in m
		if m['name'].str() == 'test-left' {
			bars := m['bars'].as_array()
			assert bars.len == 1
			assert bars[0].as_map()['edge'].str() == 'left'
		}
	}
	preset_test_restore(old_presets, old_marker, old_xdg)
}
