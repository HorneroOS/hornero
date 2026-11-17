module hornero_core

import os
import x.json2

// Template grammar, manifests, output jail and golden renders. The goldens
// and templates under testdata/chromatic are byte copies of HorneroOS/config
// (share/hornero/chromatic/templates, tests/golden/chromatic): the V engine
// and config's reference implementation must render identical bytes.

const tpl_root_name = 'hx-chromatic-template-test'

fn tpl_root() string {
	return os.join_path(os.temp_dir(), tpl_root_name)
}

fn tpl_setup() string {
	root := tpl_root()
	os.rmdir_all(root) or {}
	for d in ['config', 'data', 'state', 'cache', 'home'] {
		os.mkdir_all(os.join_path(root, d)) or { panic(err) }
	}
	os.setenv('XDG_CONFIG_HOME', os.join_path(root, 'config'), true)
	os.setenv('XDG_DATA_HOME', os.join_path(root, 'data'), true)
	os.setenv('XDG_STATE_HOME', os.join_path(root, 'state'), true)
	os.setenv('XDG_CACHE_HOME', os.join_path(root, 'cache'), true)
	os.setenv('HOME', os.join_path(root, 'home'), true)
	return root
}

fn tpl_teardown() {
	for name in ['XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_CACHE_HOME',
		'HORNERO_CHROMATIC_TEMPLATES_DIR'] {
		os.unsetenv(name)
	}
	os.rmdir_all(tpl_root()) or {}
}

fn tpl_testdata(rel string) string {
	return os.join_path(os.dir(@FILE), 'testdata', 'chromatic', rel)
}

fn tpl_theme(id string) SignalTheme {
	raw := os.read_file(os.join_path(os.dir(@FILE), '..', '..', 'testdata', 'signal-themes', id,
		'theme.json')) or { panic(err) }
	m := json2.decode[json2.Any](raw) or { panic(err) }
	return parse_signal_theme(id, m.as_map()) or { panic(err) }
}

fn tpl_terminal() []string {
	mut t := []string{}
	for _ in 0 .. 15 {
		t << '#000000'
	}
	t << '#ABCDEF'
	return t
}

fn tpl_sample() SignalTheme {
	return SignalTheme{
		id:       't'
		name:     't'
		mode:     'dark'
		palette:  {
			'signal': '#F2A33A'
			'ink':    '#ECE6DA'
			'base':   '#101419'
		}
		terminal: tpl_terminal()
	}
}

fn tpl_ok(text string) string {
	return render_template(text, tpl_sample(), 'x.tmpl') or { panic(err) }
}

fn test_filters() {
	assert tpl_ok('{{signal}}|{{ signal.hex }}|{{ signal.bare }}') == '#F2A33A|#F2A33A|F2A33A'
	assert tpl_ok('{{ signal.rgb }}|{{ signal.r }}|{{signal.g}}|{{ signal.b }}') == '242, 163, 58|242|163|58'
	assert tpl_ok('{{ signal.rgba 0.8 }}') == 'rgba(242, 163, 58, 0.80)'
	assert tpl_ok('{{ term15 }} {{ term0.bare }} {{ mode }} {{ id }}') == '#ABCDEF 000000 dark t'
}

fn test_optional_glow_falls_back_to_signal() {
	assert tpl_ok('{{ glow }}') == '#F2A33A'
}

fn test_sections() {
	assert tpl_ok('a{{#dark}}D{{/dark}}{{#light}}L{{/light}}b') == 'aDb'
	mut light := tpl_sample()
	light = SignalTheme{
		...light
		mode: 'light'
	}
	out := render_template('{{#dark}}D{{/dark}}{{#light}}{{ ink }}{{/light}}', light, 'x') or {
		panic(err)
	}
	assert out == '#ECE6DA'
}

fn test_rejections_carry_position() {
	cases := {
		'{{ nope }}':             '1:1: unknown role'
		'ok\n  {{ signal.hsl }}': '2:3: unknown filter'
		'{{ signal.rgba }}':      'bad filter arguments'
		'{{ signal.rgba 1.5 }}':  'bad filter arguments'
		'{{ signal.bare 2 }}':    'bad filter arguments'
		'{{ term16 }}':           'unknown role'
		'{{ term05 }}':           'unknown role'
		'{{ mode.bare }}':        'unknown role'
		'{{ 1 + 1 }}':            'malformed'
		'{{ signal | upper }}':   'malformed'
		'{{> include }}':         'malformed'
		'{{#each x}}{{/each}}':   'unknown section'
		'{{#dark}}x':             'unclosed section'
		'x{{/dark}}':             'unmatched'
		'{{#dark}}{{#light}}':    'cannot nest'
		'{{ signal':              'stray'
		'a }} b':                 'stray'
	}
	for text, needle in cases {
		render_template(text, tpl_sample(), 'x.tmpl') or {
			assert err.msg().starts_with('x.tmpl:'), text
			assert err.msg().contains(needle), '${text} -> ${err.msg()}'
			continue
		}
		assert false, 'accepted: ${text}'
	}
}

fn test_every_template_renders_to_its_golden() {
	dir := tpl_testdata('templates')
	for f in os.ls(dir) or { panic(err) } {
		if !f.ends_with('.json') {
			continue
		}
		raw := os.read_file(os.join_path(dir, f)) or { panic(err) }
		parsed := json2.decode[json2.Any](raw) or { panic(err) }
		m := parse_template_manifest(parsed.as_map(), dir, true) or { panic('${f}: ${err.msg()}') }
		text := os.read_file(os.join_path(dir, m.template)) or { panic(err) }
		for key, id in {
			'night': 'hornero-signal-night'
			'day':   'hornero-signal-day'
		} {
			got := render_template(text, tpl_theme(id), m.template) or { panic(err) }
			want := os.read_file(tpl_testdata('golden/${m.name}.${key}.golden')) or { panic(err) }
			assert got == want, '${m.name}.${key}'
		}
	}
}

fn test_manifest_validation() {
	dir := tpl_testdata('templates')
	good := {
		'schemaVersion': json2.Any(1)
		'name':          json2.Any('x')
		'template':      json2.Any('kitty.conf.tmpl')
		'output':        json2.Any(r'${XDG_CONFIG_HOME}/x/y.conf')
		'when':          json2.Any('chromatic')
	}
	parse_template_manifest(good, dir, false) or { panic(err) }
	for key, bad in {
		'template': json2.Any('../x')
		'output':   json2.Any('/etc/passwd')
		'when':     json2.Any('sometimes')
		'name':     json2.Any('Bad Name')
		'hook':     json2.Any('rm -rf /')
		'adapter':  json2.Any('sh')
	} {
		mut m := good.clone()
		m[key] = bad
		parse_template_manifest(m, dir, true) or { continue }
		assert false, 'accepted bad ${key}'
	}
	// A user manifest may not name an adapter (it is ignored, never run).
	mut with_adapter := good.clone()
	with_adapter['adapter'] = json2.Any('kitty')
	user := parse_template_manifest(with_adapter, dir, false) or { panic(err) }
	assert user.adapter == ''
	first := parse_template_manifest(with_adapter, dir, true) or { panic(err) }
	assert first.adapter == 'kitty'
}

fn test_output_jail() {
	root := tpl_setup()
	defer { tpl_teardown() }
	ok := jail_output(r'${XDG_CONFIG_HOME}/kitty/hornero-chromatic.conf') or { panic(err) }
	assert ok == os.join_path(root, 'config', 'kitty', 'hornero-chromatic.conf')
	home_ok := jail_output('~/x') or { '' }
	assert home_ok == '' // $HOME/x is not under an XDG directory
	for bad in [r'${XDG_CONFIG_HOME}/../escape', r'${XDG_CACHE_HOME}/a/../../b', '/etc/passwd',
		'~', r'${XDG_CONFIG_HOME}/', r'${HOME}/x', r'${XDG_STATE_HOME}/x'] {
		jail_output(bad) or { continue }
		assert false, 'accepted ${bad}'
	}
	// Symlink escape: a directory inside the config tree pointing elsewhere.
	outside := os.join_path(root, 'outside')
	os.mkdir_all(outside) or { panic(err) }
	os.symlink(outside, os.join_path(root, 'config', 'link')) or { panic(err) }
	jail_output(r'${XDG_CONFIG_HOME}/link/out.conf') or {
		assert err.msg().contains('outside')
		return
	}
	assert false, 'symlink escape accepted'
}

fn test_manifest_discovery_user_wins_and_requires() {
	root := tpl_setup()
	defer { tpl_teardown() }
	os.setenv('HORNERO_CHROMATIC_TEMPLATES_DIR', tpl_testdata('templates'), true)
	listing := list_template_manifests()
	assert listing.problems == []
	names := listing.manifests.map(it.name)
	assert names == ['foot', 'fuzzel', 'gtk3', 'gtk4', 'kitty', 'nvim', 'qt5ct', 'qt6ct', 'zed']
	// `requires`: foot is only rendered when ~/.config/foot exists.
	foot := listing.manifests.filter(it.name == 'foot')[0]
	assert !template_applicable(foot)
	os.mkdir_all(os.join_path(root, 'config', 'foot')) or { panic(err) }
	assert template_applicable(foot)
	// A user manifest with the same name replaces the first-party one.
	udir := os.join_path(root, 'config', 'hornero', 'chromatic', 'templates.d')
	os.mkdir_all(udir) or { panic(err) }
	os.write_file(os.join_path(udir, 'foot.tmpl'), 'bg {{ base }}\n') or { panic(err) }
	os.write_file(os.join_path(udir, 'foot.json'), '{"schemaVersion":1,"name":"foot","template":"foot.tmpl","output":"\${XDG_CONFIG_HOME}/foot/mine.ini","when":"chromatic","adapter":"kitty"}') or {
		panic(err)
	}
	os.write_file(os.join_path(udir, 'broken.json'), '{"schemaVersion":1,"name":"broken"}') or {
		panic(err)
	}
	again := list_template_manifests()
	mine := again.manifests.filter(it.name == 'foot')[0]
	assert !mine.first_party
	assert mine.adapter == ''
	assert again.problems.len == 1
	assert again.problems[0].contains('broken.json')
}
