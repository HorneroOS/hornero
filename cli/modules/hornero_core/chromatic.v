module hornero_core

import os
import x.json2

// Hornero Chromatic: generated palettes applied by horneroctl (RFC 0002,
// mission HorneroOS/.github#28, hornero#428). The `hornero-chromatic`
// helper only computes; this module re-validates its scheme against the
// gate table and is the only writer of the live scheme, the downstream
// outputs and `appearance.theme` / `appearance.chromatic` in shell.json.
//
// Apply is transactional: resolve + generate + validate (nothing written),
// lock, snapshot the previous contents of every output, write temp files,
// rename scheme first and shell.json last, restore from the snapshot on any
// failure. See chromatic_state.v for locking, snapshots and recovery.

pub const chromatic_theme_id = 'hornero-chromatic'

// ChromaticReply is the result of one verb. Core never prints: the CLI
// adapter renders `json` for --json and `message` for humans.
pub struct ChromaticReply {
pub:
	ok      bool
	message string
	json    string // success document, already encoded
	code    string // stable chromatic.* error code when !ok
}

fn chromatic_ok(message string, doc map[string]json2.Any) ChromaticReply {
	mut d := doc.clone()
	d['ok'] = jbool(true)
	return ChromaticReply{
		ok:      true
		message: message
		json:    jencode(d)
	}
}

fn chromatic_fail(code string, message string) ChromaticReply {
	return ChromaticReply{
		ok:      false
		message: message
		code:    code
		json:    jencode({
			'ok':      jbool(false)
			'code':    jstr(code)
			'message': jstr(message)
			'error':   json2.Any({
				'code':    jstr(code)
				'message': jstr(message)
			})
		})
	}
}

// cfail packs a stable code into an error message so `!` returns can carry
// both; csplit unpacks it.
fn cfail(code string, message string) string {
	return '${code}\n${message}'
}

fn csplit(raw string) (string, string) {
	if raw.contains('\n') && raw.starts_with('chromatic.') {
		return raw.all_before('\n'), raw.all_after('\n')
	}
	return 'chromatic.write-failed', raw
}

fn chromatic_fail_from(raw string) ChromaticReply {
	code, message := csplit(raw)
	return chromatic_fail(code, message)
}

// ChromaticOptions carries every verb's flags (empty string = not given).
pub struct ChromaticOptions {
pub:
	verb       string
	sub        string
	source     string
	seeds      []string
	variant    string
	mode       string
	contrast   string
	depth      string
	chroma     string
	hue_shift  string
	dry_run    bool
	yes        bool
	no_persist bool
	force      bool
	all        bool
	steps      int = 1
	id         string
	name       string
	from       string
	output     string
	file       string
}

// ChromaticBackends is the test seam for every external side effect.
pub struct ChromaticBackends {
pub:
	reload     fn (mode string, theme SignalTheme, gtk_theme string, icon_theme string, policy string) []string @[required]
	appearance AppearanceBackends @[required]
}

fn default_chromatic_reload(mode string, theme SignalTheme, gtk_theme string, icon_theme string, policy string) []string {
	mut warnings := []string{}
	gtk := apply_gtk_theme_native(gtk_theme, icon_theme, policy, false)
	if !gtk.ok {
		warnings << 'GTK apply failed: ${gtk.message}'
	}
	sync_kitty_include(chromatic_theme_id)
	sync_qt6ct_palette(chromatic_theme_id)
	default_reload()
	return warnings
}

pub fn default_chromatic_backends() ChromaticBackends {
	return ChromaticBackends{
		reload:     default_chromatic_reload
		appearance: default_appearance_backends()
	}
}

// --- paths ---------------------------------------------------------------------

pub fn chromatic_state_dir() string {
	return os.join_path(resolve_paths().state_dir, 'hornero', 'chromatic')
}

pub fn chromatic_state_file() string {
	return os.join_path(chromatic_state_dir(), 'state.json')
}

pub fn chromatic_history_dir() string {
	return os.join_path(chromatic_state_dir(), 'history')
}

pub fn chromatic_cache_dir() string {
	return os.join_path(resolve_paths().cache_dir, 'hornero', 'chromatic')
}

// --- helper ------------------------------------------------------------------------

// chromatic_helper_path resolves the helper: $HORNERO_CHROMATIC_BIN (an
// override that never falls through), /usr/lib/hornero, then PATH.
pub fn chromatic_helper_path() string {
	env := os.getenv('HORNERO_CHROMATIC_BIN')
	if env.len > 0 {
		return if os.is_executable(env) { env } else { '' }
	}
	if os.is_executable('/usr/lib/hornero/hornero-chromatic') {
		return '/usr/lib/hornero/hornero-chromatic'
	}
	return find_on_path('hornero-chromatic')
}

struct HelperRun {
	code int
	out  string
	err  string
}

// run_chromatic_helper executes the helper with literal argv under a 10 s
// kill timeout, keeping stdout (the JSON document) apart from stderr.
fn run_chromatic_helper(args []string) !HelperRun {
	bin := chromatic_helper_path()
	if bin.len == 0 {
		return error(cfail('chromatic.engine-missing', 'hornero-chromatic helper not found (set HORNERO_CHROMATIC_BIN, install hornero-shell, or put it on PATH). Curated themes are unaffected.'))
	}
	timeout := find_on_path('timeout')
	mut p := if timeout.len > 0 { os.new_process(timeout) } else { os.new_process(bin) }
	if timeout.len > 0 {
		mut full := ['-s', 'KILL', '10', bin]
		full << args
		p.set_args(full)
	} else {
		p.set_args(args)
	}
	p.set_redirect_stdio()
	p.run()
	out := p.stdout_slurp()
	errtext := p.stderr_slurp()
	p.wait()
	code := p.code
	p.close()
	return HelperRun{
		code: code
		out:  out
		err:  errtext
	}
}

fn stderr_tail(s string) string {
	lines := s.trim_space().split_into_lines()
	return lines#[-3..].join(' | ')
}

// helper_json runs the helper and returns its decoded document, mapping the
// documented exit codes onto stable chromatic.* codes.
fn helper_json(args []string) !map[string]json2.Any {
	r := run_chromatic_helper(args)!
	if r.code != 0 {
		mut message := stderr_tail(r.err)
		if doc := parse_json_object(r.out) {
			m := jget(jmap(doc, 'error'), 'message')
			if m.len > 0 {
				message = m
			}
		}
		if r.code == 124 || r.code == 137 {
			return error(cfail('chromatic.engine-failed', 'hornero-chromatic timed out after 10 s'))
		}
		return match r.code {
			3 {
				error(cfail('chromatic.source-unreadable', 'source unreadable or unsupported: ${message}'))
			}
			4 {
				error(cfail('chromatic.gates-failed', 'the engine could not reach the contrast gates: ${message}'))
			}
			else {
				error(cfail('chromatic.engine-failed', 'hornero-chromatic exited ${r.code}: ${message}'))
			}
		}
	}
	return parse_json_object(r.out) or {
		return error(cfail('chromatic.engine-failed', 'hornero-chromatic printed invalid JSON: ${err.msg()}'))
	}
}

// --- request -----------------------------------------------------------------------

struct ChromaticRequest {
mut:
	source    string = 'wallpaper'
	path      string
	seeds     []string
	variant   string = 'auto'
	mode      string = 'auto'
	contrast  string = 'standard'
	depth     string = 'standard'
	chroma    f64    = 1.0
	hue_shift f64
}

const request_variants = ['auto', 'balanced', 'vibrant', 'expressive', 'faithful', 'muted', 'monochrome',
	'high-contrast', 'neon']

// read_shell_appearance returns shell.json's `appearance` object ({} when
// the file or key is absent or unreadable).
fn read_shell_appearance() map[string]json2.Any {
	raw := os.read_file(shell_config_file(resolve_paths())) or {
		return map[string]json2.Any{}
	}
	doc := parse_json_object(raw) or { return map[string]json2.Any{} }
	return jmap(doc, 'appearance')
}

fn apply_request_map(mut r ChromaticRequest, m map[string]json2.Any) {
	src := jget(m, 'source')
	if src.starts_with('image:') {
		r.source = 'image'
		r.path = src['image:'.len..]
	} else if src in ['wallpaper', 'image', 'seed', 'house'] {
		r.source = src
	}
	if p := m['path'] {
		if p.str().len > 0 {
			r.path = p.str()
		}
	}
	if s := m['seeds'] {
		if s is []json2.Any {
			r.seeds = s.as_array().map(it.str())
		}
	}
	for key in ['variant', 'mode', 'contrast'] {
		v := jget(m, key)
		if v.len == 0 {
			continue
		}
		match key {
			'variant' { r.variant = v }
			'mode' { r.mode = v }
			else { r.contrast = v }
		}
	}
	if v := m['surfaceDepth'] {
		r.depth = v.str()
	}
	if v := m['chroma'] {
		r.chroma = v.f64()
	}
	if v := m['hueShift'] {
		r.hue_shift = v.f64()
	}
}

// resolve_chromatic_request merges defaults < shell.json < flags.
fn resolve_chromatic_request(o ChromaticOptions) !ChromaticRequest {
	mut r := ChromaticRequest{}
	apply_request_map(mut r, jmap(read_shell_appearance(), 'chromatic'))
	if o.source.len > 0 {
		if o.source.starts_with('image:') {
			r.source = 'image'
			r.path = o.source['image:'.len..]
		} else if o.source in ['wallpaper', 'seed', 'house'] {
			r.source = o.source
		} else {
			return error(cfail('chromatic.usage', 'unknown --source "${o.source}" (want wallpaper|image:PATH|seed|house)'))
		}
	}
	if o.seeds.len > 0 {
		r.seeds = o.seeds.clone()
		if o.source.len == 0 {
			r.source = 'seed'
		}
	}
	if o.variant.len > 0 {
		r.variant = o.variant
	}
	if o.mode.len > 0 {
		r.mode = o.mode
	}
	if o.contrast.len > 0 {
		r.contrast = o.contrast
	}
	if o.depth.len > 0 {
		r.depth = o.depth
	}
	if o.chroma.len > 0 {
		r.chroma = o.chroma.f64()
	}
	if o.hue_shift.len > 0 {
		r.hue_shift = o.hue_shift.f64()
	}
	if r.variant !in request_variants {
		return error(cfail('chromatic.usage', 'unknown variant "${r.variant}"'))
	}
	if r.mode !in ['auto', 'dark', 'light'] {
		return error(cfail('chromatic.usage', 'mode must be auto|dark|light'))
	}
	if r.contrast !in ['auto', 'standard', 'boosted', 'maximum'] {
		return error(cfail('chromatic.usage', 'contrast must be auto|standard|boosted|maximum'))
	}
	if r.depth !in ['standard', 'deep'] {
		return error(cfail('chromatic.usage', 'depth must be standard|deep'))
	}
	if r.seeds.len > 2 {
		return error(cfail('chromatic.usage', 'at most two --seed colours'))
	}
	for s in r.seeds {
		signal_hex(s) or { return error(cfail('chromatic.usage', 'seed ${err.msg()}')) }
	}
	return r
}

// request_as_json is the §8.3 shape stored in appearance.chromatic.
fn request_as_json(r ChromaticRequest) map[string]json2.Any {
	return {
		'source':       jstr(r.source)
		'seeds':        jstrs(r.seeds)
		'variant':      jstr(r.variant)
		'mode':         jstr(r.mode)
		'contrast':     jstr(r.contrast)
		'surfaceDepth': jstr(r.depth)
		'chroma':       json2.Any(r.chroma)
		'hueShift':     json2.Any(r.hue_shift)
	}
}

// helper_generate_args builds the helper argv for a request.
fn helper_generate_args(r ChromaticRequest, no_cache bool) ![]string {
	mut args := ['generate']
	match r.source {
		'wallpaper' {
			path := if r.path.len > 0 { r.path } else { current_wallpaper('') }
			if path.len == 0 {
				return error(cfail('chromatic.source-unreadable', 'no current wallpaper to derive colours from.\nExample: horneroctl wallpaper set ~/wall.jpg --yes'))
			}
			args << ['--source', path]
		}
		'image' {
			if r.path.len == 0 {
				return error(cfail('chromatic.usage', 'image source needs a path.\nExample: horneroctl appearance chromatic preview --source image:~/wall.jpg'))
			}
			args << ['--source', r.path]
		}
		'seed' {
			if r.seeds.len == 0 {
				return error(cfail('chromatic.usage', 'seed source needs --seed #RRGGBB.\nExample: horneroctl appearance chromatic preview --seed "#D98A3A"'))
			}
			for s in r.seeds {
				args << ['--seed', s]
			}
		}
		'house' {
			args << '--house'
			wall := current_wallpaper('')
			if wall.len > 0 {
				args << ['--wallpaper', wall]
			}
		}
		else {
			return error(cfail('chromatic.usage', 'unknown source ${r.source}'))
		}
	}
	args << ['--variant', r.variant, '--mode', r.mode, '--contrast', r.contrast, '--depth', r.depth,
		'--chroma', '${r.chroma:.4f}', '--hue-shift', '${r.hue_shift:.4f}']
	if live := read_signal_scheme() {
		args << ['--current-mode', live.mode]
	}
	if no_cache {
		args << '--no-cache'
	} else {
		args << ['--cache-dir', chromatic_cache_dir()]
	}
	return args
}

// --- generated document -------------------------------------------------------------

struct Generated {
	doc         map[string]json2.Any
	scheme      map[string]json2.Any
	theme       SignalTheme
	fingerprint string
	level       string
	variant     string
	mode        string
	rows        []GateRow
}

// parse_generated checks the helper document and re-validates the scheme
// against the gate table at its resolved level before anything can write.
fn parse_generated(doc map[string]json2.Any) !Generated {
	if jget(doc, 'schemaVersion') != '1' {
		return error(cfail('chromatic.engine-failed', 'unsupported helper schemaVersion ${jget(doc, 'schemaVersion')}'))
	}
	scheme := jmap(doc, 'scheme')
	if scheme.len == 0 {
		return error(cfail('chromatic.engine-failed', 'helper document has no scheme'))
	}
	theme := parse_signal_theme('', scheme) or {
		return error(cfail('chromatic.gates-failed', 'generated scheme is not a valid Signal scheme: ${err.msg()}'))
	}
	if theme.id != chromatic_theme_id {
		return error(cfail('chromatic.gates-failed', 'generated scheme id must be ${chromatic_theme_id}, got ${theme.id}'))
	}
	chrom := jmap(scheme, 'chromatic')
	resolved := jmap(chrom, 'resolved')
	level := jget(resolved, 'contrast')
	gate_level(level) or {
		return error(cfail('chromatic.gates-failed', 'generated scheme has no valid resolved contrast level'))
	}
	rows := validate_signal_gates(theme, level, true) or {
		return error(cfail('chromatic.gates-failed', err.msg()))
	}
	failures := gate_failures(rows)
	if failures.len > 0 {
		return error(cfail('chromatic.gates-failed', 'generated palette fails the ${level} gates; nothing was written:\n  ' +
			failures.join('\n  ')))
	}
	mut fp := jget(doc, 'fingerprint')
	if fp.len == 0 {
		fp = jget(chrom, 'fingerprint')
	}
	return Generated{
		doc:         doc
		scheme:      scheme
		theme:       theme
		fingerprint: fp
		level:       level
		variant:     jget(resolved, 'variant')
		mode:        theme.mode
		rows:        rows
	}
}

fn generate_validated(r ChromaticRequest, no_cache bool) !Generated {
	args := helper_generate_args(r, no_cache)!
	doc := helper_json(args)!
	return parse_generated(doc)
}

// --- planned outputs ------------------------------------------------------------------

// PlannedWrite is one file to write (or remove) in a transaction.
struct PlannedWrite {
	path    string
	content string
	remove  bool
}

// marker identifies a file generated by Chromatic templates.
const chromatic_marker = 'Hornero Chromatic — GENERATED'

// plan_chromatic_outputs renders the live scheme, the existing Signal
// derived files and every applicable template, all in memory.
fn plan_chromatic_outputs(g Generated) !([]PlannedWrite, []string) {
	t := g.theme
	out := signal_output_paths()
	mut plan := [
		PlannedWrite{
			path:    out.scheme
			content: json2.encode(g.scheme, escape_unicode: true) + '\n'
		},
		PlannedWrite{
			path:    out.hyprland_lua
			content: render_signal_hyprland_lua(t)
		},
		PlannedWrite{
			path:    out.hyprlock_conf
			content: render_signal_hyprlock_conf(t)
		},
		PlannedWrite{
			path:    out.alacritty_toml
			content: render_signal_alacritty(t)
		},
		PlannedWrite{
			path:    out.ghostty_theme
			content: render_signal_ghostty(t)
		},
		PlannedWrite{
			path:    out.btop_theme
			content: render_signal_btop(t)
		},
		PlannedWrite{
			path:    out.cava_theme
			content: render_signal_cava(t)
		},
	]
	listing := list_template_manifests()
	mut warnings := listing.problems.map('template manifest ignored: ${it}')
	for m in listing.manifests {
		if m.when !in ['chromatic', 'always'] || !template_applicable(m) {
			continue
		}
		res := resolve_template(m) or {
			return error(cfail('chromatic.template-invalid', '${m.name}: ${err.msg()}'))
		}
		text := render_template(res.text, t, '${m.name}/${m.template}') or {
			return error(cfail('chromatic.template-invalid', err.msg()))
		}
		plan << PlannedWrite{
			path:    res.output
			content: text
		}
	}
	return plan, warnings
}

// --- shell.json patch --------------------------------------------------------------------

// ShellPatch edits only appearance.theme and appearance.chromatic.
// Modes: keep | set | remove.
struct ShellPatch {
	theme_mode     string = 'keep'
	theme          string
	chromatic_mode string    = 'keep'
	chromatic      json2.Any = json2.Null{}
}

// patched_shell_json computes the new shell.json text from the current
// file (untouched keys preserved). An unreadable file is never rewritten.
fn patched_shell_json(patch ShellPatch) !string {
	path := shell_config_file(resolve_paths())
	mut doc := map[string]json2.Any{}
	if os.is_file(path) {
		raw := os.read_file(path) or {
			return error(cfail('chromatic.write-failed', 'cannot read ${path}: ${err.msg()}'))
		}
		doc = parse_json_object(raw) or {
			return error(cfail('chromatic.write-failed', '${path} is not a valid JSON object; not touching it'))
		}
	}
	mut appearance := jmap(doc, 'appearance').clone()
	match patch.theme_mode {
		'set' { appearance['theme'] = jstr(patch.theme) }
		'remove' { appearance.delete('theme') }
		else {}
	}
	match patch.chromatic_mode {
		'set' { appearance['chromatic'] = patch.chromatic }
		'remove' { appearance.delete('chromatic') }
		else {}
	}
	doc['appearance'] = json2.Any(appearance)
	return json2.encode(doc, escape_unicode: true) + '\n'
}
