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
			return error('unknown flag: ${a}.\nExample: horneroctl hypr workspace ${leaf} --dry-run')
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl hypr workspace --help')
	}
	direction := if leaf == 'prev' { 'prev' } else { 'next' }
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

// HyprWindowsOptions covers `hypr windows <status|set|restore>`.
// `status` is read-only; `set` mutates (needs --yes, --dry-run
// previews) and takes any subset of the four geometry flags — omitted
// flags keep -1 here and the dispatcher fills them from live state.
pub struct HyprWindowsOptions {
pub:
	leaf         string // status | set | restore | rules
	gaps_in      int = -1
	gaps_out     int = -1
	border       int = -1
	rounding     int = -1
	follow_mouse int = -1
	dry_run      bool
	yes          bool
	ephemeral    bool
	rules_action string // list | add | remove
	rule_match   string
	rule_pattern string
	rule_effect  string
	rule_name    string
}

pub fn parse_hypr_windows(args []string) !HyprWindowsOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl hypr windows status')
	}
	leaf := args[0]
	if leaf !in ['status', 'set', 'restore', 'rules'] {
		return error('unknown windows subcommand: ${leaf}.\nRun: horneroctl hypr windows --help')
	}
	if leaf == 'rules' {
		return parse_hypr_windows_rules(args)
	}
	mut gaps_in := -1
	mut gaps_out := -1
	mut border := -1
	mut rounding := -1
	mut follow_mouse := -1
	mut dry_run := false
	mut yes := false
	mut ephemeral := false
	mut i := 1
	for i < args.len {
		a := args[i]
		i++
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
		if a in ['--gaps-in', '--gaps-out', '--border-size', '--rounding', '--follow-mouse'] {
			if i >= args.len {
				return error('${a} needs a value.\nExample: horneroctl hypr windows set ${a} 5 --dry-run')
			}
			v := args[i]
			i++
			if v.starts_with('-') || v.int().str() != v {
				return error('${a} needs an integer, got: ${v}.\nExample: horneroctl hypr windows set ${a} 5 --dry-run')
			}
			match a {
				'--gaps-in' { gaps_in = v.int() }
				'--gaps-out' { gaps_out = v.int() }
				'--border-size' { border = v.int() }
				'--follow-mouse' { follow_mouse = v.int() }
				else { rounding = v.int() }
			}
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl hypr windows set --gaps-in 5 --dry-run')
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl hypr windows --help')
	}
	if leaf == 'status' && (dry_run || yes || ephemeral || gaps_in >= 0 || gaps_out >= 0
		|| border >= 0 || rounding >= 0 || follow_mouse >= 0) {
		return error('hypr windows status takes no flags.\nExample: horneroctl hypr windows status')
	}
	if leaf == 'restore' && (gaps_in >= 0 || gaps_out >= 0 || border >= 0 || rounding >= 0
		|| follow_mouse >= 0) {
		return error('hypr windows restore takes no geometry flags.\nExample: horneroctl hypr windows restore --yes')
	}
	if leaf == 'set' && gaps_in < 0 && gaps_out < 0 && border < 0 && rounding < 0
		&& follow_mouse < 0 {
		return error('hypr windows set needs at least one geometry flag.\nExample: horneroctl hypr windows set --gaps-in 5 --dry-run')
	}
	return HyprWindowsOptions{
		leaf:         leaf
		gaps_in:      gaps_in
		gaps_out:     gaps_out
		border:       border
		rounding:     rounding
		follow_mouse: follow_mouse
		dry_run:      dry_run
		yes:          yes
		ephemeral:    ephemeral
	}
}

fn parse_hypr_windows_rules(args []string) !HyprWindowsOptions {
	if args.len < 2 {
		return error('missing rules action.\nExample: horneroctl hypr windows rules list')
	}
	action := args[1]
	if action !in ['list', 'add', 'remove'] {
		return error('unknown rules action: ${action}.\nRun: horneroctl hypr windows --help')
	}
	mut match_kind := ''
	mut pattern := ''
	mut effect := ''
	mut name := ''
	mut dry_run := false
	mut yes := false
	mut i := 2
	for i < args.len {
		a := args[i]
		i++
		if a == '--dry-run' {
			dry_run = true
			continue
		}
		if a == '--yes' {
			yes = true
			continue
		}
		if a in ['--match', '--pattern', '--effect', '--name'] {
			if i >= args.len {
				return error('${a} needs a value.\nExample: horneroctl hypr windows rules add --match class --pattern kitty --effect float')
			}
			v := args[i]
			i++
			match a {
				'--match' { match_kind = v }
				'--pattern' { pattern = v }
				'--effect' { effect = v }
				else { name = v }
			}
			continue
		}
		return error('unknown flag: ${a}.\nRun: horneroctl hypr windows --help')
	}
	if action == 'add' && (match_kind.len == 0 || pattern.len == 0 || effect.len == 0) {
		return error('rules add needs --match, --pattern and --effect.\nExample: horneroctl hypr windows rules add --match class --pattern kitty --effect float --yes')
	}
	if action == 'remove' && name.len == 0 {
		return error('rules remove needs --name.\nExample: horneroctl hypr windows rules remove --name hornero-user-kitty --yes')
	}
	if action == 'list' && (match_kind.len > 0 || pattern.len > 0 || effect.len > 0 || name.len > 0
		|| yes) {
		return error('rules list takes only --dry-run.\nExample: horneroctl hypr windows rules list')
	}
	return HyprWindowsOptions{
		leaf:         'rules'
		dry_run:      dry_run
		yes:          yes
		rules_action: action
		rule_match:   match_kind
		rule_pattern: pattern
		rule_effect:  effect
		rule_name:    name
	}
}

// HyprInputOptions covers `hypr input <status|set|restore>`.
// `set` takes any subset of the input flags; omitted flags keep
// their current (live, else persisted) values — 999/-1/''/-1 are
// the unset sentinels the dispatcher resolves.
pub struct HyprInputOptions {
pub:
	leaf           string // status | set | restore
	sensitivity    f64 = 999
	accel_profile  string
	repeat_rate    int = -1
	repeat_delay   int = -1
	natural_scroll int = -1 // -1 unset, 0 false, 1 true
	tap_to_click   int = -1
	dry_run        bool
	yes            bool
	ephemeral      bool
}

pub fn parse_hypr_input(args []string) !HyprInputOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl hypr input status')
	}
	leaf := args[0]
	if leaf !in ['status', 'set', 'restore'] {
		return error('unknown input subcommand: ${leaf}.\nRun: horneroctl hypr input --help')
	}
	mut sensitivity := f64(999)
	mut accel_profile := ''
	mut repeat_rate := -1
	mut repeat_delay := -1
	mut natural_scroll := -1
	mut tap_to_click := -1
	mut dry_run := false
	mut yes := false
	mut ephemeral := false
	mut i := 1
	for i < args.len {
		a := args[i]
		i++
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
		if a in ['--sensitivity', '--accel-profile', '--repeat-rate', '--repeat-delay',
			'--natural-scroll', '--tap-to-click'] {
			if i >= args.len {
				return error('${a} needs a value.\nExample: horneroctl hypr input set ${a} --dry-run')
			}
			v := args[i]
			i++
			match a {
				'--sensitivity' {
					sensitivity = v.f64()
					if sensitivity == 0 && v !in ['0', '0.0', '-0', '0.00'] && !v.starts_with('0.') {
						return error('--sensitivity needs a number, got: ${v}.\nExample: horneroctl hypr input set --sensitivity 0.2 --dry-run')
					}
				}
				'--accel-profile' {
					if v !in ['adaptive', 'flat'] {
						return error('--accel-profile must be adaptive or flat, got: ${v}.')
					}
					accel_profile = v
				}
				'--repeat-rate' {
					if v.starts_with('-') || v.int().str() != v {
						return error('--repeat-rate needs an integer, got: ${v}.')
					}
					repeat_rate = v.int()
				}
				'--repeat-delay' {
					if v.starts_with('-') || v.int().str() != v {
						return error('--repeat-delay needs an integer, got: ${v}.')
					}
					repeat_delay = v.int()
				}
				'--natural-scroll' {
					if v !in ['true', 'false'] {
						return error('--natural-scroll needs true or false, got: ${v}.')
					}
					natural_scroll = if v == 'true' { 1 } else { 0 }
				}
				else {
					if v !in ['true', 'false'] {
						return error('--tap-to-click needs true or false, got: ${v}.')
					}
					tap_to_click = if v == 'true' { 1 } else { 0 }
				}
			}
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl hypr input set --sensitivity 0.2 --dry-run')
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl hypr input --help')
	}
	any_flag := sensitivity != 999 || accel_profile.len > 0 || repeat_rate >= 0
		|| repeat_delay >= 0 || natural_scroll >= 0 || tap_to_click >= 0
	if leaf == 'status' && (dry_run || yes || ephemeral || any_flag) {
		return error('hypr input status takes no flags.\nExample: horneroctl hypr input status')
	}
	if leaf == 'restore' && any_flag {
		return error('hypr input restore takes no setting flags.\nExample: horneroctl hypr input restore --yes')
	}
	if leaf == 'set' && !any_flag {
		return error('hypr input set needs at least one setting flag.\nExample: horneroctl hypr input set --sensitivity 0.2 --dry-run')
	}
	return HyprInputOptions{
		leaf:           leaf
		sensitivity:    sensitivity
		accel_profile:  accel_profile
		repeat_rate:    repeat_rate
		repeat_delay:   repeat_delay
		natural_scroll: natural_scroll
		tap_to_click:   tap_to_click
		dry_run:        dry_run
		yes:            yes
		ephemeral:      ephemeral
	}
}
