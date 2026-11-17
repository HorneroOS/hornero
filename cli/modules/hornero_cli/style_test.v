module hornero_cli

import os

const color_caps = StyleCaps{
	color:   true
	unicode: true
	width:   80
}
const narrow_caps = StyleCaps{
	color:   true
	unicode: true
	width:   40
}
const ascii_caps = StyleCaps{
	color: true
	width: 80
}

fn strip_ansi(s string) string {
	mut out := []u8{}
	mut i := 0
	for i < s.len {
		if s[i] == 0x1b && i + 1 < s.len && s[i + 1] == `[` {
			i += 2
			for i < s.len && s[i] != `m` {
				i++
			}
			i++
			continue
		}
		out << s[i]
		i++
	}
	return out.bytestr()
}

const sample = 'Usage: horneroctl doctor [--json]

ok  wayland-session: WAYLAND_DISPLAY is set
WARN fonts: partial
FAIL  shell-config: missing
doctor: 3/9 checks failed
Repository updates:
attica 6.31.0-1 -> 6.32.0-1
theme          : hornero-signal-night
Commands:
  version       Print version
'

fn test_plain_caps_are_byte_identical() {
	assert style_human(sample, plain_caps()) == sample
	assert style_human('', color_caps) == ''
}

fn test_json_like_text_is_never_changed_without_color() {
	j := '{"ok":true,"message":"ok  x: y"}'
	assert style_human(j, plain_caps()) == j
}

fn test_status_words_carry_glyph_and_word() {
	out := strip_ansi(style_human(sample, color_caps))
	assert out.contains('✓ OK')
	assert out.contains('! WARN')
	assert out.contains('✗ FAIL')
	assert out.contains('── REPOSITORY UPDATES')
	assert out.contains('USAGE horneroctl doctor [--json]')
}

fn test_ascii_fallback_has_no_unicode() {
	out := strip_ansi(style_human(sample, ascii_caps))
	assert out.contains('+ OK')
	assert out.contains('x FAIL')
	assert !out.contains('✓')
	assert !out.contains('─')
}

fn test_text_survives_stripping_modulo_decoration() {
	out := strip_ansi(style_human('FAIL  a-check: broken thing\n', color_caps))
	assert out.contains('a-check: broken thing')
}

fn test_eyebrow_never_exceeds_width() {
	for line in style_human('Package status:\n', narrow_caps).split('\n') {
		assert strip_ansi(line).runes().len <= 40
	}
}

fn test_arrow_rows_keep_versions() {
	out := strip_ansi(style_human('attica 6.31.0-1 -> 6.32.0-1', color_caps))
	assert out.contains('attica 6.31.0-1 → 6.32.0-1')
}

fn test_caps_respect_no_color_and_pipes() {
	os.setenv('NO_COLOR', '1', true)
	os.setenv('CLICOLOR_FORCE', '1', true)
	assert !caps_for(1).color
	os.unsetenv('NO_COLOR')
	assert caps_for(1).color
	os.unsetenv('CLICOLOR_FORCE')
	// the test runner's stdout is not a terminal in CI; either way no panic
	_ := caps_for(1)
}

fn test_error_marker_has_glyph_and_word_and_plain_is_identity() {
	msg := 'missing subcommand.\nExample: horneroctl appearance status'
	assert style_error(msg, plain_caps()) == msg
	out := strip_ansi(style_error(msg, StyleCaps{
		color:   true
		unicode: true
		width:   80
	}))
	assert out.starts_with('✗ ERROR missing subcommand.')
	assert out.ends_with('Example: horneroctl appearance status')
}
