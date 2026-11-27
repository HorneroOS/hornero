module hornero_core

import os
import x.json2

// Bubblewrap (bwrap) argv builder and runner for isolating external coding/agent
// CLIs. Produces a shell-free argv slice so paths containing spaces or
// metacharacters are passed verbatim without word splitting or interpolation.

pub const agent_sandbox_excluded_home_paths = [
	'.ssh',
	'.gnupg',
	'.aws',
	'.config/gh',
]

pub const agent_sandbox_browser_home_paths = [
	'.mozilla',
	'.config/google-chrome',
	'.config/chromium',
	'.config/BraveSoftware',
]

pub struct AgentSandboxOptions {
pub:
	bwrap_bin        string = 'bwrap'
	no_net           bool
	allow_git_auth   bool
	home_dir         string
	resolved_exec    string
	agent_config_dir string
	extra_ro_binds   []string
	extra_rw_binds   []string
	extra_args       []string
}

pub struct AgentRunOptions {
pub:
	id             string
	sandbox        bool
	workspace      string
	no_net         bool
	allow_git_auth bool
	dry_run        bool
	extra_args     []string
}

fn is_under_path(candidate string, base string) bool {
	if candidate.len == 0 || base.len == 0 {
		return false
	}
	return candidate == base || candidate.starts_with('${base}/')
}

fn is_under_excluded_credential_path_opts(path string, home_dir string, allow_git_auth bool) bool {
	if home_dir.len == 0 {
		return false
	}
	clean_path := agent_config_canonical(path)
	clean_home := agent_config_canonical(home_dir).trim_right('/')
	for rel in agent_sandbox_excluded_home_paths {
		if allow_git_auth && rel in ['.ssh', '.config/gh'] {
			continue
		}
		cred := '${clean_home}/${rel}'
		if is_under_path(clean_path, cred) {
			return true
		}
	}
	for rel in agent_sandbox_browser_home_paths {
		browser_dir := '${clean_home}/${rel}'
		if is_under_path(clean_path, browser_dir) {
			return true
		}
	}
	return false
}

fn is_unsafe_agent_config_dir(dir string, clean_home string, clean_workspace string, allow_git_auth bool) bool {
	if dir.len == 0 || dir == '/' {
		return true
	}
	if clean_home.len > 0 {
		if dir == clean_home
			|| dir == os.join_path(clean_home, '.config')
			|| dir == os.join_path(clean_home, '.local')
			|| dir == os.join_path(clean_home, '.local', 'share') {
			return true
		}
		if is_under_excluded_credential_path_opts(dir, clean_home, allow_git_auth) {
			return true
		}
	}
	if dir == clean_workspace || is_under_path(clean_workspace, dir) {
		return true
	}
	return false
}

// build_agent_sandbox_argv constructs a bubblewrap command line that:
// - mounts /usr, /lib, /lib64, /bin, /sbin, and /etc read-only
// - isolates $HOME via an empty tmpfs mount
// - binds `workspace` read-write and sets it as the working directory
// - binds ONLY the agent's own config directory read-write when present
// - masks ~/.ssh, ~/.gnupg, ~/.aws, ~/.config/gh, and browser profiles with
//   empty tmpfs mounts and refuses to bind them into the sandbox (unless
//   `opts.allow_git_auth` explicitly grants read-only git auth)
// - optionally isolates networking via `--unshare-net` when `opts.no_net` is true
pub fn build_agent_sandbox_argv(spec AgentSpec, workspace string, opts AgentSandboxOptions) ![]string {
	if spec.exec.trim_space().len == 0 {
		return error('agent spec exec must not be empty')
	}
	if spec.exec.contains('\0') {
		return error('agent spec exec contains NUL byte')
	}
	if workspace.trim_space().len == 0 {
		return error('workspace path must not be empty')
	}
	if workspace.contains('\0') {
		return error('workspace path contains NUL byte')
	}

	home := if opts.home_dir.len > 0 { opts.home_dir } else { os.home_dir() }
	clean_home := if home.len > 0 { agent_config_canonical(home).trim_right('/') } else { '' }
	clean_workspace := agent_config_canonical(workspace).trim_right('/')

	if clean_workspace == '/' || clean_workspace.len == 0 {
		return error('workspace cannot be /')
	}
	if clean_home.len > 0 && (clean_workspace == clean_home
		|| is_under_path(clean_home, clean_workspace)) {
		return error('workspace cannot expose the entire home directory: ${workspace}')
	}
	if is_under_excluded_credential_path_opts(clean_workspace, clean_home, opts.allow_git_auth) {
		return error('workspace cannot point to an excluded credential directory: ${workspace}')
	}

	bwrap := if opts.bwrap_bin.trim_space().len > 0 { opts.bwrap_bin } else { 'bwrap' }
	mut argv := [
		bwrap,
		'--die-with-parent',
		'--unshare-pid',
		'--unshare-uts',
		'--unshare-ipc',
		'--proc',
		'/proc',
		'--dev',
		'/dev',
		'--tmpfs',
		'/tmp',
	]

	if opts.no_net {
		argv << '--unshare-net'
	}

	// System directories mounted read-only.
	argv << ['--ro-bind', '/usr', '/usr']
	argv << ['--ro-bind-try', '/lib', '/lib']
	argv << ['--ro-bind-try', '/lib64', '/lib64']
	argv << ['--ro-bind-try', '/bin', '/bin']
	argv << ['--ro-bind-try', '/sbin', '/sbin']
	argv << ['--ro-bind', '/etc', '/etc']

	// Isolate the home directory so browser profiles, dotfiles, and credentials
	// outside the workspace and agent config dir are invisible inside the cage.
	if clean_home.len > 0 {
		argv << ['--tmpfs', clean_home]
	}

	// If the resolved agent executable lives under the masked $HOME (e.g.
	// ~/.local/bin/...), expose the executable read-only so bwrap can exec it.
	if opts.resolved_exec.len > 0 && os.is_file(opts.resolved_exec) {
		canon_exec := agent_config_canonical(opts.resolved_exec)
		if clean_home.len > 0 && is_under_path(canon_exec, clean_home)
			&& !is_under_excluded_credential_path_opts(canon_exec, clean_home, opts.allow_git_auth) {
			argv << ['--ro-bind', canon_exec, canon_exec]
			real_exec := os.real_path(opts.resolved_exec)
			if real_exec != canon_exec && is_under_path(real_exec, clean_home)
				&& !is_under_excluded_credential_path_opts(real_exec, clean_home,
					opts.allow_git_auth) && os.exists(real_exec) {
				argv << ['--ro-bind', real_exec, real_exec]
			}
		}
	}

	// Bind ONLY the agent's own config directory read-write when it exists on host.
	raw_cfg_dir := if opts.agent_config_dir.len > 0 {
		opts.agent_config_dir
	} else if clean_home.len > 0 {
		agent_config_dir_for_home(spec, clean_home)
	} else {
		''
	}
	if raw_cfg_dir.len > 0 {
		canon_cfg := agent_config_canonical(raw_cfg_dir).trim_right('/')
		if os.is_dir(canon_cfg)
			&& !is_unsafe_agent_config_dir(canon_cfg, clean_home, clean_workspace,
				opts.allow_git_auth) {
			argv << ['--bind', canon_cfg, canon_cfg]
		}
	}

	// Explicit opt-in for git authentication: read-only SSH/gh/git config and
	// optional ssh-agent socket. GPG and AWS credentials remain strictly masked.
	if opts.allow_git_auth && clean_home.len > 0 {
		for rel in ['.ssh', '.config/gh', '.config/git'] {
			dir := os.join_path(clean_home, rel)
			if os.is_dir(dir) {
				argv << ['--ro-bind', dir, dir]
			}
		}
		gitconfig := os.join_path(clean_home, '.gitconfig')
		if os.is_file(gitconfig) {
			argv << ['--ro-bind', gitconfig, gitconfig]
		}
		ssh_sock := os.getenv('SSH_AUTH_SOCK')
		if ssh_sock.len > 0 && !ssh_sock.contains('\0') && os.exists(ssh_sock) {
			canon_sock := agent_config_canonical(ssh_sock)
			argv << ['--bind', canon_sock, canon_sock]
		}
	}

	// Workspace mounted read-write.
	argv << ['--bind', clean_workspace, clean_workspace]
	argv << ['--chdir', clean_workspace]

	for p in opts.extra_ro_binds {
		if p.len == 0 {
			continue
		}
		if p.contains('\0') {
			return error('extra ro bind contains NUL byte')
		}
		canon_p := agent_config_canonical(p)
		if is_under_excluded_credential_path_opts(canon_p, clean_home, opts.allow_git_auth) {
			return error('refusing to bind excluded credential path read-only: ${p}')
		}
		argv << ['--ro-bind', canon_p, canon_p]
	}
	for p in opts.extra_rw_binds {
		if p.len == 0 {
			continue
		}
		if p.contains('\0') {
			return error('extra rw bind contains NUL byte')
		}
		canon_p := agent_config_canonical(p)
		if is_under_excluded_credential_path_opts(canon_p, clean_home, opts.allow_git_auth) {
			return error('refusing to bind excluded credential path read-write: ${p}')
		}
		argv << ['--bind', canon_p, canon_p]
	}

	// Explicitly mask sensitive host credential and browser directories with empty tmpfs mounts.
	if clean_home.len > 0 {
		for rel in agent_sandbox_excluded_home_paths {
			if opts.allow_git_auth && rel in ['.ssh', '.config/gh'] {
				continue
			}
			argv << ['--tmpfs', '${clean_home}/${rel}']
		}
		for rel in agent_sandbox_browser_home_paths {
			argv << ['--tmpfs', '${clean_home}/${rel}']
		}
	}

	exec_bin := if opts.resolved_exec.len > 0 { opts.resolved_exec } else { spec.exec }
	argv << '--'
	argv << exec_bin
	for a in opts.extra_args {
		if a.contains('\0') {
			return error('extra argument contains NUL byte')
		}
		argv << a
	}
	return argv
}

// agent_run_result builds (and unless dry_run is set, executes) a registered
// agent CLI inside a bubblewrap workspace cage via literal argv vectors.
pub fn agent_run_result(opts AgentRunOptions) CommandResult {
	spec := agent_by_id(opts.id) or {
		return fail_result('agent run', 'Unknown agent id: ${opts.id}. Known: ${agent_ids().join(', ')}')
	}
	if !opts.sandbox {
		return fail_result('agent run', 'Refusing to run ${opts.id} unsandboxed: pass --sandbox (or use `horneroctl agent launch ${opts.id}` for a dry-run proposal).')
	}
	workspace := if opts.workspace.trim_space().len > 0 { opts.workspace } else { os.getwd() }
	st := agent_probe(spec)
	found_bwrap := find_on_path('bwrap')
	bwrap_bin := if found_bwrap.len > 0 { found_bwrap } else { 'bwrap' }
	exec_bin := if st.installed { st.resolved_path } else { spec.exec }

	argv := build_agent_sandbox_argv(spec, workspace, AgentSandboxOptions{
		bwrap_bin:      bwrap_bin
		no_net:         opts.no_net
		allow_git_auth: opts.allow_git_auth
		resolved_exec:  st.resolved_path
		extra_args:     opts.extra_args
	}) or { return fail_result('agent run', err.msg()) }

	cmd_line := command_line(argv[0], argv[1..])
	argv_json := json2.encode(argv, escape_unicode: true)
	mut data := {
		'id':             spec.id
		'exec':           exec_bin
		'installed':      '${st.installed}'
		'sandbox':        'true'
		'bwrap':          bwrap_bin
		'workspace':      agent_config_canonical(workspace)
		'no_net':         '${opts.no_net}'
		'allow_git_auth': '${opts.allow_git_auth}'
		'dry_run':        '${opts.dry_run}'
		'executed':       'false'
		'command_line':   cmd_line
		'argv_json':      argv_json
		'argv_count':     '${argv.len}'
	}

	if opts.dry_run {
		mut note := 'Dry run: would execute sandboxed ${spec.id} via bwrap; nothing was executed.'
		if !st.installed {
			note = '${spec.exec} is not on PATH. ' + note
		}
		return ok_result('agent run', '${note}\nCommand: ${cmd_line}', data)
	}

	if found_bwrap.len == 0 {
		return fail_result_data('agent run', 'bubblewrap (bwrap) was not found on PATH; install bubblewrap or preview with --dry-run.',
			data)
	}
	if !st.installed {
		return fail_result_data('agent run', '${spec.exec} is not on PATH. Install source: ${spec.install_source}',
			data)
	}
	if !os.is_dir(workspace) {
		return fail_result_data('agent run', 'workspace directory does not exist: ${workspace}',
			data)
	}

	rep := run_exec(ExecSpec{
		prog:    argv[0]
		args:    argv[1..]
		dry_run: false
	})
	data['executed'] = 'true'
	data['exit_code'] = '${rep.exit_code}'
	if rep.output.len > 0 {
		data['output'] = rep.output
	}
	if rep.ok {
		msg := if rep.output.len > 0 {
			rep.output
		} else {
			'Sandboxed ${spec.id} exited cleanly (code 0).'
		}
		return ok_result('agent run', msg, data)
	}
	err_msg := if rep.output.len > 0 {
		rep.output
	} else {
		'Sandboxed ${spec.id} exited with code ${rep.exit_code}.'
	}
	return fail_result_data('agent run', err_msg, data)
}
