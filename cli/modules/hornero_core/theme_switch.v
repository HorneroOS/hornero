module hornero_core

import os
import x.json2

// Official theme switching over the flagship trio
// (hornero-dark/hornero-light/pampa, HorneroOS/config profiles/themes/).
//
// Reads stay native (installed theme.json packs, same as theme list/show)
// while every mutation delegates to the verified `dots-appearance theme
// apply` verb: no palette, GTK, or wallpaper logic is reimplemented here.
// Switching is atomic in the validate -> resolve -> apply -> verify sense:
// the pack is validated and the backend resolved before anything mutates,
// and after apply the live state is read back and must agree with the pack
// (mode + GTK). A half-applied switch (GTK=light with shell=dark) is
// reported as a failure, never as success; when the pre-apply state was a
// clean official theme, one best-effort re-apply restores it.

// official_theme_ids is the flagship trio `theme set` switches between.
// Any other installed pack still goes through `theme apply`. Order is
// significant for mode-only live states: hornero-dark and pampa are both
// dark-mode packs, so a state carrying mode=dark but no GTK signal resolves
// to hornero-dark (first); GTK is the discriminator (Hornero-Dark vs
// Hornero-Pampa) whenever the backend reports it.
pub fn official_theme_ids() []string {
	return ['hornero-dark', 'hornero-light', 'pampa']
}

pub fn is_official_theme_id(id string) bool {
	return id in official_theme_ids()
}

// AppearanceStatus is one live-state reading from the config backend
// (`dots-appearance status --json`): scheme mode plus the GTK side.
pub struct AppearanceStatus {
pub:
	mode             string
	flavour          string
	gtk_theme        string
	icon_theme       string
	gtk_color_scheme string
	wallpaper        string
}

fn status_field(m map[string]json2.Any, key string) string {
	if v := m[key] {
		return v.str()
	}
	return ''
}

// query_appearance_status delegates the live-state read to the config
// backend. The JSON shape is the backend's contract; V only decodes it.
fn query_appearance_status(helper string) !AppearanceStatus {
	bin := dots_appearance_or_fail(helper)!
	rep := delegated_run(ExecSpec{
		prog: bin
		args: ['status', '--json']
	})
	if !rep.ok {
		return error('backend failed (exit ${rep.exit_code}):\n${rep.output}')
	}
	parsed := json2.decode[json2.Any](rep.output) or {
		return error('backend returned non-JSON status:\n${rep.output}')
	}
	if parsed is map[string]json2.Any {
		return AppearanceStatus{
			mode:             status_field(parsed, 'mode')
			flavour:          status_field(parsed, 'flavour')
			gtk_theme:        status_field(parsed, 'gtkTheme')
			icon_theme:       status_field(parsed, 'iconTheme')
			gtk_color_scheme: status_field(parsed, 'gtkColorScheme')
			wallpaper:        status_field(parsed, 'wallpaper')
		}
	}
	return error('backend returned non-JSON status:\n${rep.output}')
}

// pack_expected_mode derives the mode a pack applies: the `mode` token
// when present (flagship packs), else the legacy `darkMode` boolean.
fn pack_expected_mode(m map[string]json2.Any) string {
	if v := m['mode'] {
		s := v.str()
		if s == 'dark' || s == 'light' {
			return s
		}
	}
	if v := m['darkMode'] {
		match v {
			bool {
				if v {
					return 'dark'
				}
				return 'light'
			}
			else {}
		}
	}
	return ''
}

// official_pack_mode reads the expected mode of one installed official
// pack (canonical-first, same lookup order as show_theme_pack).
fn official_pack_mode(id string) string {
	for dir in resolve_themes_dirs_for_read() {
		raw := os.read_file(os.join_path(dir, id, 'theme.json')) or { continue }
		parsed := json2.decode[json2.Any](raw) or { continue }
		if parsed is map[string]json2.Any {
			return pack_expected_mode(parsed)
		}
	}
	return ''
}

// match_official_theme resolves live backend state to one official id.
// A known value that disagrees with a pack rejects that pack; a match
// needs at least one positive signal (mode or GTK), so empty or foreign
// state resolves to '' (custom) instead of a false official hit.
fn match_official_theme(st AppearanceStatus) string {
	if st.gtk_theme.len == 0 && st.mode.len == 0 {
		return ''
	}
	for id in official_theme_ids() {
		pack := show_theme_pack(id) or { continue }
		if pack.gtk_theme.len > 0 && st.gtk_theme.len > 0 && pack.gtk_theme != st.gtk_theme {
			continue
		}
		mode := official_pack_mode(id)
		if mode.len > 0 && st.mode.len > 0 && mode != st.mode {
			continue
		}
		gtk_hit := pack.gtk_theme.len > 0 && st.gtk_theme.len > 0 && pack.gtk_theme == st.gtk_theme
		mode_hit := mode.len > 0 && st.mode.len > 0 && mode == st.mode
		if gtk_hit || mode_hit {
			return id
		}
	}
	return ''
}

pub struct ThemeGetOptions {
pub:
	dry_run bool
	helper  string
}

// theme_get_report implements `appearance theme get` (read-only): the live
// backend state matched against the official trio. Unknown/custom states
// still succeed; they report id '' with the observed values.
pub fn theme_get_report(opts ThemeGetOptions) CommandResult {
	bin := dots_appearance_or_fail(opts.helper) or {
		if opts.dry_run {
			'dots-appearance'
		} else {
			return fail_result('appearance theme get', err.msg())
		}
	}
	if opts.dry_run {
		rep := run_exec(ExecSpec{
			prog:    bin
			args:    ['status', '--json']
			dry_run: true
		})
		return ok_result('appearance theme get', 'would run: ${rep.command_line}', {
			'command_line': rep.command_line
			'dry_run':      'true'
		})
	}
	st := query_appearance_status(opts.helper) or {
		return fail_result('appearance theme get', err.msg())
	}
	data := {
		'id':               match_official_theme(st)
		'mode':             st.mode
		'flavour':          st.flavour
		'gtk_theme':        st.gtk_theme
		'icon_theme':       st.icon_theme
		'gtk_color_scheme': st.gtk_color_scheme
	}
	if data['id'].len > 0 {
		return ok_result('appearance theme get', 'current theme: ${data['id']} (mode=${st.mode}, gtk=${st.gtk_theme})',
			data)
	}
	return ok_result('appearance theme get', 'current theme: (custom) mode=${st.mode}, gtk=${st.gtk_theme}',
		data)
}

pub struct ThemeSetOptions {
pub:
	id      string
	dry_run bool
	yes     bool
	helper  string
}

// rollback_official_theme best-effort restores the previously active
// official theme after a failed set. Returns '' when there is nothing
// coherent to restore (custom pre-state, or the target never changed).
fn rollback_official_theme(bin string, pre_id string, target string) string {
	if pre_id.len == 0 || pre_id == target {
		return ''
	}
	rb := delegated_run(ExecSpec{
		prog: bin
		args: ['theme', 'apply', pre_id]
	})
	if rb.ok {
		return 'rolled back to ${pre_id}.'
	}
	return 'rollback to ${pre_id} failed (exit ${rb.exit_code}):\n${rb.output}'
}

// theme_set_report implements `appearance theme set <official-id>`:
// validate -> resolve -> apply -> verify. Apply delegates to
// `dots-appearance theme apply` (one backend verb sets palette, scheme,
// and GTK together); verify reads the live state back and refuses a split
// (GTK/shell disagree) as a failure. Mutating: needs --yes; --dry-run
// only previews.
pub fn theme_set_report(opts ThemeSetOptions) CommandResult {
	if !is_official_theme_id(opts.id) {
		return fail_result('appearance theme set', 'unknown official theme: ${opts.id} (want hornero-dark|hornero-light|pampa).\nExample: horneroctl appearance theme set hornero-dark --dry-run')
	}
	if !opts.yes && !opts.dry_run {
		return fail_result('appearance theme set', 'refusing to apply without --yes (preview with --dry-run).\nExample: horneroctl appearance theme set ${opts.id} --dry-run')
	}
	pack := show_theme_pack(opts.id) or { return fail_result('appearance theme set', err.msg()) }
	mode := official_pack_mode(opts.id)
	bin := dots_appearance_or_fail(opts.helper) or {
		if opts.dry_run {
			'dots-appearance'
		} else {
			return fail_result('appearance theme set', err.msg())
		}
	}
	apply_line := command_line(bin, ['theme', 'apply', opts.id])
	if opts.dry_run {
		return ok_result('appearance theme set', 'would run: ${apply_line} (then verify mode=${mode} gtk=${pack.gtk_theme})',
			{
			'command_line': apply_line
			'dry_run':      'true'
			'id':           opts.id
		})
	}
	pre := query_appearance_status(opts.helper) or { AppearanceStatus{} }
	pre_id := match_official_theme(pre)
	rep := delegated_run(ExecSpec{
		prog: bin
		args: ['theme', 'apply', opts.id]
	})
	if !rep.ok {
		rb := rollback_official_theme(bin, pre_id, opts.id)
		mut msg := 'backend failed (exit ${rep.exit_code}):\n${rep.output}'
		if rb.len > 0 {
			msg += '\n${rb}'
		}
		return fail_result('appearance theme set', msg)
	}
	post := query_appearance_status(opts.helper) or {
		rb := rollback_official_theme(bin, pre_id, opts.id)
		mut msg := 'verify failed: could not read back appearance state.\n${err.msg()}'
		if rb.len > 0 {
			msg += '\n${rb}'
		} else {
			msg += '\nRun: horneroctl appearance theme get'
		}
		return fail_result('appearance theme set', msg)
	}
	mut mismatches := []string{}
	if mode.len > 0 && post.mode.len > 0 && post.mode != mode {
		mismatches << 'mode is ${post.mode} (want ${mode})'
	}
	if pack.gtk_theme.len > 0 && post.gtk_theme.len > 0 && post.gtk_theme != pack.gtk_theme {
		mismatches << 'gtk is ${post.gtk_theme} (want ${pack.gtk_theme})'
	}
	if mismatches.len > 0 {
		rb := rollback_official_theme(bin, pre_id, opts.id)
		mut msg := 'verify failed: ${mismatches.join(', ')}; refusing a split state.'
		if rb.len > 0 {
			msg += '\n${rb}'
		} else {
			msg += '\nRun: horneroctl appearance theme get'
		}
		return fail_result('appearance theme set', msg)
	}
	return ok_result('appearance theme set', 'theme set to ${opts.id} (mode=${post.mode}, gtk=${post.gtk_theme})',
		{
		'id':           opts.id
		'mode':         post.mode
		'gtk_theme':    post.gtk_theme
		'command_line': rep.command_line
	})
}
