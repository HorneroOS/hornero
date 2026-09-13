module hornero_core

import os

// Package backend: pending system updates, read-only and unprivileged.
//
// Both leaves delegate to the verified `dots-checkupdates` backend
// (dotfiles reference, read-only): it prints one pending update per line
// using a throwaway sync database. `check` prints that list; `updates`
// prints the notify-oriented count readout (`dots-updates` counts the
// same lines). Privileged/mutating package work (`upgrade`, `deps`
// install) has no pinned backend and stays out (see the dispatch
// deferral + help "Later phases" note).

// resolve_checkupdates_bin locates the `dots-checkupdates` backend CLI.
// Override with HORNERO_CHECKUPDATES_BIN; falls back to plain
// `checkupdates` (pacman-contrib) on PATH.
pub fn resolve_checkupdates_bin() string {
	env := os.getenv('HORNERO_CHECKUPDATES_BIN')
	if env.len > 0 {
		return env
	}
	home_helper := os.join_path(os.home_dir(), '.local', 'bin', 'dots-checkupdates')
	if os.is_file(home_helper) {
		return home_helper
	}
	bin := find_on_path('dots-checkupdates')
	if bin.len > 0 {
		return bin
	}
	return find_on_path('checkupdates')
}

fn checkupdates_or_fail(helper string, dry_run bool) !string {
	bin := if helper.len > 0 { helper } else { resolve_checkupdates_bin() }
	if bin.len == 0 {
		if dry_run {
			return 'dots-checkupdates'
		}
		return error('package backend not found (needs dots-checkupdates or checkupdates on PATH). Set HORNERO_CHECKUPDATES_BIN.\nExample: horneroctl package check --dry-run')
	}
	return bin
}

pub struct PackageCheckOptions {
pub:
	dry_run bool
	helper  string
}

// run_checkupdates runs the backend once and returns its raw report.
fn run_checkupdates(command string, opts PackageCheckOptions) !ExecReport {
	bin := checkupdates_or_fail(opts.helper, opts.dry_run)!
	rep := run_exec(ExecSpec{
		prog:    bin
		args:    []string{}
		dry_run: opts.dry_run
	})
	return rep
}

// package_check_report implements `package check` (read-only): the pending
// update list, one line per package.
pub fn package_check_report(opts PackageCheckOptions) CommandResult {
	rep := run_checkupdates('package check', opts) or {
		return fail_result('package check', err.msg())
	}
	if opts.dry_run {
		return ok_result('package check', 'would run: ${rep.command_line}', {
			'command_line': rep.command_line
			'dry_run':      'true'
		})
	}
	if rep.ok {
		mut n := 0
		if rep.output.len > 0 {
			n = rep.output.split_into_lines().len
		}
		return ok_result('package check', rep.output, {
			'command_line': rep.command_line
			'count':        n.str()
		})
	}
	return fail_result('package check', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
}

// package_updates_report implements `package updates` (read-only): the
// notify-oriented pending-update count over the same backend output.
pub fn package_updates_report(opts PackageCheckOptions) CommandResult {
	rep := run_checkupdates('package updates', opts) or {
		return fail_result('package updates', err.msg())
	}
	if opts.dry_run {
		return ok_result('package updates', 'would run: ${rep.command_line}', {
			'command_line': rep.command_line
			'dry_run':      'true'
		})
	}
	if rep.ok {
		mut n := 0
		if rep.output.len > 0 {
			n = rep.output.split_into_lines().len
		}
		return ok_result('package updates', '${n} update(s) pending', {
			'command_line': rep.command_line
			'count':        n.str()
		})
	}
	return fail_result('package updates', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
}
