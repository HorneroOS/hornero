module hornero_core

import os
import x.json2

// Mutating Chromatic verbs: apply, follow, rollback, off.

const usage_yes = 'refusing to change the desktop without --yes (preview with --dry-run).'

fn paths_of(plan []PlannedWrite) []string {
	return plan.map(it.path)
}

// gtk_for_mode picks the GTK tree/icon/policy of the fallback pack for the
// mode ("the mode's tree"); `auto` is resolved from the palette.
fn gtk_for_mode(theme SignalTheme) (string, string, string) {
	fallback := chromatic_fallback_id(theme.mode)
	mut gtk := ''
	mut icon := ''
	mut scheme := ''
	if pack := read_pack_map(fallback) {
		gtk = pack_str(pack, 'gtkTheme')
		icon = pack_str(pack, 'iconTheme')
		scheme = pack_str(pack, 'gtkColorScheme')
	}
	if gtk.len == 0 || gtk == 'auto' {
		gtk = gtk_theme_for(theme)
	}
	if icon.len == 0 {
		icon = if theme.mode == 'dark' { 'Papirus-Dark' } else { 'Papirus-Light' }
	}
	return gtk, icon, pack_gtk_policy(scheme, '', '', theme.mode)
}

// chromatic_fallback_id is appearance.chromatic.fallback[mode], else the
// built-in Signal theme of that mode.
fn chromatic_fallback_id(mode string) string {
	cfg := jmap(jmap(read_shell_appearance(), 'chromatic'), 'fallback')
	id := jget(cfg, mode)
	if id.len > 0 && id != chromatic_theme_id {
		return id
	}
	return if mode == 'light' { 'hornero-signal-day' } else { signal_default_theme_id }
}

fn run_reloads(theme SignalTheme, deps ChromaticBackends) []string {
	gtk, icon, policy := gtk_for_mode(theme)
	return deps.reload(theme.mode, theme, gtk, icon, policy)
}

fn gates_json(g Generated) json2.Any {
	mut rows := []json2.Any{}
	for r in g.rows {
		rows << json2.Any([jstr(r.label), json2.Any(r.ratio), json2.Any(r.min)])
	}
	return json2.Any({
		'level':  jstr(g.level)
		'passed': jbool(true)
		'rows':   json2.Any(rows)
	})
}

fn generated_doc(g Generated, extra map[string]json2.Any) map[string]json2.Any {
	mut d := {
		'id':          jstr(chromatic_theme_id)
		'mode':        jstr(g.mode)
		'variant':     jstr(g.variant)
		'contrast':    jstr(g.level)
		'fingerprint': jstr(g.fingerprint)
		'scheme':      json2.Any(g.scheme)
		'gates':       gates_json(g)
		'inference':   json2.Any(jmap(g.doc, 'inference'))
	}
	for k, v in extra {
		d[k] = v
	}
	return d
}

fn personality_of(g Generated) string {
	return jget(jmap(g.doc, 'inference'), 'personality')
}

// chromatic_preview generates and validates without writing anything.
pub fn chromatic_preview(o ChromaticOptions) ChromaticReply {
	req := resolve_chromatic_request(o) or { return chromatic_fail_from(err.msg()) }
	g := generate_validated(req, o.dry_run) or { return chromatic_fail_from(err.msg()) }
	plan, warnings := plan_chromatic_outputs(g) or { return chromatic_fail_from(err.msg()) }
	msg := 'preview: ${g.mode} ${g.variant} (${g.level}) ${personality_of(g)}\nfingerprint ${g.fingerprint}\n' +
		'would write ${plan.len} files; nothing was written.'
	return chromatic_ok(msg, generated_doc(g, {
		'dryRun':     jbool(true)
		'wouldWrite': jstrs(paths_of(plan))
		'warnings':   jstrs(warnings)
	}))
}

// finish_apply is the shared tail of apply and follow: lock, commit, state,
// reloads.
fn finish_apply(g Generated, plan []PlannedWrite, patch ShellPatch, reason string, persisted bool, mut warnings []string, deps ChromaticBackends) ChromaticReply {
	mut lk := acquire_appearance_lock() or {
		return chromatic_fail('chromatic.locked', err.msg())
	}
	snap := commit_locked(plan, patch, reason) or {
		lk.release()
		return chromatic_fail_from(err.msg())
	}
	write_chromatic_state(g, snap) or {
		warnings << 'state.json not updated: ${err.msg()}'
	}
	lk.release()
	warnings << run_reloads(g.theme, deps)
	msg := 'Chromatic ${g.mode} ${g.variant} applied (${g.level}); snapshot ${snap:04}.\n' +
		'${personality_of(g)}'
	return chromatic_ok(msg, generated_doc(g, {
		'outputs':   jstrs(paths_of(plan))
		'snapshot':  jstr('${snap:04}')
		'persisted': jbool(persisted)
		'warnings':  jstrs(warnings)
	}))
}

// chromatic_apply generates, validates and applies a palette atomically.
pub fn chromatic_apply(o ChromaticOptions, deps ChromaticBackends) ChromaticReply {
	if o.dry_run {
		return chromatic_preview(o)
	}
	if !o.yes {
		return chromatic_fail('chromatic.usage', '${usage_yes}\nExample: horneroctl appearance chromatic apply --dry-run')
	}
	req := resolve_chromatic_request(o) or { return chromatic_fail_from(err.msg()) }
	g := generate_validated(req, false) or { return chromatic_fail_from(err.msg()) }
	plan, mut warnings := plan_chromatic_outputs(g) or { return chromatic_fail_from(err.msg()) }
	patch := ShellPatch{
		theme_mode:     'set'
		theme:          chromatic_theme_id
		chromatic_mode: if o.no_persist { 'keep' } else { 'set' }
		chromatic:      json2.Any(request_as_json(req))
	}
	return finish_apply(g, plan, patch, 'apply', !o.no_persist, mut warnings, deps)
}

fn skipped(reason string) ChromaticReply {
	return chromatic_ok('follow skipped: ${reason}', {
		'skipped': jbool(true)
		'reason':  jstr(reason)
	})
}

// chromatic_follow regenerates for the current wallpaper when Chromatic is
// the active theme and the explicit follow policy is `auto`.
pub fn chromatic_follow(o ChromaticOptions, deps ChromaticBackends) ChromaticReply {
	appearance := read_shell_appearance()
	if jget(appearance, 'theme') != chromatic_theme_id {
		return skipped('theme is not ${chromatic_theme_id}')
	}
	policy := jget(jmap(appearance, 'chromatic'), 'follow')
	if policy != 'auto' {
		return skipped('follow policy is "${if policy.len > 0 { policy } else { 'unset' }}" (only auto follows)')
	}
	if !o.yes && !o.dry_run {
		return chromatic_fail('chromatic.usage', '${usage_yes}\nExample: horneroctl appearance chromatic follow --yes')
	}
	mut opts := ChromaticOptions{
		...o
	}
	if opts.source.len == 0 && opts.seeds.len == 0 && jget(jmap(appearance, 'chromatic'),
		'source') == 'wallpaper' {
		opts = ChromaticOptions{
			...o
			source: 'wallpaper'
		}
	}
	req := resolve_chromatic_request(opts) or { return chromatic_fail_from(err.msg()) }
	g := generate_validated(req, o.dry_run) or { return chromatic_fail_from(err.msg()) }
	state, _ := read_chromatic_state()
	if jget(state, 'active') == 'true' && jget(state, 'fingerprint') == g.fingerprint
		&& g.fingerprint.len > 0 {
		return skipped('palette unchanged (${g.fingerprint})')
	}
	plan, mut warnings := plan_chromatic_outputs(g) or { return chromatic_fail_from(err.msg()) }
	if o.dry_run {
		return chromatic_ok('follow would apply ${g.mode} ${g.variant}; nothing was written.',
			generated_doc(g, {
				'dryRun':     jbool(true)
				'wouldWrite': jstrs(paths_of(plan))
			}))
	}
	patch := ShellPatch{
		theme_mode: 'set'
		theme:      chromatic_theme_id
	}
	return finish_apply(g, plan, patch, 'apply', false, mut warnings, deps)
}

// chromatic_follow_after_wallpaper is the single call `wallpaper set` makes.
// It returns '' when Chromatic does not follow (the common case) and a short
// status otherwise; it never fails the wallpaper change.
pub fn chromatic_follow_after_wallpaper() string {
	appearance := read_shell_appearance()
	if jget(appearance, 'theme') != chromatic_theme_id
		|| jget(jmap(appearance, 'chromatic'), 'follow') != 'auto' {
		return ''
	}
	r := chromatic_follow(ChromaticOptions{
		verb: 'follow'
		yes:  true
	}, default_chromatic_backends())
	if r.ok {
		return r.message
	}
	return 'follow failed (${r.code}): ${r.message}'
}

// --- rollback ---------------------------------------------------------------------------

// chromatic_rollback restores the snapshot `steps` back (1 = the state
// before the last change) without the helper, as a new transaction, so it
// can itself be rolled back.
pub fn chromatic_rollback(o ChromaticOptions, deps ChromaticBackends) ChromaticReply {
	if o.steps < 1 {
		return chromatic_fail('chromatic.usage', '--steps must be at least 1')
	}
	entries, corrupt := read_history()
	if entries.len < o.steps {
		return chromatic_fail('chromatic.no-snapshot', 'only ${entries.len} usable snapshot(s); cannot go back ${o.steps}.' +
			if corrupt.len > 0 {
				' Corrupt snapshots were set aside: ${corrupt.join(', ')}'
			} else {
				''
			})
	}
	entry := entries[o.steps - 1]
	files := jmap(entry.doc, 'files')
	scheme_path := signal_scheme_file()
	mut keys := files.keys()
	keys.sort()
	mut plan := []PlannedWrite{}
	mut ordered := []string{}
	if scheme_path in keys {
		ordered << scheme_path
	}
	for k in keys {
		if k != scheme_path {
			ordered << k
		}
	}
	for path in ordered {
		jail_expanded(path, path, true) or {
			return chromatic_fail('chromatic.state-corrupt', 'snapshot ${entry.number:04} names a path outside the XDG directories: ${err.msg()}')
		}
		content := files[path] or { json2.Any(json2.Null{}) }
		if content is json2.Null {
			plan << PlannedWrite{
				path:   path
				remove: true
			}
		} else {
			plan << PlannedWrite{
				path:    path
				content: content.str()
			}
		}
	}
	sa := jmap(entry.doc, 'shellAppearance')
	theme_v := sa['theme'] or { json2.Any(json2.Null{}) }
	chrom_v := sa['chromatic'] or { json2.Any(json2.Null{}) }
	patch := ShellPatch{
		theme_mode:     if theme_v is json2.Null { 'remove' } else { 'set' }
		theme:          if theme_v is json2.Null { '' } else { theme_v.str() }
		chromatic_mode: if chrom_v is json2.Null { 'remove' } else { 'set' }
		chromatic:      chrom_v
	}
	if o.dry_run {
		return chromatic_ok('rollback would restore snapshot ${entry.number:04} (${jget(entry.doc, 'themeId')}, ${plan.len} files); nothing was written.', {
			'dryRun':     jbool(true)
			'snapshot':   jstr('${entry.number:04}')
			'wouldWrite': jstrs(paths_of(plan))
		})
	}
	if !o.yes {
		return chromatic_fail('chromatic.usage', '${usage_yes}\nExample: horneroctl appearance chromatic rollback --dry-run')
	}
	mut lk := acquire_appearance_lock() or {
		return chromatic_fail('chromatic.locked', err.msg())
	}
	snap := commit_locked(plan, patch, 'rollback') or {
		lk.release()
		return chromatic_fail_from(err.msg())
	}
	lk.release()
	mut warnings := []string{}
	restored := jmap(entry.doc, 'scheme')
	mut theme_id := jget(entry.doc, 'themeId')
	if restored.len > 0 {
		if t := parse_signal_theme('', restored) {
			warnings << run_reloads(t, deps)
			theme_id = t.id
		}
	}
	mark_chromatic_inactive_unless(restored, snap)
	return chromatic_ok('rolled back to snapshot ${entry.number:04} (${theme_id}); undo with another rollback.', {
		'restored': jstr('${entry.number:04}')
		'themeId':  jstr(theme_id)
		'snapshot': jstr('${snap:04}')
		'outputs':  jstrs(paths_of(plan))
		'warnings': jstrs(warnings)
	})
}

fn mark_chromatic_inactive_unless(restored map[string]json2.Any, snap int) {
	if jget(restored, 'id') == chromatic_theme_id {
		mut doc, _ := read_chromatic_state()
		if doc.len > 0 {
			doc['active'] = jbool(true)
			doc['snapshot'] = jstr('${snap:04}')
			chrom := jmap(restored, 'chromatic')
			doc['fingerprint'] = chrom['fingerprint'] or { jstr('') }
			write_atomic_synced(chromatic_state_file(), json2.encode(doc, escape_unicode: true) +
				'\n') or {}
		}
		return
	}
	mark_chromatic_inactive(snap)
}

// --- off ----------------------------------------------------------------------------------

// chromatic_off leaves Chromatic by applying the configured fallback theme
// through the regular theme pipeline; Chromatic outputs are removed and the
// previous state stays rollback-able.
pub fn chromatic_off(o ChromaticOptions, deps ChromaticBackends) ChromaticReply {
	mode := if live := read_signal_scheme() { live.mode } else { 'dark' }
	fallback := chromatic_fallback_id(mode)
	read_pack_map(fallback) or {
		return chromatic_fail('chromatic.write-failed', 'fallback theme ${fallback} is not installed: ${err.msg()}')
	}
	if o.dry_run {
		return chromatic_ok('off would apply ${fallback} and remove Chromatic outputs; nothing was written.', {
			'dryRun':   jbool(true)
			'fallback': jstr(fallback)
		})
	}
	if !o.yes {
		return chromatic_fail('chromatic.usage', '${usage_yes}\nExample: horneroctl appearance chromatic off --dry-run')
	}
	mut lk := acquire_appearance_lock() or {
		return chromatic_fail('chromatic.locked', err.msg())
	}
	mut tracked := [signal_scheme_file()]
	out := signal_output_paths()
	tracked << [out.hyprland_lua, out.hyprlock_conf, out.alacritty_toml, out.ghostty_theme,
		out.btop_theme, out.cava_theme]
	for m in list_template_manifests().manifests {
		if p := jail_output(m.output) {
			tracked << p
		}
	}
	snap := write_snapshot(tracked, 'off') or {
		lk.release()
		return chromatic_fail_from(err.msg())
	}
	applied := theme_apply_native_with(fallback, '', false, deps.appearance)
	if !applied.ok {
		lk.release()
		return chromatic_fail('chromatic.write-failed', 'fallback ${fallback} failed: ${applied.message}\nThe previous state is in snapshot ${snap:04} (horneroctl appearance chromatic rollback).')
	}
	chromatic_release_outputs()
	mark_chromatic_inactive(snap)
	lk.release()
	return chromatic_ok('Chromatic off: ${fallback} applied; snapshot ${snap:04} keeps the previous state.', {
		'fallback': jstr(fallback)
		'snapshot': jstr('${snap:04}')
	})
}

// chromatic_marked_for_tests exposes the marker scan.
pub fn chromatic_marked_for_tests() []string {
	return chromatic_marked_outputs()
}

// is_chromatic_active reads the live scheme id.
pub fn is_chromatic_active() bool {
	live := read_signal_scheme() or { return false }
	return live.id == chromatic_theme_id && os.is_file(signal_scheme_file())
}
