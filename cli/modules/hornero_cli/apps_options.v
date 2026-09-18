module hornero_cli

// Apps option parsers: `apps <files|terminal-file|weather|git-status|
// audit|launch|toggle|switcher|performance> ...`. Error strings always
// carry a correct Example (exit-2 contract). View-open verbs (files
// open, terminal launch, launcher) need no --yes; state-changing verbs
// (toggles, switcher control, git watch/stop, profile set) need --yes
// with --dry-run previews. `audit` covers checks plus --fix/--report/
// --json; default-apps set stays a deferral under `config default-apps`.

pub const apps_verbs = ['files', 'terminal-file', 'weather', 'git-status', 'audit', 'launch', 'toggle',
	'switcher', 'performance']

// AppsCmdOptions covers `apps <verb>`: the verb routes, the rest parses
// per verb.
pub struct AppsCmdOptions {
pub:
	verb string
	rest []string
}

pub fn parse_apps_cmd(args []string) !AppsCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl apps files --dry-run')
	}
	verb := args[0]
	if verb !in apps_verbs {
		return error('unknown apps subcommand: ${verb}.\nRun: horneroctl apps --help')
	}
	return AppsCmdOptions{
		verb: verb
		rest: args[1..].clone()
	}
}

// FilesCmdOptions covers `apps files [--path P] [--info]`.
pub struct FilesCmdOptions {
pub:
	path    string
	info    bool
	dry_run bool
}

pub fn parse_apps_files(args []string) !FilesCmdOptions {
	mut path := ''
	mut info := false
	mut dry_run := false
	mut i := 0
	for i < args.len {
		a := args[i]
		if a == '--dry-run' {
			dry_run = true
			i++
			continue
		}
		if a == '--info' {
			info = true
			i++
			continue
		}
		if a == '--path' {
			if i + 1 >= args.len || args[i + 1].starts_with('-') || args[i + 1].len == 0 {
				return error('missing value for --path.\nExample: horneroctl apps files --path ~/Documents --dry-run')
			}
			path = args[i + 1]
			i += 2
			continue
		}
		if a.starts_with('--path=') {
			path = a.all_after('=')
			if path.len == 0 {
				return error('missing value for --path.\nExample: horneroctl apps files --path ~/Documents --dry-run')
			}
			i++
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl apps files --dry-run')
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl apps files --help')
	}
	if info && path.len > 0 {
		return error('files --info takes no --path.\nExample: horneroctl apps files --info')
	}
	return FilesCmdOptions{
		path:    path
		info:    info
		dry_run: dry_run
	}
}

// TerminalFileCmdOptions covers `apps terminal-file`.
pub struct TerminalFileCmdOptions {
pub:
	path         string
	selected     string
	last_dir     bool
	cheatsheet   bool
	fix_previews bool
	dry_run      bool
}

pub fn parse_apps_terminal_file(args []string) !TerminalFileCmdOptions {
	mut path := ''
	mut selected := ''
	mut last_dir := false
	mut cheatsheet := false
	mut fix_previews := false
	mut dry_run := false
	mut i := 0
	for i < args.len {
		a := args[i]
		if a == '--dry-run' {
			dry_run = true
			i++
			continue
		}
		if a == '--last-dir' {
			last_dir = true
			i++
			continue
		}
		if a == '--cheatsheet' {
			cheatsheet = true
			i++
			continue
		}
		if a == '--fix-previews' {
			fix_previews = true
			i++
			continue
		}
		if a == '--path' {
			if i + 1 >= args.len || args[i + 1].starts_with('-') || args[i + 1].len == 0 {
				return error('missing value for --path.\nExample: horneroctl apps terminal-file --path ~/Documents --dry-run')
			}
			path = args[i + 1]
			i += 2
			continue
		}
		if a.starts_with('--path=') {
			path = a.all_after('=')
			if path.len == 0 {
				return error('missing value for --path.\nExample: horneroctl apps terminal-file --path ~/Documents --dry-run')
			}
			i++
			continue
		}
		if a == '--select' {
			if i + 1 >= args.len || args[i + 1].starts_with('-') || args[i + 1].len == 0 {
				return error('missing value for --select.\nExample: horneroctl apps terminal-file --select ~/notes.txt --dry-run')
			}
			selected = args[i + 1]
			i += 2
			continue
		}
		if a.starts_with('--select=') {
			selected = a.all_after('=')
			if selected.len == 0 {
				return error('missing value for --select.\nExample: horneroctl apps terminal-file --select ~/notes.txt --dry-run')
			}
			i++
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl apps terminal-file --dry-run')
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl apps terminal-file --help')
	}
	if cheatsheet && (fix_previews || path.len > 0 || selected.len > 0 || last_dir) {
		return error('terminal-file --cheatsheet takes no other flags.\nExample: horneroctl apps terminal-file --cheatsheet')
	}
	if fix_previews && (path.len > 0 || selected.len > 0 || last_dir) {
		return error('terminal-file --fix-previews takes no other flags.\nExample: horneroctl apps terminal-file --fix-previews')
	}
	return TerminalFileCmdOptions{
		path:         path
		selected:     selected
		last_dir:     last_dir
		cheatsheet:   cheatsheet
		fix_previews: fix_previews
		dry_run:      dry_run
	}
}

// WeatherCmdOptions covers `apps weather <--field>`.
pub struct WeatherCmdOptions {
pub:
	field   string
	dry_run bool
}

pub fn parse_apps_weather(args []string) !WeatherCmdOptions {
	mut field := ''
	mut dry_run := false
	for a in args {
		if a == '--dry-run' {
			dry_run = true
			continue
		}
		if a in ['--getdata', '--icon', '--temp', '--hex', '--stat', '--loc', '--quote', '--quote2'] {
			if field.len > 0 {
				return error('weather takes exactly one field.\nExample: horneroctl apps weather --temp')
			}
			field = a.all_after('--')
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl apps weather --temp')
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl apps weather --help')
	}
	if field.len == 0 {
		return error('missing weather field (one of --getdata --icon --temp --hex --stat --loc --quote --quote2).\nExample: horneroctl apps weather --temp')
	}
	return WeatherCmdOptions{
		field:   field
		dry_run: dry_run
	}
}

// GitStatusCmdOptions covers `apps git-status [watch|jobs|stop]`.
pub struct GitStatusCmdOptions {
pub:
	leaf       string
	branch     string
	repository string
	interval   string
	async      bool
	verbose    bool
	dry_run    bool
	yes        bool
}

pub fn parse_apps_git_status(args []string) !GitStatusCmdOptions {
	mut leaf := 'watch'
	mut branch := ''
	mut repository := ''
	mut interval := ''
	mut async := false
	mut verbose := false
	mut dry_run := false
	mut yes := false
	mut i := 0
	if args.len > 0 && args[0] !in ['watch', 'jobs', 'stop'] && !args[0].starts_with('-') {
		return error('unknown git-status leaf: ${args[0]}.\nRun: horneroctl apps git-status --help')
	}
	if args.len > 0 && args[0] in ['watch', 'jobs', 'stop'] {
		leaf = args[0]
		i = 1
	}
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
		if a == '--async' {
			async = true
			i++
			continue
		}
		if a == '--verbose' {
			verbose = true
			i++
			continue
		}
		if a == '--branch' {
			if i + 1 >= args.len || args[i + 1].starts_with('-') || args[i + 1].len == 0 {
				return error('missing value for --branch.\nExample: horneroctl apps git-status watch --branch origin/main --dry-run')
			}
			branch = args[i + 1]
			i += 2
			continue
		}
		if a.starts_with('--branch=') {
			branch = a.all_after('=')
			if branch.len == 0 {
				return error('missing value for --branch.\nExample: horneroctl apps git-status watch --branch origin/main --dry-run')
			}
			i++
			continue
		}
		if a == '--repository' {
			if i + 1 >= args.len || args[i + 1].starts_with('-') || args[i + 1].len == 0 {
				return error('missing value for --repository.\nExample: horneroctl apps git-status watch --repository origin/main --dry-run')
			}
			repository = args[i + 1]
			i += 2
			continue
		}
		if a.starts_with('--repository=') {
			repository = a.all_after('=')
			if repository.len == 0 {
				return error('missing value for --repository.\nExample: horneroctl apps git-status watch --repository origin/main --dry-run')
			}
			i++
			continue
		}
		if a == '--interval' {
			if i + 1 >= args.len || args[i + 1].starts_with('-') || args[i + 1].len == 0 {
				return error('missing value for --interval.\nExample: horneroctl apps git-status watch --interval 60 --dry-run')
			}
			interval = args[i + 1]
			i += 2
			continue
		}
		if a.starts_with('--interval=') {
			interval = a.all_after('=')
			if interval.len == 0 {
				return error('missing value for --interval.\nExample: horneroctl apps git-status watch --interval 60 --dry-run')
			}
			i++
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl apps git-status jobs')
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl apps git-status --help')
	}
	if interval.len > 0 {
		for c in interval {
			if !c.is_digit() {
				return error('interval must be a number of seconds.\nExample: horneroctl apps git-status watch --interval 60 --dry-run')
			}
		}
	}
	if leaf == 'jobs'
		&& (branch.len > 0 || repository.len > 0 || interval.len > 0 || async || verbose) {
		return error('git-status jobs takes no watch flags.\nExample: horneroctl apps git-status jobs')
	}
	if leaf == 'stop'
		&& (branch.len > 0 || repository.len > 0 || interval.len > 0 || async || verbose) {
		return error('git-status stop takes no watch flags.\nExample: horneroctl apps git-status stop --dry-run')
	}
	return GitStatusCmdOptions{
		leaf:       leaf
		branch:     branch
		repository: repository
		interval:   interval
		async:      async
		verbose:    verbose
		dry_run:    dry_run
		yes:        yes
	}
}

// AuditCmdOptions covers `apps audit [--permissions|--secrets|--system]
// [--fix|--report|--json] [--yes]`.
pub struct AuditCmdOptions {
pub:
	check   string
	mode    string // check | fix | report | json
	yes     bool
	dry_run bool
}

pub fn parse_apps_audit(args []string) !AuditCmdOptions {
	mut check := 'full'
	mut mode := 'check'
	mut yes := false
	mut dry_run := false
	for a in args {
		if a == '--dry-run' {
			dry_run = true
			continue
		}
		if a == '--yes' {
			yes = true
			continue
		}
		if a in ['--permissions', '--secrets', '--system'] {
			if check != 'full' {
				return error('audit takes at most one check.\nExample: horneroctl apps audit --permissions')
			}
			check = a.all_after('--')
			continue
		}
		if a in ['--fix', '--report', '--json'] {
			if mode != 'check' {
				return error('audit takes at most one mode.\nExample: horneroctl apps audit --fix --yes')
			}
			mode = a.all_after('--')
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl apps audit --dry-run')
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl apps audit --help')
	}
	return AuditCmdOptions{
		check:   check
		mode:    mode
		yes:     yes
		dry_run: dry_run
	}
}

// LaunchCmdOptions covers `apps launch [--backend NAME] [--list]`.
pub struct LaunchCmdOptions {
pub:
	backend string
	list    bool
	dry_run bool
}

pub fn parse_apps_launch(args []string) !LaunchCmdOptions {
	mut backend := ''
	mut list := false
	mut dry_run := false
	mut i := 0
	for i < args.len {
		a := args[i]
		if a == '--dry-run' {
			dry_run = true
			i++
			continue
		}
		if a == '--list' {
			list = true
			i++
			continue
		}
		if a == '--backend' {
			if i + 1 >= args.len || args[i + 1].starts_with('-') || args[i + 1].len == 0 {
				return error('missing value for --backend (quickshell|minimal).\nExample: horneroctl apps launch --backend quickshell --dry-run')
			}
			backend = args[i + 1]
			i += 2
			continue
		}
		if a.starts_with('--backend=') {
			backend = a.all_after('=')
			if backend.len == 0 {
				return error('missing value for --backend (quickshell|minimal).\nExample: horneroctl apps launch --backend quickshell --dry-run')
			}
			i++
			continue
		}
		if a.starts_with('-') {
			return error('unknown flag: ${a}.\nExample: horneroctl apps launch --dry-run')
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl apps launch --help')
	}
	if list && backend.len > 0 {
		return error('launch --list takes no --backend.\nExample: horneroctl apps launch --list')
	}
	if backend.len > 0 && backend !in ['auto', 'quickshell', 'minimal'] {
		return error('unknown backend: ${backend} (auto, quickshell, minimal).\nExample: horneroctl apps launch --backend quickshell --dry-run')
	}
	return LaunchCmdOptions{
		backend: backend
		list:    list
		dry_run: dry_run
	}
}

// ToggleCmdOptions covers `apps toggle <component>`.
pub struct ToggleCmdOptions {
pub:
	component string
	dry_run   bool
	yes       bool
}

pub fn parse_apps_toggle(args []string) !ToggleCmdOptions {
	if args.len == 0 {
		return error('missing component (bar|launcher|dashboard|sidebar|session|utilities|redshift|caffeine).\nExample: horneroctl apps toggle bar --dry-run')
	}
	component := args[0]
	if component !in ['bar', 'launcher', 'dashboard', 'sidebar', 'session', 'utilities', 'redshift',
		'caffeine'] {
		return error('unknown toggle component: ${component}.\nRun: horneroctl apps toggle --help')
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
			return error('unknown flag: ${a}.\nExample: horneroctl apps toggle ${component} --dry-run')
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl apps toggle --help')
	}
	return ToggleCmdOptions{
		component: component
		dry_run:   dry_run
		yes:       yes
	}
}

// SwitcherCmdOptions covers `apps switcher <leaf> [arg]`.
pub struct SwitcherCmdOptions {
pub:
	leaf    string
	arg     string
	dry_run bool
	yes     bool
}

pub fn parse_apps_switcher(args []string) !SwitcherCmdOptions {
	mut leaf := 'toggle'
	mut rest_start := 0
	if args.len > 0 {
		if args[0] !in ['daemon', 'next', 'prev', 'toggle', 'hide', 'select', 'quit', 'status',
			'apply-theme', 'apply-theme-pack', 'apply-rice-theme']
			&& !args[0].starts_with('-') {
			return error('unknown switcher leaf: ${args[0]}.\nRun: horneroctl apps switcher --help')
		}
		if !args[0].starts_with('-') {
			leaf = args[0]
			rest_start = 1
		}
	}
	mut arg := ''
	mut dry_run := false
	mut yes := false
	mut i := rest_start
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
			return error('unknown flag: ${a}.\nExample: horneroctl apps switcher ${leaf} --dry-run')
		}
		if leaf !in ['apply-theme', 'apply-theme-pack', 'apply-rice-theme'] {
			return error('unexpected argument: ${a}.\nRun: horneroctl apps switcher --help')
		}
		if arg.len > 0 {
			return error('unexpected argument: ${a}.\nRun: horneroctl apps switcher --help')
		}
		arg = a
		i++
	}
	if leaf == 'apply-theme' && arg.len == 0 {
		return error('missing theme file.\nExample: horneroctl apps switcher apply-theme nord.ini --dry-run')
	}
	// status accepts --dry-run (preview); --yes is refused below.
	if leaf == 'status' && yes {
		return error('switcher status takes no --yes (it is read-only).\nExample: horneroctl apps switcher status')
	}
	return SwitcherCmdOptions{
		leaf:    leaf
		arg:     arg
		dry_run: dry_run
		yes:     yes
	}
}

// PerformanceCmdOptions covers `apps performance <leaf> [mode set]`.
pub struct PerformanceCmdOptions {
pub:
	leaf    string
	sub     string
	profile string
	dry_run bool
	yes     bool
}

pub fn parse_apps_performance(args []string) !PerformanceCmdOptions {
	if args.len == 0 {
		return error('missing subcommand.\nExample: horneroctl apps performance memory')
	}
	leaf := args[0]
	if leaf !in ['startup', 'memory', 'benchmark', 'report', 'mode'] {
		return error('unknown performance leaf: ${leaf}.\nRun: horneroctl apps performance --help')
	}
	mut sub := ''
	mut profile := ''
	mut dry_run := false
	mut yes := false
	mut i := 1
	if leaf == 'mode' && i < args.len && args[i] == 'set' {
		sub = 'set'
		i++
	}
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
			return error('unknown flag: ${a}.\nExample: horneroctl apps performance ${leaf} --dry-run')
		}
		if leaf == 'mode' && sub == 'set' && profile.len == 0 {
			profile = a
			i++
			continue
		}
		return error('unexpected argument: ${a}.\nRun: horneroctl apps performance --help')
	}
	if leaf == 'mode' && sub == 'set' && profile.len == 0 {
		return error('missing profile.\nExample: horneroctl apps performance mode set balanced --dry-run')
	}
	if leaf != 'mode' && yes {
		return error('performance ${leaf} takes no --yes (it is read-only).\nExample: horneroctl apps performance ${leaf}')
	}
	if leaf == 'mode' && sub == '' && yes {
		return error('performance mode takes no --yes (it only shows state).\nExample: horneroctl apps performance mode')
	}
	return PerformanceCmdOptions{
		leaf:    leaf
		sub:     sub
		profile: profile
		dry_run: dry_run
		yes:     yes
	}
}
