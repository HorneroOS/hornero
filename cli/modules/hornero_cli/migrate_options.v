module hornero_cli

// Migrate option parser: `config migrate [--dry-run] [--yes] [--helper PATH]`.
// Error strings always carry a correct Example (exit-2 contract).
// --helper selects the migrate-to-hornero.sh backend explicitly
// (HORNERO_MIGRATE_BIN is the environment equivalent); it travels to the
// core helper slot and never to the backend command line.

// MigrateCmdOptions covers `config migrate` (mutating: needs --yes,
// --dry-run previews the backend invocation without running it).
pub struct MigrateCmdOptions {
pub:
	dry_run bool
	yes     bool
	helper  string
}

pub fn parse_migrate_cmd(args []string) !MigrateCmdOptions {
	mut dry_run := false
	mut yes := false
	mut helper := ''
	mut i := 0
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
		if a == '--helper' {
			if i + 1 >= args.len || args[i + 1].starts_with('-') || args[i + 1].len == 0 {
				return error('missing value for --helper.\nExample: horneroctl config migrate --dry-run --helper /tmp/migrate-to-hornero.sh')
			}
			helper = args[i + 1]
			i += 2
			continue
		}
		if a.starts_with('--helper=') {
			helper = a.all_after('=')
			if helper.len == 0 {
				return error('missing value for --helper.\nExample: horneroctl config migrate --dry-run --helper /tmp/migrate-to-hornero.sh')
			}
			i++
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl config migrate --dry-run')
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl config migrate --help')
	}
	return MigrateCmdOptions{
		dry_run: dry_run
		yes:     yes
		helper:  helper
	}
}
