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

// LockCmdOptions covers `lock <now|status|update>`.
pub struct LockCmdOptions {
pub:
	leaf    string // now | status | update
	effect  string // `now --effect`: dim | blur | dimblur | pixel
	path    string // `update [path]`
	dim     int    // `update --dim`: 0-100
	blur    int    // `update --blur`: >= 0
	pixel   int    // `update --pixel`: >= 1
	dry_run bool
	yes     bool
}

pub fn parse_lock_cmd(args []string) !LockCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl lock status')
	}
	leaf := args[0]
	if leaf !in ['now', 'status', 'update'] {
		return error('unknown lock subcommand: ${leaf}.\nRun: horneroctl lock --help')
	}
	mut effect := ''
	mut path := ''
	mut dim := 40
	mut blur := 5
	mut pixel := 10
	mut dry_run := false
	mut yes := false
	mut i := 1
	for i < args.len {
		a := args[i]
		if a == '--dry-run' {
			dry_run = true
			i++
			continue
		}
		if a == '--yes' {
			yes = true
			i++
			continue
		}
		if a == '--effect' {
			if leaf != 'now' {
				return error('lock ${leaf} takes no --effect.\nExample: horneroctl lock now --effect blur --dry-run')
			}
			if i + 1 >= args.len {
				return error('missing value for --effect.\nExample: horneroctl lock now --effect blur --dry-run')
			}
			effect = args[i + 1]
			if effect !in ['dim', 'blur', 'dimblur', 'pixel'] {
				return error('unknown effect: ${effect} (want dim, blur, dimblur, or pixel).\nExample: horneroctl lock now --effect blur --dry-run')
			}
			i += 2
			continue
		}
		if a == '--dim' || a == '--blur' || a == '--pixel' {
			if leaf != 'update' {
				return error('lock ${leaf} takes no ${a}.\nExample: horneroctl lock update --dry-run')
			}
			if i + 1 >= args.len {
				return error('missing value for ${a}.\nExample: horneroctl lock update ${a} 5 --dry-run')
			}
			raw := args[i + 1].trim_space()
			mut numeric := raw.len > 0
			for j, ch in raw {
				if !ch.is_digit() && !(j == 0 && ch == `-`) {
					numeric = false
				}
			}
			if !numeric {
				return error('invalid number for ${a}: `${args[i + 1]}`.\nExample: horneroctl lock update ${a} 5 --dry-run')
			}
			n := raw.int()
			if a == '--dim' {
				if n < 0 || n > 100 {
					return error('invalid --dim ${n} (want 0-100).\nExample: horneroctl lock update --dim 40 --dry-run')
				}
				dim = n
			} else if a == '--blur' {
				if n < 0 {
					return error('invalid --blur ${n} (want >= 0).\nExample: horneroctl lock update --blur 5 --dry-run')
				}
				blur = n
			} else {
				if n < 1 {
					return error('invalid --pixel ${n} (want >= 1).\nExample: horneroctl lock update --pixel 10 --dry-run')
				}
				pixel = n
			}
			i += 2
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl lock ${leaf} --dry-run')
		}
		if leaf != 'update' || path.len > 0 {
			return error('unexpected argument: ${a}.\nRun: horneroctl lock --help')
		}
		path = a
		i++
	}
	if leaf == 'status' && (dry_run || yes) {
		return error('lock status takes no flags.\nExample: horneroctl lock status')
	}
	return LockCmdOptions{
		leaf:    leaf
		effect:  effect
		path:    path
		dim:     dim
		blur:    blur
		pixel:   pixel
		dry_run: dry_run
		yes:     yes
	}
}
