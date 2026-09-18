module hornero_core

import os
import time

// Screen capture: screenshots (`sss`), screen recordings
// (`gpu-screen-recorder`), and the clipboard manager picker
// (copyq/cliphist/wl-paste), mirroring the dots-screenshooter,
// dots-recorder, and dots-clipboard reference scripts.
//
// Screenshot and record leaves mutate (files, processes) and need --yes;
// --dry-run only previews. `clipboard` only opens read views (the picker,
// a history list, or a paste preview), so it needs no --yes — like
// `config gui` / `welcome open`. The interactive cliphist pick
// (list → prompt → wl-copy) stays in dots-clipboard: horneroctl lists the
// history non-interactively and never prompts.
// Recorder state (current file, pause flag) lives under XDG state
// (dots/recorder), matching $XDG_STATE_HOME conventions; the output and
// picture directories follow CAELESTIA_RECORDINGS_DIR, XDG_VIDEOS_DIR,
// and XDG_PICTURES_DIR exactly like the scripts.

// resolve_sss_bin locates the sss screenshot tool.
// Override with HORNERO_SSS_BIN.
pub fn resolve_sss_bin() string {
	env := os.getenv('HORNERO_SSS_BIN')
	if env.len > 0 {
		return env
	}
	home_helper := os.join_path(os.home_dir(), '.local', 'bin', 'sss')
	if os.is_file(home_helper) {
		return home_helper
	}
	return find_on_path('sss')
}

// resolve_gsr_bin locates gpu-screen-recorder.
// Override with HORNERO_GPU_SCREEN_RECORDER_BIN.
pub fn resolve_gsr_bin() string {
	env := os.getenv('HORNERO_GPU_SCREEN_RECORDER_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('gpu-screen-recorder')
}

// recorder_match is the pgrep/pkill pattern for the recorder process.
// Override with HORNERO_RECORDER_MATCH (a test seam so tests never match
// a real recording).
pub fn recorder_match() string {
	env := os.getenv('HORNERO_RECORDER_MATCH')
	if env.len > 0 {
		return env
	}
	return 'gpu-screen-recorder'
}

// resolve_copyq_bin locates copyq. Override with HORNERO_COPYQ_BIN.
pub fn resolve_copyq_bin() string {
	env := os.getenv('HORNERO_COPYQ_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('copyq')
}

// resolve_cliphist_bin locates cliphist. Override with HORNERO_CLIPHIST_BIN.
pub fn resolve_cliphist_bin() string {
	env := os.getenv('HORNERO_CLIPHIST_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('cliphist')
}

// resolve_wl_paste_bin locates wl-paste. Override with HORNERO_WL_PASTE_BIN.
pub fn resolve_wl_paste_bin() string {
	env := os.getenv('HORNERO_WL_PASTE_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('wl-paste')
}

// capture_backend_present reports whether a resolved backend names
// something runnable: a path must exist, a bare name must resolve
// on PATH.
fn capture_backend_present(bin string) bool {
	if bin.contains('/') {
		return os.is_file(bin)
	}
	return find_on_path(bin).len > 0
}

// capture_backend_or_placeholder resolves one capture backend for real
// runs, or the bare program name for dry-run previews when nothing is
// installed. A stale override (set but missing) fails with the override
// hint instead of a raw backend failure.
fn capture_backend_or_placeholder(resolved string, prog string, env_key string, dry_run bool, example string) !string {
	if resolved.len == 0 {
		if dry_run {
			return prog
		}
		return error('${prog} not found on PATH. Set ${env_key}.\nExample: ${example}')
	}
	if !dry_run && !capture_backend_present(resolved) {
		return error('${prog} backend not found: ${resolved}. Set ${env_key}.\nExample: ${example}')
	}
	return resolved
}

// recorder_pgrep_pattern brackets the first character of the match so the
// pgrep/pkill shell wrapper can never match its own command line: the
// literal '[g]pu-screen-recorder' text does not satisfy the bracket
// regex, while real recorder command lines still do.
fn recorder_pgrep_pattern() string {
	m := recorder_match()
	if m.len == 0 || m[0] >= 128 {
		return m
	}
	return '[' + m[0..1] + ']' + m[1..]
}

// recorder_running reports whether the recorder process is alive.
// pgrep -f also lists the shell wrapper that runs it, whose command line
// contains the pattern: any match on our own pid chain is discarded so a
// host shell quirk can never fake a running recorder (CI hermeticity).
fn recorder_running() bool {
	r := os.execute(command_line('pgrep', ['-f', recorder_pgrep_pattern()]))
	if r.exit_code != 0 {
		return false
	}
	own := [os.getpid(), os.getppid()]
	for line in r.output.split_into_lines() {
		pid := line.int()
		if pid > 0 && pid !in own {
			return true
		}
	}
	return false
}

fn recorder_state_dir() string {
	mut base := os.getenv('XDG_STATE_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.local', 'state')
	}
	return os.join_path(base, 'dots', 'recorder')
}

fn recorder_current_file() string {
	return os.join_path(recorder_state_dir(), 'current_file')
}

fn recorder_paused_file() string {
	return os.join_path(recorder_state_dir(), 'paused')
}

fn screenshot_default_path() string {
	mut dir := os.getenv('XDG_PICTURES_DIR')
	if dir.len == 0 {
		dir = os.join_path(os.home_dir(), 'Pictures')
	}
	ts := time.now().strftime('%Y%m%d_%H%M%S')
	return os.join_path(dir, 'screenshot_${ts}.png')
}

fn recorder_output_dir() string {
	rec := os.getenv('CAELESTIA_RECORDINGS_DIR')
	if rec.len > 0 {
		return rec
	}
	mut vids := os.getenv('XDG_VIDEOS_DIR')
	if vids.len == 0 {
		vids = os.join_path(os.home_dir(), 'Videos')
	}
	return os.join_path(vids, 'Recordings')
}

fn recorder_default_file() string {
	ts := time.now().strftime('%Y%m%d_%H-%M-%S')
	return os.join_path(recorder_output_dir(), 'recording_${ts}.mp4')
}

// recorder_primary_monitor reads the first monitor from
// `gsr --list-monitors` (name before the first '|'), falling back to
// eDP-1 like the dots-recorder wrapper. have_bin false (or any probe
// failure) yields the fallback without executing anything.
fn recorder_primary_monitor(gsr string, have_bin bool) string {
	if !have_bin {
		return 'eDP-1'
	}
	r := os.execute('${command_line(gsr, ['--list-monitors'])} 2>/dev/null')
	if r.exit_code != 0 {
		return 'eDP-1'
	}
	lines := r.output.split_into_lines()
	if lines.len == 0 {
		return 'eDP-1'
	}
	name := lines[0].split('|')[0].trim_space()
	if name.len == 0 {
		return 'eDP-1'
	}
	return name
}

fn capture_notify(icon string, title string, body string) {
	bin := find_on_path('notify-send')
	if bin.len == 0 {
		return
	}
	os.execute('${command_line(bin, ['-i', icon, '-a', 'dots-recorder', title, body])} 2>/dev/null || true')
}

pub struct ScreenshotOptions {
pub:
	region  bool
	output  string // explicit --output, else the dated Pictures default
	dry_run bool
	yes     bool
}

// screenshot_report implements `capture screenshot` via sss: fullscreen
// (`--screen --current --copy --output <file>`) by default, or a bare
// interactive region select with --region — the dots-screenshooter
// contract. Mutating: needs --yes; --dry-run only previews.
pub fn screenshot_report(opts ScreenshotOptions) CommandResult {
	if !opts.yes && !opts.dry_run {
		return fail_result('capture screenshot', 'refusing to capture without --yes (preview with --dry-run).\nExample: horneroctl capture screenshot --dry-run')
	}
	bin := capture_backend_or_placeholder(resolve_sss_bin(), 'sss', 'HORNERO_SSS_BIN',
		opts.dry_run, 'horneroctl capture screenshot --dry-run') or {
		return fail_result('capture screenshot', err.msg())
	}
	out := if opts.output.len > 0 { opts.output } else { screenshot_default_path() }
	args := if opts.region {
		[]string{}
	} else {
		['--screen', '--current', '--copy', '--output', out]
	}
	rep := run_exec(ExecSpec{
		prog:    bin
		args:    args
		dry_run: opts.dry_run
	})
	if opts.dry_run {
		return ok_result('capture screenshot', 'would run: ${rep.command_line}', {
			'command_line': rep.command_line
			'dry_run':      'true'
			'output':       out
		})
	}
	if rep.ok {
		if opts.region {
			msg := if rep.output.len > 0 { rep.output } else { 'region capture finished' }
			return ok_result('capture screenshot', msg, {
				'command_line': rep.command_line
			})
		}
		return ok_result('capture screenshot', 'saved screenshot: ${out}', {
			'command_line': rep.command_line
			'output':       out
		})
	}
	return fail_result('capture screenshot', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
}

pub struct RecordStartOptions {
pub:
	region  bool
	sound   bool
	fps     int // frames per second, 30 when unset
	dry_run bool
	yes     bool
}

// record_start_args builds the gpu-screen-recorder argv: capture target,
// fps/container/cursor/cpu-fallback, optional desktop audio, output file.
fn record_start_args(monitor string, region bool, sound bool, fps int, file string) []string {
	mut args := []string{}
	if region {
		args << '-w'
		args << 'region'
	} else {
		args << '-w'
		args << monitor
	}
	args << '-f'
	args << fps.str()
	args << '-c'
	args << 'mp4'
	args << '-cursor'
	args << 'yes'
	args << '-fallback-cpu-encoding'
	args << 'yes'
	if sound {
		args << '-a'
		args << 'default_output'
	}
	args << '-o'
	args << file
	return args
}

// record_start_report implements `capture record start`: detached launch,
// state-file bookkeeping, and a pgrep confirmation — the dots-recorder
// start contract. Mutating: needs --yes; --dry-run only previews and
// never launches. A live recorder turns start into an ok no-op.
pub fn record_start_report(opts RecordStartOptions) CommandResult {
	if !opts.yes && !opts.dry_run {
		return fail_result('capture record start', 'refusing to record without --yes (preview with --dry-run).\nExample: horneroctl capture record start --dry-run')
	}
	if recorder_running() {
		return ok_result('capture record start', 'a recording is already running (start is a no-op)',
			{
				'running': 'true'
			})
	}
	resolved_gsr := resolve_gsr_bin()
	have_bin := resolved_gsr.len > 0
	gsr := capture_backend_or_placeholder(resolved_gsr, 'gpu-screen-recorder', 'HORNERO_GPU_SCREEN_RECORDER_BIN',
		opts.dry_run, 'horneroctl capture record start --dry-run') or {
		if !opts.dry_run {
			capture_notify('dialog-error', 'Recording failed', 'gpu-screen-recorder is not installed')
		}
		return fail_result('capture record start', err.msg())
	}
	fps := if opts.fps > 0 { opts.fps } else { 30 }
	monitor := if opts.region { '' } else { recorder_primary_monitor(gsr, have_bin) }
	file := recorder_default_file()
	args := record_start_args(monitor, opts.region, opts.sound, fps, file)
	if opts.dry_run {
		return ok_result('capture record start', 'would run: ${command_line(gsr, args)}',
			{
				'command_line': command_line(gsr, args)
				'dry_run':      'true'
				'file':         file
			})
	}
	os.mkdir_all(recorder_state_dir()) or {}
	os.mkdir_all(recorder_output_dir()) or {}
	line := command_line(gsr, args)
	os.execute('${line} >/dev/null 2>&1 &')
	os.write_file(recorder_current_file(), file) or {}
	time.sleep(1 * time.second)
	if recorder_running() {
		capture_notify('media-record', 'Recording started', file)
		return ok_result('capture record start', 'recording started: ${file}', {
			'command_line': line
			'file':         file
		})
	}
	os.rm(recorder_current_file()) or {}
	capture_notify('dialog-error', 'Recording failed', 'gpu-screen-recorder failed to start')
	return fail_result('capture record start', 'gpu-screen-recorder failed to start (no process after launch).')
}

pub struct RecordStopOptions {
pub:
	dry_run bool
	yes     bool
}

// record_stop_report implements `capture record stop`: kill the recorder,
// drop the state files, notify. Idempotent (exit 0 with nothing running).
// Mutating: needs --yes; --dry-run only previews.
pub fn record_stop_report(opts RecordStopOptions) CommandResult {
	if !opts.yes && !opts.dry_run {
		return fail_result('capture record stop', 'refusing to stop without --yes (preview with --dry-run).\nExample: horneroctl capture record stop --dry-run')
	}
	line := command_line('pkill', ['-f', recorder_pgrep_pattern()])
	if opts.dry_run {
		return ok_result('capture record stop', 'would run: ${line} (then drop the recorder state)',
			{
				'command_line': line
				'dry_run':      'true'
			})
	}
	cur := os.read_file(recorder_current_file()) or { '' }
	rep := run_exec(ExecSpec{
		prog:    'pkill'
		args:    ['-f', recorder_pgrep_pattern()]
		dry_run: false
	})
	os.rm(recorder_paused_file()) or {}
	os.rm(recorder_current_file()) or {}
	trimmed := cur.trim_space()
	if trimmed.len > 0 {
		capture_notify('media-playback-stop', 'Recording saved', trimmed)
		return ok_result('capture record stop', 'stopped recording: ${trimmed}', {
			'command_line': rep.command_line
			'file':         trimmed
		})
	}
	return ok_result('capture record stop', 'no recording state found (nothing to stop)',
		{
			'command_line': rep.command_line
		})
}

pub struct RecordPauseOptions {
pub:
	dry_run bool
	yes     bool
}

// record_pause_report implements `capture record pause`: STOP/CONT toggle
// tracked by the paused flag file. A missing recorder is an ok no-op.
// Mutating: needs --yes; --dry-run only previews.
pub fn record_pause_report(opts RecordPauseOptions) CommandResult {
	if !opts.yes && !opts.dry_run {
		return fail_result('capture record pause', 'refusing to pause without --yes (preview with --dry-run).\nExample: horneroctl capture record pause --dry-run')
	}
	paused := os.is_file(recorder_paused_file())
	sig := if paused { '-CONT' } else { '-STOP' }
	line := command_line('pkill', [sig, '-f', recorder_pgrep_pattern()])
	if opts.dry_run {
		verb := if paused { 'resume' } else { 'pause' }
		return ok_result('capture record pause', 'would ${verb}: ${line}', {
			'command_line': line
			'dry_run':      'true'
		})
	}
	if !recorder_running() {
		return ok_result('capture record pause', 'no recording running', {
			'running': 'false'
		})
	}
	rep := run_exec(ExecSpec{
		prog:    'pkill'
		args:    [sig, '-f', recorder_pgrep_pattern()]
		dry_run: false
	})
	if !rep.ok {
		return fail_result('capture record pause', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
	}
	if paused {
		os.rm(recorder_paused_file()) or {}
		return ok_result('capture record pause', 'resumed recording', {
			'command_line': rep.command_line
		})
	}
	os.mkdir_all(recorder_state_dir()) or {}
	os.write_file(recorder_paused_file(), '') or {}
	return ok_result('capture record pause', 'paused recording', {
		'command_line': rep.command_line
	})
}

pub struct ClipboardOptions {
pub:
	backend string // auto | copyq | cliphist | minimal (auto when empty)
	dry_run bool
}

fn clipboard_is_wayland() bool {
	return os.getenv('XDG_SESSION_TYPE') == 'wayland'
}

// clipboard_pick_backend resolves the effective backend: explicit wins,
// else the dots-clipboard order (Wayland: copyq, cliphist, minimal;
// otherwise copyq, minimal).
fn clipboard_pick_backend(explicit string) string {
	if explicit.len > 0 && explicit != 'auto' {
		return explicit
	}
	if clipboard_is_wayland() {
		if resolve_copyq_bin().len > 0 {
			return 'copyq'
		}
		if resolve_cliphist_bin().len > 0 {
			return 'cliphist'
		}
		return 'minimal'
	}
	if resolve_copyq_bin().len > 0 {
		return 'copyq'
	}
	return 'minimal'
}

// clipboard_minimal_output runs `wl-paste | head -c 500` via the shell so
// the byte limit matches the dots-clipboard minimal fallback exactly.
fn clipboard_minimal_output(wl_paste string) ExecReport {
	line := '${command_line(wl_paste, [])} | head -c 500'
	r := os.execute(line)
	return ExecReport{
		command_line: line
		ok:           r.exit_code == 0
		output:       r.output
		exit_code:    r.exit_code
		was_dry_run:  false
	}
}

// clipboard_report implements `capture clipboard`: open the picker
// (copyq), list history (cliphist, top 25), or preview the paste
// (minimal). Read-only views only: needs no --yes; --dry-run previews.
pub fn clipboard_report(opts ClipboardOptions) CommandResult {
	if opts.backend !in ['', 'auto', 'copyq', 'cliphist', 'minimal'] {
		return fail_result('capture clipboard', 'unknown backend: ${opts.backend}.\nValid values: auto copyq cliphist minimal.\nExample: horneroctl capture clipboard --backend copyq --dry-run')
	}
	backend := clipboard_pick_backend(opts.backend)
	if backend == 'copyq' {
		bin := capture_backend_or_placeholder(resolve_copyq_bin(), 'copyq', 'HORNERO_COPYQ_BIN',
			opts.dry_run, 'horneroctl capture clipboard --backend copyq --dry-run') or {
			return fail_result('capture clipboard', err.msg())
		}
		rep := run_exec(ExecSpec{
			prog:    bin
			args:    ['show']
			dry_run: opts.dry_run
		})
		if opts.dry_run {
			return ok_result('capture clipboard', 'would run: ${rep.command_line}', {
				'command_line': rep.command_line
				'dry_run':      'true'
				'backend':      'copyq'
			})
		}
		if rep.ok {
			return ok_result('capture clipboard', 'opened copyq clipboard manager', {
				'command_line': rep.command_line
				'backend':      'copyq'
			})
		}
		return fail_result('capture clipboard', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
	}
	if backend == 'cliphist' {
		if !clipboard_is_wayland() {
			return fail_result('capture clipboard', 'cliphist is Wayland-only.\nExample: horneroctl capture clipboard --backend minimal')
		}
		bin := capture_backend_or_placeholder(resolve_cliphist_bin(), 'cliphist', 'HORNERO_CLIPHIST_BIN',
			opts.dry_run, 'horneroctl capture clipboard --backend cliphist --dry-run') or {
			return fail_result('capture clipboard', err.msg())
		}
		rep := run_exec(ExecSpec{
			prog:    bin
			args:    ['list']
			dry_run: opts.dry_run
		})
		if opts.dry_run {
			return ok_result('capture clipboard', 'would run: ${rep.command_line}', {
				'command_line': rep.command_line
				'dry_run':      'true'
				'backend':      'cliphist'
			})
		}
		if !rep.ok {
			return fail_result('capture clipboard', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
		}
		mut entries := []string{}
		for line in rep.output.split_into_lines() {
			if entries.len >= 25 {
				break
			}
			if line.trim_space().len == 0 {
				continue
			}
			entries << line
		}
		if entries.len == 0 {
			return fail_result('capture clipboard', 'no clipboard history (cliphist list is empty).')
		}
		mut out := ['Clipboard history:']
		for i, e in entries {
			out << '  ${i + 1}) ${e}'
		}
		return ok_result('capture clipboard', out.join('\n'), {
			'command_line': rep.command_line
			'backend':      'cliphist'
		})
	}
	bin := resolve_wl_paste_bin()
	if !capture_backend_present(bin) {
		if opts.dry_run {
			return ok_result('capture clipboard', 'would run: wl-paste | head -c 500',
				{
					'command_line': 'wl-paste | head -c 500'
					'dry_run':      'true'
					'backend':      'minimal'
				})
		}
		return ok_result('capture clipboard', '[dots-clipboard] minimal fallback\n(no data)',
			{
				'backend': 'minimal'
			})
	}
	if opts.dry_run {
		return ok_result('capture clipboard', 'would run: ${command_line(bin, [])} | head -c 500',
			{
				'command_line': '${command_line(bin, [])} | head -c 500'
				'dry_run':      'true'
				'backend':      'minimal'
			})
	}
	rep := clipboard_minimal_output(bin)
	if !rep.ok {
		return fail_result('capture clipboard', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
	}
	msg := if rep.output.len > 0 { rep.output } else { '(empty)' }
	return ok_result('capture clipboard', '[dots-clipboard] minimal fallback\n${msg}',
		{
			'command_line': rep.command_line
			'backend':      'minimal'
		})
}
