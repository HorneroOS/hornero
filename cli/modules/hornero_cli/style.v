module hornero_cli

import os
import term

// Signal presentation for human output.
//
// The terminal palette is the user's ANSI palette (SGR 30-37 / 90-97), which
// the Hornero terminal themes map from the Signal roles: yellow = signal,
// blue/cyan = cue, green = phosphor, red = alert. Nothing here emits RGB.
//
// Contract: styling is applied ONLY to human output on an interactive
// terminal (or CLICOLOR_FORCE=1) and never when NO_COLOR is set or TERM is
// dumb. `--json`, `--quiet`, pipes and redirects receive the exact bytes the
// command produced. Status is never colour alone: every state carries a glyph
// and a word (✓ OK / ! WARN / ✗ FAIL, ASCII fallback + / ! x).

// StyleCaps describes what the destination stream can show.
pub struct StyleCaps {
pub:
	color   bool
	unicode bool
	width   int
}

// plain_caps is the identity profile: styling disabled.
pub fn plain_caps() StyleCaps {
	return StyleCaps{
		width: 80
	}
}

fn env_utf8() bool {
	for k in ['LC_ALL', 'LC_CTYPE', 'LANG'] {
		v := os.getenv(k)
		if v.len > 0 {
			lv := v.to_lower()
			return lv.contains('utf-8') || lv.contains('utf8')
		}
	}
	return false
}

fn env_width() int {
	cols := os.getenv('COLUMNS').int()
	if cols > 0 {
		return cols
	}
	w, _ := term.get_terminal_size()
	if w > 0 {
		return w
	}
	return 80
}

// style_plain_env is set by dispatch for --json/--quiet so no output of that
// invocation is styled (internal; not a user knob, use NO_COLOR).
const style_plain_env = 'HORNERO_STYLE_PLAIN'

// caps_for decides the profile for fd (1 = stdout, 2 = stderr).
pub fn caps_for(fd int) StyleCaps {
	if os.getenv('NO_COLOR').len > 0 || os.getenv(style_plain_env).len > 0 || os.getenv('TERM') == 'dumb' {
		return plain_caps()
	}
	forced := os.getenv('CLICOLOR_FORCE').len > 0 && os.getenv('CLICOLOR_FORCE') != '0'
	if !forced && os.is_atty(fd) == 0 {
		return plain_caps()
	}
	return StyleCaps{
		color:   true
		unicode: env_utf8()
		width:   env_width()
	}
}

fn sgr(code string, s string) string {
	return '\x1b[${code}m${s}\x1b[0m'
}

fn s_dim(s string) string {
	return sgr('2', s)
}

fn s_bold(s string) string {
	return sgr('1', s)
}

struct StatusToken {
	word  string
	glyph string
	ascii string
	code  string
}

fn status_token(word string) ?StatusToken {
	return match word {
		'ok', 'OK', 'PASS' { StatusToken{'OK', '✓', '+', '32'} }
		'WARN', 'DRIFT' { StatusToken{'WARN', '!', '!', '33'} }
		'FAIL' { StatusToken{'FAIL', '✗', 'x', '31'} }
		'DONE' { StatusToken{'DONE', '■', '#', '36'} }
		else { none }
	}
}

// eyebrow renders `── TITLE ─────` as a mono-style section label, capped at
// 64 columns so it never wraps on narrow terminals.
fn eyebrow(title string, caps StyleCaps) string {
	rule := if caps.unicode { '─' } else { '-' }
	lead := rule.repeat(2)
	label := title.to_upper()
	total := if caps.width < 64 { caps.width } else { 64 }
	used := 2 + 1 + label.runes().len + 1
	tail := if total > used + 2 { rule.repeat(total - used) } else { rule.repeat(2) }
	return s_dim(lead) + ' ' + s_bold(label) + ' ' + s_dim(tail)
}

fn is_heading(line string) bool {
	if line.len < 2 || line.len > 40 || !line.ends_with(':') || line[0] == ` ` {
		return false
	}
	body := line[..line.len - 1]
	if body.contains(':') || body.contains('/') || body.contains('=') {
		return false
	}
	if !(body[0] >= `A` && body[0] <= `Z`) {
		return false
	}
	for c in body {
		if !(c.is_letter() || c == ` ` || c == `-`) {
			return false
		}
	}
	return true
}

fn style_status(line string, caps StyleCaps) ?string {
	mut word := ''
	for i, c in line {
		if !c.is_letter() {
			break
		}
		word = line[..i + 1]
	}
	tok := status_token(word) or { return none }
	rest := line[word.len..]
	if rest.len == 0 || !(rest[0] == ` ` || rest[0] == `:`) {
		return none
	}
	mut tail := rest.trim_left(': ')
	glyph := if caps.unicode { tok.glyph } else { tok.ascii }
	label := '${glyph} ${tok.word}'
	pad := ' '.repeat(if 6 - label.runes().len > 0 { 6 - label.runes().len } else { 0 })
	head := sgr('1;${tok.code}', label) + pad + ' '
	// `name: message` -> bold name, plain message
	if i := tail.index(': ') {
		if i > 0 && !tail[..i].contains(' ') {
			return head + s_bold(tail[..i]) + s_dim(':') + tail[i + 1..]
		}
	}
	tail = tail.trim_space()
	return head + tail
}

fn style_arrow(line string) ?string {
	parts := line.split(' ')
	if parts.len == 4 && parts[2] == '->' {
		return parts[0] + ' ' + s_dim(parts[1]) + ' ' + s_dim('→') + ' ' + sgr('32', parts[3])
	}
	return none
}

fn style_kv(line string) ?string {
	if line.len == 0 || line[0] == ` ` || !line[0].is_letter() {
		return none
	}
	i := line.index(': ') or { return none }
	if i == 0 || i > 26 {
		return none
	}
	key := line[..i]
	if key.contains('/') || key.contains('(') || key.contains('.') {
		return none
	}
	k := key.trim_right(' ')
	pad := key[k.len..]
	// "key : value" aligned blocks keep their padding
	return s_dim(k) + pad + s_dim(':') + line[i + 1..]
}

// style_human decorates human output. With caps.color == false it returns
// text untouched (byte-identical).
pub fn style_human(text string, caps StyleCaps) string {
	if !caps.color || text.len == 0 {
		return text
	}
	mut out := []string{}
	mut section := ''
	for line in text.split('\n') {
		if line.len == 0 {
			section = ''
			out << line
			continue
		}
		if is_heading(line) {
			section = line[..line.len - 1].to_lower()
			out << eyebrow(line[..line.len - 1], caps)
			continue
		}
		if line.starts_with('Usage: ') {
			out << s_dim('USAGE') + ' ' + line[7..]
			continue
		}
		if s := style_status(line, caps) {
			out << s
			continue
		}
		if section in ['commands', 'global flags', 'options', 'flags'] && line.starts_with('  ')
			&& line.len > 2 && line[2] != ` ` {
			body := line[2..]
			if j := body.index('  ') {
				out << '  ' + s_bold(body[..j]) + body[j..]
				continue
			}
		}
		if section == '' || section == 'exit codes' {
			if s := style_arrow(line) {
				out << s
				continue
			}
			if s := style_kv(line) {
				out << s
				continue
			}
		}
		out << line
	}
	return out.join('\n')
}

// print_human writes text to stdout with Signal styling when the stream
// allows it; otherwise the exact text.
pub fn print_human(text string) {
	print(style_human(text, caps_for(1)))
}

// println_human is print_human plus a newline.
pub fn println_human(text string) {
	println(style_human(text, caps_for(1)))
}

// style_error marks the first line of a diagnostic with a glyph + word
// (never colour alone); follow-up lines (hints, examples) stay as written.
pub fn style_error(text string, caps StyleCaps) string {
	if !caps.color || text.len == 0 {
		return text
	}
	glyph := if caps.unicode { '✗' } else { 'x' }
	lines := text.split('\n')
	mut out := [sgr('1;31', '${glyph} ERROR') + ' ' + lines[0]]
	out << lines[1..]
	return out.join('\n')
}

// eprintln_human writes a diagnostic to stderr, marked when stderr is a
// styled terminal.
pub fn eprintln_human(text string) {
	eprintln(style_error(text, caps_for(2)))
}
