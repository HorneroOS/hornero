module hornero_core

import os

// Config operations backend: the remaining `config` leaves beyond
// snapshots (see snapshots.v).
//
// `list` prints current XDG defaults natively; `set <mime> <app>` writes
// via xdg-mime. `config gui` opens the Hornero Control Center through the
// shell-owned IPC contract; there is no helper executable or duplicate pane registry.
// `config materialize` delegates to the config repo's materializer.

// resolve_materialize_bin locates the config repo's `materialize.sh`.
// Override with HORNERO_MATERIALIZE_BIN; otherwise resolve the
// materializer from PATH.
pub fn resolve_materialize_bin() string {
	env := os.getenv('HORNERO_MATERIALIZE_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('materialize.sh')
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
}

// default_apps_categories mirrors the retired horneroctl config default-apps table:
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
	}
	return id
}

// default_apps_list_report implements `config default-apps list`
// (read-only) natively: terminal via helpers.rc, MIME categories via
// handlr, friendly names via .desktop lookup. Needs no external helper;
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
}

// materialize_report implements `config materialize --dest <dir>` by
// delegating to `materialize.sh --dest <dir>` (verified backend
// verbs). Mutating: needs --yes; --dry-run only previews (passing
// `--dry-run` through so the backend previews too). The destination
// travels verbatim: callers pass the canonical target explicitly and
// the destination is passed through unchanged.
pub fn materialize_report(opts MaterializeOptions) CommandResult {
	if opts.dest.len == 0 {
		return fail_result('config materialize', 'missing --dest.\nExample: horneroctl config materialize --dest /tmp/hx-dest --dry-run')
	}
	if !opts.yes && !opts.dry_run {
		return fail_result('config materialize', 'refusing to materialize into ${opts.dest} without --yes (preview with --dry-run).\nExample: horneroctl config materialize --dest ${opts.dest} --dry-run')
	}
	bin := materialize_or_fail('', opts.dry_run) or {
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

pub struct SettingsGuiOptions {
pub:
	pane    string
	dry_run bool
}

// settings_gui_report opens Settings through the running Hornero Shell.
// The shell's PaneRegistry is the authority for valid destinations, avoiding
// a second list in horneroctl.
pub fn settings_gui_report(opts SettingsGuiOptions) CommandResult {
	mut passthrough := ['call', 'controlCenter', 'open']
	passthrough << if opts.pane.len > 0 { opts.pane } else { 'network' }
	result := ipc_report(IpcOptions{ passthrough: passthrough, dry_run: opts.dry_run })
	if result.ok && opts.dry_run {
		return ok_result('config gui', result.message, result.data)
	}
	if result.ok && result.message.contains('error:') {
		return fail_result('config gui', result.message)
	}
	if result.ok {
		return ok_result('config gui', result.message, result.data)
	}
	return fail_result('config gui', 'Could not open Hornero Settings. Is Hornero Shell running in this desktop session?\n${result.message}')
}
