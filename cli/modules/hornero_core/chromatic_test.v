module hornero_core

import crypto.sha256
import os
import x.json2

// Chromatic verbs against the fake helper (testdata/chromatic/fake-helper.sh):
// success, unreadable source, gate rejection, rollback, crash mid-apply,
// lock contention, corruption, follow, saved palettes. Every run lives in a
// fresh tree under os.temp_dir(); HOME and every XDG variable point into it,
// so the real home is never read or written.

const cx_name = 'hx-chromatic-core-test'

fn cx_root() string {
	return os.join_path(os.temp_dir(), cx_name)
}

fn cx_data(rel string) string {
	return os.join_path(os.dir(@FILE), 'testdata', rel)
}

fn cx_setup() string {
	root := cx_root()
	os.rmdir_all(root) or {}
	for d in ['config', 'data', 'state', 'cache', 'home', 'run', 'themes'] {
		os.mkdir_all(os.join_path(root, d)) or { panic(err) }
	}
	os.cp_all(os.join_path(os.dir(@FILE), '..', '..', 'testdata', 'signal-themes'), os.join_path(root,
		'themes'), true) or { panic(err) }
	os.write_file(os.join_path(root, 'wall.jpg'), 'fake-image') or { panic(err) }
	os.mkdir_all(os.join_path(root, 'state', 'hornero', 'wallpaper')) or { panic(err) }
	os.write_file(os.join_path(root, 'state', 'hornero', 'wallpaper', 'path'), os.join_path(root,
		'wall.jpg') + '\n') or { panic(err) }
	for k, v in {
		'XDG_CONFIG_HOME':                'config'
		'XDG_DATA_HOME':                  'data'
		'XDG_STATE_HOME':                 'state'
		'XDG_CACHE_HOME':                 'cache'
		'HOME':                           'home'
		'XDG_RUNTIME_DIR':                'run'
		'HORNERO_THEMES_DIR':             'themes'
		'HORNERO_WALLPAPER_POINTER_FILE': 'state/hornero/wallpaper/path'
	} {
		os.setenv(k, os.join_path(root, v), true)
	}
	os.setenv('HORNERO_CHROMATIC_BIN', cx_data('chromatic/fake-helper.sh'), true)
	os.setenv('HORNERO_CHROMATIC_TEMPLATES_DIR', cx_data('chromatic/templates'), true)
	return root
}

fn cx_teardown() {
	for k in ['XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_CACHE_HOME', 'XDG_RUNTIME_DIR',
		'HORNERO_THEMES_DIR', 'HORNERO_WALLPAPER_POINTER_FILE', 'HORNERO_CHROMATIC_BIN',
		'HORNERO_CHROMATIC_TEMPLATES_DIR', 'HORNERO_CHROMATIC_FAIL_RENAME', 'FAKE_EXIT', 'FAKE_LOG'] {
		os.unsetenv(k)
	}
	os.rmdir_all(cx_root()) or {}
}

fn cx_backends() ChromaticBackends {
	return ChromaticBackends{
		reload:     fn (mode string, theme SignalTheme, gtk string, icon string, policy string) []string {
			return []string{}
		}
		appearance: AppearanceBackends{
			gtk_apply:   fn (theme string, icon string, policy string, dry_run bool) CommandResult {
				return ok_result('gtk', 'ok', {})
			}
			pack_extras: fn (id string, gtk string, name string) {}
			reload:      fn () {}
		}
	}
}

// cx_tree hashes every file under the XDG trees (path + content).
fn cx_tree() string {
	mut entries := []string{}
	root := cx_root()
	for d in ['config', 'data', 'state', 'cache', 'home'] {
		os.walk(os.join_path(root, d), fn [mut entries] (p string) {
			if os.is_file(p) {
				entries << '${p}:${sha256.hexhash(os.read_file(p) or { '' })}'
			}
		})
	}
	entries.sort()
	return entries.join('\n')
}

fn cx_opts(variant string) ChromaticOptions {
	return ChromaticOptions{
		verb:    'apply'
		seeds:   ['#D98A3A']
		variant: variant
		yes:     true
	}
}

fn cx_doc(r ChromaticReply) map[string]json2.Any {
	return parse_json_object(r.json) or { panic('reply is not JSON: ${r.json}') }
}

fn cx_scheme() map[string]json2.Any {
	return parse_json_object(os.read_file(signal_scheme_file()) or { panic(err) }) or { panic(err) }
}

fn cx_shell() map[string]json2.Any {
	return parse_json_object(os.read_file(shell_config_file(resolve_paths())) or { '{}' }) or {
		panic(err)
	}
}

fn test_apply_writes_scheme_outputs_state_and_shell_keys() {
	root := cx_setup()
	defer { cx_teardown() }
	os.mkdir_all(os.join_path(root, 'config', 'kitty')) or { panic(err) }
	// Unrelated shell.json content must survive.
	os.mkdir_all(os.join_path(root, 'config', 'hornero')) or { panic(err) }
	os.write_file(shell_config_file(resolve_paths()), '{"bar":{"height":40},"appearance":{"theme":"hornero-signal-night","opacity":0.9}}') or {
		panic(err)
	}
	r := chromatic_apply(cx_opts('balanced'), cx_backends())
	assert r.ok, r.message
	doc := cx_doc(r)
	assert jget(doc, 'id') == 'hornero-chromatic'
	assert jget(doc, 'mode') == 'dark'
	assert jget(doc, 'snapshot') == '0001'
	assert jget(doc, 'persisted') == 'true'
	assert jget(doc, 'fingerprint').starts_with('sha256:')
	scheme := cx_scheme()
	assert jget(scheme, 'id') == 'hornero-chromatic'
	assert 'chromatic' in scheme && 'minSurfaceAlpha' in scheme && 'clearInk' in scheme
	shell := cx_shell()
	assert jget(jmap(shell, 'bar'), 'height') == '40'
	appearance := jmap(shell, 'appearance')
	assert jget(appearance, 'theme') == 'hornero-chromatic'
	assert jget(appearance, 'opacity') == '0.9'
	assert jget(jmap(appearance, 'chromatic'), 'variant') == 'balanced'
	// kitty exists -> kitty template written; foot does not -> skipped.
	assert os.is_file(os.join_path(root, 'config', 'kitty', 'hornero-chromatic.conf'))
	assert !os.is_dir(os.join_path(root, 'config', 'foot'))
	assert os.is_file(os.join_path(root, 'config', 'gtk-4.0', 'gtk.css'))
	state, corrupt := read_chromatic_state()
	assert corrupt == ''
	assert jget(state, 'active') == 'true'
	assert jget(state, 'snapshot') == '0001'
	assert os.is_file(os.join_path(chromatic_history_dir(), '0001.json'))
	assert gate_failures(validate_signal_gates(read_signal_scheme() or { panic(err) }, 'standard',
		true) or { panic(err) }) == []
}

fn test_no_persist_keeps_the_stored_request() {
	cx_setup()
	defer { cx_teardown() }
	assert chromatic_apply(cx_opts('balanced'), cx_backends()).ok
	r := chromatic_apply(ChromaticOptions{
		...cx_opts('vibrant')
		no_persist: true
	}, cx_backends())
	assert r.ok, r.message
	assert jget(cx_doc(r), 'persisted') == 'false'
	appearance := jmap(cx_shell(), 'appearance')
	assert jget(appearance, 'theme') == 'hornero-chromatic'
	assert jget(jmap(appearance, 'chromatic'), 'variant') == 'balanced'
}

fn test_dry_run_and_missing_yes_write_nothing() {
	cx_setup()
	defer { cx_teardown() }
	before := cx_tree()
	r := chromatic_apply(ChromaticOptions{
		...cx_opts('balanced')
		dry_run: true
	}, cx_backends())
	assert r.ok, r.message
	assert cx_doc(r)['wouldWrite'] or { panic('wouldWrite') }.as_array().len >= 7
	assert cx_tree() == before
	refused := chromatic_apply(ChromaticOptions{
		...cx_opts('balanced')
		yes: false
	}, cx_backends())
	assert !refused.ok
	assert refused.code == 'chromatic.usage'
	assert cx_tree() == before
	assert !os.is_dir(chromatic_state_dir())
}

fn test_unreadable_source_writes_nothing() {
	cx_setup()
	defer { cx_teardown() }
	before := cx_tree()
	r := chromatic_apply(ChromaticOptions{
		verb:   'apply'
		source: 'image:/nonexistent/wall.jpg'
		yes:    true
	}, cx_backends())
	assert !r.ok
	assert r.code == 'chromatic.source-unreadable'
	assert cx_tree() == before
	os.setenv('FAKE_EXIT', '3', true)
	r2 := chromatic_apply(cx_opts('balanced'), cx_backends())
	assert r2.code == 'chromatic.source-unreadable'
	assert cx_tree() == before
}

fn test_engine_missing_leaves_curated_themes_alone() {
	cx_setup()
	defer { cx_teardown() }
	os.setenv('HORNERO_CHROMATIC_BIN', '/nonexistent/hornero-chromatic', true)
	r := chromatic_apply(cx_opts('balanced'), cx_backends())
	assert r.code == 'chromatic.engine-missing'
	assert !os.is_file(signal_scheme_file())
	s := chromatic_status(ChromaticOptions{})
	assert s.ok
	assert jget(cx_doc(s), 'engineMissing') == 'true'
}

fn test_contrast_failure_is_rejected_before_any_write() {
	cx_setup()
	defer { cx_teardown() }
	before := cx_tree()
	r := chromatic_apply(cx_opts('neon'), cx_backends())
	assert !r.ok
	assert r.code == 'chromatic.gates-failed'
	assert r.message.contains('ink on panel')
	assert cx_tree() == before
}

fn test_crash_mid_apply_restores_every_file() {
	root := cx_setup()
	defer { cx_teardown() }
	os.mkdir_all(os.join_path(root, 'config', 'kitty')) or { panic(err) }
	assert chromatic_apply(cx_opts('balanced'), cx_backends()).ok
	before := cx_tree()
	// Fail at a middle replace, and at the very last one (shell.json).
	for step in ['1', '4', '9', '10', '11'] {
		os.setenv('HORNERO_CHROMATIC_FAIL_RENAME', step, true)
		r := chromatic_apply(cx_opts('vibrant'), cx_backends())
		assert !r.ok, 'step ${step}'
		assert r.code == 'chromatic.write-failed', 'step ${step}: ${r.code}'
		assert r.message.contains('previous state restored')
		assert cx_tree() == before, 'tree changed after failure at ${step}'
	}
	os.unsetenv('HORNERO_CHROMATIC_FAIL_RENAME')
	assert chromatic_apply(cx_opts('vibrant'), cx_backends()).ok
}

fn test_lock_contention_fails_fast() {
	cx_setup()
	defer { cx_teardown() }
	mut held := acquire_appearance_lock() or { panic(err) }
	before := cx_tree()
	r := chromatic_apply(cx_opts('balanced'), cx_backends())
	assert r.code == 'chromatic.locked'
	assert cx_tree() == before
	held.release()
	assert chromatic_apply(cx_opts('balanced'), cx_backends()).ok
}

fn test_rollback_restores_previous_contents_and_can_roll_forward() {
	root := cx_setup()
	defer { cx_teardown() }
	os.mkdir_all(os.join_path(root, 'config', 'kitty')) or { panic(err) }
	assert chromatic_apply(cx_opts('balanced'), cx_backends()).ok
	fp1 := jget(jmap(cx_scheme(), 'chromatic'), 'fingerprint')
	kitty := os.join_path(root, 'config', 'kitty', 'hornero-chromatic.conf')
	kitty1 := os.read_file(kitty) or { panic(err) }
	assert chromatic_apply(cx_opts('vibrant'), cx_backends()).ok
	fp2 := jget(jmap(cx_scheme(), 'chromatic'), 'fingerprint')
	assert fp1 != fp2
	assert (os.read_file(kitty) or { '' }) != kitty1
	dry := chromatic_rollback(ChromaticOptions{
		verb:    'rollback'
		dry_run: true
	}, cx_backends())
	assert dry.ok
	back := chromatic_rollback(ChromaticOptions{
		verb: 'rollback'
		yes:  true
	}, cx_backends())
	assert back.ok, back.message
	assert jget(jmap(cx_scheme(), 'chromatic'), 'fingerprint') == fp1
	assert (os.read_file(kitty) or { '' }) == kitty1
	assert jget(jmap(jmap(cx_shell(), 'appearance'), 'chromatic'), 'variant') == 'balanced'
	// The rollback is itself a snapshot: stepping back again returns to fp2.
	fwd := chromatic_rollback(ChromaticOptions{
		verb: 'rollback'
		yes:  true
	}, cx_backends())
	assert fwd.ok
	assert jget(jmap(cx_scheme(), 'chromatic'), 'fingerprint') == fp2
	// Rolling back before the first apply removes the files that did not exist.
	back2 := chromatic_rollback(ChromaticOptions{
		verb:  'rollback'
		yes:   true
		steps: 4
	}, cx_backends())
	assert back2.ok, back2.message
	assert !os.is_file(signal_scheme_file())
	assert !os.is_file(kitty)
	assert jget(jmap(cx_shell(), 'appearance'), 'theme') == ''
}

fn test_rollback_refuses_without_history_and_tampered_paths() {
	root := cx_setup()
	defer { cx_teardown() }
	r := chromatic_rollback(ChromaticOptions{
		verb: 'rollback'
		yes:  true
	}, cx_backends())
	assert r.code == 'chromatic.no-snapshot'
	assert chromatic_apply(cx_opts('balanced'), cx_backends()).ok
	// A history entry naming a path outside the XDG trees must not be honoured.
	path := os.join_path(chromatic_history_dir(), '0001.json')
	mut doc := parse_json_object(os.read_file(path) or { panic(err) }) or { panic(err) }
	mut files := jmap(doc, 'files').clone()
	files['/etc/hornero-evil'] = jstr('x')
	doc['files'] = json2.Any(files)
	os.write_file(path, json2.encode(doc)) or { panic(err) }
	evil := chromatic_rollback(ChromaticOptions{
		verb: 'rollback'
		yes:  true
	}, cx_backends())
	assert evil.code == 'chromatic.state-corrupt'
	assert !os.exists('/etc/hornero-evil')
	_ = root
}

fn test_history_ring_keeps_ten() {
	cx_setup()
	defer { cx_teardown() }
	for i in 0 .. 12 {
		assert chromatic_apply(cx_opts(if i % 2 == 0 { 'balanced' } else { 'vibrant' }),
			cx_backends()).ok
	}
	entries, _ := read_history()
	assert entries.len == 10
	assert entries[0].number == 12
	assert entries[9].number == 3
}

fn test_corrupt_state_and_history_are_set_aside() {
	cx_setup()
	defer { cx_teardown() }
	assert chromatic_apply(cx_opts('balanced'), cx_backends()).ok
	assert chromatic_apply(cx_opts('vibrant'), cx_backends()).ok
	os.write_file(chromatic_state_file(), '{not json') or { panic(err) }
	os.write_file(os.join_path(chromatic_history_dir(), '0002.json'), 'garbage') or { panic(err) }
	s := chromatic_status(ChromaticOptions{})
	assert s.ok
	doc := cx_doc(s)
	assert jget(doc, 'code') == 'chromatic.state-corrupt'
	assert (doc['corrupt'] or { panic('corrupt') }).as_array().len == 2
	assert !os.is_file(chromatic_state_file())
	// Apply keeps working and numbering stays monotonic past the corrupt entry.
	r := chromatic_apply(cx_opts('balanced'), cx_backends())
	assert r.ok, r.message
	assert jget(cx_doc(r), 'snapshot') == '0003'
	// Rollback skips the quarantined entry.
	back := chromatic_rollback(ChromaticOptions{
		verb:  'rollback'
		yes:   true
		steps: 2
	}, cx_backends())
	assert back.ok, back.message
	assert jget(cx_doc(back), 'restored') == '0001'
}

fn cx_set_follow(policy string, theme string, variant string) {
	os.mkdir_all(os.dir(shell_config_file(resolve_paths()))) or { panic(err) }
	os.write_file(shell_config_file(resolve_paths()), '{"appearance":{"theme":"${theme}","chromatic":{"follow":"${policy}","variant":"${variant}","source":"wallpaper"}}}') or {
		panic(err)
	}
}

fn test_follow_noops_and_regeneration() {
	cx_setup()
	defer { cx_teardown() }
	f := ChromaticOptions{
		verb: 'follow'
		yes:  true
	}
	cx_set_follow('auto', 'hornero-signal-night', 'balanced')
	r1 := chromatic_follow(f, cx_backends())
	assert r1.ok && jget(cx_doc(r1), 'skipped') == 'true'
	assert jget(cx_doc(r1), 'reason').contains('not hornero-chromatic')
	cx_set_follow('ask', 'hornero-chromatic', 'balanced')
	r2 := chromatic_follow(f, cx_backends())
	assert jget(cx_doc(r2), 'skipped') == 'true' && jget(cx_doc(r2), 'reason').contains('"ask"')
	cx_set_follow('', 'hornero-chromatic', 'balanced')
	r3 := chromatic_follow(f, cx_backends())
	assert jget(cx_doc(r3), 'reason').contains('unset')
	assert !os.is_file(signal_scheme_file())
	// auto: first follow applies, an identical palette is then a no-op.
	cx_set_follow('auto', 'hornero-chromatic', 'balanced')
	a := chromatic_follow(f, cx_backends())
	assert a.ok && jget(cx_doc(a), 'skipped') != 'true', a.message
	assert jget(cx_doc(a), 'persisted') == 'false'
	before := cx_tree()
	b := chromatic_follow(f, cx_backends())
	assert jget(cx_doc(b), 'skipped') == 'true' && jget(cx_doc(b), 'reason').contains('unchanged')
	assert cx_tree() == before
	// A different palette (new wallpaper in practice) is applied.
	cx_set_follow('auto', 'hornero-chromatic', 'vibrant')
	c := chromatic_follow(f, cx_backends())
	assert jget(cx_doc(c), 'skipped') != 'true', c.message
	// follow never rewrites the stored preference.
	assert jget(jmap(jmap(cx_shell(), 'appearance'), 'chromatic'), 'variant') == 'vibrant'
}

fn test_wallpaper_set_follows_only_when_explicitly_auto() {
	root := cx_setup()
	defer { cx_teardown() }
	os.setenv('HORNERO_SHELL_RUNNING', '0', true)
	defer { os.unsetenv('HORNERO_SHELL_RUNNING') }
	wall2 := os.join_path(root, 'wall2.jpg')
	os.write_file(wall2, 'x') or { panic(err) }
	cx_set_follow('ask', 'hornero-chromatic', 'balanced')
	r := wallpaper_report(WallpaperOptions{
		action: 'set'
		path:   wall2
		yes:    true
	})
	assert r.ok
	assert 'chromatic' !in r.data
	assert !os.is_file(signal_scheme_file())
}

fn test_off_applies_the_fallback_and_removes_chromatic_files() {
	root := cx_setup()
	defer { cx_teardown() }
	os.mkdir_all(os.join_path(root, 'config', 'kitty')) or { panic(err) }
	assert chromatic_apply(cx_opts('balanced'), cx_backends()).ok
	kitty := os.join_path(root, 'config', 'kitty', 'hornero-chromatic.conf')
	assert os.is_file(kitty)
	r := chromatic_off(ChromaticOptions{
		verb: 'off'
		yes:  true
	}, cx_backends())
	assert r.ok, r.message
	assert jget(cx_scheme(), 'id') == 'hornero-signal-night'
	assert jget(jmap(cx_shell(), 'appearance'), 'theme') == 'hornero-signal-night'
	assert !os.is_file(kitty)
	assert !os.is_file(os.join_path(root, 'config', 'gtk-3.0', 'gtk.css'))
	state, _ := read_chromatic_state()
	assert jget(state, 'active') == 'false'
	// off is undoable.
	back := chromatic_rollback(ChromaticOptions{
		verb: 'rollback'
		yes:  true
	}, cx_backends())
	assert back.ok, back.message
	assert jget(cx_scheme(), 'id') == 'hornero-chromatic'
}

fn test_saved_palettes_round_trip() {
	root := cx_setup()
	defer { cx_teardown() }
	assert chromatic_apply(cx_opts('balanced'), cx_backends()).ok
	bad := chromatic_save(ChromaticOptions{
		id:   'hornero-chromatic'
		name: 'x'
		yes:  true
	})
	assert bad.code == 'chromatic.usage'
	assert chromatic_save(ChromaticOptions{
		id:   'hornero-signal-night'
		name: 'x'
		yes:  true
	}).code == 'chromatic.usage'
	assert chromatic_save(ChromaticOptions{
		id:   'Bad Id'
		name: 'x'
		yes:  true
	}).code == 'chromatic.usage'
	dry := chromatic_save(ChromaticOptions{
		id:      'amber-dusk'
		name:    'Amber dusk'
		dry_run: true
	})
	assert dry.ok
	assert !os.exists(os.join_path(root, 'themes', 'amber-dusk'))
	saved := chromatic_save(ChromaticOptions{
		id:   'amber-dusk'
		name: 'Amber dusk'
		yes:  true
	})
	assert saved.ok, saved.message
	pack := parse_json_object(os.read_file(os.join_path(root, 'themes', 'amber-dusk', 'theme.json')) or {
		panic(err)
	}) or { panic(err) }
	assert jget(pack, 'collection') == 'user'
	assert jget(jmap(pack, 'chromatic'), 'engine') == '1.0.0'
	parse_signal_theme('amber-dusk', pack) or { panic(err) }
	// A saved palette is an ordinary theme: duplicates need --force.
	assert chromatic_save(ChromaticOptions{
		id:   'amber-dusk'
		name: 'Again'
		yes:  true
	}).code == 'chromatic.usage'
	assert chromatic_save(ChromaticOptions{
		id:    'amber-dusk'
		name:  'Again'
		yes:   true
		force: true
	}).ok
	listed := chromatic_list(ChromaticOptions{})
	assert (cx_doc(listed)['palettes'] or { panic('p') }).as_array().len == 1
	assert chromatic_rename(ChromaticOptions{
		id:   'amber-dusk'
		name: 'Dusk'
		yes:  true
	}).ok
	renamed := parse_json_object(os.read_file(os.join_path(root, 'themes', 'amber-dusk', 'theme.json')) or {
		panic(err)
	}) or { panic(err) }
	assert jget(renamed, 'name') == 'Dusk'
	// Catalogue themes can be neither renamed nor deleted.
	assert chromatic_rename(ChromaticOptions{
		id:   'hornero-signal-night'
		name: 'x'
		yes:  true
	}).code == 'chromatic.usage'
	assert chromatic_delete(ChromaticOptions{
		id:  'hornero-signal-night'
		yes: true
	}).code == 'chromatic.usage'
	// export -> import under a new id.
	exp := os.join_path(root, 'export.json')
	assert chromatic_export(ChromaticOptions{
		output: exp
		id:     'exported'
	}).ok
	imp := chromatic_import(ChromaticOptions{
		file: exp
		id:   'imported'
		yes:  true
	})
	assert imp.ok, imp.message
	assert pack_is_user('imported')
	// An import that fails the gates is refused.
	mut broken := parse_json_object(os.read_file(exp) or { panic(err) }) or { panic(err) }
	mut pal := jmap(broken, 'palette').clone()
	pal['ink'] = pal['panel'] or { jstr('#000000') }
	broken['palette'] = json2.Any(pal)
	bpath := os.join_path(root, 'broken.json')
	os.write_file(bpath, json2.encode(broken)) or { panic(err) }
	refused := chromatic_import(ChromaticOptions{
		file: bpath
		id:   'broken'
		yes:  true
	})
	assert refused.code == 'chromatic.gates-failed'
	assert !pack_is_user('broken')
	assert chromatic_delete(ChromaticOptions{
		id:  'imported'
		yes: true
	}).ok
	assert !os.exists(os.join_path(root, 'themes', 'imported'))
}

fn test_import_rejects_untrusted_free_text_fields() {
	root := cx_setup()
	defer { cx_teardown() }
	assert chromatic_apply(cx_opts('balanced'), cx_backends()).ok
	exp := os.join_path(root, 'export.json')
	assert chromatic_export(ChromaticOptions{
		output: exp
		id:     'exported'
	}).ok
	good := parse_json_object(os.read_file(exp) or { panic(err) }) or { panic(err) }
	// Hostile values for each free-text field; every one must be refused and
	// leave nothing behind.
	hostile := {
		'iconTheme':        'x\ngtk-modules=evil'
		'gtkTheme':         'a"\nmodule_path "/tmp/x"'
		'defaultWallpaper': '../../../../etc/hostname'
		'wallpaperDir':     '../outside'
	}
	for key, value in hostile {
		mut doc := good.clone()
		doc[key] = jstr(value)
		path := os.join_path(root, 'hostile.json')
		os.write_file(path, json2.encode(doc)) or { panic(err) }
		r := chromatic_import(ChromaticOptions{
			file: path
			id:   'hostile'
			yes:  true
		})
		assert r.code == 'chromatic.usage', '${key}: ${r.message}'
		assert !pack_is_user('hostile')
	}
	// A normal document still imports.
	assert chromatic_import(ChromaticOptions{
		file: exp
		id:   'fine'
		yes:  true
	}).ok
}

fn test_templates_verbs() {
	root := cx_setup()
	defer { cx_teardown() }
	os.mkdir_all(os.join_path(root, 'config', 'foot')) or { panic(err) }
	assert chromatic_apply(cx_opts('balanced'), cx_backends()).ok
	listed := chromatic_templates_list(ChromaticOptions{})
	assert listed.ok
	assert listed.message.contains('foot  applies')
	assert listed.message.contains('zed  skipped')
	before := cx_tree()
	dry := chromatic_templates_render(ChromaticOptions{
		all:     true
		dry_run: true
	})
	assert dry.ok
	assert cx_tree() == before
	rendered := chromatic_templates_render(ChromaticOptions{
		name: 'zed'
		yes:  true
	})
	assert rendered.ok, rendered.message
	assert os.is_file(os.join_path(root, 'config', 'zed', 'themes', 'hornero-chromatic.json'))
	good := os.join_path(root, 'ok.tmpl')
	os.write_file(good, 'bg {{ base }} {{ term3.bare }}') or { panic(err) }
	assert chromatic_templates_check(ChromaticOptions{
		file: good
	}).ok
	bad := os.join_path(root, 'bad.tmpl')
	os.write_file(bad, 'line\n  {{ nope }}') or { panic(err) }
	r := chromatic_templates_check(ChromaticOptions{
		file: bad
	})
	assert r.code == 'chromatic.template-invalid'
	assert r.message.contains('bad.tmpl:2:3')
	// A manifest whose output escapes the XDG trees is invalid.
	os.write_file(os.join_path(root, 'esc.tmpl'), 'x') or { panic(err) }
	os.write_file(os.join_path(root, 'esc.json'), '{"schemaVersion":1,"name":"esc","template":"esc.tmpl","output":"\${XDG_CONFIG_HOME}/../etc/x","when":"chromatic"}') or {
		panic(err)
	}
	e := chromatic_templates_check(ChromaticOptions{
		file: os.join_path(root, 'esc.json')
	})
	assert e.code == 'chromatic.template-invalid'
}

fn test_history_and_doctor_and_variants_and_analyze() {
	cx_setup()
	defer { cx_teardown() }
	assert chromatic_apply(cx_opts('balanced'), cx_backends()).ok
	h := chromatic_history(ChromaticOptions{})
	assert h.ok && h.message.contains('0001')
	d := chromatic_doctor(ChromaticOptions{})
	assert d.ok, d.message
	assert d.message.contains('helper') && d.message.contains('ffmpeg'), d.message
	v := chromatic_variants(ChromaticOptions{})
	assert v.ok && v.message.contains('balanced')
	a := chromatic_analyze(ChromaticOptions{
		verb: 'analyze'
	})
	assert a.ok, a.message
	os.setenv('HORNERO_CHROMATIC_BIN', '/nonexistent', true)
	d2 := chromatic_doctor(ChromaticOptions{})
	assert d2.ok && d2.message.contains('optional')
}

fn test_real_home_is_never_used() {
	cx_setup()
	defer { cx_teardown() }
	assert os.home_dir() == os.join_path(cx_root(), 'home')
	assert chromatic_state_dir().starts_with(cx_root())
	assert appearance_lock_file().starts_with(cx_root())
	assert signal_scheme_file().starts_with(cx_root())
}

// Integration test against the REAL hornero-chromatic binary (built from
// HorneroOS/shell: cmake -DENABLE_MODULES=extras, target hornero-chromatic).
// Opt in with HORNERO_CHROMATIC_REAL_BIN=/path/to/hornero-chromatic; without
// it the test is skipped, so the unit suite never needs the C++ toolchain.
// Everything runs in the isolated tree of cx_setup(); the real home is
// never touched.

fn real_helper() string {
	return os.getenv('HORNERO_CHROMATIC_REAL_BIN')
}

// real_wallpaper writes a small PPM gradient (decoded by QImageReader).
fn real_wallpaper(root string) string {
	path := os.join_path(root, 'real-wall.ppm')
	w := 96
	h := 54
	mut data := 'P6 ${w} ${h} 255\n'.bytes()
	for y in 0 .. h {
		for x in 0 .. w {
			data << u8(40 + x)
			data << u8(30 + y * 2)
			data << u8(90 + x / 2)
		}
	}
	os.write_file_array(path, data) or { panic(err) }
	return path
}

fn test_real_helper_apply_follow_rollback() {
	bin := real_helper()
	if bin.len == 0 {
		eprintln('skipped: HORNERO_CHROMATIC_REAL_BIN not set')
		return
	}
	root := cx_setup()
	defer { cx_teardown() }
	os.setenv('HORNERO_CHROMATIC_BIN', bin, true)
	os.mkdir_all(os.join_path(root, 'config', 'kitty')) or { panic(err) }
	wall := real_wallpaper(root)
	os.write_file(os.join_path(root, 'state', 'hornero', 'wallpaper', 'path'), wall + '\n') or {
		panic(err)
	}
	v := chromatic_variants(ChromaticOptions{})
	assert v.ok, v.message
	a := chromatic_analyze(ChromaticOptions{
		source: 'image:${wall}'
	})
	assert a.ok, a.message
	for level in ['standard', 'boosted', 'maximum'] {
		r := chromatic_apply(ChromaticOptions{
			verb:     'apply'
			source:   'image:${wall}'
			contrast: level
			yes:      true
		}, cx_backends())
		assert r.ok, '${level}: ${r.message}'
		live := read_signal_scheme() or { panic(err) }
		assert live.id == 'hornero-chromatic'
		rows := validate_signal_gates(live, level, true) or { panic(err) }
		assert gate_failures(rows) == [], level
	}
	// Seeds, house, every variant: always gate-clean, never an engine failure.
	for variant in ['balanced', 'vibrant', 'expressive', 'faithful', 'muted', 'monochrome',
		'high-contrast', 'neon'] {
		r := chromatic_preview(ChromaticOptions{
			verb:    'preview'
			seeds:   ['#2F6FD9']
			variant: variant
			mode:    if variant == 'neon' { 'dark' } else { '' }
		})
		assert r.ok, '${variant}: ${r.message}'
	}
	assert chromatic_preview(ChromaticOptions{
		source: 'house'
	}).ok
	// Follow policy auto: same wallpaper -> unchanged; the cache makes it cheap.
	os.write_file(shell_config_file(resolve_paths()), '{"appearance":{"theme":"hornero-chromatic","chromatic":{"follow":"auto","source":"wallpaper","contrast":"maximum"}}}') or {
		panic(err)
	}
	first := chromatic_follow(ChromaticOptions{
		verb: 'follow'
		yes:  true
	}, cx_backends())
	assert first.ok, first.message
	again := chromatic_follow(ChromaticOptions{
		verb: 'follow'
		yes:  true
	}, cx_backends())
	assert again.ok && again.message.contains('unchanged'), again.message
	// Unreadable image: stable code, nothing written.
	before := cx_tree()
	bad := chromatic_apply(ChromaticOptions{
		verb:   'apply'
		source: 'image:${root}/missing.png'
		yes:    true
	}, cx_backends())
	assert bad.code == 'chromatic.source-unreadable'
	assert cx_tree() == before
	empty := os.join_path(root, 'empty.png')
	os.write_file(empty, '') or { panic(err) }
	assert chromatic_apply(ChromaticOptions{
		verb:   'apply'
		source: 'image:${empty}'
		yes:    true
	}, cx_backends()).code == 'chromatic.source-unreadable'
	back := chromatic_rollback(ChromaticOptions{
		verb: 'rollback'
		yes:  true
	}, cx_backends())
	assert back.ok, back.message
	d := chromatic_doctor(ChromaticOptions{})
	assert d.ok && d.message.contains('engine 1.0.0'), d.message
	// Save the live palette; a saved Chromatic palette is an ordinary theme.
	assert chromatic_apply(ChromaticOptions{
		verb:   'apply'
		source: 'image:${wall}'
		yes:    true
	}, cx_backends()).ok
	saved := chromatic_save(ChromaticOptions{
		id:   'real-saved'
		name: 'Real saved'
		yes:  true
	})
	assert saved.ok, saved.message
}
