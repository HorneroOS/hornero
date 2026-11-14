module hornero_cli

// RefreshHyprCmdOptions covers `config refresh-hypr [--dry-run|--yes]`.
pub struct RefreshHyprCmdOptions {
pub:
	dry_run bool
	yes     bool
}

pub fn parse_refresh_hypr_cmd(args []string) !RefreshHyprCmdOptions {
	mut dry_run := false
	mut yes := false
	for a in args {
		if a == '--dry-run' {
			dry_run = true
			continue
		}
		if a == '--yes' {
			yes = true
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl config refresh-hypr --dry-run')
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl config refresh-hypr --help')
	}
	return RefreshHyprCmdOptions{
		dry_run: dry_run
		yes:     yes
	}
}
