module hornero_cli

// Power/lock option parsers: `power <lock|suspend|reboot|shutdown|logout|
// status>` and `lock <now|status>`. Error strings always carry a correct
// Example (exit-2 contract). Only status is read-only; every other leaf is
// mutating (needs --yes, --dry-run previews).

// PowerCmdOptions covers `power <leaf>`.
pub struct PowerCmdOptions {
pub:
	leaf    string // lock | suspend | reboot | shutdown | logout | status
	dry_run bool
	yes     bool
}

pub fn parse_power_cmd(args []string) !PowerCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl power status')
	}
	leaf := args[0]
	if leaf !in ['lock', 'suspend', 'reboot', 'shutdown', 'logout', 'status'] {
		return error('unknown power subcommand: ${leaf}.\nRun: horneroctl power --help')
	}
	mut dry_run := false
	mut yes := false
	for i := 1; i < args.len; i++ {
		a := args[i]
		if a == '--dry-run' {
			dry_run = true
			continue
		}
		if a == '--yes' {
			yes = true
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl power ${leaf} --dry-run')
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl power --help')
	}
	if leaf == 'status' && (dry_run || yes) {
		return error('power status takes no flags.\nExample: horneroctl power status')
	}
	return PowerCmdOptions{
		leaf:    leaf
		dry_run: dry_run
		yes:     yes
	}
}

// LockCmdOptions covers `lock <now|status>`.
pub struct LockCmdOptions {
pub:
	leaf    string // now | status
	dry_run bool
	yes     bool
}

pub fn parse_lock_cmd(args []string) !LockCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl lock status')
	}
	leaf := args[0]
	if leaf !in ['now', 'status'] {
		return error('unknown lock subcommand: ${leaf}.\nRun: horneroctl lock --help')
	}
	mut dry_run := false
	mut yes := false
	for i := 1; i < args.len; i++ {
		a := args[i]
		if a == '--dry-run' {
			dry_run = true
			continue
		}
		if a == '--yes' {
			yes = true
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl lock ${leaf} --dry-run')
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl lock --help')
	}
	if leaf == 'status' && (dry_run || yes) {
		return error('lock status takes no flags.\nExample: horneroctl lock status')
	}
	return LockCmdOptions{
		leaf:    leaf
		dry_run: dry_run
		yes:     yes
	}
}
