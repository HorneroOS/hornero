module hornero_core

import os

// Package backend: pending system updates, read-only and unprivileged.
//
// Both leaves use pacman-contrib's `checkupdates`: it prints one pending
// update per line using a throwaway sync database. `check` prints that list;
// `updates` returns the count. Privileged/mutating work lives in package_ops.v:
// `upgrade` via polkit, `deps` check/install via pacman/paru.

// resolve_checkupdates_bin locates pacman-contrib's `checkupdates`.
// Override with HORNERO_CHECKUPDATES_BIN for isolated environments.
pub fn resolve_checkupdates_bin() string {
	env := os.getenv('HORNERO_CHECKUPDATES_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('checkupdates')
}

fn checkupdates_or_fail(helper string, dry_run bool) !string {
	bin := if helper.len > 0 { helper } else { resolve_checkupdates_bin() }
	if bin.len == 0 {
		if dry_run {
			return 'checkupdates'
		}
		return error('checkupdates not found; install pacman-contrib or set HORNERO_CHECKUPDATES_BIN.\nExample: horneroctl package check --dry-run')
	}
	return bin
}

pub struct PackageCheckOptions {
pub:
	dry_run bool
	helper  string
}

// run_checkupdates runs the backend once and returns its raw report.
fn run_checkupdates(opts PackageCheckOptions) !ExecReport {
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
	rep := run_checkupdates(opts) or {
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
	rep := run_checkupdates(opts) or {
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
