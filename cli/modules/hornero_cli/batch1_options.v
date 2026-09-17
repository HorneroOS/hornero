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

// PackageCmdOptions covers `package <check|updates|upgrade|deps>`.
// `check`/`updates` are read-only; `upgrade`/`deps --install` mutate.
pub struct PackageCmdOptions {
pub:
	leaf     string // check | updates | upgrade | deps
	dry_run  bool
	yes      bool
	install  bool // deps --install
	optional bool // deps --optional (include dev/media/AI groups)
}

pub fn parse_package_cmd(args []string) !PackageCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl package check')
	}
	leaf := args[0]
	if leaf !in ['check', 'updates', 'upgrade', 'deps'] {
		return error('unknown package subcommand: ${leaf}.\nRun: horneroctl package --help')
	}
	mut dry_run := false
	mut yes := false
	mut install := false
	mut optional := false
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
		if a == '--install' {
			install = true
			continue
		}
		if a == '--optional' {
			optional = true
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl package ${leaf} --dry-run')
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl package --help')
	}
	if leaf in ['check', 'updates'] && (yes || install || optional) {
		return error('package ${leaf} takes no --yes/--install/--optional.\nExample: horneroctl package ${leaf} --dry-run')
	}
	if leaf == 'upgrade' && (install || optional) {
		return error('package upgrade takes no --install/--optional.\nExample: horneroctl package upgrade --dry-run')
	}
	if leaf == 'deps' && !install && yes {
		return error('package deps check takes no --yes.\nExample: horneroctl package deps --optional')
	}
	return PackageCmdOptions{
		leaf:     leaf
		dry_run:  dry_run
		yes:      yes
		install:  install
		optional: optional
	}
}

// BackupCmdOptions covers `backup <list|schedule|create|restore>`.
// `list`/`schedule` are read-only; `create`/`restore` mutate.
pub struct BackupCmdOptions {
pub:
	leaf    string // list | schedule | create | restore
	id      string // restore target | create --name value
	is_name bool   // id came from --name (create) vs positional (restore)
	dry_run bool
	yes     bool
}

pub fn parse_backup_cmd(args []string) !BackupCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl backup list')
	}
	leaf := args[0]
	if leaf !in ['list', 'schedule', 'create', 'restore'] {
		return error('unknown backup subcommand: ${leaf}.\nRun: horneroctl backup --help')
	}
	if leaf in ['list', 'schedule'] {
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
	mut id := ''
	mut is_name := false
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
		if a == '--name' {
			if leaf != 'create' {
				return error('--name belongs to backup create.\nExample: horneroctl backup create --name my_backup --dry-run')
			}
			if i + 1 >= args.len || args[i + 1].starts_with('-') || args[i + 1].len == 0 {
				return error('missing value for --name.\nExample: horneroctl backup create --name my_backup --dry-run')
			}
			id = args[i + 1]
			is_name = true
			i += 2
			continue
		}
		if a.starts_with('--name=') {
			if leaf != 'create' {
				return error('--name belongs to backup create.\nExample: horneroctl backup create --name my_backup --dry-run')
			}
			id = a.all_after('=')
			if id.len == 0 {
				return error('missing value for --name.\nExample: horneroctl backup create --name my_backup --dry-run')
			}
			is_name = true
			i++
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl backup ${leaf} --dry-run')
		}
		if leaf == 'create' {
			return error('backup create takes no positional arguments (use --name).\nExample: horneroctl backup create --name my_backup --dry-run')
		}
		if id.len > 0 {
			return error('unexpected argument: ${a}.\nRun: horneroctl backup --help')
		}
		id = a
		i++
	}
	if leaf == 'restore' && id.len == 0 {
		return error('missing backup id.\nExample: horneroctl backup restore dotfiles_backup --dry-run')
	}
	return BackupCmdOptions{
		leaf:    leaf
		id:      id
		is_name: is_name
		dry_run: dry_run
		yes:     yes
	}
}
