module hornero_cli

import hornero_core

// Mode option parser: `mode <list|get|set|reset|status> ...`.
// Error strings always carry a correct Example (exit-2 contract).
// Switching modes is reversible (`mode set everyday`) and only asks the
// shell, so set needs no --yes (like `welcome open`). reset also reapplies
// the factory layout and theme, so it needs --yes or --dry-run.

pub struct ModeCmdOptions {
pub:
	action  string // list | get | set | reset | status
	mode    string // set: target mode id
	dry_run bool
	yes     bool
}

pub fn parse_mode(args []string) !ModeCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl mode get')
	}
	action := args[0]
	if action !in ['list', 'get', 'set', 'reset', 'status'] {
		return error('unknown mode subcommand: ${action}.\nRun: horneroctl mode --help')
	}
	mut value := ''
	mut dry_run := false
	mut yes := false
	for a in args[1..] {
		if a == '--dry-run' {
			dry_run = true
			continue
		}
		if a == '--yes' {
			yes = true
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl mode ${action} --dry-run')
		}
		if value.len > 0 {
			return error('unexpected argument: ${a}.\nRun: horneroctl mode --help')
		}
		value = a
	}
	if action == 'set' {
		if value.len == 0 {
			return error('missing mode (${hornero_core.experience_modes.join('|')}).\nExample: horneroctl mode set signal --dry-run')
		}
		if yes {
			return error('mode set needs no --yes (it only asks the shell; undo with mode set <previous>).\nExample: horneroctl mode set signal --dry-run')
		}
	} else if value.len > 0 {
		return error('mode ${action} takes no arguments.\nExample: horneroctl mode ${action}')
	}
	if action != 'reset' && yes {
		return error('mode ${action} needs no --yes.\nExample: horneroctl mode ${action}')
	}
	return ModeCmdOptions{
		action:  action
		mode:    value
		dry_run: dry_run
		yes:     yes
	}
}
