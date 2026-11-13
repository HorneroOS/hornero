module hornero_cli

pub struct AssistantCmdOptions {
pub:
	leaf           string
	value          string
	arg1           string
	arg2           string
	parts          []string
	dry_run        bool
	yes            bool
	remove         bool
	adopt_dotfiles bool
	stream         bool
	attach         []string
	session        string
	mode           string
	filter         string
	command        string
	has_command    bool
	workspace      string
}

pub fn parse_assistant(args []string) !AssistantCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl assistant status')
	}
	leaf := args[0]
	if leaf !in ['status', 'health', 'enable', 'disable', 'tools', 'knowledge', 'sessions', 'model',
		'ask', 'stop', 'approve', 'clarify', 'events', 'log', 'gateway', 'setup', 'usage', 'policy',
		'workspace', 'profile', 'prompt', 'tool', 'shell-proposal', 'delegate'] {
		return error('unknown assistant subcommand: ${leaf}.\nRun: horneroctl assistant --help')
	}
	mut parts := []string{}
	mut dry_run := false
	mut yes := false
	mut remove := false
	mut adopt_dotfiles := false
	mut stream := false
	mut attach := []string{}
	mut session := ''
	mut mode := ''
	mut filter := ''
	mut command := ''
	mut has_command := false
	mut workspace := ''
	mut i := 1
	for i < args.len {
		arg := args[i]
		i++
		if arg == '--mode' {
			if i >= args.len {
				return error('--mode needs ask, agent or chat.\nExample: horneroctl assistant ask "hi" --mode ask')
			}
			mode = args[i]
			i++
			if mode !in ['ask', 'agent', 'chat'] {
				return error('--mode must be ask, agent or chat (ask is read-only).\nExample: horneroctl assistant ask "hi" --mode ask')
			}
			continue
		}
		if arg == '--command' {
			if i >= args.len {
				return error('--command needs a command string.\nExample: horneroctl assistant shell-proposal --command "ls -la"')
			}
			command = args[i]
			has_command = true
			i++
			continue
		}
		if arg == '--workspace' {
			if i >= args.len {
				return error('--workspace needs a directory.\nExample: horneroctl assistant delegate codex --workspace /tmp "task"')
			}
			workspace = args[i]
			i++
			continue
		}
		if arg == '--filter' {
			if i >= args.len {
				return error('--filter needs a search text.\nExample: horneroctl assistant log --filter deny')
			}
			filter = args[i]
			i++
			continue
		}
		if arg == '--session' {
			if i >= args.len {
				return error('--session needs a chat id.\nExample: horneroctl assistant ask "hi" --session s123')
			}
			session = args[i]
			i++
			continue
		}
		if arg == '--attach' {
			if i >= args.len {
				return error('--attach needs a file path.\nExample: horneroctl assistant ask "look" --attach ~/shot.png')
			}
			attach << args[i]
			i++
			continue
		}
		if arg == '--dry-run' {
			dry_run = true
			continue
		}
		if arg == '--yes' {
			yes = true
			continue
		}
		if arg == '--remove' {
			remove = true
			continue
		}
		if arg == '--adopt-dotfiles' {
			adopt_dotfiles = true
			continue
		}
		if arg == '--stream' {
			stream = true
			continue
		}
		if arg.starts_with('-') {
			return error('unknown flag: ${arg}.\nExample: horneroctl assistant enable --dry-run')
		}
		parts << arg
	}
	value := parts.join(' ')
	if leaf == 'ask' && value.len == 0 {
		return error('missing prompt.\nExample: horneroctl assistant ask "what updates are available?"')
	}
	if leaf == 'stop' && value.len == 0 {
		return error('missing run id.\nExample: horneroctl assistant stop run_abc123')
	}
	if leaf == 'events' && value.len == 0 {
		return error('missing run id.\nExample: horneroctl assistant events run_abc123')
	}
	if leaf == 'approve' && parts.len != 2 {
		return error('expected a run id and a decision.\nExample: horneroctl assistant approve run_abc123 approve')
	}
	if leaf == 'approve' && parts[1] !in ['approve', 'deny'] {
		return error('decision must be approve or deny.\nExample: horneroctl assistant approve run_abc123 deny')
	}
	if leaf == 'clarify' && parts.len < 2 {
		return error('expected a run id and answer text.\nExample: horneroctl assistant clarify run_abc123 "use the dark theme"')
	}
	if leaf == 'gateway' && parts.len > 0 && parts[0] !in ['start', 'stop', 'status'] {
		return error('unknown gateway action: ${parts[0]}.\nExample: horneroctl assistant gateway start --yes')
	}
	if leaf == 'gateway' && parts.len > 1 {
		return error('gateway ${parts[0]} takes no extra argument.\nExample: horneroctl assistant gateway ${parts[0]}')
	}
	if leaf in ['status', 'tools', 'usage'] && value.len > 0 {
		return error('unexpected argument: ${value}.\nExample: horneroctl assistant ${leaf}')
	}
	if leaf == 'knowledge' && parts.len > 0 {
		if parts[0] != 'vault' || parts.len > 2
			|| (parts.len == 2 && parts[1] !in ['generate', 'check', 'status']) {
			return error('unknown knowledge action: ${value}.\nExample: horneroctl assistant knowledge vault generate --yes')
		}
	}
	if mode.len > 0 && leaf !in ['ask', 'sessions'] {
		return error('--mode only applies to ask and sessions.\nExample: horneroctl assistant sessions new "Quick" --mode ask')
	}
	if filter.len > 0 && leaf != 'log' {
		return error('--filter only applies to log.\nExample: horneroctl assistant log --filter deny')
	}
	if session.len > 0 && leaf != 'ask' {
		return error('--session only applies to ask.\nExample: horneroctl assistant ask "hi" --session s123')
	}
	if attach.len > 0 && leaf != 'ask' {
		return error('--attach only applies to ask.\nExample: horneroctl assistant ask "look at this" --attach ~/shot.png')
	}
	if stream && leaf !in ['ask', 'events'] {
		return error('--stream only applies to ask and events.\nExample: horneroctl assistant ask "hi" --stream')
	}
	if dry_run && yes {
		return error('--dry-run and --yes are mutually exclusive.\nExample: horneroctl assistant enable --dry-run')
	}
	if remove && leaf != 'setup' {
		return error('--remove only applies to setup.\nExample: horneroctl assistant setup --remove --yes')
	}
	if adopt_dotfiles && leaf != 'setup' {
		return error('--adopt-dotfiles only applies to setup.\nExample: horneroctl assistant setup --adopt-dotfiles --dry-run')
	}
	if remove && adopt_dotfiles {
		return error('--remove and --adopt-dotfiles are separate setup operations.\nExample: horneroctl assistant setup --adopt-dotfiles --dry-run')
	}
	if leaf == 'setup' && value.len > 0 {
		return error('setup takes no argument.\nExample: horneroctl assistant setup --dry-run')
	}
	if has_command && leaf != 'shell-proposal' {
		return error('--command only applies to shell-proposal.\nExample: horneroctl assistant shell-proposal --command "ls -la"')
	}
	if workspace.len > 0 && leaf != 'delegate' {
		return error('--workspace only applies to delegate.\nExample: horneroctl assistant delegate codex --workspace /tmp "task"')
	}
	if leaf == 'shell-proposal' {
		if !has_command {
			return error('missing --command.\nExample: horneroctl assistant shell-proposal --command "ls -la"')
		}
		if value.len > 0 {
			return error('shell-proposal takes no positional argument; use --command.\nExample: horneroctl assistant shell-proposal --command "ls -la"')
		}
	}
	if leaf == 'delegate' && parts.len == 0 {
		return error('missing agent id.\nExample: horneroctl assistant delegate codex --workspace /tmp "task"')
	}
	return AssistantCmdOptions{
		leaf:           leaf
		value:          value
		arg1:           if parts.len > 0 { parts[0] } else { '' }
		arg2:           if parts.len > 1 { parts[1..].join(' ') } else { '' }
		parts:          parts
		dry_run:        dry_run
		yes:            yes
		remove:         remove
		adopt_dotfiles: adopt_dotfiles
		stream:         stream
		attach:         attach
		session:        session
		mode:           mode
		filter:         filter
		command:        command
		has_command:    has_command
		workspace:      workspace
	}
}
