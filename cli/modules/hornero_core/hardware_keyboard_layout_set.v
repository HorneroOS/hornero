module hornero_core

import os

// Keyboard layout list/set (shell#226 remainder): enumerate XKB
// layouts from the system evdev registry and set the session layout
// list + variant through the same hyprctl/setxkbmap backends as the
// toggle. The set is persisted as a state token next to the input
// settings (`hornero/hypr/keyboard-layout/current`); config keeps
// owning factory defaults in input.conf.

pub struct XkbLayout {
pub:
	name        string
	description string
	variants    []string
}

pub struct LayoutSetOptions {
pub:
	layouts string // comma-separated, e.g. "us,latam"
	variant string // kb_variant value, e.g. "intl," (per-layout, comma-aligned)
	dry_run bool
	yes     bool
}

fn xkb_rules_path() string {
	env := os.getenv('HORNERO_XKB_RULES_FILE')
	if env.len > 0 {
		return env
	}
	return '/usr/share/X11/xkb/rules/evdev.xml'
}

fn resolve_keyboard_layout_state_file() string {
	env := os.getenv('HORNERO_KEYBOARD_LAYOUT_STATE_FILE')
	if env.len > 0 {
		return env
	}
	return os.join_path(hypr_state_base(), 'hornero', 'hypr', 'keyboard-layout', 'current')
}

fn xml_tag_text(block string, tag string) string {
	open := '<' + tag + '>'
	idx := block.index(open) or { return '' }
	rest := block[idx + open.len..]
	end := rest.index('</' + tag + '>') or { return '' }
	return rest[..end].trim_space()
}

// parse_xkb_layouts extracts layout name/description/variants from
// evdev.xml with a small scanner (the registry shape is stable and
// the CLI has no XML dependency).
pub fn parse_xkb_layouts(text string) []XkbLayout {
	mut out := []XkbLayout{}
	mut rest := text
	for {
		start := rest.index('<layout>') or { break }
		rest = rest[start + 8..]
		end := rest.index('</layout>') or { break }
		block := rest[..end]
		rest = rest[end + 9..]
		name := xml_tag_text(block, 'name')
		if name.len == 0 {
			continue
		}
		mut variants := []string{}
		mut vrest := block
		for {
			vs := vrest.index('<variant>') or { break }
			vrest = vrest[vs + 9..]
			ve := vrest.index('</variant>') or { break }
			vname := xml_tag_text(vrest[..ve], 'name')
			if vname.len > 0 {
				variants << vname
			}
			vrest = vrest[ve + 10..]
		}
		out << XkbLayout{
			name:        name
			description: xml_tag_text(block, 'description')
			variants:    variants
		}
	}
	return out
}

pub fn keyboard_layout_list_report(dry_run bool) CommandResult {
	path := xkb_rules_path()
	if dry_run {
		return ok_result('hardware keyboard layout', 'would parse: ${path}', {
			'file':    path
			'dry_run': 'true'
		})
	}
	text := os.read_file(path) or {
		return fail_result('hardware keyboard layout', 'XKB registry not found (${path}).')
	}
	entries := parse_xkb_layouts(text)
	mut lines := []string{}
	for e in entries {
		mut line := '${e.name} — ${e.description}'
		if e.variants.len > 0 {
			line += ' [variants: ${e.variants.join(', ')}]'
		}
		lines << line
	}
	return ok_result('hardware keyboard layout', lines.join('\n'), {
		'count': entries.len.str()
		'file':  path
	})
}

fn valid_xkb_token(tok string) bool {
	if tok.len == 0 {
		return false
	}
	for c in tok.bytes() {
		if !(c.is_letter() && c >= `a` && c <= `z`) && !(c >= `0` && c <= `9`)
			&& c !in [`_`, `-`, `+`, `.`] {
			return false
		}
	}
	return true
}

pub fn keyboard_layout_set_report(opts LayoutSetOptions) CommandResult {
	layouts := opts.layouts.split(',').map(it.trim_space())
	if layouts.len == 0 || layouts.any(!valid_xkb_token(it)) {
		return fail_result('hardware keyboard layout', 'Invalid layout list "${opts.layouts}". Use comma-separated XKB names, e.g. us,latam.')
	}
	variant := opts.variant.trim_space()
	if variant.len > 0 {
		vtoks := variant.split(',')
		if vtoks.len > 1 && vtoks.len != layouts.len {
			return fail_result('hardware keyboard layout', 'Variant list must align with the layout list (${layouts.len} entries).')
		}
		for t in vtoks {
			tt := t.trim_space()
			if tt.len > 0 && !valid_xkb_token(tt) {
				return fail_result('hardware keyboard layout', 'Invalid variant "${tt}".')
			}
		}
	}
	joined := layouts.join(',')
	session := detect_session()
	if opts.dry_run {
		return ok_result('hardware keyboard layout', 'Would set kb_layout=${joined} kb_variant=${variant} on ${session}', {
			'dry_run': 'true'
			'layout':  joined
			'variant': variant
			'session': session
		})
	}
	if !opts.yes {
		return fail_result('hardware keyboard layout', 'Setting the keyboard layout changes the live session. Re-run with --yes (or --dry-run to preview).')
	}
	if session == 'hyprland' {
		bin := resolve_hyprctl_bin()
		if bin.len == 0 {
			return fail_result('hardware keyboard layout', 'hyprctl not found on PATH. Set HORNERO_HYPRCTL_BIN.')
		}
		if hypr_lua_config_enabled() {
			expr := keyboard_layout_lua_expression(joined, variant)
			rep := hypr_lua_eval(bin, expr, false) or {
				return fail_result('hardware keyboard layout', err.msg())
			}
			if !rep.ok {
				return fail_result('hardware keyboard layout', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
			}
		} else {
			r1 := run_exec(ExecSpec{
				prog: bin
				args: ['keyword', 'input:kb_layout', joined]
			})
			if !r1.ok {
				return fail_result('hardware keyboard layout', 'backend failed (exit ${r1.exit_code}):\n${r1.output}')
			}
			r2 := run_exec(ExecSpec{
				prog: bin
				args: ['keyword', 'input:kb_variant', variant]
			})
			if !r2.ok {
				return fail_result('hardware keyboard layout', 'backend failed (exit ${r2.exit_code}):\n${r2.output}')
			}
		}
	} else {
		bin := resolve_setxkbmap_bin()
		if bin.len == 0 {
			return fail_result('hardware keyboard layout', 'setxkbmap not found on PATH. Set HORNERO_SETXKBMAP_BIN.')
		}
		mut args := ['-layout', joined]
		if variant.len > 0 {
			args << ['-variant', variant]
		}
		rep := run_exec(ExecSpec{
			prog: bin
			args: args
		})
		if !rep.ok {
			return fail_result('hardware keyboard layout', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
		}
	}
	write_state_token(resolve_keyboard_layout_state_file(), 'layout=${joined} variant=${variant}') or {
		return fail_result('hardware keyboard layout', 'Layout applied live but could not persist: ${err.msg()}')
	}
	return ok_result('hardware keyboard layout', 'Keyboard layout set to ${joined}${if variant.len > 0 {
		' (${variant})'
	} else {
		''
	}}', {
		'layout':  joined
		'variant': variant
		'session': session
	})
}
