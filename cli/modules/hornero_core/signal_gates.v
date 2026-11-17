module hornero_core

import math

// Contrast gates for Hornero Signal and Hornero Chromatic schemes.
//
// The thresholds below mirror HorneroOS/config
// profiles/themes/contrast-gates.json (the single gate table, RFC 0002 §11).
// signal_gates_test.v compares these constants with the vendored copy in
// testdata/contrast-gates.json, so a drift between config, the shell
// engine and horneroctl fails CI instead of shipping. Level semantics and
// the colour maths are identical to lib/hornero/signal_theme.py.

pub const gate_levels = ['standard', 'boosted', 'maximum']

// gate_surfaces is every surface role, darkest first.
pub const gate_surfaces = ['ground', 'sunken', 'base', 'panel', 'raised', 'lifted']

const gate_text_roles = ['ink', 'inkMuted', 'signal', 'cue', 'phosphor', 'alert']
const gate_text_surfaces = ['sunken', 'base', 'panel', 'raised']
const gate_boundary_surfaces = ['base', 'panel', 'lifted']

const gate_on_pairs = [['onSignal', 'signal'], ['onSignalWell', 'signalWell'], ['onCue', 'cue'],
	['onCueWell', 'cueWell'], ['onPhosphor', 'phosphor'], ['onPhosphorWell', 'phosphorWell'],
	['onAlert', 'alert'], ['onAlertWell', 'alertWell'], ['onInverse', 'inverse'],
	['inverseSignal', 'inverse']]

// gate_separation_pairs are the status/accent pairs that must stay
// distinguishable in a Chromatic scheme.
const gate_separation_pairs = [['signal', 'alert'], ['cue', 'phosphor'], ['signal', 'cue']]

// GateTerminal holds the terminal-palette thresholds.
pub struct GateTerminal {
pub:
	normal_min  f64
	bright_min  f64
	rgy_min_de  f64
	ramp_min_de f64
}

pub const gate_terminal = GateTerminal{
	normal_min:  4.5
	bright_min:  3.0
	rgy_min_de:  10.0
	ramp_min_de: 6.0
}

// GateLevel is one resolved level (inheritance already applied).
pub struct GateLevel {
pub:
	name           string
	text_min       f64
	ink_min        f64
	ink_muted_min  f64
	on_pairs_min   f64
	boundary_min   f64
	focus_min      f64
	focus_surfaces []string
}

// gate_level resolves a level name, or none for an unknown name.
pub fn gate_level(name string) ?GateLevel {
	return match name {
		'standard' {
			GateLevel{
				name:           'standard'
				text_min:       4.5
				ink_min:        4.5
				ink_muted_min:  4.5
				on_pairs_min:   4.5
				boundary_min:   3.0
				focus_min:      3.0
				focus_surfaces: ['base']
			}
		}
		'boosted' {
			GateLevel{
				name:           'boosted'
				text_min:       4.5
				ink_min:        7.0
				ink_muted_min:  5.5
				on_pairs_min:   4.5
				boundary_min:   4.5
				focus_min:      4.5
				focus_surfaces: gate_surfaces
			}
		}
		'maximum' {
			GateLevel{
				name:           'maximum'
				text_min:       7.0
				ink_min:        7.0
				ink_muted_min:  7.0
				on_pairs_min:   7.0
				boundary_min:   4.5
				focus_min:      4.5
				focus_surfaces: gate_surfaces
			}
		}
		else {
			return none
		}
	}
}

// gate_focus_every_surface_min is the Chromatic-only focus floor on every
// surface; the separation floors are the OKLab distance and OKLCH hue
// distance a pair needs (both).
pub const gate_focus_every_surface_min = 3.0
pub const gate_separation_min_de_ok = 0.10
pub const gate_separation_min_hue = 25.0

// GateRow is one measured gate: label, measured value, minimum, pass.
pub struct GateRow {
pub:
	label string
	ratio f64
	min   f64
	pass  bool
}

fn gate_row(label string, ratio f64, min f64) GateRow {
	return GateRow{
		label: label
		ratio: ratio
		min:   min
		pass:  ratio >= min
	}
}

// --- colour maths (identical to signal_theme.py) ---------------------------------

fn hex_channels(hex string) (int, int, int) {
	r, g, b := parse_hex6(hex.trim_left('#')) or { return 0, 0, 0 }
	return r, g, b
}

fn srgb_linear(channel int) f64 {
	c := f64(channel) / 255.0
	return if c <= 0.04045 { c / 12.92 } else { math.pow((c + 0.055) / 1.055, 2.4) }
}

pub fn gate_luminance(hex string) f64 {
	r, g, b := hex_channels(hex)
	return 0.2126 * srgb_linear(r) + 0.7152 * srgb_linear(g) + 0.0722 * srgb_linear(b)
}

pub fn gate_contrast(a string, b string) f64 {
	la := gate_luminance(a)
	lb := gate_luminance(b)
	lo := if la < lb { la } else { lb }
	hi := if la < lb { lb } else { la }
	return (hi + 0.05) / (lo + 0.05)
}

fn lab_f(t f64) f64 {
	return if t > 0.008856 { math.cbrt(t) } else { 7.787 * t + 16.0 / 116.0 }
}

fn to_cielab(hex string) (f64, f64, f64) {
	ri, gi, bi := hex_channels(hex)
	r := srgb_linear(ri)
	g := srgb_linear(gi)
	b := srgb_linear(bi)
	x := (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047
	y := r * 0.2126 + g * 0.7152 + b * 0.0722
	z := (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883
	fx := lab_f(x)
	fy := lab_f(y)
	fz := lab_f(z)
	return 116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz)
}

// gate_delta_e76 is CIE76 distance, as used for the terminal gates.
pub fn gate_delta_e76(a string, b string) f64 {
	l1, a1, b1 := to_cielab(a)
	l2, a2, b2 := to_cielab(b)
	return math.sqrt((l1 - l2) * (l1 - l2) + (a1 - a2) * (a1 - a2) + (b1 - b2) * (b1 - b2))
}

fn to_oklab(hex string) (f64, f64, f64) {
	ri, gi, bi := hex_channels(hex)
	r := srgb_linear(ri)
	g := srgb_linear(gi)
	b := srgb_linear(bi)
	l := math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
	m := math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
	s := math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
	return 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s, 1.9779984951 * l - 2.4285922050 * m +
		0.4505937099 * s, 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
}

pub fn gate_delta_e_ok(a string, b string) f64 {
	l1, a1, b1 := to_oklab(a)
	l2, a2, b2 := to_oklab(b)
	return math.sqrt((l1 - l2) * (l1 - l2) + (a1 - a2) * (a1 - a2) + (b1 - b2) * (b1 - b2))
}

fn hue_ok(hex string) f64 {
	_, a, b := to_oklab(hex)
	mut h := math.degrees(math.atan2(b, a))
	if h < 0 {
		h += 360.0
	}
	return h
}

// gate_hue_distance is the shortest OKLCH hue arc between two colours.
pub fn gate_hue_distance(a string, b string) f64 {
	d := math.abs(hue_ok(a) - hue_ok(b))
	return if d > 180.0 { 360.0 - d } else { d }
}

// --- reports ---------------------------------------------------------------------

// signal_contrast_report measures every gated pair of one level.
pub fn signal_contrast_report(t SignalTheme, level GateLevel) []GateRow {
	mut rows := []GateRow{}
	for role in gate_text_roles {
		min := match role {
			'ink' { level.ink_min }
			'inkMuted' { level.ink_muted_min }
			else { level.text_min }
		}
		for surface in gate_text_surfaces {
			rows << gate_row('${role} on ${surface}', gate_contrast(t.role(role), t.role(surface)),
				min)
		}
	}
	for pair in gate_on_pairs {
		rows << gate_row('${pair[0]} on ${pair[1]}', gate_contrast(t.role(pair[0]), t.role(pair[1])),
			level.on_pairs_min)
	}
	for surface in gate_boundary_surfaces {
		rows << gate_row('ruleStrong on ${surface}', gate_contrast(t.role('ruleStrong'),
			t.role(surface)), level.boundary_min)
	}
	for surface in level.focus_surfaces {
		rows << gate_row('focus on ${surface}', gate_contrast(t.role('focus'), t.role(surface)),
			level.focus_min)
	}
	return rows
}

// signal_chromatic_report adds the Chromatic-only rows: focus on every
// surface and status/accent separation (OKLab distance and hue arc).
pub fn signal_chromatic_report(t SignalTheme) []GateRow {
	mut rows := []GateRow{}
	for surface in gate_surfaces {
		rows << gate_row('focus on ${surface} (chromatic)', gate_contrast(t.role('focus'),
			t.role(surface)), gate_focus_every_surface_min)
	}
	for pair in gate_separation_pairs {
		a := t.role(pair[0])
		b := t.role(pair[1])
		rows << gate_row('${pair[0]}/${pair[1]} deltaE-OK', gate_delta_e_ok(a, b),
			gate_separation_min_de_ok)
		rows << gate_row('${pair[0]}/${pair[1]} hue degrees', gate_hue_distance(a, b),
			gate_separation_min_hue)
	}
	return rows
}

// signal_terminal_report measures the terminal palette gates.
pub fn signal_terminal_report(t SignalTheme) []GateRow {
	g := gate_terminal
	bg := t.role('base')
	mut rows := []GateRow{}
	rows << gate_row('terminal foreground (ink) on base', gate_contrast(t.role('ink'), bg),
		g.normal_min)
	for i in 1 .. 7 {
		rows << gate_row('terminal[${i}] on base', gate_contrast(t.terminal[i], bg), g.normal_min)
	}
	for i in 9 .. 15 {
		rows << gate_row('terminal[${i}] on base', gate_contrast(t.terminal[i], bg), g.bright_min)
	}
	for start in [1, 9] {
		r := t.terminal[start]
		gr := t.terminal[start + 1]
		y := t.terminal[start + 2]
		rows << gate_row('terminal red/green (from ${start}) dE76', gate_delta_e76(r, gr),
			g.rgy_min_de)
		rows << gate_row('terminal red/yellow (from ${start}) dE76', gate_delta_e76(r, y),
			g.rgy_min_de)
		rows << gate_row('terminal green/yellow (from ${start}) dE76', gate_delta_e76(gr, y),
			g.rgy_min_de)
	}
	for i in 1 .. 7 {
		rows << gate_row('terminal[${i}] vs [${i + 8}] dE76', gate_delta_e76(t.terminal[i],
			t.terminal[i + 8]), g.ramp_min_de)
	}
	return rows
}

// validate_signal_gates measures everything a scheme must satisfy at
// `level`; `chromatic` adds the Chromatic-only rows. An unknown level is an
// error, never a silent fallback to standard.
pub fn validate_signal_gates(t SignalTheme, level_name string, chromatic bool) ![]GateRow {
	level := gate_level(level_name) or {
		return error('unknown gate level "${level_name}" (want ${gate_levels.join('|')})')
	}
	mut rows := signal_contrast_report(t, level)
	if chromatic {
		rows << signal_chromatic_report(t)
	}
	rows << signal_terminal_report(t)
	return rows
}

// gate_failures lists the failing rows as human-readable lines.
pub fn gate_failures(rows []GateRow) []string {
	mut out := []string{}
	for r in rows {
		if !r.pass {
			out << '${r.label} = ${r.ratio:.2f}, below ${r.min:.2f}'
		}
	}
	return out
}
