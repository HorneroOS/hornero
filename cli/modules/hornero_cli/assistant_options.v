module hornero_cli

pub struct AssistantCmdOptions {
pub:
	leaf    string
	value   string
	arg1    string
	arg2    string
	dry_run bool
	yes     bool
	stream  bool
	attach  []string
	session string
}

pub fn parse_assistant(args []string) !AssistantCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl assistant status')
	}
	leaf := args[0]
	if leaf !in ['status', 'health', 'enable', 'disable', 'tools', 'knowledge', 'sessions', 'model', 'ask',
		'stop', 'approve', 'clarify', 'events'] {
		return error('unknown assistant subcommand: ${leaf}.\nRun: horneroctl assistant --help')
	}
	mut parts := []string{}
	mut dry_run := false
	mut yes := false
	mut stream := false
	mut attach := []string{}
	mut session := ''
	mut i := 1
	for i < args.len {
		arg := args[i]
		i++
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
	if leaf in ['status', 'tools', 'knowledge'] && value.len > 0 {
		return error('unexpected argument: ${value}.\nExample: horneroctl assistant ${leaf}')
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
	return AssistantCmdOptions{
		leaf:    leaf
		value:   value
		arg1:    if parts.len > 0 { parts[0] } else { '' }
		arg2:    if parts.len > 1 { parts[1..].join(' ') } else { '' }
		dry_run: dry_run
		yes:     yes
		stream:  stream
		attach:  attach
		session: session
	}
}
