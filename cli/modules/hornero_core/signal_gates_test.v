module hornero_core

import os
import x.json2

// Gate validator vs the vendored config gate table. testdata/contrast-gates.json
// is a byte copy of HorneroOS/config profiles/themes/contrast-gates.json: a
// threshold change in config must be mirrored here, or this test fails.

fn gates_testdata(rel string) string {
	return os.join_path(os.dir(@FILE), 'testdata', rel)
}

fn gate_table_json() map[string]json2.Any {
	raw := os.read_file(gates_testdata('contrast-gates.json')) or { panic(err) }
	parsed := json2.decode[json2.Any](raw) or { panic(err) }
	return parsed.as_map()
}

fn json_f64(m map[string]json2.Any, key string) f64 {
	return (m[key] or { panic('missing ${key}') }).f64()
}

fn json_strs(m map[string]json2.Any, key string) []string {
	mut out := []string{}
	for v in (m[key] or { panic('missing ${key}') }).as_array() {
		out << v.str()
	}
	return out
}

// merge_json_level applies one level over its parent: dict sections merge
// key by key, everything else replaces (same rule as signal_theme.py).
fn merge_json_level(base map[string]json2.Any, over map[string]json2.Any) map[string]json2.Any {
	mut merged := base.clone()
	for key, value in over {
		if key == 'inherits' {
			continue
		}
		if value is map[string]json2.Any {
			if existing := merged[key] {
				if existing is map[string]json2.Any {
					mut inner := existing.as_map().clone()
					for k, v in value.as_map() {
						inner[k] = v
					}
					merged[key] = json2.Any(inner)
					continue
				}
			}
		}
		merged[key] = value
	}
	return merged
}

fn resolve_json_level(levels map[string]json2.Any, name string) map[string]json2.Any {
	level := (levels[name] or { panic('no level ${name}') }).as_map()
	parent := (level['inherits'] or { json2.Any('') }).str()
	base := if parent.len > 0 {
		resolve_json_level(levels, parent)
	} else {
		map[string]json2.Any{}
	}
	return merge_json_level(base, level)
}

fn test_gate_levels_match_the_config_table() {
	table := gate_table_json()
	assert (table['version'] or { panic('version') }).int() == 1
	levels := (table['levels'] or { panic('levels') }).as_map()
	assert levels.keys().sorted() == gate_levels.clone().sorted()
	for name in gate_levels {
		want := resolve_json_level(levels, name)
		got := gate_level(name) or { panic('no level ${name}') }
		text := (want['text'] or { panic('text') }).as_map()
		overrides := (want['textOverrides'] or { panic('overrides') }).as_map()
		on_pairs := (want['onPairs'] or { panic('onPairs') }).as_map()
		boundary := (want['boundary'] or { panic('boundary') }).as_map()
		focus := (want['focus'] or { panic('focus') }).as_map()
		text_min := json_f64(text, 'min')
		assert got.text_min == text_min, name
		assert got.ink_min == (if 'ink' in overrides {
			json_f64(overrides, 'ink')
		} else {
			text_min
		}), name
		assert got.ink_muted_min == (if 'inkMuted' in overrides {
			json_f64(overrides, 'inkMuted')
		} else {
			text_min
		}), name
		assert got.on_pairs_min == json_f64(on_pairs, 'min'), name
		assert got.boundary_min == json_f64(boundary, 'min'), name
		assert got.focus_min == json_f64(focus, 'min'), name
		assert got.focus_surfaces == json_strs(focus, 'on'), name
		assert json_strs(text, 'roles') == gate_text_roles, name
		assert json_strs(text, 'on') == gate_text_surfaces, name
		assert json_strs(boundary, 'on') == gate_boundary_surfaces, name
		mut pairs := [][]string{}
		for p in (on_pairs['pairs'] or { panic('pairs') }).as_array() {
			pairs << p.as_array().map(it.str())
		}
		assert pairs == gate_on_pairs, name
	}
}

fn test_terminal_and_chromatic_extra_match_the_config_table() {
	table := gate_table_json()
	term := (table['terminal'] or { panic('terminal') }).as_map()
	assert json_f64(term, 'normalMin') == gate_terminal.normal_min
	assert json_f64(term, 'brightMin') == gate_terminal.bright_min
	assert json_f64(term, 'rgyMinDeltaE76') == gate_terminal.rgy_min_de
	assert json_f64(term, 'rampMinDeltaE76') == gate_terminal.ramp_min_de
	extra := (table['chromaticExtra'] or { panic('extra') }).as_map()
	assert json_f64(extra, 'focusOnEverySurfaceMin') == gate_focus_every_surface_min
	sep := (extra['separation'] or { panic('sep') }).as_map()
	assert json_f64(sep, 'minDeltaEOK') == gate_separation_min_de_ok
	assert json_f64(sep, 'minHueDeg') == gate_separation_min_hue
	mut pairs := [][]string{}
	for p in (sep['pairs'] or { panic('pairs') }).as_array() {
		pairs << p.as_array().map(it.str())
	}
	assert pairs == gate_separation_pairs
}

fn fixture_theme(id string) SignalTheme {
	raw := os.read_file(os.join_path(os.dir(@FILE), '..', '..', 'testdata', 'signal-themes', id,
		'theme.json')) or { panic(err) }
	m := json2.decode[json2.Any](raw) or { panic(err) }
	return parse_signal_theme(id, m.as_map()) or { panic(err) }
}

fn chromatic_fixture_scheme(file string) SignalTheme {
	raw := os.read_file(gates_testdata(os.join_path('chromatic', file))) or { panic(err) }
	m := json2.decode[json2.Any](raw) or { panic(err) }
	scheme := (m.as_map()['scheme'] or { panic('scheme') }).as_map()
	return parse_signal_theme('', scheme) or { panic(err) }
}

fn test_curated_themes_pass_standard() {
	for id in signal_builtin_theme_ids {
		rows := validate_signal_gates(fixture_theme(id), 'standard', false) or { panic(err) }
		assert gate_failures(rows) == [], id
		// 24 text + 10 on-pairs + 3 boundary + 1 focus, then terminal rows.
		assert rows.len > 38
	}
}

fn test_standard_rows_have_the_curated_minimums() {
	rows := signal_contrast_report(fixture_theme('hornero-signal-night'), gate_level('standard') or {
		panic('level')
	})
	assert rows.len == 24 + 10 + 3 + 1
	for r in rows {
		assert r.min in [4.5, 3.0]
	}
}

fn test_chromatic_fixtures_pass_standard_with_extra_rows() {
	for f in ['generate-balanced.json', 'generate-vibrant.json'] {
		t := chromatic_fixture_scheme(f)
		rows := validate_signal_gates(t, 'standard', true) or { panic(err) }
		assert gate_failures(rows) == [], f
		assert rows.any(it.label == 'signal/alert hue degrees')
		assert rows.any(it.label == 'focus on ground (chromatic)')
	}
}

fn test_higher_levels_demand_more() {
	t := chromatic_fixture_scheme('generate-balanced.json')
	for level in ['boosted', 'maximum'] {
		rows := validate_signal_gates(t, level, true) or { panic(err) }
		assert gate_failures(rows).len > 0, level
	}
}

fn test_contrast_failure_is_reported_by_label() {
	t := chromatic_fixture_scheme('generate-neon.json')
	rows := validate_signal_gates(t, 'standard', true) or { panic(err) }
	fails := gate_failures(rows)
	assert fails.len > 0
	assert fails.any(it.starts_with('ink on panel'))
}

fn test_separation_is_checked_only_for_chromatic() {
	t := chromatic_fixture_scheme('generate-balanced.json')
	plain := validate_signal_gates(t, 'standard', false) or { panic(err) }
	assert !plain.any(it.label.contains('hue degrees'))
}

fn test_unknown_level_is_an_error() {
	t := fixture_theme('hornero-signal-night')
	validate_signal_gates(t, 'extreme', false) or {
		assert err.msg().contains('unknown gate level')
		return
	}
	assert false
}

fn test_colour_maths_matches_the_python_reference() {
	// Values computed with lib/hornero/signal_theme.py.
	assert gate_contrast('#000000', '#FFFFFF') > 20.99 && gate_contrast('#000000', '#FFFFFF') < 21.01
	assert gate_hue_distance('#FF0000', '#FF0000') < 0.001
	assert gate_delta_e_ok('#000000', '#FFFFFF') > 0.99 && gate_delta_e_ok('#000000', '#FFFFFF') < 1.01
	assert gate_delta_e76('#000000', '#FFFFFF') > 99.9 && gate_delta_e76('#000000', '#FFFFFF') < 100.1
}
