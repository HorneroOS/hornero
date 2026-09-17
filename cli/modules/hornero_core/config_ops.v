module hornero_core

import os

// Config operations backend: the remaining `config` leaves beyond
// snapshots (see snapshots.v).
//
// `list` prints current XDG defaults natively (terminal via
// xfce4/helpers.rc, the rest via handlr); `set <mime>
// <app>` writes via xdg-mime directly (the upstream `--set` verb
// never binds its arguments under EasyOptions, and handlr stays
// internal). `config gui` delegates to
// `dots-settings-gui` (`--pane=<name>` selects the control-center
// pane, bare invocation opens the hub). `config materialize`
// delegates to the config repo's `scripts/materialize.sh`
// (`--dest <dir> [--dry-run]`, hermetic into a temp HOME for tests).
// Path handling follows docs/PATH_CONTRACT.md: backend locations are
// resolved through the helpers below (explicit override, then the
// installed `~/.local/bin` helper, then PATH) and `--dest` is passed
// through verbatim -- never rewritten to a hardcoded `dots/*` path.

// resolve_default_apps_bin locates the `dots-default-apps` backend CLI.
// Override with HORNERO_DEFAULT_APPS_BIN.
pub fn resolve_default_apps_bin() string {
	env := os.getenv('HORNERO_DEFAULT_APPS_BIN')
	if env.len > 0 {
		return env
	}
	home_helper := os.join_path(os.home_dir(), '.local', 'bin', 'dots-default-apps')
	if os.is_file(home_helper) {
		return home_helper
	}
	return find_on_path('dots-default-apps')
}

// resolve_settings_gui_bin locates the `dots-settings-gui` backend CLI.
// Override with HORNERO_SETTINGS_GUI_BIN.
pub fn resolve_settings_gui_bin() string {
	env := os.getenv('HORNERO_SETTINGS_GUI_BIN')
	if env.len > 0 {
		return env
	}
	home_helper := os.join_path(os.home_dir(), '.local', 'bin', 'dots-settings-gui')
	if os.is_file(home_helper) {
		return home_helper
	}
	return find_on_path('dots-settings-gui')
}

// resolve_materialize_bin locates the config repo's `materialize.sh`.
// Override with HORNERO_MATERIALIZE_BIN. Unlike the `dots-*` helpers
// above there is no installed `~/.local/bin` default: the script lives
// in the config repo checkout (`scripts/`), so resolution is the
// explicit override, then PATH.
pub fn resolve_materialize_bin() string {
	env := os.getenv('HORNERO_MATERIALIZE_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('materialize.sh')
}

fn settings_gui_or_fail(helper string, dry_run bool) !string {
	bin := if helper.len > 0 { helper } else { resolve_settings_gui_bin() }
	if bin.len == 0 {
		if dry_run {
			return 'dots-settings-gui'
		}
		return error('settings-gui backend not found. Set HORNERO_SETTINGS_GUI_BIN.\nExample: horneroctl config gui --dry-run')
	}
	return bin
}

fn materialize_or_fail(helper string, dry_run bool) !string {
	bin := if helper.len > 0 { helper } else { resolve_materialize_bin() }
	if bin.len == 0 {
		if dry_run {
			return 'materialize.sh'
		}
		return error('materialize backend not found. Set HORNERO_MATERIALIZE_BIN.\nExample: horneroctl config materialize --dest /tmp/hx-dest --dry-run')
	}
	return bin
}

pub struct DefaultAppsListOptions {
pub:
	dry_run bool
	helper  string
}

// default_apps_categories mirrors the retired dots-default-apps table:
// category id, display label, probe MIME (terminal reads helpers.rc).
const default_apps_categories = [
	['file-manager', '📁 File Manager', 'inode/directory'],
	['terminal', '💻 Terminal', 'x-scheme-handler/terminal'],
	['web-browser', '🌐 Web Browser', 'x-scheme-handler/http'],
	['text-editor', '📝 Text Editor', 'text/plain'],
	['image-viewer', '🖼️  Image Viewer', 'image/png'],
	['video-player', '🎬 Video Player', 'video/mp4'],
	['audio-player', '🎵 Audio Player', 'audio/mpeg'],
	['pdf-viewer', '📄 PDF Viewer', 'application/pdf'],
]

// default_apps_terminal_default reads the terminal emulator from
// xfce4/helpers.rc, mirroring the retired script (kitty/alacritty/xterm
// get friendly names), or 'Not set' when absent.
fn default_apps_terminal_default() string {
	mut base := os.getenv('XDG_CONFIG_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.config')
	}
	raw := os.read_file(os.join_path(base, 'xfce4', 'helpers.rc')) or { return 'Not set' }
	for line in raw.split_into_lines() {
		if line.starts_with('TerminalEmulator=') {
			v := line['TerminalEmulator='.len..].trim_space()
			if v.len == 0 {
				return 'Not set'
			}
			return match v {
				'kitty' { 'Kitty Terminal' }
				'alacritty' { 'Alacritty' }
				'xterm' { 'XTerm' }
				else { v }
			}
		}
	}
	return 'Not set'
}

// default_apps_friendly_name resolves a desktop id to its Name= entry,
// searching the XDG application dirs like the retired script, falling
// back to the id itself when no .desktop file exists.
fn default_apps_friendly_name(id string, app_dirs []string) string {
	for dir in app_dirs {
		p := os.join_path(dir, id)
		raw := os.read_file(p) or { continue }
		for line in raw.split_into_lines() {
			if line.starts_with('Name=') {
				return line['Name='.len..].trim_space()
			}
		}
		return id
	}
	return id
}

// default_apps_list_report implements `config default-apps list`
// (read-only) natively: terminal via helpers.rc, MIME categories via
// handlr, friendly names via .desktop lookup. Needs no dots backend;
// --dry-run previews the handlr probe command.
pub fn default_apps_list_report(opts DefaultAppsListOptions) CommandResult {
	mut handlr := resolve_handlr_bin()
	if handlr.len == 0 {
		if opts.dry_run {
			handlr = 'handlr'
		} else {
			return fail_result('config default-apps list', 'handlr not found (needed for MIME lookups). Set HORNERO_HANDLR_BIN.\nExample: horneroctl config default-apps list --dry-run')
		}
	}
	if opts.dry_run {
		probe := command_line(handlr, ['get', 'inode/directory'])
		return ok_result('config default-apps list', 'would query handlr for 8 default associations (--list)',
			{
			'command_line': probe
			'dry_run':      'true'
		})
	}
	app_dirs := [os.join_path(os.home_dir(), '.local', 'share', 'applications'),
		'/usr/share/applications']
	mut lines := ['Current Default Applications:', '==============================', '']
	mut data := map[string]string{}
	for cat in default_apps_categories {
		id := cat[0]
		label := cat[1]
		name := if id == 'terminal' {
			default_apps_terminal_default()
		} else {
			rep := run_exec(ExecSpec{
				prog: handlr
				args: ['get', cat[2]]
			})
			app := rep.output.trim_space()
			if !rep.ok || app.len == 0 {
				'Not set'
			} else {
				default_apps_friendly_name(app, app_dirs)
			}
		}
		mut row := label
		for row.len < 20 {
			row += ' '
		}
		lines << '${row} ${name}'
		data[id] = if name == 'Not set' { 'Not set' } else { name }
	}
	return ok_result('config default-apps list', lines.join('\n'), data)
}

pub struct MaterializeOptions {
pub:
	dest    string
	dry_run bool
	yes     bool
	helper  string
}

// materialize_report implements `config materialize --dest <dir>` by
// delegating to `materialize.sh --dest <dir>` (verified backend
// verbs). Mutating: needs --yes; --dry-run only previews (passing
// `--dry-run` through so the backend previews too). The destination
// travels verbatim: callers pass the canonical target explicitly and
// nothing here rewrites it to a legacy `dots/*` path.
pub fn materialize_report(opts MaterializeOptions) CommandResult {
	if opts.dest.len == 0 {
		return fail_result('config materialize', 'missing --dest.\nExample: horneroctl config materialize --dest /tmp/hx-dest --dry-run')
	}
	if !opts.yes && !opts.dry_run {
		return fail_result('config materialize', 'refusing to materialize into ${opts.dest} without --yes (preview with --dry-run).\nExample: horneroctl config materialize --dest ${opts.dest} --dry-run')
	}
	bin := materialize_or_fail(opts.helper, opts.dry_run) or {
		return fail_result('config materialize', err.msg())
	}
	mut args := ['--dest', opts.dest]
	if opts.dry_run {
		args << '--dry-run'
	}
	rep := run_exec(ExecSpec{
		prog:    bin
		args:    args
		dry_run: opts.dry_run
	})
	if opts.dry_run {
		return ok_result('config materialize', 'would run: ${rep.command_line}', {
			'command_line': rep.command_line
			'dry_run':      'true'
		})
	}
	if rep.ok {
		return ok_result('config materialize', rep.output, {
			'command_line': rep.command_line
			'dest':         opts.dest
		})
	}
	return fail_result('config materialize', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
}

// valid_gui_panes are the control-center panes `dots-settings-gui`
// documents (`--pane=NAME`); anything else is a caller-side typo.
const valid_gui_panes = ['network', 'bluetooth', 'audio', 'appearance', 'taskbar', 'launcher',
	'dashboard', 'system']

pub struct SettingsGuiOptions {
pub:
	pane    string
	dry_run bool
	helper  string
}

// settings_gui_report implements `config gui [--pane <name>]` by
// delegating to `dots-settings-gui [--pane=<name>]` (verified backend
// verbs). Launcher semantics (mirroring `shell ipc`): --dry-run
// previews, no --yes needed.
pub fn settings_gui_report(opts SettingsGuiOptions) CommandResult {
	if opts.pane.len > 0 && opts.pane !in valid_gui_panes {
		return fail_result('config gui', 'invalid pane: ${opts.pane} (want network|bluetooth|audio|appearance|taskbar|launcher|dashboard|system).\nExample: horneroctl config gui --pane appearance --dry-run')
	}
	bin := settings_gui_or_fail(opts.helper, opts.dry_run) or {
		return fail_result('config gui', err.msg())
	}
	mut args := []string{}
	if opts.pane.len > 0 {
		args << '--pane=${opts.pane}'
	}
	rep := run_exec(ExecSpec{
		prog:    bin
		args:    args
		dry_run: opts.dry_run
	})
	if opts.dry_run {
		return ok_result('config gui', 'would run: ${rep.command_line}', {
			'command_line': rep.command_line
			'dry_run':      'true'
		})
	}
	if rep.ok {
		return ok_result('config gui', rep.output, {
			'command_line': rep.command_line
		})
	}
	return fail_result('config gui', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
}

// Config migration backend: the one-shot `dots/*` to `hornero/*` move.
// `config migrate` delegates out-of-process to the config repo's
// `lib/dots/migrate-to-hornero.sh` (copy-if-absent over the Hornero-owned
// rows only: themes, presets, the preset pointer, scheme.json plus scheme
// state, the wallpaper pointer, and notifs), following the same pattern as
// `config materialize` above: HORNERO_MIGRATE_BIN override, --yes required
// to mutate, --dry-run previews (passed through so the backend previews
// too), and machine-readable per-row output.
//
// Backend row contract: the migrator prints one `ROW <domain> <status>`
// line per row to stdout, where domain is one of migrate_row_domains and
// status is one token (copied, already-canonical, absent-source, skipped,
// dry-run, error) with optional free-text detail after it. Lines of the
// form `<domain>: <status>` for a known domain are accepted too; anything
// else passes through verbatim into the human message.

// migrate_row_domains are the Hornero-owned dots/* rows the migrator moves
// (docs/PATH_CONTRACT.md rows 1-5, 9-10; snapshots and wallpaper binaries
// stay out: no verified backend verb moves them yet).
const migrate_row_domains = ['themes', 'presets', 'preset-pointer', 'scheme', 'scheme-state',
	'wallpaper-pointer', 'notifs']

// resolve_migrate_bin locates the `migrate-to-hornero.sh` backend.
// Override with HORNERO_MIGRATE_BIN. Like materialize (and unlike the
// installed `dots-*` helpers) there is no `~/.local/bin` default: the
// script lives in the config repo checkout (`lib/dots/`), so resolution
// is the explicit override, then PATH.
pub fn resolve_migrate_bin() string {
	env := os.getenv('HORNERO_MIGRATE_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('migrate-to-hornero.sh')
}

fn migrate_or_fail(helper string, dry_run bool) !string {
	bin := if helper.len > 0 { helper } else { resolve_migrate_bin() }
	if bin.len == 0 {
		if dry_run {
			return 'migrate-to-hornero.sh'
		}
		return error('migrate backend not found. Set HORNERO_MIGRATE_BIN.\nExample: horneroctl config migrate --dry-run')
	}
	return bin
}

pub struct MigrateRow {
pub:
	domain string
	status string
	detail string
}

fn split_row_tail(tail string) (string, string) {
	for i := 0; i < tail.len; i++ {
		if tail[i] == ` ` || tail[i] == `\t` {
			return tail[..i], tail[i + 1..].trim_space()
		}
	}
	return tail, ''
}

// parse_migrate_rows extracts per-row results from backend stdout.
// Canonical form is `ROW <domain> <status> [detail]`; `<domain>: <status>`
// lines for a known domain are accepted as well. Anything else is ignored
// here (it still reaches the human message verbatim).
pub fn parse_migrate_rows(output string) []MigrateRow {
	mut rows := []MigrateRow{}
	for line in output.split_into_lines() {
		t := line.trim_space()
		if t.starts_with('ROW ') {
			rest := t[4..].trim_space()
			if rest.len == 0 {
				continue
			}
			domain, tail := split_row_tail(rest)
			if domain !in migrate_row_domains {
				continue
			}
			status, detail := split_row_tail(tail)
			if status.len == 0 {
				continue
			}
			rows << MigrateRow{
				domain: domain
				status: status
				detail: detail
			}
			continue
		}
		for d in migrate_row_domains {
			prefix := '${d}:'
			if t.starts_with(prefix) {
				status := t[prefix.len..].trim_space()
				if status.len > 0 {
					rows << MigrateRow{
						domain: d
						status: status
						detail: ''
					}
				}
				break
			}
		}
	}
	return rows
}

pub struct MigrateOptions {
pub:
	dry_run bool
	yes     bool
	helper  string
}

// migrate_report implements `config migrate [--dry-run] [--yes]` by
// delegating to `migrate-to-hornero.sh [--dry-run]` (verified backend
// verbs). Mutating: needs --yes; --dry-run only previews. On success the
// per-row results are machine-readable: one `row.<domain>` data entry per
// parsed row plus a `rows` count (--json carries them; the human message
// lists one line per row).
pub fn migrate_report(opts MigrateOptions) CommandResult {
	if !opts.yes && !opts.dry_run {
		return fail_result('config migrate', 'refusing to migrate without --yes (preview with --dry-run).\nExample: horneroctl config migrate --dry-run')
	}
	bin := migrate_or_fail(opts.helper, opts.dry_run) or {
		return fail_result('config migrate', err.msg())
	}
	mut args := []string{}
	if opts.dry_run {
		args << '--dry-run'
	}
	if opts.yes {
		args << '--yes'
	}
	rep := run_exec(ExecSpec{
		prog:    bin
		args:    args
		dry_run: opts.dry_run
	})
	if opts.dry_run {
		return ok_result('config migrate', 'would run: ${rep.command_line}', {
			'command_line': rep.command_line
			'dry_run':      'true'
		})
	}
	if rep.ok {
		rows := parse_migrate_rows(rep.output)
		mut data := map[string]string{}
		data['command_line'] = rep.command_line
		data['rows'] = rows.len.str()
		if rows.len == 0 {
			msg := if rep.output.len > 0 { rep.output } else { 'backend completed with no output' }
			return ok_result('config migrate', msg, data)
		}
		mut lines := []string{}
		for r in rows {
			value := if r.detail.len > 0 { '${r.status}: ${r.detail}' } else { r.status }
			data['row.${r.domain}'] = value
			lines << '${r.status}  ${r.domain}: ${if r.detail.len > 0 {
				r.detail
			} else {
				'(no detail)'
			}}'
		}
		lines << 'config migrate: ${rows.len} row(s) reported'
		return ok_result('config migrate', lines.join('\n'), data)
	}
	return fail_result('config migrate', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
}
