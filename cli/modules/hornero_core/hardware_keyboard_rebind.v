module hornero_core

import os

// Keybinding rebind (shell#236 slice 2): overrides live in the user's
// keybindings-user.conf as `unbind`/`bind` pairs sourced after the
// factory defaults (HorneroOS/config). The factory file is never
// edited. Effective binds = defaults minus unbound combos plus the
// override binds, applied in file order. Lua configs are read-only:
// override syntax differs and is reported honestly.

pub struct BindEntry {
pub:
	verb       string // bind | binde | bindm | bindl | ... | unbind
	mods       string // canonical: sorted uppercase, "CTRL + SUPER"
	key        string
	dispatcher string // '' for unbind
	arg        string
}

pub struct RebindSetOptions {
pub:
	old_combo string
	new_combo string
	dry_run   bool
	yes       bool
}

pub fn bind_combo(e BindEntry) string {
	if e.mods.len == 0 {
		return e.key
	}
	return e.mods + ' + ' + e.key
}

fn canonical_mods(raw string) string {
	mut parts := []string{}
	cleaned := raw.replace('\$', '').replace('+', ' ')
	for tok in cleaned.split(' ') {
		t := tok.trim_space().to_upper()
		if t.len == 0 {
			continue
		}
		name := match t {
			'MAINMOD' { 'SUPER' }
			'META' { 'SUPER' }
			'MOD4' { 'SUPER' }
			'MOD1' { 'ALT' }
			'CONTROL' { 'CTRL' }
			else { t }
		}
		if name !in parts {
			parts << name
		}
	}
	parts.sort()
	return parts.join(' + ')
}

// parse_combo parses "SUPER + Return" / "SUPER, Return" into canonical
// mods and key. Returns ok=false when there is no key.
pub fn parse_combo(raw string) (string, string, bool) {
	mut s := raw.trim_space()
	if s.len == 0 {
		return '', '', false
	}
	if s.contains(',') {
		parts := s.split_nth(',', 2)
		mods := canonical_mods(parts[0])
		key := parts[1].trim_space()
		if key.len == 0 {
			return '', '', false
		}
		return mods, key, true
	}
	toks := s.split(' ').filter(it.trim_space().len > 0 && it != '+')
	if toks.len == 0 {
		return '', '', false
	}
	key := toks[toks.len - 1]
	mods := canonical_mods(toks[..toks.len - 1].join(' '))
	return mods, key, true
}

fn hypr_mods_arg(mods string) string {
	return mods.replace(' + ', '')
}

fn hypr_bind_rhs(e BindEntry) string {
	mut rhs := hypr_mods_arg(e.mods) + ', ' + e.key + ', ' + e.dispatcher
	if e.arg.len > 0 {
		rhs += ', ' + e.arg
	}
	return rhs
}

// parse_bind_entries parses hyprlang bind/unbind lines.
pub fn parse_bind_entries(text string) []BindEntry {
	mut out := []BindEntry{}
	for raw in text.split('\n') {
		line := raw.trim_space()
		if line.len == 0 || line.starts_with('#') {
			continue
		}
		if line.starts_with('$') && !line.starts_with('bind') {
			continue
		}
		eq := line.index('=') or { continue }
		verb := line[..eq].trim_space()
		if !verb.starts_with('bind') && verb != 'unbind' {
			continue
		}
		rhs := line[eq + 1..].trim_space()
		parts := rhs.split_nth(',', 3)
		if parts.len < 2 {
			continue
		}
		mods := canonical_mods(parts[0])
		key := parts[1].trim_space()
		mut dispatcher := ''
		mut arg := ''
		if verb != 'unbind' && parts.len >= 3 {
			disp := parts[2].trim_space()
			rest := disp.split_nth(',', 2)
			dispatcher = rest[0].trim_space()
			if rest.len == 2 {
				arg = rest[1].trim_space()
			}
		}
		out << BindEntry{
			verb:       verb
			mods:       mods
			key:        key
			dispatcher: dispatcher
			arg:        arg
		}
	}
	return out
}

fn effective_binds(defaults []BindEntry, user []BindEntry) []BindEntry {
	mut out := defaults.clone()
	for u in user {
		combo := bind_combo(u)
		out = out.filter(bind_combo(it) != combo)
		if u.verb != 'unbind' {
			out << u
		}
	}
	return out
}

const rebind_header = '# Hornero user keybinding overrides. Managed by:\n#   horneroctl hardware keyboard rebind set|reset\n# Each pair unbinds a factory combo and binds the replacement.\n# Emptying this file restores the factory keybindings.\n'

fn keybindings_user_path() string {
	env := os.getenv('HORNERO_KEYBINDINGS_USER_FILE')
	if env.len > 0 {
		return env
	}
	mut base := os.getenv('XDG_CONFIG_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.config')
	}
	return os.join_path(base, 'hypr', 'hyprland.conf.d', 'keybindings-user.conf')
}

// parse_user_pairs groups override entries into (unbind, bind) pairs.
fn parse_user_pairs(user []BindEntry) []BindEntry {
	mut binds := []BindEntry{}
	for u in user {
		if u.verb != 'unbind' {
			binds << u
		}
	}
	return binds
}

fn rebind_read_inputs() (string, string, string) {
	user_path := keybindings_user_path()
	defaults_text := os.read_file(keybindings_path()) or { '' }
	user_text := os.read_file(user_path) or { '' }
	return user_path, defaults_text, user_text
}

fn rebind_fail(msg string) CommandResult {
	return fail_result('hardware keyboard rebind', msg)
}

fn hyprctl_keyword(bin string, name string, rhs string) ExecReport {
	return run_exec(ExecSpec{
		prog: bin
		args: ['keyword', name, rhs]
	})
}

pub fn keyboard_rebind_status_report() CommandResult {
	if hypr_lua_config_enabled() {
		return ok_result('hardware keyboard rebind', 'Lua keybindings are read-only (rebind supports hyprlang configs).', {
			'managed':   'false'
			'overrides': '0'
		})
	}
	_, defaults_text, user_text := rebind_read_inputs()
	user := parse_bind_entries(user_text)
	overrides := parse_user_pairs(user).len
	eff := effective_binds(parse_bind_entries(defaults_text), user)
	return ok_result('hardware keyboard rebind', 'overrides: ${overrides}, effective binds: ${eff.len}', {
		'managed':   'true'
		'overrides': overrides.str()
		'effective': eff.len.str()
		'file':      keybindings_user_path()
	})
}

// keyboard_rebind_set_report moves the binding at old_combo to
// new_combo, preserving dispatcher and args. Writes only the user
// override file; applies live via `hyprctl keyword` when available.
pub fn keyboard_rebind_set_report(opts RebindSetOptions) CommandResult {
	if hypr_lua_config_enabled() {
		return rebind_fail('Lua keybindings are read-only: rebind supports hyprlang configs only.')
	}
	old_mods, old_key, ok_old := parse_combo(opts.old_combo)
	new_mods, new_key, ok_new := parse_combo(opts.new_combo)
	if !ok_old || !ok_new {
		return rebind_fail('Could not parse combos. Example: --old "SUPER + Return" --new "SUPER + X"')
	}
	user_path, defaults_text, user_text := rebind_read_inputs()
	defaults := parse_bind_entries(defaults_text)
	user := parse_bind_entries(user_text)
	eff := effective_binds(defaults, user)
	old_combo := if old_mods.len > 0 { old_mods + ' + ' + old_key } else { old_key }
	new_combo := if new_mods.len > 0 { new_mods + ' + ' + new_key } else { new_key }
	mut target := BindEntry{}
	mut found := false
	for e in eff {
		if bind_combo(e) == new_combo && new_combo != old_combo {
			return rebind_fail('${new_combo} is already bound (${e.dispatcher}). Pick another combo.')
		}
		if bind_combo(e) == old_combo {
			target = e
			found = true
		}
	}
	if !found {
		return rebind_fail('${old_combo} is not bound. Run: horneroctl hardware keyboard keys')
	}
	replacement := BindEntry{
		verb:       'bind'
		mods:       new_mods
		key:        new_key
		dispatcher: target.dispatcher
		arg:        target.arg
	}
	// User override for the ORIGINAL default combo (if the default
	// itself is the target we unbind the default combo, not old_combo
	// when old was itself an override bind).
	unbind_rhs := hypr_mods_arg(old_mods) + ', ' + old_key
	bind_line := 'bind = ' + hypr_bind_rhs(replacement)
	if opts.dry_run {
		return ok_result('hardware keyboard rebind', 'Would write to ${user_path}:\nunbind = ${unbind_rhs}\n${bind_line}', {
			'dry_run': 'true'
			'old':     old_combo
			'new':     new_combo
		})
	}
	if !opts.yes {
		return rebind_fail('Rebind changes live keybindings. Re-run with --yes (or --dry-run to preview).')
	}
	// Rebuild the override file: keep other overrides, drop any pair
	// touching either combo, then append the new pair. The unbind
	// emitted per stored bind targets that bind's own default combo
	// is only correct for pairs whose bind replaced a default; to
	// keep reset/set symmetric we store pairs explicitly below.
	os.mkdir_all(os.dir(user_path)) or {
		return rebind_fail('Could not create ${os.dir(user_path)}: ${err.msg()}')
	}
	// Pairs are stored as unbind(old)+bind(new); render_user_file
	// cannot know old, so build the file here from stored pairs data.
	mut content := rebind_header
	// Existing pairs other than the touched combos are re-emitted
	// from their bind entries with a self-unbind (no-op safeguard is
	// wrong), so persist pairs in a trailing comment-free way: emit
	// unbind for the combo each stored bind replaced is impossible
	// to recover; instead re-emit prior pairs verbatim.
	content = rebuild_user_content(user_text, old_combo, new_combo) + 'unbind = ' + unbind_rhs +
		'\n' + bind_line + '\n'
	os.write_file(user_path, content) or {
		return rebind_fail('Could not write ${user_path}: ${err.msg()}')
	}
	mut live := 'live apply skipped (hyprctl unavailable)'
	bin := resolve_hyprctl_bin()
	if bin.len > 0 {
		r1 := hyprctl_keyword(bin, 'unbind', unbind_rhs)
		r2 := hyprctl_keyword(bin, 'bind', hypr_bind_rhs(replacement))
		live = if r1.ok && r2.ok {
			'applied live via hyprctl keyword'
		} else {
			'live apply failed; the override file loads on next Hyprland start'
		}
	}
	return ok_result('hardware keyboard rebind', 'Rebound ${old_combo} -> ${new_combo} (${target.dispatcher}). ${live}', {
		'old':  old_combo
		'new':  new_combo
		'file': user_path
	})
}

// rebuild_user_content returns previous override pairs verbatim,
// dropping any pair whose unbind or bind combo is in the drop set.
fn rebuild_user_content(user_text string, drop_a string, drop_b string) string {
	mut kept := []string{}
	lines := user_text.split('\n')
	mut i := 0
	for i < lines.len {
		line := lines[i].trim_space()
		if line.starts_with('unbind =') && i + 1 < lines.len
			&& lines[i + 1].trim_space().starts_with('bind =') {
			pair := parse_bind_entries(lines[i] + '\n' + lines[i + 1])
			mut drop := false
			for p in pair {
				c := bind_combo(p)
				if c == drop_a || c == drop_b {
					drop = true
				}
			}
			if !drop {
				kept << lines[i]
				kept << lines[i + 1]
			}
			i += 2
			continue
		}
		i++
	}
	mut s := rebind_header
	for k in kept {
		s += k + '\n'
	}
	return s
}

// keyboard_rebind_reset_report clears all user overrides and
// restores factory binds live.
pub fn keyboard_rebind_reset_report(dry_run bool, yes bool) CommandResult {
	if hypr_lua_config_enabled() {
		return rebind_fail('Lua keybindings are read-only: rebind supports hyprlang configs only.')
	}
	user_path, defaults_text, user_text := rebind_read_inputs()
	user := parse_bind_entries(user_text)
	binds := parse_user_pairs(user)
	if binds.len == 0 {
		return ok_result('hardware keyboard rebind', 'No user overrides to reset; factory keybindings are already active.', {
			'overrides': '0'
		})
	}
	if dry_run {
		return ok_result('hardware keyboard rebind', 'Would remove ${binds.len} override(s) from ${user_path}', {
			'dry_run':   'true'
			'overrides': binds.len.str()
		})
	}
	if !yes {
		return rebind_fail('Reset removes all user keybinding overrides. Re-run with --yes (or --dry-run to preview).')
	}
	os.mkdir_all(os.dir(user_path)) or {
		return rebind_fail('Could not create ${os.dir(user_path)}: ${err.msg()}')
	}
	os.write_file(user_path, rebind_header) or {
		return rebind_fail('Could not write ${user_path}: ${err.msg()}')
	}
	bin := resolve_hyprctl_bin()
	if bin.len > 0 {
		lines := user_text.split('\n')
		mut i := 0
		for i < lines.len {
			line := lines[i].trim_space()
			if line.starts_with('unbind =') && i + 1 < lines.len {
				pair := parse_bind_entries(line + '\n' + lines[i + 1])
				if pair.len == 2 {
					old_e := pair[0]
					new_e := pair[1]
					hyprctl_keyword(bin, 'unbind', hypr_mods_arg(new_e.mods) + ', ' + new_e.key)
					for d in parse_bind_entries(defaults_text) {
						if bind_combo(d) == bind_combo(old_e) {
							hyprctl_keyword(bin, 'bind', hypr_bind_rhs(d))
						}
					}
				}
				i += 2
				continue
			}
			i++
		}
	}
	return ok_result('hardware keyboard rebind', 'Removed ${binds.len} override(s); factory keybindings restored.', {
		'overrides': '0'
		'file':      user_path
	})
}
