module hornero_cli

// Batch-1 option parsers: `config snapshot`, `package`, `backup`.
// Error strings always carry a correct Example (exit-2 contract) and
// deferrals name the missing backend instead of inventing behavior.

// ConfigSnapshotOptions covers `config snapshot <create|list|restore>`.
pub struct ConfigSnapshotOptions {
pub:
	leaf    string // create | list | restore
	id      string
	dry_run bool
	yes     bool
}

pub fn parse_config_snapshot(args []string) !ConfigSnapshotOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl config snapshot list')
	}
	leaf := args[0]
	if leaf !in ['create', 'list', 'restore'] {
		return error('unknown snapshot subcommand: ${leaf}.\nRun: horneroctl config snapshot --help')
	}
	mut id := ''
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
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl config snapshot list')
		}
		if id.len > 0 {
			return error('unexpected argument: ${a}.\nRun: horneroctl config snapshot --help')
		}
		id = a
		i++
	}
	if leaf == 'restore' && id.len == 0 {
		return error('missing snapshot id.\nExample: horneroctl config snapshot restore config_20260101_020000 --dry-run')
	}
	if leaf == 'create' && id.len > 0 {
		return error('unexpected argument: ${id}.\nRun: horneroctl config snapshot --help')
	}
	if leaf == 'list' && (id.len > 0 || dry_run || yes) {
		return error('snapshot list takes no arguments.\nExample: horneroctl config snapshot list')
	}
	return ConfigSnapshotOptions{
		leaf:    leaf
		id:      id
		dry_run: dry_run
		yes:     yes
	}
}

// PackageCmdOptions covers `package <check|updates>` (read-only).
pub struct PackageCmdOptions {
pub:
	leaf    string // check | updates
	dry_run bool
}

pub fn parse_package_cmd(args []string) !PackageCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl package check')
	}
	leaf := args[0]
	if leaf in ['upgrade', 'deps'] {
		return error('package ${leaf} needs a pinned backend (polkit privilege for upgrade, installer for deps).\nRun: horneroctl package --help')
	}
	if leaf !in ['check', 'updates'] {
		return error('unknown package subcommand: ${leaf}.\nRun: horneroctl package --help')
	}
	mut dry_run := false
	for i := 1; i < args.len; i++ {
		a := args[i]
		if a == '--dry-run' {
			dry_run = true
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl package check --dry-run')
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl package --help')
	}
	return PackageCmdOptions{
		leaf:    leaf
		dry_run: dry_run
	}
}

// BackupCmdOptions covers `backup <list|schedule>` (read-only).
pub struct BackupCmdOptions {
pub:
	leaf string // list | schedule
}

pub fn parse_backup_cmd(args []string) !BackupCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl backup list')
	}
	leaf := args[0]
	if leaf in ['create', 'restore'] {
		return error('backup ${leaf} needs a pinned non-interactive backend (legacy flows prompt).\nRun: horneroctl backup --help')
	}
	if leaf !in ['list', 'schedule'] {
		return error('unknown backup subcommand: ${leaf}.\nRun: horneroctl backup --help')
	}
	if args.len > 1 {
		if args[1].starts_with('-') {
			return error('unknown flag: ${args[1]}.\nExample: horneroctl backup ${leaf}')
		}
		return error('unexpected argument: ${args[1]}.\nExample: horneroctl backup ${leaf}')
	}
	return BackupCmdOptions{
		leaf: leaf
	}
}
