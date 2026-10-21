module hornero_core

import os

// Package backend: pending repository and AUR updates, plus pacman's read-only
// upgrade-ignore and removal-confirmation policies. Repository updates use
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
	policy     PackagePolicySnapshot
}

struct PackagePolicySnapshot {
	packages  []string
	groups    []string
	hold_pkgs []string
	status    string
	error     string
	pkg_cmd   string
	group_cmd string
	hold_cmd  string
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

fn read_pacman_policy_snapshot(dry_run bool) PackagePolicySnapshot {
	helper := resolve_pacman_conf_bin()
	if helper.len == 0 {
		return PackagePolicySnapshot{
			status: 'unavailable'
		}
	}
	pkg := pacman_conf_values(helper, 'IgnorePkg', dry_run)
	group := pacman_conf_values(helper, 'IgnoreGroup', dry_run)
	hold := pacman_conf_values(helper, 'HoldPkg', dry_run)
	if dry_run {
		return PackagePolicySnapshot{
			status:    'planned'
			pkg_cmd:   pkg.command_line
			group_cmd: group.command_line
			hold_cmd:  hold.command_line
		}
	}
	if !pkg.ok || !group.ok || !hold.ok {
		failed := if !pkg.ok {
			pkg
		} else if !group.ok {
			group
		} else {
			hold
		}
		return PackagePolicySnapshot{
			status:    'error'
			error:     'pacman-conf failed (exit ${failed.exit_code}): ${failed.output}'
			pkg_cmd:   pkg.command_line
			group_cmd: group.command_line
			hold_cmd:  hold.command_line
		}
	}
	return PackagePolicySnapshot{
		packages:  parse_pacman_conf_values(pkg.output)
		groups:    parse_pacman_conf_values(group.output)
		hold_pkgs: parse_pacman_conf_values(hold.output)
		status:    'checked'
		pkg_cmd:   pkg.command_line
		group_cmd: group.command_line
		hold_cmd:  hold.command_line
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
			policy:     read_pacman_policy_snapshot(opts.dry_run)
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
			policy:     read_pacman_policy_snapshot(opts.dry_run)
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
		policy:     read_pacman_policy_snapshot(opts.dry_run)
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
		'ignored_package_patterns': snapshot.policy.packages.join(', ')
		'ignored_group_patterns':   snapshot.policy.groups.join(', ')
		'hold_package_patterns':    snapshot.policy.hold_pkgs.join(', ')
		'hold_package_count':       if snapshot.policy.status == 'checked' {
			snapshot.policy.hold_pkgs.len.str()
		} else {
			''
		}
		'ignored_package_count':    if snapshot.policy.status == 'checked' {
			snapshot.policy.packages.len.str()
		} else {
			''
		}
		'ignored_group_count':      if snapshot.policy.status == 'checked' {
			snapshot.policy.groups.len.str()
		} else {
			''
		}
		'ignored_status':           snapshot.policy.status // retained for existing consumers
		'package_policy_status':    snapshot.policy.status
		'ignored_error':            snapshot.policy.error
		'ignorepkg_command':        snapshot.policy.pkg_cmd
		'ignoregroup_command':      snapshot.policy.group_cmd
		'holdpkg_command':          snapshot.policy.hold_cmd
	}
}

fn package_policy_message(snapshot PackagePolicySnapshot) string {
	if snapshot.status == 'unavailable' {
		return 'Pacman package policies: not checked (pacman-conf unavailable)'
	}
	if snapshot.status == 'planned' {
		return 'would run: ${snapshot.pkg_cmd}\nwould run: ${snapshot.group_cmd}\nwould run: ${snapshot.hold_cmd}'
	}
	if snapshot.status == 'error' {
		return 'Pacman package policies: could not be read (${snapshot.error})'
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
	hold_pkgs := if snapshot.hold_pkgs.len > 0 {
		'HoldPkg (removal confirmation): ${snapshot.hold_pkgs.join(', ')}'
	} else {
		'HoldPkg (removal confirmation): none'
	}
	return 'Pacman ignored upgrade patterns:\n${packages}\n${groups}\n${hold_pkgs}\nHoldPkg only prompts before removal; it does not block upgrades.'
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
	sections << package_policy_message(snapshot.policy)
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
			'would run: ${snapshot.repository.command_line}\nwould run: ${snapshot.aur.command_line}\n${package_policy_message(snapshot.policy)}'
		} else {
			'would run: ${snapshot.repository.command_line}\nAUR updates: not checked (install yay or paru)\n${package_policy_message(snapshot.policy)}'
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
			'would run: ${snapshot.repository.command_line}\nwould run: ${snapshot.aur.command_line}\n${package_policy_message(snapshot.policy)}'
		} else {
			'would run: ${snapshot.repository.command_line}\nAUR updates: not checked (install yay or paru)\n${package_policy_message(snapshot.policy)}'
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
	message := '${updates_message}; ${package_policy_message(snapshot.policy)}'
	return ok_result('package updates', message, data)
}

// --- Update status lanes (hornero#178) -------------------------------------
// One read-only report that separates what a user actually needs to
// decide: Hornero-owned packages behind, the rest of the system
// waiting, and held/ignored policy. Snapshot availability is reported
// honestly: no snapshot backend contract exists yet (hornero#179), so
// the lane says "none" instead of guessing from filesystem layout.

// hornero_owned_package_names is the curated HorneroOS package set.
// Package names, not components: the edition profiles name components
// (shell/config/horneroctl) but pacman knows packages. Keep this list
// in sync with the AUR packages the org publishes.
pub fn hornero_owned_package_names() []string {
	return [
		'hornero-shell',
		'hornero-shell-debug',
		'hornero-config',
		'hornero-greeter',
		'hornero-greeter-media-base',
		'horneroctl-bin',
		'horneroctl',
	]
}

// parse_pending_update_names extracts package names from checkupdates
// or `yay -Qua` output lines ("name oldver -> newver ...").
pub fn parse_pending_update_names(output string) []string {
	mut names := []string{}
	for line in output.split_into_lines() {
		trimmed := line.trim_space()
		if trimmed.len == 0 {
			continue
		}
		name := trimmed.split_any(' \t')[0]
		if name.len > 0 && name !in names {
			names << name
		}
	}
	return names
}

// classify_update_lanes splits pending updates into Hornero-owned and
// system lanes. Pure function: unit-tested without a live pacman.
pub fn classify_update_lanes(repository_output string, aur_output string) ([]string, []string) {
	owned := hornero_owned_package_names()
	mut hornero_pending := []string{}
	mut system_pending := []string{}
	for name in parse_pending_update_names(repository_output) {
		if name in owned {
			hornero_pending << name
		} else {
			system_pending << name
		}
	}
	for name in parse_pending_update_names(aur_output) {
		if name in owned {
			if name !in hornero_pending {
				hornero_pending << name
			}
		} else if name !in system_pending {
			system_pending << name
		}
	}
	return hornero_pending, system_pending
}

pub fn package_status_report(opts PackageCheckOptions) CommandResult {
	snapshot := run_package_update_snapshot(opts) or {
		return fail_result('package status', err.msg())
	}
	if opts.dry_run {
		mut data := package_update_data(snapshot)
		data['dry_run'] = 'true'
		data['snapshot_backend'] = 'none'
		data['snapshot_status'] = 'unavailable: no snapshot backend contract yet (see docs/UPDATE_RECOVERY.md)'
		message := 'would run: ${snapshot.repository.command_line}\nwould run: ${snapshot.aur.command_line}\n${package_policy_message(snapshot.policy)}\nSnapshots: none available (no snapshot backend contract yet)'
		return ok_result('package status', message, data)
	}
	hornero_pending, system_pending := classify_update_lanes(snapshot.repository.output,
		snapshot.aur.output)
	mut data := package_update_data(snapshot)
	data['hornero_pending'] = hornero_pending.join(', ')
	data['hornero_pending_count'] = hornero_pending.len.str()
	data['system_pending_count'] = system_pending.len.str()
	data['snapshot_backend'] = 'none'
	data['snapshot_status'] = 'unavailable: no snapshot backend contract yet (see docs/UPDATE_RECOVERY.md)'
	hornero_line := if hornero_pending.len > 0 {
		'Hornero packages behind (${hornero_pending.len}): ${hornero_pending.join(', ')}'
	} else {
		'Hornero packages: up to date'
	}
	system_line := 'System updates pending: ${system_pending.len}'
	snapshot_line := 'Snapshots: none available (no snapshot backend contract yet)'
	message := '${hornero_line}\n${system_line}\n${package_policy_message(snapshot.policy)}\n${snapshot_line}'
	return ok_result('package status', message, data)
}
