module hornero_core

import os

// Privileged package backend: system upgrade plus dependency check and
// install, ported from `dots-sysupdate` (31 lines) and
// `dots-dependencies` (222 lines).
//
// - `upgrade` runs the full system upgrade through polkit
//   (`pkexec pacman -Syu`). The legacy script preferred AUR helpers
//   (yay/trizen/...) with a `sudo pacman -Syyuu` fallback; here pacman
//   is pinned and polkit is required: without pkexec the command fails
//   with guidance instead of falling back to sudo.
// - `deps` checks the pinned dependency table (core + Wayland stack,
//   plus dev/media/AI groups with --optional) with pure PATH lookups
//   (no execution, CI-hermetic), and installs the missing ones via
//   `pkexec pacman -S --needed` (repo packages) plus `paru -S --needed`
//   (AUR-only packages, user-level like the legacy yay flow).
//   chezmoi installs from the repos instead of the legacy curl pipe.
//
// Mutations need --yes; --dry-run only previews.

// resolve_pkexec_bin locates pkexec (polkit privilege). Override with
// HORNERO_PKEXEC_BIN.
pub fn resolve_pkexec_bin() string {
	env := os.getenv('HORNERO_PKEXEC_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('pkexec')
}

// resolve_pacman_bin locates pacman. Override with HORNERO_PACMAN_BIN.
pub fn resolve_pacman_bin() string {
	env := os.getenv('HORNERO_PACMAN_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('pacman')
}

// resolve_paru_bin locates paru (AUR helper, user-level).
// Override with HORNERO_PARU_BIN.
pub fn resolve_paru_bin() string {
	env := os.getenv('HORNERO_PARU_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('paru')
}

fn pkexec_or_fail(leaf string, dry_run bool) !string {
	bin := resolve_pkexec_bin()
	if bin.len == 0 {
		if dry_run {
			return 'pkexec'
		}
		return error('pkexec not found: system upgrades need polkit. Install polkit, then retry.\nExample: horneroctl package ${leaf} --dry-run')
	}
	return bin
}

fn pacman_or_fail(leaf string, dry_run bool) !string {
	bin := resolve_pacman_bin()
	if bin.len == 0 {
		if dry_run {
			return 'pacman'
		}
		return error('pacman not found. This command requires an Arch-based system.\nExample: horneroctl package ${leaf} --dry-run')
	}
	return bin
}

pub struct PackageUpgradeOptions {
pub:
	dry_run bool
	yes     bool
}

// package_upgrade_report implements `package upgrade` (privileged):
// the full system upgrade via polkit. Mutating: needs --yes;
// --dry-run only previews.
pub fn package_upgrade_report(opts PackageUpgradeOptions) CommandResult {
	if !opts.yes && !opts.dry_run {
		return fail_result('package upgrade', 'refusing to upgrade the system without --yes (preview with --dry-run).\nExample: horneroctl package upgrade --dry-run')
	}
	pkexec := pkexec_or_fail('upgrade', opts.dry_run) or {
		return fail_result('package upgrade', err.msg())
	}
	pacman := pacman_or_fail('upgrade', opts.dry_run) or {
		return fail_result('package upgrade', err.msg())
	}
	rep := run_exec(ExecSpec{
		prog:    pkexec
		args:    [pacman, '-Syu']
		dry_run: opts.dry_run
	})
	if opts.dry_run {
		return ok_result('package upgrade', 'would run: ${rep.command_line}\nPrivilege: polkit (pkexec). AUR-helper flows (yay -Syu) stay manual.',
			{
				'command_line': rep.command_line
				'dry_run':      'true'
			})
	}
	if rep.ok {
		return ok_result('package upgrade', rep.output, {
			'command_line': rep.command_line
		})
	}
	return fail_result('package upgrade', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
}

// DepEntry is one pinned dependency: the command to probe plus the
// package that provides it (repo `pkg`, or AUR-only `aur`).
struct DepEntry {
	check string
	pkg   string
	aur   string
	group string
}

fn package_dep_table(optional bool) []DepEntry {
	mut deps := [
		DepEntry{'git', 'git', '', 'core'},
		DepEntry{'curl', 'curl', '', 'core'},
		DepEntry{'wget', 'wget', '', 'core'},
		DepEntry{'chezmoi', 'chezmoi', '', 'core'},
		DepEntry{'zsh', 'zsh', '', 'core'},
		DepEntry{'hyprland', 'hyprland', '', 'wayland'},
		DepEntry{'quickshell', 'quickshell', '', 'wayland'},
		DepEntry{'hyprlock', 'hyprlock', '', 'wayland'},
		DepEntry{'hypridle', 'hypridle', '', 'wayland'},
		DepEntry{'cliphist', 'cliphist', '', 'wayland'},
	]
	if optional {
		deps << [
			DepEntry{'kitty', 'kitty', '', 'dev'},
			DepEntry{'nvim', 'neovim', '', 'dev'},
			DepEntry{'tmux', 'tmux', '', 'dev'},
			DepEntry{'yazi', 'yazi', '', 'dev'},
			DepEntry{'btop', 'btop', '', 'dev'},
			DepEntry{'fastfetch', 'fastfetch', '', 'dev'},
			DepEntry{'pipewire', 'pipewire', '', 'media'},
			DepEntry{'spotify', '', 'spotify', 'media'},
			DepEntry{'mpv', 'mpv', '', 'media'},
			DepEntry{'cava', 'cava', '', 'media'},
			DepEntry{'code', '', 'visual-studio-code-bin', 'ai'},
			DepEntry{'cursor', '', 'cursor-bin', 'ai'},
			DepEntry{'claude', '', 'claude-code-stable', 'ai'},
			DepEntry{'opencode', 'opencode', '', 'ai'},
			DepEntry{'ollama', 'ollama', '', 'ai'},
			DepEntry{'pi', '', 'pi-coding-agent', 'ai'},
			DepEntry{'llmfit', '', 'llmfit-bin', 'ai'},
		]
		// The legacy script also pulls nodejs/npm for the AI tools.
		deps << [DepEntry{'node', 'nodejs', '', 'ai'}, DepEntry{'npm', 'npm', '', 'ai'}]
	}
	return deps
}

// missing_deps returns the table entries whose command is not on PATH.
fn missing_deps(optional bool) []DepEntry {
	mut missing := []DepEntry{}
	for d in package_dep_table(optional) {
		if find_on_path(d.check).len == 0 {
			missing << d
		}
	}
	return missing
}

pub struct PackageDepsOptions {
pub:
	optional bool
	install  bool
	dry_run  bool
	yes      bool
}

// package_deps_check_report implements `package deps` (read-only):
// the missing core/Wayland dependencies (plus optional groups with
// --optional), via pure PATH lookups. It never fails: an empty
// missing set is success.
pub fn package_deps_check_report(opts PackageDepsOptions) CommandResult {
	missing := missing_deps(opts.optional)
	if missing.len == 0 {
		return ok_result('package deps', 'All core dependencies are satisfied!', {
			'missing': ''
			'count':   '0'
		})
	}
	mut lines := []string{}
	mut names := []string{}
	for d in missing {
		lines << '${d.check} (${d.group}, missing)'
		names << d.check
	}
	lines << '${missing.len} missing dependencies (install with: horneroctl package deps --install --yes)'
	return ok_result('package deps', lines.join('\n'), {
		'missing': names.join(',')
		'count':   missing.len.str()
	})
}

// package_deps_install_report implements `package deps --install`:
// install the missing dependencies via pacman (repo) and paru (AUR).
// Mutating: needs --yes; --dry-run only previews.
pub fn package_deps_install_report(opts PackageDepsOptions) CommandResult {
	if !opts.yes && !opts.dry_run {
		return fail_result('package deps', 'refusing to install dependencies without --yes (preview with --dry-run).\nExample: horneroctl package deps --install --dry-run')
	}
	missing := missing_deps(opts.optional)
	if missing.len == 0 {
		return ok_result('package deps', 'All core dependencies are satisfied!', {
			'missing': ''
			'count':   '0'
		})
	}
	mut repo := []string{}
	mut aur := []string{}
	for d in missing {
		if d.aur.len > 0 {
			if d.aur !in aur {
				aur << d.aur
			}
		} else if d.pkg !in repo {
			repo << d.pkg
		}
	}
	pkexec := pkexec_or_fail('deps', opts.dry_run) or {
		return fail_result('package deps', err.msg())
	}
	pacman := pacman_or_fail('deps', opts.dry_run) or {
		return fail_result('package deps', err.msg())
	}
	mut steps := [][]string{}
	if repo.len > 0 {
		mut step := [pkexec, pacman, '-S', '--needed']
		step << repo
		steps << step
	}
	if aur.len > 0 {
		paru := resolve_paru_bin()
		if paru.len == 0 {
			if !opts.dry_run {
				return fail_result('package deps', 'paru not found: cannot install AUR packages (${aur.join(', ')}). Install paru or yay, then retry.\nExample: horneroctl package deps --install --dry-run')
			}
			mut step := ['paru', '-S', '--needed']
			step << aur
			steps << step
		} else {
			mut step := [paru, '-S', '--needed']
			step << aur
			steps << step
		}
	}
	mut previews := []string{}
	for s in steps {
		previews << command_line(s[0], s[1..])
	}
	if opts.dry_run {
		mut lines := ['would install ${missing.len} missing dependencies:']
		for p in previews {
			lines << 'would run: ${p}'
		}
		return ok_result('package deps', lines.join('\n'), {
			'command_line': previews.join('; ')
			'missing':      missing.map(it.check).join(',')
			'dry_run':      'true'
		})
	}
	for s in steps {
		rep := run_exec(ExecSpec{
			prog: s[0]
			args: s[1..]
		})
		if !rep.ok {
			return fail_result('package deps', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
		}
	}
	return ok_result('package deps', 'installed ${missing.len} missing dependencies',
		{
			'command_line': previews.join('; ')
			'missing':      missing.map(it.check).join(',')
		})
}
