module hornero_core

import os
import x.json2

// Read-only and saved-palette Chromatic verbs.

// --- status / history / analyze / variants -----------------------------------------

pub fn chromatic_status(o ChromaticOptions) ChromaticReply {
	state, corrupt_state := read_chromatic_state()
	entries, corrupt_hist := read_history()
	live := read_signal_scheme() or { SignalTheme{} }
	appearance := read_shell_appearance()
	cfg := jmap(appearance, 'chromatic')
	helper := chromatic_helper_path()
	mut corrupt := corrupt_hist.clone()
	if corrupt_state.len > 0 {
		corrupt << corrupt_state
	}
	active := live.id == chromatic_theme_id
	mut doc := {
		'active':        jbool(active)
		'selected':      jstr(jget(appearance, 'theme'))
		'liveTheme':     jstr(live.id)
		'mode':          jstr(live.mode)
		'follow':        jstr(jget(cfg, 'follow'))
		'helper':        jstr(helper)
		'engineMissing': jbool(helper.len == 0)
		'state':         json2.Any(state)
		'snapshots':     jint(entries.len)
		'corrupt':       jstrs(corrupt)
	}
	if corrupt.len > 0 {
		doc['code'] = jstr('chromatic.state-corrupt')
	}
	mut lines := [
		if active {
			'Chromatic is active (${live.mode}, fingerprint ${jget(state, 'fingerprint')}).'
		} else {
			'Chromatic is not the live theme (live: ${if live.id.len > 0 {
				live.id
			} else {
				'none'
			}}).'
		},
		'follow policy: ${if jget(cfg, 'follow').len > 0 { jget(cfg, 'follow') } else { 'unset' }}; snapshots: ${entries.len}',
		'helper: ${if helper.len > 0 { helper } else { 'not found (chromatic.engine-missing)' }}',
	]
	if corrupt.len > 0 {
		lines << 'chromatic.state-corrupt: set aside ${corrupt.join(', ')}; apply still works, rollback skips them.'
	}
	return chromatic_ok(lines.join('\n'), doc)
}

pub fn chromatic_history(o ChromaticOptions) ChromaticReply {
	entries, corrupt := read_history()
	mut rows := []json2.Any{}
	mut lines := []string{}
	for e in entries {
		rows << json2.Any({
			'snapshot':  jstr('${e.number:04}')
			'createdAt': jstr(jget(e.doc, 'createdAt'))
			'reason':    jstr(jget(e.doc, 'reason'))
			'themeId':   jstr(jget(e.doc, 'themeId'))
			'files':     jint(jmap(e.doc, 'files').len)
		})
		lines << '${e.number:04}  ${jget(e.doc, 'createdAt')}  ${jget(e.doc, 'reason')}  ${jget(e.doc, 'themeId')}'
	}
	if lines.len == 0 {
		lines << 'no snapshots yet'
	}
	return chromatic_ok(lines.join('\n'), {
		'history': json2.Any(rows)
		'corrupt': jstrs(corrupt)
	})
}

pub fn chromatic_analyze(o ChromaticOptions) ChromaticReply {
	// Analysis needs an image: an explicit image:PATH, else the wallpaper
	// (the stored request source is irrelevant here).
	path := if o.source.starts_with('image:') {
		o.source['image:'.len..]
	} else {
		current_wallpaper('')
	}
	if path.len == 0 || (o.source.len > 0 && o.source != 'wallpaper' && !o.source.starts_with('image:')) {
		return chromatic_fail('chromatic.source-unreadable', 'analyze needs an image: a current wallpaper or --source image:PATH.\nExample: horneroctl appearance chromatic analyze --source image:~/wall.jpg')
	}
	mut args := ['analyze', '--source', path]
	if o.dry_run {
		args << '--no-cache'
	} else {
		args << ['--cache-dir', chromatic_cache_dir()]
	}
	doc := helper_json(args) or { return chromatic_fail_from(err.msg()) }
	infer := jmap(doc, 'inference')
	return chromatic_ok('${jget(infer, 'personality')} (mode ${jget(infer, 'mode')}, variant ${jget(infer, 'variant')}, confidence ${jget(infer, 'confidence')})', {
		'analysis':  json2.Any(jmap(doc, 'analysis'))
		'inference': json2.Any(infer)
		'source':    jstr(path)
	})
}

pub fn chromatic_variants(o ChromaticOptions) ChromaticReply {
	doc := helper_json(['variants']) or { return chromatic_fail_from(err.msg()) }
	mut names := []string{}
	for v in (doc['variants'] or { json2.Any([]json2.Any{}) }).as_array() {
		names << jget(v.as_map(), 'id')
	}
	return chromatic_ok('variants: ${names.join(', ')}', {
		'variants': doc['variants'] or { json2.Any([]json2.Any{}) }
	})
}

// --- doctor ----------------------------------------------------------------------------

struct DoctorAcc {
mut:
	checks []json2.Any
	lines  []string
}

fn (mut a DoctorAcc) add(name string, ok bool, detail string) {
	a.checks << json2.Any({
		'name':   jstr(name)
		'ok':     jbool(ok)
		'detail': jstr(detail)
	})
	a.lines << '${if ok { 'ok  ' } else { 'FAIL' }} ${name}: ${detail}'
}

pub fn chromatic_doctor(o ChromaticOptions) ChromaticReply {
	mut acc := DoctorAcc{}
	mut failed := false
	helper := chromatic_helper_path()
	if helper.len == 0 {
		acc.add('helper', true, 'hornero-chromatic not found (optional; chromatic.engine-missing until hornero-shell is installed)')
	} else if ver := helper_json(['version']) {
		acc.add('helper', true, '${helper} (engine ${jget(jmap(ver, 'engine'), 'version')}, algorithm ${jget(ver, 'algorithm')})')
		ff := jget(ver, 'ffmpeg')
		acc.add('ffmpeg', true, if ff.len > 0 && ff != 'null' {
			ff
		} else {
			'absent: video wallpapers are unavailable (images and GIFs still work)'
		})
	} else {
		failed = true
		acc.add('helper', false, '${helper} did not answer: ${err.msg()}')
	}
	_, corrupt_state := read_chromatic_state()
	_, corrupt_hist := read_history()
	corrupt := corrupt_hist.len + if corrupt_state.len > 0 { 1 } else { 0 }
	acc.add('state', corrupt == 0, if corrupt == 0 {
		'state.json and history readable'
	} else {
		'chromatic.state-corrupt: ${corrupt} file(s) set aside'
	})
	listing := list_template_manifests()
	acc.add('templates', listing.problems.len == 0, '${listing.manifests.len} manifests' +
		if listing.problems.len > 0 { '; problems: ${listing.problems.join('; ')}' } else { '' })
	lk := acquire_appearance_lock() or {
		acc.add('lock', false, err.msg())
		AppearanceLock{}
	}
	mut l := lk
	if l.file.is_opened {
		l.release()
		acc.add('lock', true, '${appearance_lock_file()} is free')
	}
	return ChromaticReply{
		ok:      !failed
		message: acc.lines.join('\n')
		json:    jencode({
			'ok':     jbool(!failed)
			'checks': json2.Any(acc.checks)
		})
		code:    if failed { 'chromatic.engine-failed' } else { '' }
	}
}

// --- templates --------------------------------------------------------------------------

pub fn chromatic_templates_list(o ChromaticOptions) ChromaticReply {
	listing := list_template_manifests()
	mut rows := []json2.Any{}
	mut lines := []string{}
	for m in listing.manifests {
		out := jail_output(m.output) or { 'INVALID: ${err.msg()}' }
		applicable := template_applicable(m)
		rows << json2.Any({
			'name':       jstr(m.name)
			'output':     jstr(out)
			'when':       jstr(m.when)
			'adapter':    jstr(m.adapter)
			'firstParty': jbool(m.first_party)
			'applicable': jbool(applicable)
		})
		lines << '${m.name}  ${if applicable { 'applies' } else { 'skipped (app not installed)' }}  ${out}'
	}
	for p in listing.problems {
		lines << 'problem: ${p}'
	}
	return chromatic_ok(lines.join('\n'), {
		'templates': json2.Any(rows)
		'problems':  jstrs(listing.problems)
	})
}

// template_scheme is the scheme templates render against: the live one, else
// the Signal Night pack (so `templates check` works before any apply).
fn template_scheme() !SignalTheme {
	if live := read_signal_scheme() {
		return live
	}
	return load_signal_theme(signal_default_theme_id)
}

pub fn chromatic_templates_render(o ChromaticOptions) ChromaticReply {
	theme := template_scheme() or {
		return chromatic_fail('chromatic.template-invalid', 'no scheme to render: ${err.msg()}')
	}
	listing := list_template_manifests()
	mut plan := []PlannedWrite{}
	for m in listing.manifests {
		if o.name.len > 0 && m.name != o.name {
			continue
		}
		if o.name.len == 0 && !o.all && !template_applicable(m) {
			continue
		}
		res := resolve_template(m) or {
			return chromatic_fail('chromatic.template-invalid', '${m.name}: ${err.msg()}')
		}
		text := render_template(res.text, theme, '${m.name}/${m.template}') or {
			return chromatic_fail('chromatic.template-invalid', err.msg())
		}
		plan << PlannedWrite{
			path:    res.output
			content: text
		}
	}
	if plan.len == 0 {
		return chromatic_fail('chromatic.template-invalid', 'no template selected.\nExample: horneroctl appearance chromatic templates render --all --dry-run')
	}
	if o.dry_run {
		return chromatic_ok('would render ${plan.len} templates; nothing was written.', {
			'dryRun':     jbool(true)
			'wouldWrite': jstrs(paths_of(plan))
		})
	}
	if !o.yes {
		return chromatic_fail('chromatic.usage', '${usage_yes}\nExample: horneroctl appearance chromatic templates render --all --dry-run')
	}
	mut lk := acquire_appearance_lock() or {
		return chromatic_fail('chromatic.locked', err.msg())
	}
	snap := commit_locked(plan, ShellPatch{}, 'templates') or {
		lk.release()
		return chromatic_fail_from(err.msg())
	}
	lk.release()
	return chromatic_ok('rendered ${plan.len} templates; snapshot ${snap:04}.', {
		'outputs':  jstrs(paths_of(plan))
		'snapshot': jstr('${snap:04}')
	})
}

// chromatic_templates_check validates a manifest (*.json) or a template
// file against the grammar without writing anything.
pub fn chromatic_templates_check(o ChromaticOptions) ChromaticReply {
	if o.file.len == 0 {
		return chromatic_fail('chromatic.usage', 'missing FILE.\nExample: horneroctl appearance chromatic templates check my.json')
	}
	theme := template_scheme() or {
		return chromatic_fail('chromatic.template-invalid', err.msg())
	}
	raw := os.read_file(o.file) or {
		return chromatic_fail('chromatic.template-invalid', 'cannot read ${o.file}: ${err.msg()}')
	}
	if o.file.ends_with('.json') {
		m := parse_json_object(raw) or {
			return chromatic_fail('chromatic.template-invalid', '${o.file}: ${err.msg()}')
		}
		manifest := parse_template_manifest(m, os.dir(os.real_path(o.file)), false) or {
			return chromatic_fail('chromatic.template-invalid', '${o.file}: ${err.msg()}')
		}
		res := resolve_template(manifest) or {
			return chromatic_fail('chromatic.template-invalid', '${o.file}: ${err.msg()}')
		}
		render_template(res.text, theme, manifest.template) or {
			return chromatic_fail('chromatic.template-invalid', err.msg())
		}
		return chromatic_ok('${o.file}: valid manifest; output ${res.output}', {
			'name':   jstr(manifest.name)
			'output': jstr(res.output)
		})
	}
	render_template(raw, theme, o.file) or {
		return chromatic_fail('chromatic.template-invalid', err.msg())
	}
	return chromatic_ok('${o.file}: valid template', {
		'file': jstr(o.file)
	})
}

// --- saved palettes ------------------------------------------------------------------------

fn valid_palette_id(id string) bool {
	return id.len > 0 && id.len <= 48 && !id.starts_with('-') && !id.ends_with('-')
		&& !id.contains('--') && id.bytes().all((it >= `a` && it <= `z`) || (it >= `0` && it <= `9`)
		|| it == `-`)
}

fn user_pack_path(id string) string {
	return os.join_path(resolve_themes_dir(), id, 'theme.json')
}

// pack_is_user reports whether a pack exists as a user-collection palette.
fn pack_is_user(id string) bool {
	raw := os.read_file(user_pack_path(id)) or { return false }
	m := parse_json_object(raw) or { return false }
	return jget(m, 'collection') == 'user'
}

// theme_document builds the schema-v2 theme.json of a live Chromatic scheme.
fn theme_document(live map[string]json2.Any, id string, name string) !map[string]json2.Any {
	theme := parse_signal_theme('', live) or { return error(err.msg()) }
	chrom := jmap(live, 'chromatic')
	if chrom.len == 0 {
		return error('the live scheme is not a Chromatic palette')
	}
	gtk, icon, _ := gtk_for_mode(theme)
	wall := os.file_name(current_wallpaper(''))
	mut prov := {
		'engine':      chrom['engine'] or { jstr('') }
		'algorithm':   chrom['algorithm'] or { jint(1) }
		'request':     json2.Any(jmap(chrom, 'request'))
		'seeds':       chrom['seeds'] or { json2.Any([]json2.Any{}) }
		'createdAt':   jstr(chromatic_now_iso())
		'fingerprint': chrom['fingerprint'] or { json2.Any(json2.Null{}) }
		'resolved':    json2.Any(jmap(chrom, 'resolved'))
	}
	if sk := chrom['sourceKey'] {
		prov['sourceKey'] = sk
	}
	return {
		'schemaVersion':    jint(2)
		'id':               jstr(id)
		'name':             jstr(name)
		'description':      jstr('Saved Hornero Chromatic palette')
		'collection':       jstr('user')
		'mode':             jstr(theme.mode)
		'palette':          json2.Any(jmap(live, 'palette'))
		'terminal':         live['terminal'] or { json2.Any([]json2.Any{}) }
		'gtkTheme':         jstr(gtk)
		'iconTheme':        jstr(icon)
		'defaultWallpaper': jstr(if wall.len > 0 { wall } else { 'none' })
		'wallpaperDir':     jstr(id)
		'colorOnly':        jbool(true)
		'chromatic':        json2.Any(prov)
	}
}

fn live_chromatic_scheme() !map[string]json2.Any {
	raw := os.read_file(signal_scheme_file()) or {
		return error('no live scheme; apply Chromatic first.\nExample: horneroctl appearance chromatic apply --yes')
	}
	m := parse_json_object(raw) or { return error('live scheme is not valid JSON') }
	if jget(m, 'id') != chromatic_theme_id {
		return error('the live theme is ${jget(m, 'id')}, not Chromatic; apply Chromatic first.\nExample: horneroctl appearance chromatic apply --yes')
	}
	return m
}

// gated_theme_doc validates a theme document structurally and against the
// gates at its own level before it may be stored.
fn gated_theme_doc(doc map[string]json2.Any) ! {
	theme := parse_signal_theme('', doc) or { return error(err.msg()) }
	mut level := jget(jmap(jmap(doc, 'chromatic'), 'resolved'), 'contrast')
	if level.len == 0 {
		level = 'standard'
	}
	rows := validate_signal_gates(theme, level, false)!
	failures := gate_failures(rows)
	if failures.len > 0 {
		return error('palette fails the ${level} gates: ' + failures.join('; '))
	}
}

fn store_user_pack(doc map[string]json2.Any) !string {
	id := jget(doc, 'id')
	path := user_pack_path(id)
	write_atomic_synced(path, json2.encode(doc, escape_unicode: true) + '\n')!
	return path
}

fn check_save_target(id string, force bool) ! {
	if !valid_palette_id(id) {
		return error('id must be lowercase kebab-case (letters, digits, single dashes)')
	}
	if id == chromatic_theme_id || id in signal_builtin_theme_ids {
		return error('id ${id} is reserved')
	}
	if _ := read_pack_map(id) {
		if !pack_is_user(id) {
			return error('id ${id} names an installed catalogue theme; choose another id')
		}
		if !force {
			return error('palette ${id} already exists; pass --force to replace it')
		}
	}
}

// chromatic_save stores the live Chromatic palette as a user theme.
pub fn chromatic_save(o ChromaticOptions) ChromaticReply {
	if o.id.len == 0 || o.name.len == 0 {
		return chromatic_fail('chromatic.usage', 'save needs --id and --name.\nExample: horneroctl appearance chromatic save --id amber-dusk --name "Amber dusk" --yes')
	}
	if o.from.len > 0 && o.from != 'current' {
		return chromatic_fail('chromatic.usage', '--from only supports "current"')
	}
	check_save_target(o.id, o.force) or {
		return chromatic_fail('chromatic.usage', err.msg())
	}
	live := live_chromatic_scheme() or { return chromatic_fail('chromatic.usage', err.msg()) }
	doc := theme_document(live, o.id, o.name) or {
		return chromatic_fail('chromatic.usage', err.msg())
	}
	gated_theme_doc(doc) or { return chromatic_fail('chromatic.gates-failed', err.msg()) }
	if o.dry_run {
		return chromatic_ok('would save ${o.id} to ${user_pack_path(o.id)}; nothing was written.', {
			'dryRun': jbool(true)
			'id':     jstr(o.id)
			'path':   jstr(user_pack_path(o.id))
		})
	}
	if !o.yes {
		return chromatic_fail('chromatic.usage', '${usage_yes}\nExample: horneroctl appearance chromatic save --id ${o.id} --name "${o.name}" --dry-run')
	}
	path := store_user_pack(doc) or {
		return chromatic_fail('chromatic.write-failed', err.msg())
	}
	return chromatic_ok('saved ${o.name} as ${o.id} (${path})', {
		'id':   jstr(o.id)
		'path': jstr(path)
	})
}

// chromatic_list lists saved (user-collection) palettes.
pub fn chromatic_list(o ChromaticOptions) ChromaticReply {
	dir := resolve_themes_dir()
	mut rows := []json2.Any{}
	mut lines := []string{}
	mut ids := os.ls(dir) or { []string{} }
	ids.sort()
	for id in ids {
		raw := os.read_file(os.join_path(dir, id, 'theme.json')) or { continue }
		m := parse_json_object(raw) or { continue }
		if jget(m, 'collection') != 'user' {
			continue
		}
		rows << json2.Any({
			'id':        jstr(id)
			'name':      jstr(jget(m, 'name'))
			'mode':      jstr(jget(m, 'mode'))
			'chromatic': jbool('chromatic' in m)
			'createdAt': jstr(jget(jmap(m, 'chromatic'), 'createdAt'))
		})
		lines << '${id}  ${jget(m, 'name')}  ${jget(m, 'mode')}'
	}
	if lines.len == 0 {
		lines << 'no saved palettes'
	}
	return chromatic_ok(lines.join('\n'), {
		'palettes': json2.Any(rows)
	})
}

// chromatic_rename changes the display name of a saved palette.
pub fn chromatic_rename(o ChromaticOptions) ChromaticReply {
	if o.id.len == 0 || o.name.len == 0 {
		return chromatic_fail('chromatic.usage', 'rename needs an id and --name.\nExample: horneroctl appearance chromatic rename amber-dusk --name "Dusk" --yes')
	}
	if !pack_is_user(o.id) {
		return chromatic_fail('chromatic.usage', '${o.id} is not a saved palette')
	}
	if o.dry_run {
		return chromatic_ok('would rename ${o.id} to "${o.name}"; nothing was written.', {
			'dryRun': jbool(true)
		})
	}
	if !o.yes {
		return chromatic_fail('chromatic.usage', '${usage_yes}\nExample: horneroctl appearance chromatic rename ${o.id} --name "${o.name}" --dry-run')
	}
	raw := os.read_file(user_pack_path(o.id)) or {
		return chromatic_fail('chromatic.write-failed', err.msg())
	}
	mut m := parse_json_object(raw) or {
		return chromatic_fail('chromatic.state-corrupt', '${user_pack_path(o.id)}: ${err.msg()}')
	}
	m['name'] = jstr(o.name)
	store_user_pack(m) or { return chromatic_fail('chromatic.write-failed', err.msg()) }
	return chromatic_ok('renamed ${o.id} to "${o.name}"', {
		'id':   jstr(o.id)
		'name': jstr(o.name)
	})
}

// chromatic_delete removes a saved palette (never a catalogue theme, never
// the one selected in shell.json).
pub fn chromatic_delete(o ChromaticOptions) ChromaticReply {
	if o.id.len == 0 {
		return chromatic_fail('chromatic.usage', 'delete needs an id.\nExample: horneroctl appearance chromatic delete amber-dusk --yes')
	}
	if !valid_palette_id(o.id) || !pack_is_user(o.id) {
		return chromatic_fail('chromatic.usage', '${o.id} is not a saved palette')
	}
	if jget(read_shell_appearance(), 'theme') == o.id {
		return chromatic_fail('chromatic.usage', '${o.id} is the selected theme; apply another theme first')
	}
	if o.dry_run {
		return chromatic_ok('would delete ${o.id}; nothing was removed.', {
			'dryRun': jbool(true)
		})
	}
	if !o.yes {
		return chromatic_fail('chromatic.usage', '${usage_yes}\nExample: horneroctl appearance chromatic delete ${o.id} --dry-run')
	}
	dir := os.join_path(resolve_themes_dir(), o.id)
	os.rm(user_pack_path(o.id)) or {
		return chromatic_fail('chromatic.write-failed', err.msg())
	}
	os.rmdir(dir) or {}
	return chromatic_ok('deleted ${o.id}', {
		'id': jstr(o.id)
	})
}

// chromatic_export prints (or writes) the live palette as a theme document.
pub fn chromatic_export(o ChromaticOptions) ChromaticReply {
	live := live_chromatic_scheme() or { return chromatic_fail('chromatic.usage', err.msg()) }
	fp := jget(jmap(live, 'chromatic'), 'fingerprint')
	id := if o.id.len > 0 {
		o.id
	} else if fp.len > 14 {
		'chromatic-' + fp['sha256:'.len..'sha256:'.len + 8]
	} else {
		'chromatic-export'
	}
	if !valid_palette_id(id) || id == chromatic_theme_id {
		return chromatic_fail('chromatic.usage', 'invalid export id ${id}')
	}
	name := if o.name.len > 0 { o.name } else { 'Chromatic ${id}' }
	doc := theme_document(live, id, name) or {
		return chromatic_fail('chromatic.usage', err.msg())
	}
	text := json2.encode(doc, escape_unicode: true) + '\n'
	if o.output.len == 0 {
		return chromatic_ok(text.trim_space(), {
			'id':    jstr(id)
			'theme': json2.Any(doc)
		})
	}
	if o.dry_run {
		return chromatic_ok('would write ${o.output}; nothing was written.', {
			'dryRun': jbool(true)
		})
	}
	write_atomic_synced(o.output, text) or {
		return chromatic_fail('chromatic.write-failed', err.msg())
	}
	return chromatic_ok('exported ${id} to ${o.output}', {
		'id':   jstr(id)
		'path': jstr(o.output)
	})
}

// chromatic_import installs a theme document as a user palette after the
// same structural and gate checks as any applied theme.
pub fn chromatic_import(o ChromaticOptions) ChromaticReply {
	if o.file.len == 0 {
		return chromatic_fail('chromatic.usage', 'missing FILE.\nExample: horneroctl appearance chromatic import palette.json --yes')
	}
	raw := os.read_file(o.file) or {
		return chromatic_fail('chromatic.usage', 'cannot read ${o.file}: ${err.msg()}')
	}
	mut doc := parse_json_object(raw) or {
		return chromatic_fail('chromatic.usage', '${o.file}: ${err.msg()}')
	}
	id := if o.id.len > 0 { o.id } else { jget(doc, 'id') }
	check_save_target(id, o.force) or { return chromatic_fail('chromatic.usage', err.msg()) }
	doc['id'] = jstr(id)
	doc['collection'] = jstr('user')
	doc['schemaVersion'] = jint(2)
	if 'name' !in doc {
		doc['name'] = jstr(id)
	}
	for k, v in {
		'gtkTheme':         'auto'
		'iconTheme':        'Papirus-Dark'
		'defaultWallpaper': 'none'
		'wallpaperDir':     id
	} {
		if jget(doc, k).len == 0 {
			doc[k] = jstr(v)
		}
	}
	gated_theme_doc(doc) or { return chromatic_fail('chromatic.gates-failed', err.msg()) }
	if o.dry_run {
		return chromatic_ok('would import ${id} to ${user_pack_path(id)}; nothing was written.', {
			'dryRun': jbool(true)
			'id':     jstr(id)
		})
	}
	if !o.yes {
		return chromatic_fail('chromatic.usage', '${usage_yes}\nExample: horneroctl appearance chromatic import ${o.file} --dry-run')
	}
	path := store_user_pack(doc) or {
		return chromatic_fail('chromatic.write-failed', err.msg())
	}
	return chromatic_ok('imported ${id} (${path})', {
		'id':   jstr(id)
		'path': jstr(path)
	})
}
