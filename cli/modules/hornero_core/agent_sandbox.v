module hornero_core

import os

// Bubblewrap (bwrap) argv builder for isolating external coding/agent CLIs.
// Produces a shell-free argv slice so paths containing spaces or metacharacters
// are passed verbatim without word splitting or interpolation.

pub const agent_sandbox_excluded_home_paths = [
	'.ssh',
	'.gnupg',
	'.aws',
	'.config/gh',
]

pub struct AgentSandboxOptions {
pub:
	bwrap_bin      string = 'bwrap'
	no_net         bool
	home_dir       string
	extra_ro_binds []string
	extra_rw_binds []string
	extra_args     []string
}

fn is_under_excluded_credential_path(path string, home_dir string) bool {
	if home_dir.len == 0 {
		return false
	}
	clean_path := os.real_path(path)
	clean_home := os.real_path(home_dir).trim_right('/')
	for rel in agent_sandbox_excluded_home_paths {
		cred := '${clean_home}/${rel}'
		if clean_path == cred || clean_path.starts_with('${cred}/') {
			return true
		}
	}
	return false
}

// build_agent_sandbox_argv constructs a bubblewrap command line that:
// - mounts /usr, /lib, /lib64, /bin, /sbin, and /etc read-only
// - binds `workspace` read-write and sets it as the working directory
// - masks ~/.ssh, ~/.gnupg, ~/.aws, and ~/.config/gh with empty tmpfs mounts
//   and refuses to bind them into the sandbox
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
	clean_home := home.trim_right('/')

	if is_under_excluded_credential_path(workspace, clean_home) {
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

	// Workspace mounted read-write.
	argv << ['--bind', workspace, workspace]
	argv << ['--chdir', workspace]

	for p in opts.extra_ro_binds {
		if p.len == 0 {
			continue
		}
		if is_under_excluded_credential_path(p, clean_home) {
			return error('refusing to bind excluded credential path read-only: ${p}')
		}
		argv << ['--ro-bind', p, p]
	}
	for p in opts.extra_rw_binds {
		if p.len == 0 {
			continue
		}
		if is_under_excluded_credential_path(p, clean_home) {
			return error('refusing to bind excluded credential path read-write: ${p}')
		}
		argv << ['--bind', p, p]
	}

	// Explicitly mask sensitive host credential directories with empty tmpfs mounts.
	if clean_home.len > 0 {
		for rel in agent_sandbox_excluded_home_paths {
			argv << ['--tmpfs', '${clean_home}/${rel}']
		}
	}

	argv << '--'
	argv << spec.exec
	for a in opts.extra_args {
		argv << a
	}
	return argv
}
