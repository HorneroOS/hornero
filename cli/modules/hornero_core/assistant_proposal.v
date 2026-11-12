module hornero_core

import os

// Assistant shell/delegate proposals (Workflow D slice 1): pure, local,
// proposal-only helpers. Neither function executes anything, spawns a
// process, or grants an approval. A shell proposal is text for the user
// to inspect/edit/copy and run themselves (or route through the existing
// typed `assistant tool` broker); a delegate proposal is a handoff built
// on the dry-run `agent_launch_result`.

pub const assistant_proposal_requires = 'explicit manual run or existing typed broker approval'

fn proposal_tokens(command string) []string {
	mut out := []string{}
	for raw in command.to_lower().split_any(' \t\r\n;|&') {
		tok := raw.trim(' \t\r\n"\'`()<>')
		if tok.len > 0 {
			out << tok
		}
	}
	return out
}

fn proposal_has(tokens []string, words []string) bool {
	for t in tokens {
		// Match by basename too so /usr/bin/sudo counts as sudo.
		if t in words || t.split('/').last() in words {
			return true
		}
	}
	return false
}

fn proposal_has_prefix(tokens []string, prefixes []string) bool {
	for t in tokens {
		for p in prefixes {
			if t.starts_with(p) {
				return true
			}
		}
	}
	return false
}

// assistant_shell_risk classifies a proposed command conservatively:
// protected > privileged > mutating > read-only. Unknown verbs default
// to mutating so an unrecognised command is never called read-only.
pub fn assistant_shell_risk(command string) string {
	lower := command.to_lower()
	tokens := proposal_tokens(command)
	// Protected: credential stores, remote-code pipes, device/disk
	// destruction, and wiping root/home/system trees.
	if lower.contains('.ssh') || lower.contains('.gnupg')
		|| lower.contains('assistant.key') {
		return 'protected'
	}
	if (lower.contains('curl') || lower.contains('wget'))
		&& (lower.contains('| sh') || lower.contains('|sh') || lower.contains('| bash')
			|| lower.contains('|bash')) {
		return 'protected'
	}
	if proposal_has(tokens, ['mkfs', 'shred']) || lower.contains('mkfs.') {
		return 'protected'
	}
	if proposal_has(tokens, ['dd']) && lower.contains('of=/dev/') {
		return 'protected'
	}
	if proposal_has(tokens, ['rm']) && (lower.contains('--no-preserve-root')
		|| proposal_has(tokens, ['/', '/*', '~', '~/', '\$home', '/etc', '/usr', '/boot', '/var',
			'/bin', '/lib', '/lib64'])) {
		return 'protected'
	}
	// Privileged: elevation, package/service management, and writes or
	// permission changes on system paths.
	if proposal_has(tokens, ['sudo', 'doas', 'pkexec', 'reboot', 'shutdown', 'poweroff']) {
		return 'privileged'
	}
	if proposal_has(tokens, ['pacman']) {
		for t in tokens {
			if t.starts_with('-s') || t.starts_with('-u') || t.starts_with('-r')
				|| t == '--sync' || t == '--upgrade' || t == '--remove' {
				return 'privileged'
			}
		}
	}
	if proposal_has(tokens, ['systemctl']) {
		if proposal_has(tokens, ['status', 'show', 'is-active', 'is-enabled', 'list-units',
			'list-unit-files']) {
			// falls through: read-only unless chained with a mutation
			if !proposal_has(tokens, ['rm', 'mv', 'cp', 'tee']) && !lower.contains('>') {
				return 'read-only'
			}
		}
		return 'privileged'
	}
	// Device writes are destructive even without dd.
	if lower.contains('> /dev/') || lower.contains('>/dev/')
		|| lower.contains('of=/dev/') {
		return 'protected'
	}
	system_paths := ['/etc/', '/usr/', '/boot/', '/etc', '/usr', '/boot']
	if proposal_has_prefix(tokens, system_paths) || lower.contains('/etc/')
		|| lower.contains('/usr/') || lower.contains('/boot/') {
		// Any write-shaped verb, in-place edit, interpreter, or
		// redirection touching a system path is at least privileged.
		if proposal_has(tokens, ['chmod', 'chown', 'rm', 'mv', 'cp', 'tee', 'install', 'dd', 'ln',
			'mkdir', 'touch', 'truncate', 'sed', 'python3', 'python', 'perl', 'ruby', 'node', 'bash',
			'sh'])
			|| lower.contains('>') || lower.contains('-i') {
			return 'privileged'
		}
	}
	if proposal_has_prefix(tokens, ['/dev/'])
		&& proposal_has(tokens, ['rm', 'mv', 'cp', 'tee', 'install', 'dd', 'touch', 'truncate',
			'sed']) {
		return 'protected'
	}
	// Mutating: known write verbs, redirection, in-place edits.
	if proposal_has(tokens, ['rm', 'mv', 'cp', 'mkdir', 'touch', 'install', 'tee', 'chmod', 'chown',
		'ln', 'truncate', 'dd', 'kill', 'pkill', 'rename', 'rmdir', 'git']) {
		return 'mutating'
	}
	if lower.contains('>') || lower.contains('sed -i') || lower.contains('--in-place') {
		return 'mutating'
	}
	if proposal_has(tokens, ['ls', 'cat', 'grep', 'rg', 'find', 'echo', 'printf', 'pwd', 'whoami',
		'id', 'uname', 'hostname', 'date', 'env', 'printenv', 'head', 'tail', 'wc', 'sort', 'uniq',
		'diff', 'file', 'stat', 'du', 'df', 'free', 'ps', 'which', 'true', 'test', 'journalctl']) {
		return 'read-only'
	}
	return 'mutating'
}

// assistant_shell_proposal_result never executes `command`: it only
// classifies and echoes it back for manual inspection and execution.
pub fn assistant_shell_proposal_result(command string) CommandResult {
	if command.trim_space().len == 0 {
		return fail_result('assistant shell-proposal', 'Missing command. Example: horneroctl assistant shell-proposal --command "ls -la"')
	}
	risk := assistant_shell_risk(command)
	msg := 'Shell proposal only (nothing executed): ${command}\nRisk: ${risk}. Inspect, edit, or copy this command and run it yourself in a terminal if you want it executed, or use the existing typed broker: horneroctl assistant tool <name> [arg]. Requires: ${assistant_proposal_requires}.'
	return ok_result('assistant shell-proposal', msg, {
		'executed': 'false'
		'dry_run':  'true'
		'risk':     risk
		'command':  command
		'requires': assistant_proposal_requires
	})
}

// assistant_delegate_result builds a handoff proposal on the dry-run
// agent launch proposal. It fails closed on an unknown agent, a missing
// or non-directory workspace, or an empty task, and executes nothing.
pub fn assistant_delegate_result(agent_id string, workspace string, task string) CommandResult {
	id := agent_id.trim_space()
	spec := agent_by_id(id) or {
		return fail_result('assistant delegate', 'Unknown agent id: ${id}. Known: ${agent_ids().join(', ')}')
	}
	ws := workspace.trim_space()
	if ws.len == 0 {
		return fail_result('assistant delegate', 'Missing workspace. Example: horneroctl assistant delegate ${id} --workspace /path/to/dir "task"')
	}
	if !os.is_dir(ws) {
		return fail_result('assistant delegate', 'Workspace is not an existing directory: ${ws}')
	}
	if task.trim_space().len == 0 {
		return fail_result('assistant delegate', 'Missing task. Example: horneroctl assistant delegate ${id} --workspace ${ws} "describe the task"')
	}
	launch := agent_launch_result(spec.id)
	proposal := launch.data['proposal'] or { spec.exec }
	security := 'the external runtime (${spec.name}) keeps its OWN security model and does NOT inherit Hornero ABAC/bubblewrap/workspace policy'
	msg := "Delegate handoff proposal only (nothing executed): launch ${spec.name} (${spec.id}) yourself in a terminal in workspace ${ws} with task: ${task.trim_space()}\nWould launch: ${proposal}\nTruthful boundary: ${security}. Hornero records this proposal only; the user launches it in a terminal themselves and the external runtime's own approvals and sandbox apply."
	return ok_result('assistant delegate', msg, {
		'executed':                'false'
		'dry_run':                 'true'
		'agent':                   spec.id
		'id':                      spec.id
		'workspace':               ws
		'task':                    task.trim_space()
		'proposal':                proposal
		'external_security_model': security
		'requires':                assistant_proposal_requires
	})
}
