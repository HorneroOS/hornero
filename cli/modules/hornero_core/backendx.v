module hornero_core

import os

// wallpaper_shell_quote safely quotes arbitrary CLI values across the
// process-launch boundary, including paths containing shell metacharacters.
fn wallpaper_shell_quote(s string) string {
	return "'" + s.replace("'", '\'"\'"\'') + "'"
}

// Native external-tool backends for appearance operations. Hornero owns the
// coordination logic; compositor tools, settings daemons, and interpreters
// remain platform dependencies with HORNERO_*_BIN test/override seams.

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
	r := run_exec(ExecSpec{
		prog: prog
		args: args
	})
	return ExecReport{
		command_line: line
		ok:           r.ok
		output:       r.output
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
