module hornero_core

import os

// User window rules (shell#235): horneroctl-managed overlay in
// window-rules-user.conf (Hyprland block syntax, sourced after the
// factory rules by HorneroOS/config). Rules take effect on Hyprland
// config reload or restart; the CLI says so instead of pretending a
// live apply. Lua configs are read-only here. Factory rules are
// never read for writing nor edited.

pub struct WindowRule {
pub mut:
	name       string
	match_kind string // class | title
	pattern    string
	effect     string // float | pin
}

pub struct WindowsRulesAddOptions {
pub:
	match_kind string
	pattern    string
	effect     string
	dry_run    bool
	yes        bool
}

const window_rules_header = '# User window rules — managed by horneroctl hypr windows rules.\n# Hyprland block syntax; takes effect on config reload or restart.\n# Emptying this file removes all user rules.\n'

pub fn resolve_window_rules_user_file() string {
	env := os.getenv('HORNERO_WINDOW_RULES_USER_FILE')
	if env.len > 0 {
		return env
	}
	mut base := os.getenv('XDG_CONFIG_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.config')
	}
	return os.join_path(base, 'hypr', 'hyprland.conf.d', 'window-rules-user.conf')
}

// parse_window_rules extracts horneroctl-managed blocks. It reads
// `name`, `match:class|match:title` and the `float|pin = true` line.
pub fn parse_window_rules(text string) []WindowRule {
	mut out := []WindowRule{}
	mut rest := text
	for {
		start := rest.index('windowrule {') or { break }
		rest = rest[start + 12..]
		end := rest.index('\n}') or { break }
		block := rest[..end]
		rest = rest[end + 2..]
		mut rule := WindowRule{}
		for raw in block.split('\n') {
			line := raw.trim_space()
			if line.starts_with('name = ') {
				rule.name = line[7..].trim_space()
			} else if line.starts_with('match:class = ') {
				rule.match_kind = 'class'
				rule.pattern = line[14..].trim_space()
			} else if line.starts_with('match:title = ') {
				rule.match_kind = 'title'
				rule.pattern = line[14..].trim_space()
			} else if line.starts_with('float = ') {
				rule.effect = 'float'
			} else if line.starts_with('pin = ') {
				rule.effect = 'pin'
			}
		}
		if rule.name.len > 0 && rule.pattern.len > 0 && rule.effect.len > 0 {
			out << rule
		}
	}
	return out
}

pub fn render_window_rules(rules []WindowRule) string {
	mut s := window_rules_header
	for r in rules {
		s += '\nwindowrule {\n    name = ${r.name}\n    match:${r.match_kind} = ${r.pattern}\n\n    ${r.effect} = true\n}\n'
	}
	return s
}

fn rule_slug(pattern string) string {
	mut slug := ''
	for c in pattern.bytes() {
		if (c >= `a` && c <= `z`) || (c >= `0` && c <= `9`) {
			slug += c.ascii_str()
		} else if c >= `A` && c <= `Z` {
			slug += (c + 32).ascii_str()
		} else if slug.len > 0 && !slug.ends_with('-') {
			slug += '-'
		}
	}
	slug = slug.trim('-')
	if slug.len > 24 {
		slug = slug[..24].trim('-')
	}
	if slug.len == 0 {
		slug = 'rule'
	}
	return slug
}

fn read_user_rules() []WindowRule {
	text := os.read_file(resolve_window_rules_user_file()) or { return []WindowRule{} }
	return parse_window_rules(text)
}

fn write_user_rules(rules []WindowRule) ! {
	path := resolve_window_rules_user_file()
	os.mkdir_all(os.dir(path)) or { return error('cannot create ${os.dir(path)}: ${err.msg()}') }
	os.write_file(path, render_window_rules(rules)) or {
		return error('cannot write ${path}: ${err.msg()}')
	}
}

pub fn windows_rules_list_report() CommandResult {
	rules := read_user_rules()
	mut lines := []string{}
	for r in rules {
		lines << '${r.name}: match:${r.match_kind} = ${r.pattern} -> ${r.effect}'
	}
	if lines.len == 0 {
		lines << 'No user window rules.'
	}
	return ok_result('hypr windows rules', lines.join('\n'), {
		'count': rules.len.str()
		'file':  resolve_window_rules_user_file()
	})
}

fn valid_rule_pattern(pattern string) bool {
	if pattern.len == 0 || pattern.len > 120 {
		return false
	}
	for c in pattern.bytes() {
		if c in [`{`, `}`, `\n`] {
			return false
		}
	}
	return true
}

const rules_apply_note = 'Takes effect on Hyprland config reload (Super+Shift+R) or restart; already-open windows are unaffected.'

pub fn windows_rules_add_report(opts WindowsRulesAddOptions) CommandResult {
	if hypr_lua_config_enabled() {
		return fail_result('hypr windows rules', 'User window rules are hyprlang-only; Lua configs stay read-only here.')
	}
	if opts.match_kind !in ['class', 'title'] {
		return fail_result('hypr windows rules', 'Match kind must be class or title.')
	}
	if opts.effect !in ['float', 'pin'] {
		return fail_result('hypr windows rules', 'Effect must be float or pin.')
	}
	if !valid_rule_pattern(opts.pattern) {
		return fail_result('hypr windows rules', 'Pattern must be 1-120 chars without braces or newlines.')
	}
	mut rules := read_user_rules()
	for r in rules {
		if r.match_kind == opts.match_kind && r.pattern == opts.pattern {
			return fail_result('hypr windows rules', 'A user rule for ${opts.match_kind} "${opts.pattern}" already exists (${r.name}). Remove it first.')
		}
	}
	base := 'hornero-user-' + rule_slug(opts.pattern)
	mut name := base
	mut n := 2
	for rules.any(it.name == name) {
		name = '${base}-${n}'
		n++
	}
	rule := WindowRule{
		name:       name
		match_kind: opts.match_kind
		pattern:    opts.pattern
		effect:     opts.effect
	}
	if opts.dry_run {
		return ok_result('hypr windows rules', 'Would add rule ${name}: match:${rule.match_kind} = ${rule.pattern} -> ${rule.effect}', {
			'dry_run': 'true'
			'name':    name
		})
	}
	if !opts.yes {
		return fail_result('hypr windows rules', 'Adding a window rule writes your user rules file. Re-run with --yes (or --dry-run to preview).')
	}
	rules << rule
	write_user_rules(rules) or { return fail_result('hypr windows rules', err.msg()) }
	return ok_result('hypr windows rules', 'Added rule ${name} (${rule.effect} on ${rule.match_kind} "${rule.pattern}"). ${rules_apply_note}', {
		'name':  name
		'count': rules.len.str()
		'file':  resolve_window_rules_user_file()
	})
}

pub fn windows_rules_remove_report(name string, dry_run bool, yes bool) CommandResult {
	if hypr_lua_config_enabled() {
		return fail_result('hypr windows rules', 'User window rules are hyprlang-only; Lua configs stay read-only here.')
	}
	rules := read_user_rules()
	kept := rules.filter(it.name != name)
	if kept.len == rules.len {
		return fail_result('hypr windows rules', 'No user rule named ${name}. Run: horneroctl hypr windows rules list')
	}
	if dry_run {
		return ok_result('hypr windows rules', 'Would remove rule ${name}', {
			'dry_run': 'true'
			'name':    name
		})
	}
	if !yes {
		return fail_result('hypr windows rules', 'Removing a window rule rewrites your user rules file. Re-run with --yes (or --dry-run to preview).')
	}
	write_user_rules(kept) or { return fail_result('hypr windows rules', err.msg()) }
	return ok_result('hypr windows rules', 'Removed rule ${name}. ${rules_apply_note}', {
		'name':  name
		'count': kept.len.str()
		'file':  resolve_window_rules_user_file()
	})
}
