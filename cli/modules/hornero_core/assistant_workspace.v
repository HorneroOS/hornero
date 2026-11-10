module hornero_core

import crypto.rand
import os
import x.json2

// -- Javi workspaces ---------------------------------------------------------
// A workspace is the only filesystem scope the agent may write by default.
// Roots live under the XDG data dir (never $HOME itself), each with a stable
// id, purpose and instructions file. Registry: assistant_dir/workspaces.json
// (0600, outside the agent sandbox bind set, so the agent cannot rewrite
// its own scope).

pub struct AssistantWorkspace {
pub mut:
	id      string
	name    string
	root    string
	purpose string
	active  bool
}

pub fn assistant_workspaces_file() string {
	env := os.getenv('HORNERO_ASSISTANT_WORKSPACES_FILE')
	if env.len > 0 {
		return env
	}
	return os.join_path(assistant_dir(), 'workspaces.json')
}

pub fn assistant_workspaces_base() string {
	paths := resolve_paths()
	return os.join_path(paths.data_dir, 'hornero', 'javi-workspaces')
}

pub fn assistant_workspace_default() AssistantWorkspace {
	root := os.join_path(assistant_workspaces_base(), 'default')
	return AssistantWorkspace{
		id:      'default'
		name:    'Default'
		root:    root
		purpose: 'General Javi workspace'
		active:  true
	}
}

pub fn assistant_workspaces_load() []AssistantWorkspace {
	raw := os.read_file(assistant_workspaces_file()) or {
		return [assistant_workspace_default()]
	}
	decoded := json2.decode[json2.Any](raw) or { return [assistant_workspace_default()] }
	if decoded !is []json2.Any {
		return [assistant_workspace_default()]
	}
	mut out := []AssistantWorkspace{}
	for item in decoded.as_array() {
		if item !is map[string]json2.Any {
			continue
		}
		m := item.as_map()
		get := fn [m] (k string) string {
			if k in m && m[k] is string {
				return m[k].str()
			}
			return ''
		}
		out << AssistantWorkspace{
			id:      get('id')
			name:    get('name')
			root:    get('root')
			purpose: get('purpose')
			active:  'active' in m && m['active'] is bool && m['active'].bool()
		}
	}
	if out.len == 0 {
		return [assistant_workspace_default()]
	}
	return out
}

fn assistant_workspaces_save(list []AssistantWorkspace) ! {
	os.mkdir_all(os.dir(assistant_workspaces_file()))!
	mut arr := []json2.Any{}
	for w in list {
		arr << json2.Any({
			'id':      json2.Any(w.id)
			'name':    json2.Any(w.name)
			'root':    json2.Any(w.root)
			'purpose': json2.Any(w.purpose)
			'active':  json2.Any(w.active)
		})
	}
	os.write_file(assistant_workspaces_file(), json2.encode(arr, escape_unicode: true) + '\n')!
	os.chmod(assistant_workspaces_file(), 0o600) or {}
}

pub fn assistant_workspace_active() AssistantWorkspace {
	for w in assistant_workspaces_load() {
		if w.active {
			return w
		}
	}
	return assistant_workspace_default()
}

fn assistant_workspace_valid_id(id string) bool {
	if id.len == 0 || id.len > 64 {
		return false
	}
	for ch in id {
		if !(ch.is_letter() || ch.is_digit() || ch == `-` || ch == `_`) {
			return false
		}
	}
	return true
}

pub fn assistant_workspace_create_report(name string, dry_run bool, yes bool) CommandResult {
	if !yes && !dry_run {
		return fail_result('assistant workspace create', 'Creating a workspace needs --yes. Preview with --dry-run.')
	}
	raw := rand.bytes(6) or { return fail_result('assistant workspace create', 'Cannot generate workspace id.') }
	id := 'ws-' + raw.hex()
	root := os.join_path(assistant_workspaces_base(), id)
	if dry_run {
		return ok_result('assistant workspace create', 'Dry run: would create workspace ${id} at ${root}. Nothing written.', {
			'dryRun': 'true'
			'root':   root
		})
	}
	os.mkdir_all(root) or {
		return fail_result('assistant workspace create', 'Cannot create ${root}: ${err.msg()}')
	}
	os.write_file(os.join_path(root, 'AGENTS.md'), '# Javi workspace instructions\n\nFiles here are in scope for Javi. Nothing outside this directory is.\n') or {}
	mut list := assistant_workspaces_load()
	// Persist the implicit default before adding a second workspace.
	if list.len == 1 && list[0].id == 'default' && !os.exists(assistant_workspaces_file()) {
		os.mkdir_all(list[0].root) or {}
	}
	list << AssistantWorkspace{
		id:      id
		name:    if name.len > 0 { name } else { id }
		root:    root
		purpose: ''
	}
	assistant_workspaces_save(list) or {
		return fail_result('assistant workspace create', 'Cannot save registry: ${err.msg()}')
	}
	assistant_log_append('workspace.create', '', id, 'ok')
	return ok_result('assistant workspace create', 'Created workspace ${id} at ${root}. Reveal it with: horneroctl assistant workspace reveal --json', {
		'id':   id
		'root': root
	})
}

pub fn assistant_workspace_list_report() CommandResult {
	list := assistant_workspaces_load()
	mut lines := []string{}
	for w in list {
		lines << '${if w.active { '*' } else { ' ' }} ${w.id}  ${w.name}  ${w.root}'
	}
	return ok_result('assistant workspace', lines.join('\n'), {
		'count':  list.len.str()
		'active': assistant_workspace_active().id
	})
}

pub fn assistant_workspace_use_report(id string, yes bool) CommandResult {
	if !assistant_workspace_valid_id(id) {
		return fail_result('assistant workspace use', 'Invalid workspace id "${id}".')
	}
	if !yes {
		return fail_result('assistant workspace use', 'Switching the active workspace needs --yes.')
	}
	mut list := assistant_workspaces_load()
	mut found := false
	for mut w in list {
		w.active = w.id == id
		if w.active {
			found = true
		}
	}
	if !found {
		return fail_result('assistant workspace use', 'No workspace with id "${id}". List with: horneroctl assistant workspace list')
	}
	assistant_workspaces_save(list) or {
		return fail_result('assistant workspace use', 'Cannot save registry: ${err.msg()}')
	}
	assistant_log_append('workspace.use', '', id, 'ok')
	return ok_result('assistant workspace use', 'Active workspace is now ${id}. Sessions keep their own workspace association; no history was merged.', {
		'active': id
	})
}

pub fn assistant_workspace_reveal_report() CommandResult {
	w := assistant_workspace_active()
	return ok_result('assistant workspace reveal', w.root, {
		'id':   w.id
		'root': w.root
	})
}
