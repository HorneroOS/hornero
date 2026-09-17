module hornero_core

import os

// Native external-tool backends for the appearance domain. Everything
// implemented IN dots-* bash lives in V now; only genuinely external
// programs (compositor tools, settings daemons, interpreters) stay
// backends, each with a HORNERO_*_BIN override. No dots-* delegation
// remains: HORNEROCTL_DELEGATED shims are gone with the scripts.

// strict_command_line quotes every word with single quotes (the shared
// strict quoter): appearance args are caller-controlled (theme ids,
// wallpaper paths, accent seeds like `#8839ef` that would otherwise
// become shell comments), so the weak space-only quoter is unsafe here.
pub fn strict_command_line(prog string, args []string) string {
	mut parts := [wallpaper_shell_quote(prog)]
	for a in args {
		parts << wallpaper_shell_quote(a)
	}
	return parts.join(' ')
}

// strict_exec runs prog with args under strict quoting, or previews the
// exact line when dry_run is set. Dry-run previews never execute.
pub fn strict_exec(prog string, args []string, dry_run bool) ExecReport {
	line := strict_command_line(prog, args)
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

// backend_or_empty resolves an explicit HORNERO_*_BIN override (returned
// as-is, even when missing, so the caller can fail loudly) or a PATH
// lookup ('' when absent, so the caller can degrade gracefully).
fn backend_or_empty(env_key string, prog string) string {
	env := os.getenv(env_key)
	if env.len > 0 {
		return env
	}
	return find_on_path(prog)
}

// backend_or_fail is backend_or_empty that fails when nothing resolves.
// An explicit override pointing at a missing file fails too (but never
// on dry-run: previews must not need anything installed).
fn backend_or_fail(env_key string, prog string, dry_run bool) !string {
	bin := backend_or_empty(env_key, prog)
	if bin.len == 0 {
		return error('${prog} not found on PATH. Set ${env_key}.')
	}
	if !dry_run {
		override := os.getenv(env_key)
		if override.len > 0 && !os.exists(override) {
			return error('${env_key} points at a missing file: ${override}')
		}
	}
	return bin
}

// resolve_gsettings_bin locates gsettings (GNOME settings daemon client).
// Override with HORNERO_GSETTINGS_BIN.
pub fn resolve_gsettings_bin() string {
	return backend_or_empty('HORNERO_GSETTINGS_BIN', 'gsettings')
}

// resolve_xrdb_bin locates xrdb (X resource palette input).
// Override with HORNERO_XRDB_BIN.
pub fn resolve_xrdb_bin() string {
	return backend_or_empty('HORNERO_XRDB_BIN', 'xrdb')
}

// resolve_wal_bin locates pywal (palette generation from wallpapers).
// Override with HORNERO_WAL_BIN.
pub fn resolve_wal_bin() string {
	return backend_or_empty('HORNERO_WAL_BIN', 'wal')
}

// resolve_pkill_bin locates pkill (backend process control).
// Override with HORNERO_PKILL_BIN. Falls back to the bare name so
// stop-escalation call sites always have something to exec.
pub fn resolve_pkill_bin() string {
	env := os.getenv('HORNERO_PKILL_BIN')
	if env.len > 0 {
		return env
	}
	bin := find_on_path('pkill')
	if bin.len > 0 {
		return bin
	}
	return 'pkill'
}

// resolve_m3_script locates the M3 synthesis script
// (generate-m3-colors.py, needs a Python with materialyoucolor).
// Override with HORNERO_M3_SCRIPT.
pub fn resolve_m3_script() string {
	env := os.getenv('HORNERO_M3_SCRIPT')
	if env.len > 0 {
		return env
	}
	return os.join_path(os.home_dir(), '.local', 'lib', 'dots', 'generate-m3-colors.py')
}

// m3_python_candidates lists interpreters to probe, richest first:
// explicit override, /usr/bin/python3 (Arch python-materialyoucolor),
// then PATH python3. Probing executes nothing here; the caller probes
// with `import materialyoucolor` only on real runs, never on dry-run.
pub fn m3_python_candidates() []string {
	mut out := []string{}
	env := os.getenv('HORNERO_M3_PYTHON_BIN')
	if env.len > 0 {
		out << env
	}
	if '/usr/bin/python3' !in out {
		out << '/usr/bin/python3'
	}
	out << 'python3'
	return out
}

// resolve_m3_python picks the interpreter for a real M3 run by probing
// `import materialyoucolor`. Dry-run never probes: it returns the
// override (or /usr/bin/python3 when present, else python3) for preview.
pub fn resolve_m3_python(dry_run bool) !string {
	cands := m3_python_candidates()
	override := os.getenv('HORNERO_M3_PYTHON_BIN')
	if dry_run {
		if override.len > 0 {
			return override
		}
		for c in cands {
			if c == 'python3' {
				continue
			}
			if os.exists(c) {
				return c
			}
		}
		return 'python3'
	}
	if override.len > 0 {
		if !os.exists(override) {
			return error('HORNERO_M3_PYTHON_BIN points at a missing file: ${override}')
		}
		probe := strict_exec(override, ['-c', 'import materialyoucolor'], false)
		if !probe.ok {
			return error('HORNERO_M3_PYTHON_BIN lacks materialyoucolor: ${override}')
		}
		return override
	}
	for c in cands {
		prog := if c == 'python3' { find_on_path('python3') } else { c }
		if prog.len == 0 || !os.exists(prog) {
			continue
		}
		probe := strict_exec(prog, ['-c', 'import materialyoucolor'], false)
		if probe.ok {
			return prog
		}
	}
	return error('no Python with materialyoucolor: install python-materialyoucolor (Arch: yay -S --needed python-materialyoucolor). Override with HORNERO_M3_PYTHON_BIN.')
}

// run_m3_synthesis invokes the M3 backend natively (python + script +
// args), or previews the exact line on dry-run. Accent seeds pass through
// --source-color exactly like dots-color-scheme did.
pub fn run_m3_synthesis(image string, output string, flavour string, mode string, accent string, dry_run bool) !ExecReport {
	script := resolve_m3_script()
	if !dry_run && !os.is_file(script) {
		return error('M3 script not found: ${script} (set HORNERO_M3_SCRIPT).')
	}
	py := resolve_m3_python(dry_run)!
	mut full := [script, '--image', image, '--output', output, '--mode', mode, '--scheme-type',
		flavour]
	if accent.len > 0 {
		full << '--source-color'
		full << accent
	}
	return strict_exec(py, full, dry_run)
}
