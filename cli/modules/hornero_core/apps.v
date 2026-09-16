module hornero_core

import os

// Everyday app launchers: file manager, terminal files, weather, git
// watcher, security audit, launcher, toggles, window switcher, and
// performance tooling — mirroring the dots-file-manager, dots-yazi,
// dots-weather-info, dots-git-notify, dots-security-audit,
// dots-default-apps (list already lives under `config default-apps`),
// dots-config-manager (create/list/restore already live under `config
// snapshot`), dots-launcher, dots-toggle, dots-snappy-switcher,
// dots-performance, and dots-performance-mode reference scripts.
//
// Reads delegate to the dots-* wrappers (HORNEROCTL_DELEGATED=1 guard);
// leaf tools (exo-open, yazi, powerprofilesctl) run directly. View-open
// verbs (files open, terminal launch, launcher) need no --yes — like
// `config gui` / `welcome open` / `capture clipboard`. State-changing
// verbs (toggles, switcher control, git watch/stop, profile set) need
// --yes; --dry-run only previews. `audit` ports the read-only checks
// only: --fix (chmod/history scrub) and --report stay legacy.

// dots_helper_bin resolves one dots-* wrapper: explicit override, then
// ~/.local/bin, then PATH.
fn dots_helper_bin(env_key string, script string) string {
	env := os.getenv(env_key)
	if env.len > 0 {
		return env
	}
	home_helper := os.join_path(os.home_dir(), '.local', 'bin', script)
	if os.is_file(home_helper) {
		return home_helper
	}
	return find_on_path(script)
}

// leaf_bin resolves one leaf tool: explicit override, then PATH.
fn leaf_bin(env_key string, prog string) string {
	env := os.getenv(env_key)
	if env.len > 0 {
		return env
	}
	return find_on_path(prog)
}

// resolve_dots_file_manager_bin locates dots-file-manager.
// Override with HORNERO_FILE_MANAGER_BIN.
pub fn resolve_dots_file_manager_bin() string {
	return dots_helper_bin('HORNERO_FILE_MANAGER_BIN', 'dots-file-manager')
}

// resolve_exo_open_bin locates exo-open. Override with HORNERO_EXO_OPEN_BIN.
pub fn resolve_exo_open_bin() string {
	return leaf_bin('HORNERO_EXO_OPEN_BIN', 'exo-open')
}

// resolve_handlr_bin locates handlr. Override with HORNERO_HANDLR_BIN.
pub fn resolve_handlr_bin() string {
	return leaf_bin('HORNERO_HANDLR_BIN', 'handlr')
}

// resolve_xdg_open_bin locates xdg-open. Override with HORNERO_XDG_OPEN_BIN.
pub fn resolve_xdg_open_bin() string {
	return leaf_bin('HORNERO_XDG_OPEN_BIN', 'xdg-open')
}

// resolve_dots_yazi_bin locates the dots-yazi wrapper.
// Override with HORNERO_DOTS_YAZI_BIN.
pub fn resolve_dots_yazi_bin() string {
	return dots_helper_bin('HORNERO_DOTS_YAZI_BIN', 'dots-yazi')
}

// resolve_yazi_bin locates yazi itself. Override with HORNERO_YAZI_BIN.
pub fn resolve_yazi_bin() string {
	return leaf_bin('HORNERO_YAZI_BIN', 'yazi')
}

// resolve_dots_weather_bin locates dots-weather-info.
// Override with HORNERO_WEATHER_BIN.
pub fn resolve_dots_weather_bin() string {
	return dots_helper_bin('HORNERO_WEATHER_BIN', 'dots-weather-info')
}

// resolve_dots_git_notify_bin locates dots-git-notify.
// Override with HORNERO_GIT_NOTIFY_BIN.
pub fn resolve_dots_git_notify_bin() string {
	return dots_helper_bin('HORNERO_GIT_NOTIFY_BIN', 'dots-git-notify')
}

// resolve_dots_security_audit_bin locates dots-security-audit.
// Override with HORNERO_SECURITY_AUDIT_BIN.
pub fn resolve_dots_security_audit_bin() string {
	return dots_helper_bin('HORNERO_SECURITY_AUDIT_BIN', 'dots-security-audit')
}

// resolve_dots_launcher_bin locates dots-launcher.
// Override with HORNERO_LAUNCHER_BIN.
pub fn resolve_dots_launcher_bin() string {
	return dots_helper_bin('HORNERO_LAUNCHER_BIN', 'dots-launcher')
}

// resolve_dots_toggle_bin locates dots-toggle.
// Override with HORNERO_TOGGLE_BIN.
pub fn resolve_dots_toggle_bin() string {
	return dots_helper_bin('HORNERO_TOGGLE_BIN', 'dots-toggle')
}

// resolve_dots_snappy_bin locates dots-snappy-switcher.
// Override with HORNERO_SNAPPY_BIN.
pub fn resolve_dots_snappy_bin() string {
	return dots_helper_bin('HORNERO_SNAPPY_BIN', 'dots-snappy-switcher')
}

// resolve_dots_performance_bin locates dots-performance.
// Override with HORNERO_PERFORMANCE_BIN.
pub fn resolve_dots_performance_bin() string {
	return dots_helper_bin('HORNERO_PERFORMANCE_BIN', 'dots-performance')
}

// resolve_powerprofilesctl_bin locates powerprofilesctl.
// Override with HORNERO_POWERPROFILESCTL_BIN.
pub fn resolve_powerprofilesctl_bin() string {
	return leaf_bin('HORNERO_POWERPROFILESCTL_BIN', 'powerprofilesctl')
}

// apps_backend_or_placeholder resolves one apps backend for real runs,
// or the bare program name for dry-run previews when nothing is
// installed. A stale override (set but missing) fails with the override
// hint instead of a raw backend failure.
fn apps_backend_or_placeholder(resolved string, prog string, env_key string, dry_run bool, example string) !string {
	if resolved.len == 0 {
		if dry_run {
			return prog
		}
		return error('${prog} not found. Set ${env_key}.\nExample: ${example}')
	}
	if !dry_run && resolved.contains('/') && !os.is_file(resolved) {
		return error('${prog} backend not found: ${resolved}. Set ${env_key}.\nExample: ${example}')
	}
	return resolved
}

// apps_shell_quote single-quotes one argv word: backend arguments carry
// user paths and branch names, so every word is quoted (the shared
// quote_arg only covers spaces/quotes): without this, a value like
// `wall.jpg;id` would run `id` as a second command.
fn apps_shell_quote(s string) string {
	return "'" + s.replace("'", '\'"\'"\'') + "'"
}

// apps_quote_line builds a strictly-quoted shell line from words.
fn apps_quote_line(words []string) string {
	mut quoted := []string{}
	for w in words {
		quoted << apps_shell_quote(w)
	}
	return quoted.join(' ')
}

// apps_run_delegated invokes one dots-* wrapper under the
// HORNEROCTL_DELEGATED re-entrancy guard via env(1), or previews the
// guarded command on dry-run. Dry-run previews never execute.
fn apps_run_delegated(bin string, args []string, dry_run bool) ExecReport {
	mut words := ['env', 'HORNEROCTL_DELEGATED=1', bin]
	for a in args {
		words << a
	}
	line := apps_quote_line(words)
	if dry_run {
		return ExecReport{
			command_line: line
			ok:           true
			output:       '(dry-run: not executed)'
			exit_code:    0
			was_dry_run:  true
		}
	}
	r := os.execute(line)
	return ExecReport{
		command_line: line
		ok:           r.exit_code == 0
		output:       r.output.trim_space()
		exit_code:    r.exit_code
		was_dry_run:  false
	}
}

// apps_run_leaf runs one leaf tool with strict quoting (no delegation
// guard: leaf tools are not shims), or previews it on dry-run.
fn apps_run_leaf(prog string, args []string, dry_run bool) ExecReport {
	mut words := [prog]
	for a in args {
		words << a
	}
	line := apps_quote_line(words)
	if dry_run {
		return ExecReport{
			command_line: line
			ok:           true
			output:       '(dry-run: not executed)'
			exit_code:    0
			was_dry_run:  true
		}
	}
	r := os.execute(line)
	return ExecReport{
		command_line: line
		ok:           r.exit_code == 0
		output:       r.output.trim_space()
		exit_code:    r.exit_code
		was_dry_run:  false
	}
}

// apps_delegated_ok folds a real backend run into a CommandResult.
fn apps_delegated_ok(command string, rep ExecReport, data map[string]string) CommandResult {
	if rep.ok {
		msg := if rep.output.len > 0 { rep.output } else { '${command}: done' }
		mut d := map[string]string{}
		for k, v in data {
			d[k] = v
		}
		d['command_line'] = rep.command_line
		return ok_result(command, msg, d)
	}
	return fail_result(command, 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
}

pub struct FilesOptions {
pub:
	path    string // explicit --path, else the working directory
	info    bool
	dry_run bool
}

// files_report implements `apps files`: open the default file manager
// at --path (view-open, needs no --yes) or show the default with
// --info (read-only). Backend chain mirrors dots-file-manager:
// exo-open, handlr, xdg-open. --dry-run only previews.
pub fn files_report(opts FilesOptions) CommandResult {
	if opts.info {
		bin := apps_backend_or_placeholder(resolve_dots_file_manager_bin(), 'dots-file-manager',
			'HORNERO_FILE_MANAGER_BIN', opts.dry_run, 'horneroctl apps files --info --dry-run') or {
			return fail_result('apps files --info', err.msg())
		}
		rep := apps_run_delegated(bin, ['--info'], opts.dry_run)
		if opts.dry_run {
			return ok_result('apps files --info', 'would run: ${rep.command_line}', {
				'command_line': rep.command_line
				'dry_run':      'true'
			})
		}
		return apps_delegated_ok('apps files --info', rep, {})
	}
	target := if opts.path.len > 0 { opts.path } else { os.getwd() }
	exo := resolve_exo_open_bin()
	handlr := resolve_handlr_bin()
	xdg := resolve_xdg_open_bin()
	if exo.len > 0 {
		rep := apps_run_leaf(exo, ['--launch', 'FileManager', target], opts.dry_run)
		if opts.dry_run {
			return ok_result('apps files', 'would run: ${rep.command_line}', {
				'command_line': rep.command_line
				'dry_run':      'true'
				'path':         target
			})
		}
		return apps_delegated_ok('apps files', rep, {
			'path': target
		})
	}
	if handlr.len > 0 {
		rep := apps_run_leaf(handlr, ['open', target], opts.dry_run)
		if opts.dry_run {
			return ok_result('apps files', 'would run: ${rep.command_line}', {
				'command_line': rep.command_line
				'dry_run':      'true'
				'path':         target
			})
		}
		return apps_delegated_ok('apps files', rep, {
			'path': target
		})
	}
	if xdg.len > 0 {
		rep := apps_run_leaf(xdg, [target], opts.dry_run)
		if opts.dry_run {
			return ok_result('apps files', 'would run: ${rep.command_line}', {
				'command_line': rep.command_line
				'dry_run':      'true'
				'path':         target
			})
		}
		return apps_delegated_ok('apps files', rep, {
			'path': target
		})
	}
	if opts.dry_run {
		rep := apps_run_leaf('exo-open', ['--launch', 'FileManager', target], true)
		return ok_result('apps files', 'would run: ${rep.command_line}', {
			'command_line': rep.command_line
			'dry_run':      'true'
			'path':         target
		})
	}
	return fail_result('apps files', 'no file manager launcher found (exo-open, handlr, or xdg-open). Set HORNERO_EXO_OPEN_BIN.\nExample: horneroctl apps files --dry-run')
}

pub struct TerminalFileOptions {
pub:
	path         string
	selected     string
	last_dir     bool
	cheatsheet   bool
	fix_previews bool
	dry_run      bool
}

// terminal_file_report implements `apps terminal-file`: cheatsheet and
// fix-previews read backend output (read-only); otherwise open yazi via
// the dots-yazi wrapper (view-open, needs no --yes), falling back to
// bare yazi. --dry-run only previews.
pub fn terminal_file_report(opts TerminalFileOptions) CommandResult {
	if opts.cheatsheet || opts.fix_previews {
		flag := if opts.cheatsheet { '--cheatsheet' } else { '--fix-previews' }
		name := if opts.cheatsheet {
			'apps terminal-file --cheatsheet'
		} else {
			'apps terminal-file --fix-previews'
		}
		bin := apps_backend_or_placeholder(resolve_dots_yazi_bin(), 'dots-yazi', 'HORNERO_DOTS_YAZI_BIN',
			opts.dry_run, 'horneroctl ${name} --dry-run') or { return fail_result(name, err.msg()) }
		rep := apps_run_delegated(bin, [flag], opts.dry_run)
		if opts.dry_run {
			return ok_result(name, 'would run: ${rep.command_line}', {
				'command_line': rep.command_line
				'dry_run':      'true'
			})
		}
		return apps_delegated_ok(name, rep, {})
	}
	mut args := []string{}
	if opts.last_dir {
		args << '--last-dir'
	}
	if opts.selected.len > 0 {
		args << '--select'
		args << opts.selected
	}
	if opts.path.len > 0 {
		args << '--path'
		args << opts.path
	}
	wrapper := resolve_dots_yazi_bin()
	if wrapper.len > 0 {
		rep := apps_run_delegated(wrapper, args, opts.dry_run)
		if opts.dry_run {
			return ok_result('apps terminal-file', 'would run: ${rep.command_line}', {
				'command_line': rep.command_line
				'dry_run':      'true'
			})
		}
		return apps_delegated_ok('apps terminal-file', rep, {})
	}
	yazi := resolve_yazi_bin()
	target := if opts.path.len > 0 { opts.path } else { os.getwd() }
	if yazi.len > 0 {
		rep := apps_run_leaf(yazi, [target], opts.dry_run)
		if opts.dry_run {
			return ok_result('apps terminal-file', 'would run: ${rep.command_line}', {
				'command_line': rep.command_line
				'dry_run':      'true'
			})
		}
		return apps_delegated_ok('apps terminal-file', rep, {})
	}
	if opts.dry_run {
		rep := apps_run_delegated('dots-yazi', args, true)
		return ok_result('apps terminal-file', 'would run: ${rep.command_line}', {
			'command_line': rep.command_line
			'dry_run':      'true'
		})
	}
	return fail_result('apps terminal-file', 'no yazi backend found (dots-yazi or yazi). Set HORNERO_DOTS_YAZI_BIN.\nExample: horneroctl apps terminal-file --dry-run')
}

pub struct WeatherOptions {
pub:
	field   string // getdata | icon | temp | hex | stat | loc | quote | quote2
	dry_run bool
}

// weather_report implements `apps weather`: read one cached weather
// field, or refresh the cache with --getdata — the dots-weather-info
// contract. Read-only; --dry-run only previews.
pub fn weather_report(opts WeatherOptions) CommandResult {
	if opts.field !in ['getdata', 'icon', 'temp', 'hex', 'stat', 'loc', 'quote', 'quote2'] {
		return fail_result('apps weather', 'unknown weather field: ${opts.field}.\nRun: horneroctl apps weather --help')
	}
	bin := apps_backend_or_placeholder(resolve_dots_weather_bin(), 'dots-weather-info',
		'HORNERO_WEATHER_BIN', opts.dry_run, 'horneroctl apps weather --${opts.field} --dry-run') or {
		return fail_result('apps weather --${opts.field}', err.msg())
	}
	rep := apps_run_delegated(bin, ['--${opts.field}'], opts.dry_run)
	if opts.dry_run {
		return ok_result('apps weather --${opts.field}', 'would run: ${rep.command_line}',
			{
			'command_line': rep.command_line
			'dry_run':      'true'
			'field':        opts.field
		})
	}
	return apps_delegated_ok('apps weather --${opts.field}', rep, {
		'field': opts.field
	})
}

pub struct GitStatusOptions {
pub:
	leaf       string // watch | jobs | stop
	branch     string
	repository string
	interval   string
	async      bool
	verbose    bool
	dry_run    bool
	yes        bool
}

// git_status_report implements `apps git-status` over dots-git-notify:
// `jobs` lists background watchers (read-only); `stop` kills them and
// `watch` starts the notify loop (both mutating: need --yes);
// --dry-run only previews.
pub fn git_status_report(opts GitStatusOptions) CommandResult {
	if opts.leaf !in ['watch', 'jobs', 'stop'] {
		return fail_result('apps git-status', 'unknown git-status leaf: ${opts.leaf}.\nRun: horneroctl apps git-status --help')
	}
	bin := apps_backend_or_placeholder(resolve_dots_git_notify_bin(), 'dots-git-notify',
		'HORNERO_GIT_NOTIFY_BIN', opts.dry_run, 'horneroctl apps git-status jobs --dry-run') or {
		return fail_result('apps git-status ${opts.leaf}', err.msg())
	}
	if opts.leaf == 'jobs' {
		rep := apps_run_delegated(bin, ['-l'], opts.dry_run)
		if opts.dry_run {
			return ok_result('apps git-status jobs', 'would run: ${rep.command_line}',
				{
				'command_line': rep.command_line
				'dry_run':      'true'
			})
		}
		return apps_delegated_ok('apps git-status jobs', rep, {})
	}
	if !opts.yes && !opts.dry_run {
		return fail_result('apps git-status ${opts.leaf}', 'refusing to ${opts.leaf} without --yes (preview with --dry-run).\nExample: horneroctl apps git-status ${opts.leaf} --dry-run')
	}
	mut args := []string{}
	if opts.leaf == 'stop' {
		args << '-k'
	} else {
		if opts.branch.len > 0 {
			args << '-b'
			args << opts.branch
		}
		if opts.repository.len > 0 {
			args << '-r'
			args << opts.repository
		}
		if opts.interval.len > 0 {
			args << '-t'
			args << opts.interval
		}
		if opts.async {
			args << '-a'
		}
		if opts.verbose {
			args << '-v'
		}
	}
	rep := apps_run_delegated(bin, args, opts.dry_run)
	if opts.dry_run {
		return ok_result('apps git-status ${opts.leaf}', 'would run: ${rep.command_line}',
			{
			'command_line': rep.command_line
			'dry_run':      'true'
		})
	}
	return apps_delegated_ok('apps git-status ${opts.leaf}', rep, {})
}

pub struct AuditOptions {
pub:
	check   string // full | permissions | secrets | system
	dry_run bool
}

// audit_report implements `apps audit`: the dots-security-audit
// read-only checks (full audit by default). --fix (permission changes,
// history scrub) and --report stay legacy and are intentionally not
// ported. --dry-run only previews.
pub fn audit_report(opts AuditOptions) CommandResult {
	if opts.check !in ['full', 'permissions', 'secrets', 'system'] {
		return fail_result('apps audit', 'unknown audit check: ${opts.check}.\nRun: horneroctl apps audit --help')
	}
	flag := if opts.check == 'full' { '--audit' } else { '--' + opts.check }
	bin := apps_backend_or_placeholder(resolve_dots_security_audit_bin(), 'dots-security-audit',
		'HORNERO_SECURITY_AUDIT_BIN', opts.dry_run, 'horneroctl apps audit --dry-run') or {
		return fail_result('apps audit', err.msg())
	}
	rep := apps_run_delegated(bin, [flag], opts.dry_run)
	if opts.dry_run {
		return ok_result('apps audit', 'would run: ${rep.command_line}', {
			'command_line': rep.command_line
			'dry_run':      'true'
			'check':        opts.check
		})
	}
	return apps_delegated_ok('apps audit', rep, {
		'check': opts.check
	})
}

pub struct LaunchOptions {
pub:
	backend string // auto | quickshell | minimal (auto when empty)
	list    bool
	dry_run bool
}

// launch_report implements `apps launch`: list detected backends
// (read-only) or open the launcher via dots-launcher (view-open, needs
// no --yes) — the dots-launcher contract. --dry-run only previews.
pub fn launch_report(opts LaunchOptions) CommandResult {
	if opts.backend !in ['', 'auto', 'quickshell', 'minimal'] {
		return fail_result('apps launch', 'unknown backend: ${opts.backend} (auto, quickshell, minimal).\nExample: horneroctl apps launch --backend quickshell --dry-run')
	}
	bin := apps_backend_or_placeholder(resolve_dots_launcher_bin(), 'dots-launcher', 'HORNERO_LAUNCHER_BIN',
		opts.dry_run, 'horneroctl apps launch --dry-run') or {
		return fail_result('apps launch', err.msg())
	}
	if opts.list {
		rep := apps_run_delegated(bin, ['--list'], opts.dry_run)
		if opts.dry_run {
			return ok_result('apps launch --list', 'would run: ${rep.command_line}', {
				'command_line': rep.command_line
				'dry_run':      'true'
			})
		}
		return apps_delegated_ok('apps launch --list', rep, {})
	}
	mut args := []string{}
	if opts.backend.len > 0 && opts.backend != 'auto' {
		args << '--backend'
		args << opts.backend
	}
	rep := apps_run_delegated(bin, args, opts.dry_run)
	if opts.dry_run {
		return ok_result('apps launch', 'would run: ${rep.command_line}', {
			'command_line': rep.command_line
			'dry_run':      'true'
		})
	}
	return apps_delegated_ok('apps launch', rep, {})
}

pub struct ToggleOptions {
pub:
	component string // bar | launcher | dashboard | sidebar | session | utilities | redshift | caffeine
	dry_run   bool
	yes       bool
}

// toggle_report implements `apps toggle` over dots-toggle: quickshell
// component toggles go through `ipc <component> toggle`; redshift and
// caffeine toggle once via --toggle (their monitor loops stay legacy).
// Mutating: needs --yes; --dry-run only previews.
pub fn toggle_report(opts ToggleOptions) CommandResult {
	if opts.component !in ['bar', 'launcher', 'dashboard', 'sidebar', 'session', 'utilities',
		'redshift', 'caffeine'] {
		return fail_result('apps toggle', 'unknown toggle component: ${opts.component}.\nRun: horneroctl apps toggle --help')
	}
	if !opts.yes && !opts.dry_run {
		return fail_result('apps toggle ${opts.component}', 'refusing to toggle without --yes (preview with --dry-run).\nExample: horneroctl apps toggle ${opts.component} --dry-run')
	}
	bin := apps_backend_or_placeholder(resolve_dots_toggle_bin(), 'dots-toggle', 'HORNERO_TOGGLE_BIN',
		opts.dry_run, 'horneroctl apps toggle ${opts.component} --dry-run') or {
		return fail_result('apps toggle ${opts.component}', err.msg())
	}
	mut args := ['--' + opts.component]
	if opts.component in ['redshift', 'caffeine'] {
		args = ['--' + opts.component, '--toggle']
	}
	rep := apps_run_delegated(bin, args, opts.dry_run)
	if opts.dry_run {
		return ok_result('apps toggle ${opts.component}', 'would run: ${rep.command_line}',
			{
			'command_line': rep.command_line
			'dry_run':      'true'
			'component':    opts.component
		})
	}
	return apps_delegated_ok('apps toggle ${opts.component}', rep, {
		'component': opts.component
	})
}

pub struct SwitcherOptions {
pub:
	leaf    string // daemon | next | prev | toggle | hide | select | quit | status | apply-theme | apply-theme-pack | apply-rice-theme
	arg     string // apply-theme file | apply-theme-pack id
	dry_run bool
	yes     bool
}

// switcher_report implements `apps switcher` over dots-snappy-switcher:
// `status` is read-only; every control leaf mutates (windows, daemon,
// theme) and needs --yes. --dry-run only previews.
pub fn switcher_report(opts SwitcherOptions) CommandResult {
	if opts.leaf !in ['daemon', 'next', 'prev', 'toggle', 'hide', 'select', 'quit', 'status',
		'apply-theme', 'apply-theme-pack', 'apply-rice-theme'] {
		return fail_result('apps switcher', 'unknown switcher leaf: ${opts.leaf}.\nRun: horneroctl apps switcher --help')
	}
	if opts.leaf == 'apply-theme' && opts.arg.len == 0 {
		return fail_result('apps switcher apply-theme', 'missing theme file.\nExample: horneroctl apps switcher apply-theme nord.ini --dry-run')
	}
	bin := apps_backend_or_placeholder(resolve_dots_snappy_bin(), 'dots-snappy-switcher',
		'HORNERO_SNAPPY_BIN', opts.dry_run, 'horneroctl apps switcher status --dry-run') or {
		return fail_result('apps switcher ${opts.leaf}', err.msg())
	}
	if opts.leaf == 'status' {
		rep := apps_run_delegated(bin, ['status'], opts.dry_run)
		if opts.dry_run {
			return ok_result('apps switcher status', 'would run: ${rep.command_line}',
				{
				'command_line': rep.command_line
				'dry_run':      'true'
			})
		}
		return apps_delegated_ok('apps switcher status', rep, {})
	}
	if !opts.yes && !opts.dry_run {
		return fail_result('apps switcher ${opts.leaf}', 'refusing to ${opts.leaf} without --yes (preview with --dry-run).\nExample: horneroctl apps switcher ${opts.leaf} --dry-run')
	}
	mut args := [opts.leaf]
	if opts.arg.len > 0 && opts.leaf in ['apply-theme', 'apply-theme-pack', 'apply-rice-theme'] {
		args << opts.arg
	}
	rep := apps_run_delegated(bin, args, opts.dry_run)
	if opts.dry_run {
		return ok_result('apps switcher ${opts.leaf}', 'would run: ${rep.command_line}',
			{
			'command_line': rep.command_line
			'dry_run':      'true'
		})
	}
	return apps_delegated_ok('apps switcher ${opts.leaf}', rep, {})
}

pub struct PerformanceOptions {
pub:
	leaf    string // startup | memory | benchmark | report | mode
	sub     string // mode sub-leaf: '' (show) | set
	profile string // mode set profile
	dry_run bool
	yes     bool
}

// performance_report implements `apps performance`: shell startup,
// memory, benchmark, and report read through dots-performance
// (read-only); `mode` shows the powerprofilesctl profile and `mode set`
// switches it (needs --yes). --dry-run only previews.
pub fn performance_report(opts PerformanceOptions) CommandResult {
	if opts.leaf !in ['startup', 'memory', 'benchmark', 'report', 'mode'] {
		return fail_result('apps performance', 'unknown performance leaf: ${opts.leaf}.\nRun: horneroctl apps performance --help')
	}
	if opts.leaf == 'mode' {
		return performance_mode_report(opts)
	}
	bin := apps_backend_or_placeholder(resolve_dots_performance_bin(), 'dots-performance',
		'HORNERO_PERFORMANCE_BIN', opts.dry_run, 'horneroctl apps performance ${opts.leaf} --dry-run') or {
		return fail_result('apps performance ${opts.leaf}', err.msg())
	}
	rep := apps_run_delegated(bin, ['--' + opts.leaf], opts.dry_run)
	if opts.dry_run {
		return ok_result('apps performance ${opts.leaf}', 'would run: ${rep.command_line}',
			{
			'command_line': rep.command_line
			'dry_run':      'true'
		})
	}
	return apps_delegated_ok('apps performance ${opts.leaf}', rep, {})
}

// performance_mode_profiles lists powerprofilesctl profiles natively.
fn performance_mode_profiles(bin string) ![]string {
	r := os.execute('${apps_quote_line([bin, 'list'])} 2>/dev/null')
	if r.exit_code != 0 {
		return error('powerprofilesctl list failed.')
	}
	mut profiles := []string{}
	for line in r.output.split_into_lines() {
		body := line.trim_space().trim_string_left('*').trim_space()
		// Profile rows look like `* balanced:` / `  power-saver:` (the
		// name plus a lone colon); indented `Key: value` detail rows
		// never end the line at the colon, so they are skipped.
		if !body.ends_with(':') {
			continue
		}
		name := body.trim_string_right(':').trim_space()
		if name.len == 0 || name.contains(' ') || name.contains('\t') {
			continue
		}
		profiles << name
	}
	return profiles
}

// performance_mode_report implements `apps performance mode [set]`:
// show the current profile plus available ones (read-only), or switch
// with `set` (needs --yes). Verbs mirror dots-performance-mode;
// the interactive menu, quickshell pane, and auto-cpufreq GUI stay
// legacy.
fn performance_mode_report(opts PerformanceOptions) CommandResult {
	if opts.sub !in ['', 'set'] {
		return fail_result('apps performance mode', 'unknown mode subcommand: ${opts.sub}.\nExample: horneroctl apps performance mode set balanced --dry-run')
	}
	if opts.sub == 'set' && opts.profile.len == 0 {
		return fail_result('apps performance mode set', 'missing profile.\nExample: horneroctl apps performance mode set balanced --dry-run')
	}
	bin := resolve_powerprofilesctl_bin()
	if bin.len == 0 {
		if opts.dry_run {
			ph := if opts.sub == 'set' { ['set', opts.profile] } else { ['get'] }
			rep := apps_run_leaf('powerprofilesctl', ph, true)
			return ok_result('apps performance mode', 'would run: ${rep.command_line}',
				{
				'command_line': rep.command_line
				'dry_run':      'true'
			})
		}
		return fail_result('apps performance mode', 'powerprofilesctl not found. Set HORNERO_POWERPROFILESCTL_BIN.\nExample: horneroctl apps performance mode --dry-run')
	}
	if opts.sub == '' {
		cur := os.execute('${apps_quote_line([bin, 'get'])} 2>/dev/null')
		profiles := performance_mode_profiles(bin) or { []string{} }
		current := cur.output.trim_space()
		mut lines := []string{}
		if cur.exit_code == 0 && current.len > 0 {
			lines << 'current: ${current}'
		} else {
			lines << 'current: unknown'
		}
		if profiles.len > 0 {
			lines << 'available: ${profiles.join(', ')}'
		} else {
			lines << 'available: unknown'
		}
		return ok_result('apps performance mode', lines.join('\n'), {
			'current':   current
			'available': profiles.join(',')
		})
	}
	if !opts.yes && !opts.dry_run {
		return fail_result('apps performance mode set', 'refusing to set without --yes (preview with --dry-run).\nExample: horneroctl apps performance mode set ${opts.profile} --dry-run')
	}
	profiles := performance_mode_profiles(bin) or {
		if opts.dry_run {
			rep := apps_run_leaf(bin, ['set', opts.profile], true)
			return ok_result('apps performance mode set', 'would run: ${rep.command_line}',
				{
				'command_line': rep.command_line
				'dry_run':      'true'
				'profile':      opts.profile
			})
		}
		return fail_result('apps performance mode set', 'cannot list profiles: ${err.msg()}')
	}
	if opts.profile !in profiles {
		known := if profiles.len > 0 { profiles[0] } else { 'balanced' }
		return fail_result('apps performance mode set', 'unknown profile: ${opts.profile} (available: ${profiles.join(', ')}).\nExample: horneroctl apps performance mode set ${known} --dry-run')
	}
	rep := apps_run_leaf(bin, ['set', opts.profile], opts.dry_run)
	if opts.dry_run {
		return ok_result('apps performance mode set', 'would run: ${rep.command_line}',
			{
			'command_line': rep.command_line
			'dry_run':      'true'
			'profile':      opts.profile
		})
	}
	return apps_delegated_ok('apps performance mode set', rep, {
		'profile': opts.profile
	})
}
