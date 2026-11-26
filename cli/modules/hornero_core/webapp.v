module hornero_core

import os
import strings

// DesktopAppEntry represents a Hornero-managed XDG .desktop entry.
pub struct DesktopAppEntry {
pub:
	id        string
	kind      string // webapp | tui
	name      string
	exec      string
	wm_class  string
	file_path string
}

// WebAppSpec configures a new XDG WebApp .desktop entry.
pub struct WebAppSpec {
pub:
	id         string
	name       string
	url        string
	icon       string
	browser    string
	categories string
}

// TuiAppSpec configures a new XDG TUI App .desktop entry.
pub struct TuiAppSpec {
pub:
	id         string
	name       string
	command    string
	icon       string
	terminal   string
	categories string
}

// applications_dir returns the XDG applications directory, respecting
// XDG_DATA_HOME for deterministic testing and user overrides.
pub fn applications_dir() string {
	xdg := os.getenv('XDG_DATA_HOME').trim_space()
	if xdg.len > 0 {
		return os.join_path(xdg, 'applications')
	}
	return os.join_path(os.home_dir(), '.local', 'share', 'applications')
}

// validate_app_id enforces strict path-traversal and filename safety:
// rejects empty strings, `/`, `\`, `..`, NUL bytes, leading `.`, and
// non-slug characters.
pub fn validate_app_id(id string) !string {
	if id.len == 0 {
		return error('app id must not be empty')
	}
	if id.contains('/') || id.contains('\\') || id.contains('..') || id.contains('\0') {
		return error('invalid app id: path traversal characters are forbidden')
	}
	if id.starts_with('.') || id.starts_with('-') {
		return error('invalid app id: must start with an alphanumeric character')
	}
	for c in id {
		ok := (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || (c >= `0` && c <= `9`)
			|| c == `-` || c == `_`
		if !ok {
			return error('invalid app id: only letters, digits, hyphens, and underscores are allowed')
		}
	}
	return id
}

fn validate_desktop_field(label string, val string) ! {
	if val.contains('\n') || val.contains('\r') || val.contains('\0') {
		return error('invalid ${label}: control characters are not allowed')
	}
}

fn desktop_file_path(kind string, id string) !string {
	safe_id := validate_app_id(id)!
	prefix := if kind == 'webapp' { 'hornero-webapp-' } else { 'hornero-tui-' }
	return os.join_path(applications_dir(), '${prefix}${safe_id}.desktop')
}

// webapp_add writes a clean XDG .desktop entry for a WebApp.
pub fn webapp_add(spec WebAppSpec) !DesktopAppEntry {
	safe_id := validate_app_id(spec.id)!
	if spec.name.trim_space().len == 0 {
		return error('webapp name must not be empty')
	}
	if !spec.url.starts_with('https://') && !spec.url.starts_with('http://') {
		return error('webapp url must start with http:// or https://')
	}
	validate_desktop_field('name', spec.name)!
	validate_desktop_field('url', spec.url)!
	validate_desktop_field('icon', spec.icon)!

	browser := if spec.browser.trim_space().len > 0 { spec.browser.trim_space() } else { 'chromium' }
	validate_desktop_field('browser', browser)!
	cats := if spec.categories.trim_space().len > 0 {
		spec.categories.trim_space()
	} else {
		'Network;WebBrowser;'
	}
	wm_class := 'hornero-webapp-${safe_id}'
	exec_cmd := '${browser} --app=${spec.url}'

	dir := applications_dir()
	os.mkdir_all(dir)!
	path := desktop_file_path('webapp', safe_id)!

	mut sb := strings.new_builder(256)
	sb.write_string('[Desktop Entry]\n')
	sb.write_string('Version=1.0\n')
	sb.write_string('Type=Application\n')
	sb.write_string('Name=${spec.name.trim_space()}\n')
	sb.write_string('Exec=${exec_cmd}\n')
	if spec.icon.trim_space().len > 0 {
		sb.write_string('Icon=${spec.icon.trim_space()}\n')
	}
	sb.write_string('Terminal=false\n')
	sb.write_string('Categories=${cats}\n')
	sb.write_string('StartupNotify=true\n')
	sb.write_string('StartupWMClass=${wm_class}\n')
	sb.write_string('X-Hornero-Kind=webapp\n')
	sb.write_string('X-Hornero-Id=${safe_id}\n')

	os.write_file(path, sb.str())!
	return DesktopAppEntry{
		id:        safe_id
		kind:      'webapp'
		name:      spec.name.trim_space()
		exec:      exec_cmd
		wm_class:  wm_class
		file_path: path
	}
}

// webapp_remove removes a Hornero-managed WebApp .desktop entry by id.
pub fn webapp_remove(id string) !string {
	path := desktop_file_path('webapp', id)!
	if !os.exists(path) {
		return error('webapp not found: ${id}')
	}
	os.rm(path)!
	return path
}

// tui_app_add writes a clean XDG .desktop entry for a TUI application.
pub fn tui_app_add(spec TuiAppSpec) !DesktopAppEntry {
	safe_id := validate_app_id(spec.id)!
	if spec.name.trim_space().len == 0 {
		return error('tui app name must not be empty')
	}
	if spec.command.trim_space().len == 0 {
		return error('tui app command must not be empty')
	}
	validate_desktop_field('name', spec.name)!
	validate_desktop_field('command', spec.command)!
	validate_desktop_field('icon', spec.icon)!

	terminal := if spec.terminal.trim_space().len > 0 {
		spec.terminal.trim_space()
	} else {
		'kitty'
	}
	validate_desktop_field('terminal', terminal)!
	cats := if spec.categories.trim_space().len > 0 {
		spec.categories.trim_space()
	} else {
		'Utility;ConsoleOnly;'
	}
	wm_class := 'hornero-tui-${safe_id}'
	exec_cmd := '${terminal} --class ${wm_class} -e ${spec.command.trim_space()}'

	dir := applications_dir()
	os.mkdir_all(dir)!
	path := desktop_file_path('tui', safe_id)!

	mut sb := strings.new_builder(256)
	sb.write_string('[Desktop Entry]\n')
	sb.write_string('Version=1.0\n')
	sb.write_string('Type=Application\n')
	sb.write_string('Name=${spec.name.trim_space()}\n')
	sb.write_string('Exec=${exec_cmd}\n')
	if spec.icon.trim_space().len > 0 {
		sb.write_string('Icon=${spec.icon.trim_space()}\n')
	}
	sb.write_string('Terminal=false\n')
	sb.write_string('Categories=${cats}\n')
	sb.write_string('StartupNotify=true\n')
	sb.write_string('StartupWMClass=${wm_class}\n')
	sb.write_string('X-Hornero-Kind=tui\n')
	sb.write_string('X-Hornero-Id=${safe_id}\n')

	os.write_file(path, sb.str())!
	return DesktopAppEntry{
		id:        safe_id
		kind:      'tui'
		name:      spec.name.trim_space()
		exec:      exec_cmd
		wm_class:  wm_class
		file_path: path
	}
}

// tui_app_remove removes a Hornero-managed TUI app .desktop entry by id.
pub fn tui_app_remove(id string) !string {
	path := desktop_file_path('tui', id)!
	if !os.exists(path) {
		return error('tui app not found: ${id}')
	}
	os.rm(path)!
	return path
}

fn parse_desktop_entry(path string, kind string) DesktopAppEntry {
	raw := os.read_file(path) or { '' }
	mut id := ''
	mut name := ''
	mut exec := ''
	mut wm_class := ''
	for line in raw.split_into_lines() {
		if line.starts_with('Name=') {
			name = line['Name='.len..]
		} else if line.starts_with('Exec=') {
			exec = line['Exec='.len..]
		} else if line.starts_with('StartupWMClass=') {
			wm_class = line['StartupWMClass='.len..]
		} else if line.starts_with('X-Hornero-Id=') {
			id = line['X-Hornero-Id='.len..]
		}
	}
	return DesktopAppEntry{
		id:        id
		kind:      kind
		name:      name
		exec:      exec
		wm_class:  wm_class
		file_path: path
	}
}

fn list_managed_apps(kind string) []DesktopAppEntry {
	dir := applications_dir()
	entries := os.ls(dir) or { return []DesktopAppEntry{} }
	prefix := if kind == 'webapp' { 'hornero-webapp-' } else { 'hornero-tui-' }
	mut out := []DesktopAppEntry{}
	for f in entries {
		if f.starts_with(prefix) && f.ends_with('.desktop') {
			out << parse_desktop_entry(os.join_path(dir, f), kind)
		}
	}
	out.sort(a.id < b.id)
	return out
}

// webapp_list returns all Hornero-managed WebApp .desktop entries.
pub fn webapp_list() []DesktopAppEntry {
	return list_managed_apps('webapp')
}

// tui_app_list returns all Hornero-managed TUI app .desktop entries.
pub fn tui_app_list() []DesktopAppEntry {
	return list_managed_apps('tui')
}
