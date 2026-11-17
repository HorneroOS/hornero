module hornero_cli

import os
import x.json2

// `appearance chromatic` through dispatch(): exit codes, JSON envelopes and
// flag handling against the fake helper, inside a throwaway HOME/XDG tree.

const cd_root_name = 'hx-chromatic-dispatch-test'

fn cd_root() string {
	return os.join_path(os.temp_dir(), cd_root_name)
}

fn cd_setup() {
	root := cd_root()
	os.rmdir_all(root) or {}
	for d in ['config', 'data', 'state', 'cache', 'home', 'run'] {
		os.mkdir_all(os.join_path(root, d)) or { panic(err) }
	}
	data := os.join_path(os.dir(@FILE), '..', 'hornero_core', 'testdata', 'chromatic')
	for k, v in {
		'XDG_CONFIG_HOME': 'config'
		'XDG_DATA_HOME':   'data'
		'XDG_STATE_HOME':  'state'
		'XDG_CACHE_HOME':  'cache'
		'HOME':            'home'
		'XDG_RUNTIME_DIR': 'run'
	} {
		os.setenv(k, os.join_path(root, v), true)
	}
	os.setenv('HORNERO_CHROMATIC_BIN', os.join_path(data, 'fake-helper.sh'), true)
	os.setenv('HORNERO_CHROMATIC_TEMPLATES_DIR', os.join_path(data, 'templates'), true)
}

fn cd_teardown() {
	for k in ['XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_CACHE_HOME', 'XDG_RUNTIME_DIR',
		'HORNERO_CHROMATIC_BIN', 'HORNERO_CHROMATIC_TEMPLATES_DIR'] {
		os.unsetenv(k)
	}
	os.rmdir_all(cd_root()) or {}
}

fn test_chromatic_options_parse() {
	o := parse_chromatic(['apply', '--seed', '#D98A3A', '--seed', '#3A7FD9', '--variant', 'vibrant',
		'--chroma', '1.2', '--no-persist', '--dry-run']) or { panic(err) }
	assert o.verb == 'apply' && o.seeds.len == 2 && o.variant == 'vibrant' && o.chroma == '1.2'
	assert o.no_persist && o.dry_run && !o.yes
	r := parse_chromatic(['rollback', '--steps', '3', '--yes']) or { panic(err) }
	assert r.steps == 3 && r.yes
	t := parse_chromatic(['templates', 'check', 'x.tmpl']) or { panic(err) }
	assert t.sub == 'check' && t.file == 'x.tmpl'
	d := parse_chromatic(['delete', 'amber', '--yes']) or { panic(err) }
	assert d.id == 'amber'
}

fn test_chromatic_options_reject_with_examples() {
	for bad in [[]string{}, ['nope'], ['apply', '--wat'], ['apply', '--variant'], ['rollback',
		'--steps', '0'], ['status', 'extra'], ['templates'], ['templates', 'zap']] {
		parse_chromatic(bad) or {
			assert err.msg().contains('Example:') || err.msg().contains('Run:'), '${bad}: ${err.msg()}'
			continue
		}
		assert false, 'accepted ${bad}'
	}
}

fn test_chromatic_usage_errors_exit_2() {
	cd_setup()
	defer { cd_teardown() }
	assert dispatch(['horneroctl', 'appearance', 'chromatic']) == 2
	assert dispatch(['horneroctl', 'appearance', 'chromatic', 'apply', '--wat']) == 2
	assert dispatch(['horneroctl', '--json', 'appearance', 'chromatic', 'zap']) == 2
}

fn test_chromatic_help_has_examples() {
	h := command_help('appearance chromatic')
	assert h.contains('Examples:')
	for verb in chromatic_verbs {
		assert h.contains('  ${verb}'), verb
	}
	assert dispatch(['horneroctl', 'appearance', 'chromatic', '--help']) == 0
	assert command_help('appearance').contains('chromatic')
}

fn test_chromatic_dispatch_status_apply_and_errors() {
	cd_setup()
	defer { cd_teardown() }
	assert dispatch(['horneroctl', '--json', 'appearance', 'chromatic', 'status']) == 0
	assert dispatch(['horneroctl', 'appearance', 'chromatic', 'apply', '--seed', '#D98A3A', '--dry-run']) == 0
	assert !os.is_file(os.join_path(cd_root(), 'state', 'hornero', 'signal', 'scheme.json'))
	// Without --yes a real apply is refused (exit 1), with nothing written.
	assert dispatch(['horneroctl', 'appearance', 'chromatic', 'apply', '--seed', '#D98A3A']) == 1
	// Gate failure and a missing engine are exit 1 with stable codes.
	assert dispatch(['horneroctl', '--json', 'appearance', 'chromatic', 'preview', '--seed', '#D98A3A',
		'--variant', 'neon']) == 1
	os.setenv('HORNERO_CHROMATIC_BIN', '/nonexistent', true)
	assert dispatch(['horneroctl', '--json', 'appearance', 'chromatic', 'preview', '--seed', '#D98A3A']) == 1
	assert dispatch(['horneroctl', 'appearance', 'chromatic', 'doctor']) == 0
}

fn test_chromatic_json_envelopes() {
	cd_setup()
	defer { cd_teardown() }
	// The reply JSON is what --json prints; check the shapes directly.
	deps_ok := parse_chromatic(['preview', '--seed', '#D98A3A', '--variant', 'balanced']) or {
		panic(err)
	}
	r := hornero_core_preview(deps_ok)
	m := json2.decode[json2.Any](r.json) or { panic(err) }.as_map()
	assert m['ok'] or { panic('ok') } == json2.Any(true)
	assert (m['scheme'] or { panic('scheme') }).as_map()['id'] or { panic('id') } == json2.Any('hornero-chromatic')
	bad := hornero_core_preview(parse_chromatic(['preview', '--seed', '#D98A3A', '--variant', 'neon']) or {
		panic(err)
	})
	bm := json2.decode[json2.Any](bad.json) or { panic(err) }.as_map()
	assert bm['ok'] or { panic('ok') } == json2.Any(false)
	assert (bm['error'] or { panic('error') }).as_map()['code'] or { panic('code') } == json2.Any('chromatic.gates-failed')
	assert bm['code'] or { panic('code') } == json2.Any('chromatic.gates-failed')
}
