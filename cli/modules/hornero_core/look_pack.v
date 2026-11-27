module hornero_core

import math
import os
import x.json2

// Look packs: share the shell customisation (looks, sizes, behaviour) as a
// small JSON document. Same format and rules as the shell's Control Center
// (shell services/customisation.js, `hornero/look-pack@1`): a pack holds only
// the settings that differ from the factory defaults, keyed by dotted path.
// Import validates every entry against the factory file: the path must be a
// customisation path that exists there, the value must have the same type,
// and numbers are clamped to 0..10x the factory value. User data (apps,
// paths, favourites, layouts, plugins) is never exported or imported.

pub const look_pack_schema = 'hornero/look-pack@1'

// Keep in sync with SECTIONS / EXCLUDED in shell services/customisation.js.
const look_pack_sections = ['appearance', 'border', 'notifs', 'osd', 'session', 'lock', 'sidebar',
	'utilities', 'launcher', 'controlCenter', 'bar', 'background', 'dashboard']

const look_pack_excluded = ['launcher.favouriteApps', 'launcher.hiddenApps', 'launcher.actions',
	'session.commands', 'session.icons', 'bar.bars', 'bar.perScreen', 'bar.excludedScreens',
	'controlCenter.appearanceOpenSections', 'appearance.transparency.elements', 'appearance.chromatic',
	'utilities.vpn', 'launcher.useFuzzy']

fn look_pack_is_customisation(path string) bool {
	top := path.all_before('.')
	if top !in look_pack_sections {
		return false
	}
	for ex in look_pack_excluded {
		if path == ex || path.starts_with(ex + '.') {
			return false
		}
	}
	return true
}

// look_pack_flatten flattens nested objects to dotted paths; arrays and empty
// objects are leaves.
fn look_pack_flatten(m map[string]json2.Any, prefix string, mut out map[string]json2.Any) {
	for k, v in m {
		path := if prefix.len > 0 { '${prefix}.${k}' } else { k }
		if v is map[string]json2.Any {
			if v.len > 0 {
				look_pack_flatten(v, path, mut out)
				continue
			}
		}
		out[path] = v
	}
}

fn look_pack_kind(v json2.Any) string {
	return match v {
		string { 'string' }
		bool { 'bool' }
		int, i64, u64, f32, f64 { 'number' }
		[]json2.Any { 'array' }
		map[string]json2.Any { 'object' }
		else { 'null' }
	}
}

fn look_pack_same(a json2.Any, b json2.Any) bool {
	if look_pack_kind(a) == 'number' && look_pack_kind(b) == 'number' {
		return math.abs(a.f64() - b.f64()) < 1e-9
	}
	return json2.encode(a) == json2.encode(b)
}

fn look_pack_read_object(path string) !map[string]json2.Any {
	raw := os.read_file(path) or { return error('cannot read ${path}: ${err}') }
	parsed := json2.decode[json2.Any](raw) or { return error('${path}: invalid JSON: ${err}') }
	if parsed !is map[string]json2.Any {
		return error('${path}: must be a JSON object')
	}
	return parsed.as_map()
}

// look_pack_changed lists customisation paths whose value differs from the
// factory (sorted by path).
fn look_pack_changed(current map[string]json2.Any, factory map[string]json2.Any) map[string]json2.Any {
	mut cur := map[string]json2.Any{}
	mut fac := map[string]json2.Any{}
	look_pack_flatten(current, '', mut cur)
	look_pack_flatten(factory, '', mut fac)
	mut out := map[string]json2.Any{}
	for path, f in fac {
		if !look_pack_is_customisation(path) || path !in cur {
			continue
		}
		if !look_pack_same(cur[path], f) {
			out[path] = cur[path]
		}
	}
	return out
}

pub fn look_pack_export_text(current map[string]json2.Any, factory map[string]json2.Any, name string) string {
	changed := look_pack_changed(current, factory)
	mut keys := changed.keys()
	keys.sort()
	mut values := map[string]json2.Any{}
	for k in keys {
		values[k] = changed[k]
	}
	pack := {
		'schema': json2.Any(look_pack_schema)
		'name':   json2.Any(name)
		'values': json2.Any(values)
	}
	return json2.encode(pack, prettify: true, escape_unicode: true) + '\n'
}

pub struct LookPackVerdict {
pub mut:
	accepted map[string]json2.Any
	rejected []string
}

// look_pack_validate checks a decoded pack against the factory file.
pub fn look_pack_validate(pack map[string]json2.Any, factory map[string]json2.Any) !LookPackVerdict {
	if 'schema' !in pack || pack['schema'].str() != look_pack_schema || 'values' !in pack
		|| pack['values'] !is map[string]json2.Any {
		return error('not a Hornero look pack (expected schema ${look_pack_schema})')
	}
	mut fac := map[string]json2.Any{}
	look_pack_flatten(factory, '', mut fac)
	values := pack['values'].as_map()
	mut paths := values.keys()
	paths.sort()
	mut verdict := LookPackVerdict{}
	for path in paths {
		v := values[path]
		if path !in fac || !look_pack_is_customisation(path) {
			verdict.rejected << '${path}: unknown setting'
			continue
		}
		f := fac[path]
		if look_pack_kind(v) != look_pack_kind(f) {
			verdict.rejected << '${path}: wrong type'
			continue
		}
		if look_pack_kind(v) == 'number' {
			x := v.f64()
			base := f.f64()
			if math.is_nan(x) || math.is_inf(x, 0) {
				verdict.rejected << '${path}: not a number'
				continue
			}
			lo := if base > 0 { 0.0 } else { base - 1000.0 }
			hi := if base > 0 { math.max(base * 10.0, 10.0) } else { base + 1000.0 }
			clamped := math.max(lo, math.min(hi, x))
			if clamped != x {
				verdict.accepted[path] = json2.Any(clamped)
				continue
			}
		}
		verdict.accepted[path] = v
	}
	return verdict
}

fn look_pack_set_path(m map[string]json2.Any, parts []string, v json2.Any) map[string]json2.Any {
	mut out := m.clone()
	if parts.len == 1 {
		out[parts[0]] = v
		return out
	}
	child := if parts[0] in out && out[parts[0]] is map[string]json2.Any {
		out[parts[0]].as_map()
	} else {
		map[string]json2.Any{}
	}
	out[parts[0]] = json2.Any(look_pack_set_path(child, parts[1..], v))
	return out
}

pub struct LookPackExportOptions {
pub:
	file    string
	factory string
	name    string
}

pub struct LookPackImportOptions {
pub:
	file    string
	factory string
	dry_run bool
	yes     bool
}

fn look_pack_factory_file(override_path string) string {
	if override_path.len > 0 {
		return override_path
	}
	return system_shell_config_file(resolve_paths())
}

// config_look_export_report implements `config export [--file F] [--name N]`.
pub fn config_look_export_report(opts LookPackExportOptions) CommandResult {
	conf := shell_config_file(resolve_paths())
	fac_file := look_pack_factory_file(opts.factory)
	current := if os.is_file(conf) {
		look_pack_read_object(conf) or { return fail_result('config export', err.msg()) }
	} else {
		map[string]json2.Any{}
	}
	factory := look_pack_read_object(fac_file) or {
		return fail_result('config export', '${err.msg()}\nPass the factory defaults with --factory <shell.default.json>.')
	}
	name := if opts.name.len > 0 { opts.name } else { 'My look' }
	text := look_pack_export_text(current, factory, name)
	if opts.file.len == 0 {
		return ok_result('config export', text.trim_space(), {
			'config':  conf
			'factory': fac_file
		})
	}
	os.write_file(opts.file, text) or {
		return fail_result('config export', 'cannot write ${opts.file}: ${err}')
	}
	return ok_result('config export', 'wrote look pack to ${opts.file}', {
		'file':    opts.file
		'config':  conf
		'factory': fac_file
	})
}

// config_look_import_report implements `config import <file> [--dry-run|--yes]`.
// Mutating: needs --yes; --dry-run only previews. Writes shell.json atomically.
pub fn config_look_import_report(opts LookPackImportOptions) CommandResult {
	if !opts.yes && !opts.dry_run {
		return fail_result('config import', 'refusing to import ${opts.file} without --yes (preview with --dry-run).\nExample: horneroctl config import look.json --dry-run')
	}
	fac_file := look_pack_factory_file(opts.factory)
	factory := look_pack_read_object(fac_file) or {
		return fail_result('config import', '${err.msg()}\nPass the factory defaults with --factory <shell.default.json>.')
	}
	pack := look_pack_read_object(opts.file) or { return fail_result('config import', err.msg()) }
	verdict := look_pack_validate(pack, factory) or { return fail_result('config import', err.msg()) }
	conf := shell_config_file(resolve_paths())
	summary := 'accepted ${verdict.accepted.len}, skipped ${verdict.rejected.len}'
	mut data := {
		'config':   conf
		'accepted': verdict.accepted.len.str()
		'skipped':  verdict.rejected.len.str()
	}
	if verdict.rejected.len > 0 {
		data['skipped_detail'] = verdict.rejected.join('; ')
	}
	if opts.dry_run {
		data['dry_run'] = 'true'
		return ok_result('config import', 'would apply look pack to ${conf} (${summary})', data)
	}
	mut config := if os.is_file(conf) {
		look_pack_read_object(conf) or { return fail_result('config import', err.msg()) }
	} else {
		map[string]json2.Any{}
	}
	mut paths := verdict.accepted.keys()
	paths.sort()
	for p in paths {
		config = look_pack_set_path(config, p.split('.'), verdict.accepted[p])
	}
	tmp := preset_write_tmp(conf, json2.encode(config, escape_unicode: true) + '\n') or {
		return fail_result('config import', err.msg())
	}
	os.mv(tmp, conf) or {
		os.rm(tmp) or {}
		return fail_result('config import', 'cannot move ${tmp} to ${conf}: ${err}')
	}
	return ok_result('config import', 'applied look pack (${summary})', data)
}
