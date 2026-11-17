module hornero_core

import os
import strings
import x.json2

// Safe template engine for Hornero Chromatic outputs (RFC 0002 §12.2).
//
// A template is plain text with colour placeholders; a manifest says where
// the rendered file goes. The grammar is deliberately tiny and has no
// hooks, includes, loops, expressions or command execution:
//
//   {{ role }}  {{ role.hex }}   #RRGGBB          {{ role.bare }}  RRGGBB
//   {{ role.rgb }}  r, g, b      {{ role.r|g|b }}  decimal channel
//   {{ role.rgba A }}            rgba(r, g, b, A)  A in 0..1, two decimals
//   {{ termN }}  N in 0..15, same filters
//   {{ mode }}  {{ id }}
//   {{#dark}}..{{/dark}}  {{#light}}..{{/light}}   (no nesting)
//
// Anything else is `chromatic.template-invalid` naming file:line:col and the
// output is left untouched. Mirrors HorneroOS/config tests/chromatic_template.py
// (the reference implementation); both render the same goldens.

const template_filters = ['hex', 'bare', 'rgb', 'r', 'g', 'b', 'rgba']

// template_error formats one grammar failure as file:line:col: message.
fn template_error(text string, offset int, source string, message string) string {
	mut line := 1
	mut last_nl := -1
	for i in 0 .. offset {
		if text[i] == `\n` {
			line++
			last_nl = i
		}
	}
	return '${source}:${line}:${offset - last_nl}: ${message}'
}

fn is_ident_start(c u8) bool {
	return (c >= `A` && c <= `Z`) || (c >= `a` && c <= `z`)
}

fn is_ident_char(c u8) bool {
	return is_ident_start(c) || (c >= `0` && c <= `9`)
}

// template_colour resolves a role or termN name; '' when unknown.
fn template_colour(t SignalTheme, name string) string {
	if name.starts_with('term') {
		rest := name['term'.len..]
		if rest.len > 0 && rest.len <= 2 && rest.bytes().all(it >= `0` && it <= `9`) {
			n := rest.int()
			if n.str() == rest && n >= 0 && n <= 15 {
				return t.terminal[n]
			}
		}
	}
	if name in signal_roles || name in signal_optional_roles {
		return t.role(name)
	}
	return ''
}

// template_filtered applies one filter; '' means bad filter or arguments.
fn template_filtered(hex string, filter string, arg string) string {
	r, g, b := hex_channels(hex)
	match filter {
		'', 'hex' {
			return if arg.len > 0 { '' } else { hex }
		}
		'bare' {
			return if arg.len > 0 { '' } else { hex[1..] }
		}
		'rgb' {
			return if arg.len > 0 { '' } else { '${r}, ${g}, ${b}' }
		}
		'r' {
			return if arg.len > 0 { '' } else { r.str() }
		}
		'g' {
			return if arg.len > 0 { '' } else { g.str() }
		}
		'b' {
			return if arg.len > 0 { '' } else { b.str() }
		}
		'rgba' {
			if arg.len == 0 || !arg.bytes().all(it == `.` || (it >= `0` && it <= `9`)) {
				return ''
			}
			alpha := arg.f64()
			if alpha < 0.0 || alpha > 1.0 || arg.count('.') > 1 {
				return ''
			}
			return 'rgba(${r}, ${g}, ${b}, ${alpha:.2f})'
		}
		else {
			return ''
		}
	}
}

// parse_template_body splits `name[.filter][ arg]`; ok is false when the
// body does not match the grammar.
fn parse_template_body(body string) (string, string, string, bool) {
	if body.len == 0 || !is_ident_start(body[0]) {
		return '', '', '', false
	}
	mut i := 0
	for i < body.len && is_ident_char(body[i]) {
		i++
	}
	name := body[..i]
	mut filter := ''
	if i < body.len && body[i] == `.` {
		i++
		start := i
		for i < body.len && body[i] >= `a` && body[i] <= `z` {
			i++
		}
		filter = body[start..i]
		if filter.len == 0 {
			return '', '', '', false
		}
	}
	mut arg := ''
	if i < body.len {
		if body[i] != ` ` && body[i] != `\t` && body[i] != `\n` {
			return '', '', '', false
		}
		for i < body.len && (body[i] == ` ` || body[i] == `\t` || body[i] == `\n`) {
			i++
		}
		start := i
		for i < body.len && (body[i] == `.` || (body[i] >= `0` && body[i] <= `9`)) {
			i++
		}
		arg = body[start..i]
		if arg.len == 0 || i != body.len {
			return '', '', '', false
		}
	}
	return name, filter, arg, true
}

// render_template renders one template against a scheme. Errors carry
// `source:line:col: message`.
pub fn render_template(text string, t SignalTheme, source string) !string {
	mut out := strings.new_builder(text.len)
	mut section := ''
	mut section_at := 0
	mut i := 0
	for i < text.len {
		c := text[i]
		next := if i + 1 < text.len { text[i + 1] } else { u8(0) }
		keep := section.len == 0 || section == t.mode
		if c == `}` && next == `}` {
			return error(template_error(text, i, source, "stray '}}'"))
		}
		if !(c == `{` && next == `{`) {
			if keep {
				out.write_u8(c)
			}
			i++
			continue
		}
		mut close := -1
		mut j := i + 2
		for j + 1 < text.len {
			if text[j] == `}` && text[j + 1] == `}` {
				close = j
				break
			}
			j++
		}
		if close < 0 {
			return error(template_error(text, i, source, "stray '{{'"))
		}
		body := text[i + 2..close].trim_space()
		if body in ['#dark', '#light'] {
			if section.len > 0 {
				return error(template_error(text, i, source, 'sections cannot nest'))
			}
			section = body[1..]
			section_at = i
		} else if body in ['/dark', '/light'] {
			if section != body[1..] {
				return error(template_error(text, i, source, 'unmatched {{${body}}}'))
			}
			section = ''
		} else if body.starts_with('#') || body.starts_with('/') {
			return error(template_error(text, i, source, 'unknown section "${body}"'))
		} else if keep {
			if body == 'mode' {
				out.write_string(t.mode)
			} else if body == 'id' {
				out.write_string(t.id)
			} else {
				name, filter, arg, ok := parse_template_body(body)
				if !ok {
					return error(template_error(text, i, source, 'malformed placeholder "${body}"'))
				}
				if filter.len > 0 && filter !in template_filters {
					return error(template_error(text, i, source, 'unknown filter "${filter}"'))
				}
				colour := template_colour(t, name)
				if colour.len == 0 {
					return error(template_error(text, i, source, 'unknown role "${name}"'))
				}
				value := template_filtered(colour, filter, arg)
				if value.len == 0 {
					return error(template_error(text, i, source, 'bad filter arguments in "${body}"'))
				}
				out.write_string(value)
			}
		}
		i = close + 2
	}
	if section.len > 0 {
		return error(template_error(text, section_at, source, 'unclosed section {{#${section}}}'))
	}
	return out.str()
}

// --- manifests ---------------------------------------------------------------

// TemplateManifest is one `*.json` manifest (config template-manifest.schema.json).
pub struct TemplateManifest {
pub:
	name        string
	template    string // file name inside dir
	output      string // raw, with ${XDG_*} / ~/ prefix
	when        string // chromatic | always
	adapter     string // first-party reload hook name, '' for none
	requires    string // raw directory that must exist, '' for none
	dir         string // manifest directory
	first_party bool
}

const template_adapters = ['kitty', 'gtk3', 'gtk4', 'qt6ct', 'qt5ct']
const output_prefixes = [r'${XDG_CONFIG_HOME}', r'${XDG_CACHE_HOME}', r'${XDG_DATA_HOME}', '~']

// first_party_template_dirs lists where config ships templates: the
// override for tests, else the user data copy and the system package.
fn first_party_template_dirs() []string {
	override := os.getenv('HORNERO_CHROMATIC_TEMPLATES_DIR')
	if override.len > 0 {
		return [override]
	}
	p := resolve_paths()
	mut dirs := [os.join_path(p.data_dir, 'hornero', 'chromatic', 'templates')]
	for base in system_data_dirs() {
		d := os.join_path(base, 'hornero', 'chromatic', 'templates')
		if d !in dirs {
			dirs << d
		}
	}
	return dirs
}

// user_template_dir is the user manifest directory.
fn user_template_dir() string {
	return os.join_path(resolve_paths().config_dir, 'hornero', 'chromatic', 'templates.d')
}

fn manifest_str(m map[string]json2.Any, key string) string {
	v := m[key] or { return '' }
	return v.str()
}

// parse_template_manifest validates one decoded manifest. first_party gates
// the adapter key: user manifests may never name a reload hook.
pub fn parse_template_manifest(m map[string]json2.Any, dir string, first_party bool) !TemplateManifest {
	for key, _ in m {
		if key !in ['schemaVersion', 'name', 'template', 'output', 'when', 'adapter', 'requires'] {
			return error('unknown manifest key "${key}"')
		}
	}
	version := m['schemaVersion'] or { return error('missing schemaVersion') }
	if version.str() != '1' {
		return error('schemaVersion must be 1')
	}
	name := manifest_str(m, 'name')
	if name.len == 0 || !name.bytes().all((it >= `a` && it <= `z`) || (it >= `0` && it <= `9`)
		|| it == `-`) {
		return error('name must be lowercase kebab-case')
	}
	template := manifest_str(m, 'template')
	if template.len == 0 || template.contains('/') || template.contains('\\') || template == '.'
		|| template == '..' {
		return error('template must be a file name in the manifest directory')
	}
	output := manifest_str(m, 'output')
	if !output_has_allowed_prefix(output) {
		return error('output must start with \${XDG_CONFIG_HOME}/, \${XDG_CACHE_HOME}/, \${XDG_DATA_HOME}/ or ~/')
	}
	when := manifest_str(m, 'when')
	if when !in ['chromatic', 'always'] {
		return error('when must be chromatic or always')
	}
	adapter := if first_party { manifest_str(m, 'adapter') } else { '' }
	if adapter.len > 0 && adapter !in template_adapters {
		return error('unknown adapter "${adapter}"')
	}
	requires := manifest_str(m, 'requires')
	if requires.len > 0 && !output_has_allowed_prefix(requires) {
		return error('requires must start with an XDG prefix or ~/')
	}
	return TemplateManifest{
		name:        name
		template:    template
		output:      output
		when:        when
		adapter:     adapter
		requires:    requires
		dir:         dir
		first_party: first_party
	}
}

fn output_has_allowed_prefix(raw string) bool {
	for prefix in output_prefixes {
		if raw.starts_with(prefix + '/') && raw.len > prefix.len + 1 {
			return true
		}
	}
	return false
}

// TemplateListing is every manifest found plus per-file problems.
pub struct TemplateListing {
pub:
	manifests []TemplateManifest
	problems  []string
}

fn read_manifests_from(dir string, first_party bool, mut seen map[string]bool, mut manifests []TemplateManifest, mut problems []string) {
	if !os.is_dir(dir) {
		return
	}
	mut files := os.ls(dir) or { return }
	files.sort()
	for f in files {
		if !f.ends_with('.json') {
			continue
		}
		path := os.join_path(dir, f)
		raw := os.read_file(path) or {
			problems << '${path}: ${err.msg()}'
			continue
		}
		parsed := json2.decode[json2.Any](raw) or {
			problems << '${path}: not JSON'
			continue
		}
		if parsed !is map[string]json2.Any {
			problems << '${path}: not an object'
			continue
		}
		manifest := parse_template_manifest(parsed.as_map(), dir, first_party) or {
			problems << '${path}: ${err.msg()}'
			continue
		}
		if manifest.name in seen {
			continue
		}
		if !os.is_file(os.join_path(dir, manifest.template)) {
			problems << '${path}: template ${manifest.template} not found'
			continue
		}
		seen[manifest.name] = true
		manifests << manifest
	}
}

// list_template_manifests discovers user manifests (they win by name) then
// first-party ones, each sorted by file name.
pub fn list_template_manifests() TemplateListing {
	mut seen := map[string]bool{}
	mut manifests := []TemplateManifest{}
	mut problems := []string{}
	read_manifests_from(user_template_dir(), false, mut seen, mut manifests, mut problems)
	for dir in first_party_template_dirs() {
		read_manifests_from(dir, true, mut seen, mut manifests, mut problems)
	}
	manifests.sort(a.name < b.name)
	return TemplateListing{
		manifests: manifests
		problems:  problems
	}
}

// --- output jail -----------------------------------------------------------------

// expand_output_prefix replaces the XDG variable or `~` prefix with the
// resolved directory, without touching the filesystem.
fn expand_output_prefix(raw string) string {
	p := resolve_paths()
	if raw.starts_with(r'${XDG_CONFIG_HOME}/') {
		return os.join_path(p.config_dir, raw[r'${XDG_CONFIG_HOME}/'.len..])
	}
	if raw.starts_with(r'${XDG_CACHE_HOME}/') {
		return os.join_path(p.cache_dir, raw[r'${XDG_CACHE_HOME}/'.len..])
	}
	if raw.starts_with(r'${XDG_DATA_HOME}/') {
		return os.join_path(p.data_dir, raw[r'${XDG_DATA_HOME}/'.len..])
	}
	if raw.starts_with('~/') {
		return os.join_path(os.home_dir(), raw[2..])
	}
	return ''
}

// real_prefix resolves the deepest existing ancestor of path through
// symlinks and re-appends the rest, so a not-yet-created output is judged
// by where its parent really lives.
fn real_prefix(path string) string {
	mut existing := path
	mut rest := []string{}
	for existing.len > 1 && !os.exists(existing) {
		rest.prepend(os.file_name(existing))
		existing = os.dir(existing)
	}
	mut real := os.real_path(existing)
	for part in rest {
		real = os.join_path(real, part)
	}
	return real
}

// jail_output expands an output path and proves it stays under
// $XDG_CONFIG_HOME, $XDG_CACHE_HOME or $XDG_DATA_HOME after symlink
// resolution. `..` segments and symlink escapes are rejected.
pub fn jail_output(raw string) !string {
	if !output_has_allowed_prefix(raw) {
		return error('output must start with \${XDG_CONFIG_HOME}/, \${XDG_CACHE_HOME}/, \${XDG_DATA_HOME}/ or ~/ (got "${raw}")')
	}
	if raw.contains('\x00') || raw.split('/').any(it == '..') {
		return error('output "${raw}" may not contain ".."')
	}
	return jail_expanded(expand_output_prefix(raw), raw, false)
}

// jail_expanded proves an absolute path stays under the XDG directories
// after symlink resolution (state too when include_state, for snapshot
// restores); `label` names it in errors.
pub fn jail_expanded(expanded string, label string, include_state bool) !string {
	p := resolve_paths()
	mut roots := []string{}
	mut dirs := [p.config_dir, p.cache_dir, p.data_dir]
	if include_state {
		dirs << p.state_dir
	}
	for root in dirs {
		roots << real_prefix(root)
	}
	mut real := real_prefix(expanded)
	if os.is_link(expanded) {
		real = os.real_path(expanded)
	}
	for root in roots {
		if real.starts_with(root + '/') {
			return expanded
		}
	}
	return error('output "${label}" resolves outside the XDG directories (${real})')
}

// ResolvedTemplate is a manifest ready to render: jailed output path and
// the template text.
pub struct ResolvedTemplate {
pub:
	manifest TemplateManifest
	output   string
	text     string
}

// resolve_template jails the output and loads the template text.
pub fn resolve_template(m TemplateManifest) !ResolvedTemplate {
	output := jail_output(m.output)!
	text := os.read_file(os.join_path(m.dir, m.template)) or {
		return error('cannot read template ${m.template}: ${err.msg()}')
	}
	return ResolvedTemplate{
		manifest: m
		output:   output
		text:     text
	}
}

// template_applicable reports whether the optional `requires` directory
// exists, so apps the user does not have are never given files.
pub fn template_applicable(m TemplateManifest) bool {
	if m.requires.len == 0 {
		return true
	}
	dir := jail_output(m.requires) or { return false }
	return os.is_dir(dir)
}
