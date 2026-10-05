module hornero_core

import os
import x.json2

const default_system_profile_file = '/usr/lib/hornero/system-profile.json'
const system_profile_hex_digits = '0123456789abcdef'

fn system_profile_file() string {
	override := os.getenv('HORNERO_SYSTEM_PROFILE_FILE')
	if override.len > 0 {
		return override
	}
	return default_system_profile_file
}

fn system_profile_string(m map[string]json2.Any, key string) string {
	if key !in m {
		return ''
	}
	return m[key].str()
}

fn system_profile_string_list(value json2.Any) !string {
	if value !is []json2.Any {
		return error('expected an array of strings')
	}
	mut items := []string{}
	for item in value.as_array() {
		if item !is string {
			return error('expected an array of strings')
		}
		items << item.str()
	}
	if items.len == 0 {
		return error('expected a non-empty array')
	}
	return items.join(',')
}

fn system_profile_is_commit(value string) bool {
	if value.len != 40 {
		return false
	}
	for index in 0 .. value.len {
		if !system_profile_hex_digits.contains(value[index].ascii_str()) {
			return false
		}
	}
	return true
}

// system_profile_result reads the immutable profile record installed by the
// selected Calamares composition. It never infers an edition from coincidental
// package presence. Systems installed by another path remain explicitly
// unrecorded while still reporting the current supported compositor session.
pub fn system_profile_result() CommandResult {
	path := system_profile_file()
	active := active_compositor()
	if !os.is_file(path) {
		return ok_result('system info', 'No installed edition profile is recorded. Active compositor: ${active}.', {
			'activeCompositor': active
			'edition':          'unrecorded'
			'profileRecorded':  'false'
		})
	}
	raw := os.read_file(path) or {
		return fail_result('system info', 'Cannot read the installed profile at ${path}: ${err.msg()}')
	}
	decoded := json2.decode[json2.Any](raw) or {
		return fail_result('system info', 'Installed profile is invalid JSON at ${path}. Reinstall its Hornero profile package.')
	}
	if decoded !is map[string]json2.Any {
		return fail_result('system info', 'Installed profile is not a JSON object at ${path}. Reinstall its Hornero profile package.')
	}
	root := decoded.as_map()
	if system_profile_string(root, 'apiVersion') != 'hornero.os/v1'
		|| system_profile_string(root, 'kind') != 'InstalledProfile' {
		return fail_result('system info', 'Installed profile has an unsupported format at ${path}. Reinstall its Hornero profile package.')
	}
	if 'edition' !in root || root['edition'] !is map[string]json2.Any {
		return fail_result('system info', 'Installed profile is missing edition metadata at ${path}. Reinstall its Hornero profile package.')
	}
	if !system_profile_is_commit(system_profile_string(root, 'sourceRevision')) {
		return fail_result('system info', 'Installed profile has an invalid source revision at ${path}. Reinstall its Hornero profile package.')
	}
	if !system_profile_string(root, 'profilePackage').starts_with('hornero-profile-') {
		return fail_result('system info', 'Installed profile has no valid metadata package identity at ${path}. Reinstall its Hornero profile package.')
	}
	edition := root['edition'].as_map()
	for required in ['edition', 'title', 'role', 'maturity'] {
		if system_profile_string(edition, required).len == 0 {
			return fail_result('system info', 'Installed profile is missing ${required} at ${path}. Reinstall its Hornero profile package.')
		}
	}
	edition_id := system_profile_string(edition, 'edition')
	edition_maturity := system_profile_string(edition, 'maturity')
	if edition_maturity !in ['planned', 'experimental', 'preview', 'supported'] {
		return fail_result('system info', 'Installed profile has an unknown maturity at ${path}. Reinstall its Hornero profile package.')
	}
	configured_compositor := system_profile_string(edition, 'compositor')
	compositor_maturity := system_profile_string(edition, 'compositorMaturity')
	sets := system_profile_string_list(edition['packageSets']) or {
		return fail_result('system info', 'Installed profile has no package-set composition at ${path}. Reinstall its Hornero profile package.')
	}
	if configured_compositor.len > 0 && compositor_maturity !in ['experimental', 'preview', 'supported'] {
		return fail_result('system info', 'Installed profile has an unknown compositor maturity at ${path}. Reinstall its Hornero profile package.')
	}
	name := system_profile_string(edition, 'title')
	mut message := 'Installed edition: ${name} (${edition_maturity}).'
	if configured_compositor.len > 0 {
		message += ' Configured compositor: ${configured_compositor}'
		if compositor_maturity.len > 0 {
			message += ' (${compositor_maturity})'
		}
		message += '.'
	}
	message += ' Active compositor: ${active}.'
	return ok_result('system info', message, {
		'activeCompositor':   active
		'compositor':         configured_compositor
		'compositorMaturity': compositor_maturity
		'edition':            edition_id
		'editionMaturity':    edition_maturity
		'editionTitle':       name
		'packageSets':        sets
		'profilePackage':     system_profile_string(root, 'profilePackage')
		'profileRecorded':    'true'
		'role':               system_profile_string(edition, 'role')
		'sourceRevision':     system_profile_string(root, 'sourceRevision')
	})
}
