module hornero_core

import os
import x.json2

// config_paths_report prints the resolved XDG path contract.
pub fn config_paths_report() CommandResult {
	p := resolve_paths()
	lines := [
		'user config:   ${p.config_dir}',
		'user data:     ${p.data_dir}',
		'user state:    ${p.state_dir}',
		'user cache:    ${p.cache_dir}',
		'system config: ${p.system_config_dir}',
		'shell config:  ${shell_config_file(p)}',
	]
	return ok_result('config paths', lines.join('\n'), {
		'config_dir':   p.config_dir
		'shell_config': shell_config_file(p)
	})
}

pub struct ThemeManifest {
pub mut:
	id   string
	name string
}

// load_shell_config reads the materialized shell settings: the user file
// first, the shipped system default as fallback. Returns the path used and
// the parsed document. Mirrors the `dots-quickshell config get` lookup
// order without spawning the backend.
fn load_shell_config() !(string, map[string]json2.Any) {
	p := resolve_paths()
	user := shell_config_file(p)
	sys := system_shell_config_file(p)
	path := if os.is_file(user) { user } else { sys }
	if !os.is_file(path) {
		return error('no shell config found (looked at ${user} and ${sys}).\nRun: horneroctl config validate')
	}
	raw := os.read_file(path)!
	parsed := json2.decode[json2.Any](raw) or {
		return error('shell config does not parse: ${path}')
	}
	if parsed is map[string]json2.Any {
		return path, parsed
	}
	return error('shell config is not an object: ${path}')
}

fn config_scalar_summary(key string, v json2.Any) string {
	if v is map[string]json2.Any {
		m := v.clone()
		return '${key}: (object, ${m.len} keys)'
	}
	if v is []json2.Any {
		a := v.clone()
		return '${key}: (array, ${a.len} items)'
	}
	return '${key}: ${v.str()}'
}

// config_lookup walks one dot-notation key (`bar.position`) through nested
// objects, mirroring `dots-quickshell config get` (dictionaries only;
// a container result prints as JSON).
fn config_lookup(doc map[string]json2.Any, key string) !json2.Any {
	return lookup_parts(doc, key, key.split('.'))
}

fn lookup_parts(doc map[string]json2.Any, key string, parts []string) !json2.Any {
	first := parts[0]
	if first !in doc {
		return error('Key not found: ${key}.\nRun: horneroctl config show')
	}
	v := doc[first]
	if parts.len == 1 {
		return v
	}
	if v is map[string]json2.Any {
		return lookup_parts(v, key, parts[1..])
	}
	return error('Key not found: ${key}.\nRun: horneroctl config show')
}

// config_show_report implements `config show [key]` (read-only). Without a
// key it summarizes every top-level key of the materialized shell.json;
// with a key it prints the dot-notation value.
pub fn config_show_report(key string) CommandResult {
	path, doc := load_shell_config() or { return fail_result('config show', err.msg()) }
	if key.len == 0 {
		mut names := doc.keys()
		names.sort()
		mut lines := []string{}
		for k in names {
			lines << config_scalar_summary(k, doc[k])
		}
		lines << '${names.len} key(s) in ${path}'
		lines << 'Query one with: horneroctl config show <key>'
		return ok_result('config show', lines.join('\n'), {
			'count': names.len.str()
			'file':  path
		})
	}
	val := config_lookup(doc, key) or { return fail_result('config show', err.msg()) }
	return ok_result('config show', val.str(), {
		'key':   key
		'value': val.str()
		'file':  path
	})
}

// config_validate_report checks the materialized config without changing it.
pub fn config_validate_report() CommandResult {
	p := resolve_paths()
	mut lines := []string{}
	mut failed := 0
	cfg := shell_config_file(p)
	if os.is_file(cfg) {
		lines << 'ok  shell config: ${cfg}'
	} else {
		lines << 'missing shell config: ${cfg} (defaults apply)'
	}
	sys := system_shell_config_file(p)
	if os.is_file(sys) {
		lines << 'ok  system default: ${sys}'
	}
	manifest := os.join_path(p.data_dir, 'hornero', 'themes', 'wallpapers.manifest.json')
	if os.is_file(manifest) {
		raw := os.read_file(manifest) or { '' }
		if parsed := json2.decode[[]ThemeManifest](raw) {
			lines << 'ok  theme manifest: ${manifest} (${parsed.len} entries)'
		} else {
			lines << 'FAIL theme manifest: ${manifest} does not parse'
			failed++
		}
	} else {
		lines << 'missing theme manifest: ${manifest} (optional)'
	}
	if failed == 0 {
		lines << 'config: valid'
	} else {
		lines << 'config: ${failed} problem(s)'
	}
	return CommandResult{
		command: 'config validate'
		ok:      failed == 0
		message: lines.join('\n')
		data:    map[string]string{}
	}
}
