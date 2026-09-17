module hornero_cli

// Hypr option parsers: `hypr <animations|layout|monitors|workspace|plugins>
// <leaf>`. Error strings always carry a correct Example (exit-2 contract).
// list/current/status leaves are read-only and take no flags; every other
// leaf is mutating (needs --yes, --dry-run previews). animations/layout
// also accept --ephemeral to skip persisting the selection.

// HyprAnimationsOptions covers `hypr animations <leaf>`.
pub struct HyprAnimationsOptions {
pub:
	leaf      string // list | current | set | next | restore
	profile   string // set target
	dry_run   bool
	yes       bool
	ephemeral bool
}

pub fn parse_hypr_animations(args []string) !HyprAnimationsOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl hypr animations list')
	}
	leaf := args[0]
	if leaf !in ['list', 'current', 'set', 'next', 'restore'] {
		return error('unknown animations subcommand: ${leaf}.\nRun: horneroctl hypr animations --help')
	}
	mut profile := ''
	mut dry_run := false
	mut yes := false
	mut ephemeral := false
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
		if a == '--ephemeral' {
			ephemeral = true
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl hypr animations ${leaf} --dry-run')
		}
		if leaf == 'set' && profile.len == 0 {
			profile = a
			continue
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl hypr animations --help')
	}
	if leaf in ['list', 'current'] && (dry_run || yes || ephemeral) {
		return error('hypr animations ${leaf} takes no flags.\nExample: horneroctl hypr animations ${leaf}')
	}
	if leaf == 'set' && profile.len == 0 {
		return error('missing profile.\nExample: horneroctl hypr animations set cozy --dry-run')
	}
	if leaf != 'set' && profile.len > 0 {
		return error('unexpected argument: ${profile}.\nRun: horneroctl hypr animations --help')
	}
	return HyprAnimationsOptions{
		leaf:      leaf
		profile:   profile
		dry_run:   dry_run
		yes:       yes
		ephemeral: ephemeral
	}
}

// HyprLayoutOptions covers `hypr layout <leaf>`.
pub struct HyprLayoutOptions {
pub:
	leaf      string // current | status | set | toggle | restore
	layout    string // set target
	dry_run   bool
	yes       bool
	ephemeral bool
}

pub fn parse_hypr_layout(args []string) !HyprLayoutOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl hypr layout status')
	}
	leaf := args[0]
	if leaf !in ['current', 'status', 'set', 'toggle', 'restore'] {
		return error('unknown layout subcommand: ${leaf}.\nRun: horneroctl hypr layout --help')
	}
	mut layout := ''
	mut dry_run := false
	mut yes := false
	mut ephemeral := false
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
		if a == '--ephemeral' {
			ephemeral = true
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl hypr layout ${leaf} --dry-run')
		}
		if leaf == 'set' && layout.len == 0 {
			layout = a
			continue
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl hypr layout --help')
	}
	if leaf in ['current', 'status'] && (dry_run || yes || ephemeral) {
		return error('hypr layout ${leaf} takes no flags.\nExample: horneroctl hypr layout ${leaf}')
	}
	if leaf == 'set' && layout.len == 0 {
		return error('missing layout.\nExample: horneroctl hypr layout set scrolling --dry-run')
	}
	if leaf != 'set' && layout.len > 0 {
		return error('unexpected argument: ${layout}.\nRun: horneroctl hypr layout --help')
	}
	return HyprLayoutOptions{
		leaf:      leaf
		layout:    layout
		dry_run:   dry_run
		yes:       yes
		ephemeral: ephemeral
	}
}

// HyprMonitorsOptions covers `hypr monitors <leaf>`.
pub struct HyprMonitorsOptions {
pub:
	leaf    string // list | status | set
	mode    string // set target
	dry_run bool
	yes     bool
}

pub fn parse_hypr_monitors(args []string) !HyprMonitorsOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl hypr monitors status')
	}
	leaf := args[0]
	if leaf !in ['list', 'status', 'set'] {
		return error('unknown monitors subcommand: ${leaf}.\nRun: horneroctl hypr monitors --help')
	}
	mut mode := ''
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
			return error('unknown flag: ${a}.\nExample: horneroctl hypr monitors ${leaf} --dry-run')
		}
		if leaf == 'set' && mode.len == 0 {
			mode = a
			continue
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl hypr monitors --help')
	}
	if leaf in ['list', 'status'] && (dry_run || yes) {
		return error('hypr monitors ${leaf} takes no flags.\nExample: horneroctl hypr monitors ${leaf}')
	}
	if leaf == 'set' && mode.len == 0 {
		return error('missing mode.\nExample: horneroctl hypr monitors set extend-right --dry-run')
	}
	if leaf != 'set' && mode.len > 0 {
		return error('unexpected argument: ${mode}.\nRun: horneroctl hypr monitors --help')
	}
	return HyprMonitorsOptions{
		leaf:    leaf
		mode:    mode
		dry_run: dry_run
		yes:     yes
	}
}

// HyprWorkspaceOptions covers `hypr workspace <next|prev>`.
pub struct HyprWorkspaceOptions {
pub:
	leaf    string // next | prev
	dry_run bool
	yes     bool
}

pub fn parse_hypr_workspace(args []string) !HyprWorkspaceOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl hypr workspace next --dry-run')
	}
	leaf := args[0]
	if leaf !in ['next', 'prev'] {
		return error('unknown workspace subcommand: ${leaf}.\nRun: horneroctl hypr workspace --help')
	}
	mut dry_run := false
	mut yes := false
	mut prev_alias := false
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
		if a in ['--previous', '--left'] {
			prev_alias = true
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl hypr workspace ${leaf} --dry-run')
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl hypr workspace --help')
	}
	direction := if leaf == 'prev' || prev_alias { 'prev' } else { 'next' }
	return HyprWorkspaceOptions{
		leaf:    direction
		dry_run: dry_run
		yes:     yes
	}
}

// HyprPluginsOptions covers `hypr plugins <list|status|install>`.
// `list`/`status` are read-only; `install` mutates (needs --yes).
pub struct HyprPluginsOptions {
pub:
	leaf      string // list | status | install
	force     bool   // install: rebuild hyprpm headers
	no_update bool   // install: skip the header update
	dry_run   bool
	yes       bool
}

pub fn parse_hypr_plugins(args []string) !HyprPluginsOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl hypr plugins status')
	}
	leaf := args[0]
	if leaf !in ['list', 'status', 'install'] {
		return error('unknown plugins subcommand: ${leaf}.\nRun: horneroctl hypr plugins --help')
	}
	mut force := false
	mut no_update := false
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
		if a == '--force' {
			force = true
			continue
		}
		if a == '--no-update' {
			no_update = true
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl hypr plugins ${leaf} --dry-run')
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl hypr plugins --help')
	}
	if leaf in ['list', 'status'] && (force || no_update || dry_run || yes) {
		return error('hypr plugins ${leaf} takes no flags.\nExample: horneroctl hypr plugins ${leaf}')
	}
	if leaf == 'install' && force && no_update {
		return error('hypr plugins install takes either --force or --no-update, not both.\nExample: horneroctl hypr plugins install --yes')
	}
	return HyprPluginsOptions{
		leaf:      leaf
		force:     force
		no_update: no_update
		dry_run:   dry_run
		yes:       yes
	}
}
