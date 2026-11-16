module hornero_core

// Official theme switching over the built-in Hornero Signal themes
// (hornero-signal-night/day/contrast, HorneroOS/config profiles/themes/).
//
// Switching is atomic in the validate -> apply -> verify sense: the pack
// is validated before anything mutates, and after apply the live scheme
// and GTK state are read back and must agree with the pack. A
// half-applied switch is reported as a failure, never as success; when the
// pre-apply state was a clean official theme, one best-effort re-apply
// restores it.

// official_theme_ids is the built-in trio `theme set` switches between.
// Any other installed schema-v2 pack still goes through `theme apply`.
pub fn official_theme_ids() []string {
	return signal_builtin_theme_ids
}

pub fn is_official_theme_id(id string) bool {
	return id in official_theme_ids()
}

// AppearanceStatus is one native live-state reading (selected theme, live
// scheme mode, GTK side), gathered by read_appearance_status_native.
pub struct AppearanceStatus {
pub:
	theme            string
	mode             string
	gtk_theme        string
	icon_theme       string
	gtk_color_scheme string
	wallpaper        string
}

// query_appearance_status reads the live state natively.
fn query_appearance_status() !AppearanceStatus {
	return read_appearance_status_native()
}

// match_official_theme resolves live state to one official id: the
// selected theme must be built-in and agree with the live scheme mode.
fn match_official_theme(st AppearanceStatus) string {
	if !is_official_theme_id(st.theme) {
		return ''
	}
	live := read_signal_scheme() or { return '' }
	if live.id != st.theme {
		return ''
	}
	return st.theme
}

pub struct ThemeGetOptions {
pub:
	dry_run bool
}

// theme_get_report implements `appearance theme get` (read-only): the
// selected theme (live scheme, persisted state, shell setting, factory
// default) plus GTK. A persisted retired id reports its Signal
// replacement and `migrated_from`; nothing is written.
pub fn theme_get_report(opts ThemeGetOptions) CommandResult {
	if opts.dry_run {
		return ok_result('appearance theme get', 'would run: read scheme state + gtk settings',
			{
				'command_line': 'read ${scheme_state_file()} + ${resolve_gtk3_file()}'
				'dry_run':      'true'
			})
	}
	st := query_appearance_status() or { return fail_result('appearance theme get', err.msg()) }
	sel := resolve_signal_selection()
	data := {
		'id':               sel.id
		'source':           sel.source
		'migrated_from':    sel.migrated_from
		'official':         is_official_theme_id(sel.id).str()
		'mode':             st.mode
		'gtk_theme':        st.gtk_theme
		'icon_theme':       st.icon_theme
		'gtk_color_scheme': st.gtk_color_scheme
	}
	mut msg := 'current theme: ${sel.id} (${sel.source}; mode=${or_unknown(st.mode)}, gtk=${st.gtk_theme})'
	if sel.migrated_from.len > 0 {
		msg += '\npersisted ${sel.migrated_from} migrates to ${sel.id}; run: horneroctl appearance sync --yes'
	}
	return ok_result('appearance theme get', msg, data)
}

pub struct ThemeSetOptions {
pub:
	id      string
	dry_run bool
	yes     bool
}

// rollback_official_theme best-effort restores the previously active
// official theme after a failed set. Returns '' when there is nothing
// coherent to restore (custom pre-state, or the target never changed).
fn rollback_official_theme(apply_fn fn (string, string, bool) CommandResult, pre_id string, target string) string {
	if pre_id.len == 0 || pre_id == target {
		return ''
	}
	rb := apply_fn(pre_id, '', false)
	if rb.ok {
		return 'rolled back to ${pre_id}.'
	}
	return 'rollback to ${pre_id} failed:\n${rb.message}'
}

// theme_set_report implements `appearance theme set <official-id>`:
// validate -> apply -> verify. Apply runs the native theme pipeline
// (scheme, derived files and GTK together); verify reads the live state
// back and refuses a split (scheme/GTK disagree) as a failure.
// Mutating: needs --yes; --dry-run only previews.
pub fn theme_set_report(opts ThemeSetOptions) CommandResult {
	return theme_set_report_with(opts, theme_apply_native)
}

// theme_set_report_with is the test seam: apply_fn replaces the native
// pipeline so verify/rollback stay hermetic (no GTK, no shell).
pub fn theme_set_report_with(opts ThemeSetOptions, apply_fn fn (string, string, bool) CommandResult) CommandResult {
	if !is_official_theme_id(opts.id) {
		return fail_result('appearance theme set', 'unknown official theme: ${opts.id} (want ${official_theme_ids().join('|')}).\nExample: horneroctl appearance theme set ${signal_default_theme_id} --dry-run')
	}
	if !opts.yes && !opts.dry_run {
		return fail_result('appearance theme set', 'refusing to apply without --yes (preview with --dry-run).\nExample: horneroctl appearance theme set ${opts.id} --dry-run')
	}
	pack := show_theme_pack(opts.id) or { return fail_result('appearance theme set', err.msg()) }
	mode := pack.mode
	if opts.dry_run {
		return ok_result('appearance theme set', 'would run: theme apply ${opts.id} (then verify mode=${mode} gtk=${pack.gtk_theme})',
			{
				'command_line': 'theme apply ${opts.id}'
				'dry_run':      'true'
				'id':           opts.id
			})
	}
	pre := query_appearance_status() or { AppearanceStatus{} }
	pre_id := match_official_theme(pre)
	rep := apply_fn(opts.id, '', false)
	if !rep.ok {
		rb := rollback_official_theme(apply_fn, pre_id, opts.id)
		mut msg := 'backend failed:\n${rep.message}'
		if rb.len > 0 {
			msg += '\n${rb}'
		}
		return fail_result('appearance theme set', msg)
	}
	post := query_appearance_status() or {
		rb := rollback_official_theme(apply_fn, pre_id, opts.id)
		mut msg := 'verify failed: could not read back appearance state.\n${err.msg()}'
		if rb.len > 0 {
			msg += '\n${rb}'
		} else {
			msg += '\nRun: horneroctl appearance theme get'
		}
		return fail_result('appearance theme set', msg)
	}
	mut mismatches := []string{}
	if post.theme != opts.id {
		mismatches << 'selected theme is ${post.theme} (want ${opts.id})'
	}
	if mode.len > 0 && post.mode.len > 0 && post.mode != mode {
		mismatches << 'mode is ${post.mode} (want ${mode})'
	}
	if pack.gtk_theme.len > 0 && post.gtk_theme.len > 0 && post.gtk_theme != pack.gtk_theme {
		mismatches << 'gtk is ${post.gtk_theme} (want ${pack.gtk_theme})'
	}
	if mismatches.len > 0 {
		rb := rollback_official_theme(apply_fn, pre_id, opts.id)
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
			'id':        opts.id
			'mode':      post.mode
			'gtk_theme': post.gtk_theme
		})
}
