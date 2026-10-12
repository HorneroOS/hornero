module hornero_core

import os

// Package backend: pending repository and AUR updates, plus pacman's ignored
// upgrade patterns, all read-only and unprivileged. Repository updates use
// pacman-contrib's `checkupdates`; AUR updates use yay or paru when available.
// Privileged/mutating work lives in package_ops.v.

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

// resolve_pacman_conf_bin locates pacman-conf, which resolves IgnorePkg and
// IgnoreGroup using pacman's own config parser (including Include directives).
// Override with HORNERO_PACMAN_CONF_BIN for isolated environments.
pub fn resolve_pacman_conf_bin() string {
	env := os.getenv('HORNERO_PACMAN_CONF_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('pacman-conf')
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
	ignored    PackageIgnoreSnapshot
}

struct PackageIgnoreSnapshot {
	packages  []string
	groups    []string
	status    string
	error     string
	pkg_cmd   string
	group_cmd string
}

fn pacman_conf_values(helper string, directive string, dry_run bool) ExecReport {
	return run_exec(ExecSpec{
		prog:        helper
		args:        [directive]
		dry_run:     dry_run
		timeout_sec: 5
	})
}

fn parse_pacman_conf_values(output string) []string {
	mut values := []string{}
	for line in output.split_into_lines() {
		values << line.fields()
	}
	return values
}

fn read_pacman_ignore_snapshot(dry_run bool) PackageIgnoreSnapshot {
	helper := resolve_pacman_conf_bin()
	if helper.len == 0 {
		return PackageIgnoreSnapshot{
			status: 'unavailable'
		}
	}
	pkg := pacman_conf_values(helper, 'IgnorePkg', dry_run)
	group := pacman_conf_values(helper, 'IgnoreGroup', dry_run)
	if dry_run {
		return PackageIgnoreSnapshot{
			status:    'planned'
			pkg_cmd:   pkg.command_line
			group_cmd: group.command_line
		}
	}
	if !pkg.ok || !group.ok {
		failed := if !pkg.ok { pkg } else { group }
		return PackageIgnoreSnapshot{
			status:    'error'
			error:     'pacman-conf failed (exit ${failed.exit_code}): ${failed.output}'
			pkg_cmd:   pkg.command_line
			group_cmd: group.command_line
		}
	}
	return PackageIgnoreSnapshot{
		packages:  parse_pacman_conf_values(pkg.output)
		groups:    parse_pacman_conf_values(group.output)
		status:    'checked'
		pkg_cmd:   pkg.command_line
		group_cmd: group.command_line
	}
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
			ignored:    read_pacman_ignore_snapshot(opts.dry_run)
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
			ignored:    read_pacman_ignore_snapshot(opts.dry_run)
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
		ignored:    read_pacman_ignore_snapshot(opts.dry_run)
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
		'count':                    (repository_count + aur_count).str()
		'repository_count':         repository_count.str()
		'aur_count':                aur_count.str()
		'aur_helper':               snapshot.aur_helper
		'aur_status':               if snapshot.aur_helper.len == 0 {
			'unavailable'
		} else if snapshot.aur.was_dry_run {
			'planned'
		} else {
			'checked'
		}
		'repository_command':       snapshot.repository.command_line
		'aur_command':              snapshot.aur.command_line
		'ignored_package_patterns': snapshot.ignored.packages.join(', ')
		'ignored_group_patterns':   snapshot.ignored.groups.join(', ')
		'ignored_package_count':    if snapshot.ignored.status == 'checked' {
			snapshot.ignored.packages.len.str()
		} else {
			''
		}
		'ignored_group_count':      if snapshot.ignored.status == 'checked' {
			snapshot.ignored.groups.len.str()
		} else {
			''
		}
		'ignored_status':           snapshot.ignored.status
		'ignored_error':            snapshot.ignored.error
		'ignorepkg_command':        snapshot.ignored.pkg_cmd
		'ignoregroup_command':      snapshot.ignored.group_cmd
	}
}

fn package_ignore_message(snapshot PackageIgnoreSnapshot) string {
	if snapshot.status == 'unavailable' {
		return 'Pacman ignored updates: not checked (pacman-conf unavailable)'
	}
	if snapshot.status == 'planned' {
		return 'would run: ${snapshot.pkg_cmd}\nwould run: ${snapshot.group_cmd}'
	}
	if snapshot.status == 'error' {
		return 'Pacman ignored updates: could not be read (${snapshot.error})'
	}
	if snapshot.packages.len == 0 && snapshot.groups.len == 0 {
		return 'Pacman ignored update patterns: none configured'
	}
	packages := if snapshot.packages.len > 0 {
		'IgnorePkg: ${snapshot.packages.join(', ')}'
	} else {
		'IgnorePkg: none'
	}
	groups := if snapshot.groups.len > 0 {
		'IgnoreGroup: ${snapshot.groups.join(', ')}'
	} else {
		'IgnoreGroup: none'
	}
	return 'Pacman ignored upgrade patterns:\n${packages}\n${groups}'
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
	sections << package_ignore_message(snapshot.ignored)
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
			'would run: ${snapshot.repository.command_line}\nwould run: ${snapshot.aur.command_line}\n${package_ignore_message(snapshot.ignored)}'
		} else {
			'would run: ${snapshot.repository.command_line}\nAUR updates: not checked (install yay or paru)\n${package_ignore_message(snapshot.ignored)}'
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
			'would run: ${snapshot.repository.command_line}\nwould run: ${snapshot.aur.command_line}\n${package_ignore_message(snapshot.ignored)}'
		} else {
			'would run: ${snapshot.repository.command_line}\nAUR updates: not checked (install yay or paru)\n${package_ignore_message(snapshot.ignored)}'
		}
		return ok_result('package updates', message, data)
	}
	data := package_update_data(snapshot)
	repository_count := data['repository_count']
	aur_count := data['aur_count']
	updates_message := if snapshot.aur_helper.len > 0 {
		'${repository_count} repository update(s), ${aur_count} AUR update(s) pending'
	} else {
		'${repository_count} repository update(s) pending; AUR updates were not checked (install yay or paru)'
	}
	message := '${updates_message}; ${package_ignore_message(snapshot.ignored)}'
	return ok_result('package updates', message, data)
}
