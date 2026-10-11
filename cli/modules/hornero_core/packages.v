module hornero_core

import os

// Package backend: pending repository and AUR updates, read-only and
// unprivileged. Repository updates use pacman-contrib's `checkupdates`; AUR
// updates use the installed yay or paru helper when available. `check` prints
// both lanes and `updates` returns their counts. Privileged/mutating work lives
// in package_ops.v: `upgrade` via polkit, `deps` check/install via pacman/paru.

// resolve_checkupdates_bin locates pacman-contrib's `checkupdates`.
// Override with HORNERO_CHECKUPDATES_BIN for isolated environments.
pub fn resolve_checkupdates_bin() string {
	env := os.getenv('HORNERO_CHECKUPDATES_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('checkupdates')
}

// resolve_aur_helper_bin prefers yay because it is HorneroOS's declared AUR
// helper, and supports paru for existing Arch installations. Override with
// HORNERO_AUR_HELPER_BIN for isolated environments.
pub fn resolve_aur_helper_bin() string {
	env := os.getenv('HORNERO_AUR_HELPER_BIN')
	if env.len > 0 {
		return env
	}
	yay := find_on_path('yay')
	if yay.len > 0 {
		return yay
	}
	return find_on_path('paru')
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
	dry_run    bool
	helper     string
	aur_helper string
}

struct PackageUpdateSnapshot {
	repository ExecReport
	aur        ExecReport
	aur_helper string
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

fn run_package_update_snapshot(opts PackageCheckOptions) !PackageUpdateSnapshot {
	repository := run_checkupdates(opts)!
	if !repository.ok {
		return error('repository update check failed (exit ${repository.exit_code}):\n${repository.output}')
	}
	aur_helper := if opts.aur_helper.len > 0 {
		opts.aur_helper
	} else {
		resolve_aur_helper_bin()
	}
	if aur_helper.len == 0 {
		return PackageUpdateSnapshot{
			repository: repository
		}
	}
	if opts.dry_run {
		return PackageUpdateSnapshot{
			repository: repository
			aur:        ExecReport{
				command_line: command_line(aur_helper, ['-Qua'])
				ok:           true
				was_dry_run:  true
			}
			aur_helper: aur_helper
		}
	}
	aur := run_exec(ExecSpec{
		prog:        aur_helper
		args:        ['-Qua']
		timeout_sec: 30
	})
	if !aur.ok {
		return error('AUR update check failed via ${aur_helper} (exit ${aur.exit_code}):\n${aur.output}')
	}
	return PackageUpdateSnapshot{
		repository: repository
		aur:        aur
		aur_helper: aur_helper
	}
}

fn pending_update_count(output string) int {
	if output.len == 0 {
		return 0
	}
	mut count := 0
	for line in output.split_into_lines() {
		if line.trim_space().len > 0 {
			count++
		}
	}
	return count
}

fn package_update_data(snapshot PackageUpdateSnapshot) map[string]string {
	repository_count := if snapshot.repository.was_dry_run {
		0
	} else {
		pending_update_count(snapshot.repository.output)
	}
	aur_count := if snapshot.aur.was_dry_run {
		0
	} else {
		pending_update_count(snapshot.aur.output)
	}
	return {
		'count':              (repository_count + aur_count).str()
		'repository_count':   repository_count.str()
		'aur_count':          aur_count.str()
		'aur_helper':         snapshot.aur_helper
		'aur_status':         if snapshot.aur_helper.len == 0 {
			'unavailable'
		} else if snapshot.aur.was_dry_run {
			'planned'
		} else {
			'checked'
		}
		'repository_command': snapshot.repository.command_line
		'aur_command':        snapshot.aur.command_line
	}
}

fn package_update_check_message(snapshot PackageUpdateSnapshot) string {
	mut sections := []string{}
	if snapshot.repository.output.len > 0 {
		sections << 'Repository updates:\n${snapshot.repository.output}'
	} else {
		sections << 'Repository packages: up to date'
	}
	if snapshot.aur_helper.len > 0 {
		if snapshot.aur.output.len > 0 {
			sections << 'AUR updates (${snapshot.aur_helper}):\n${snapshot.aur.output}'
		} else {
			sections << 'AUR packages (${snapshot.aur_helper}): up to date'
		}
	} else {
		sections << 'AUR packages: not checked (install yay or paru)'
	}
	return sections.join('\n\n')
}

// package_check_report implements `package check` (read-only): the pending
// update list, one line per package.
pub fn package_check_report(opts PackageCheckOptions) CommandResult {
	snapshot := run_package_update_snapshot(opts) or {
		return fail_result('package check', err.msg())
	}
	if opts.dry_run {
		mut data := package_update_data(snapshot)
		data['dry_run'] = 'true'
		message := if snapshot.aur_helper.len > 0 {
			'would run: ${snapshot.repository.command_line}\nwould run: ${snapshot.aur.command_line}'
		} else {
			'would run: ${snapshot.repository.command_line}\nAUR updates: not checked (install yay or paru)'
		}
		return ok_result('package check', message, data)
	}
	return ok_result('package check', package_update_check_message(snapshot), package_update_data(snapshot))
}

// package_updates_report implements `package updates` (read-only): the
// notify-oriented pending-update count over the same backend output.
pub fn package_updates_report(opts PackageCheckOptions) CommandResult {
	snapshot := run_package_update_snapshot(opts) or {
		return fail_result('package updates', err.msg())
	}
	if opts.dry_run {
		mut data := package_update_data(snapshot)
		data['dry_run'] = 'true'
		message := if snapshot.aur_helper.len > 0 {
			'would run: ${snapshot.repository.command_line}\nwould run: ${snapshot.aur.command_line}'
		} else {
			'would run: ${snapshot.repository.command_line}\nAUR updates: not checked (install yay or paru)'
		}
		return ok_result('package updates', message, data)
	}
	data := package_update_data(snapshot)
	repository_count := data['repository_count']
	aur_count := data['aur_count']
	message := if snapshot.aur_helper.len > 0 {
		'${repository_count} repository update(s), ${aur_count} AUR update(s) pending'
	} else {
		'${repository_count} repository update(s) pending; AUR updates were not checked (install yay or paru)'
	}
	return ok_result('package updates', message, data)
}
