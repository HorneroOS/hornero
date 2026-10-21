module hornero_core

import os

// -- Assistant setup contract (hornero#191) ---------------------------------
// `assistant setup` performs the Hornero-owned, network-free half of
// standing Hermes up: enablement + 0600 key (via assistant enable),
// the gateway user unit, and the Hornero skill installed into the
// Hermes home. Hermes itself is installed by the user following the
// pinned contract below — horneroctl never downloads it, never runs
// a remote install script, and never needs root (the packaging
// decision stays with the installer track; hornero#174/#191).
// Everything setup writes is removable with --remove; the Hermes
// installation itself is user-owned and never touched.

pub const assistant_hermes_repo_url = 'https://github.com/NousResearch/hermes-agent'

const assistant_skill_embedded = $embed_file('../../../skills/hornero/SKILL.md')

pub fn assistant_skill_markdown() string {
	return assistant_skill_embedded.to_string()
}

pub fn assistant_hermes_src_dir() string {
	paths := resolve_paths()
	return os.join_path(paths.data_dir, 'hornero', 'hermes', 'src')
}

pub fn assistant_hermes_wrapper() string {
	return os.join_path(os.home_dir(), '.local', 'bin', 'hermes')
}

pub fn assistant_skill_file() string {
	hermes_home := os.getenv('HERMES_HOME')
	base := if hermes_home.len > 0 {
		hermes_home
	} else {
		os.join_path(os.home_dir(), '.hermes')
	}
	return os.join_path(base, 'skills', 'hornero', 'SKILL.md')
}

// assistant_setup_plan is pure text so tests can pin the contract:
// pinned upstream, expected layout, 0600 key, and the explicit next
// step. It must never promise a download or a privileged action.
pub fn assistant_setup_plan(hermes string) []string {
	return [
		'Hermes prerequisite: ${hermes} on PATH, from the pinned source ${assistant_hermes_repo_url} at ${assistant_studied_hermes_commit} (expected layout: ${assistant_hermes_src_dir()} with its .venv; horneroctl never downloads it)',
		'Enable the assistant and generate the local Bearer key at ${assistant_key_file()} (0600, contents never printed)',
		'Write the gateway user unit ${assistant_gateway_unit_file()} (user-level only, loopback endpoint, nothing enabled at login)',
		'Install the Hornero skill to ${assistant_skill_file()} (embedded copy, refreshed only when changed)',
		'Next step after setup: horneroctl assistant gateway start --yes',
	]
}

fn assistant_setup_contract_text() string {
	return 'Hermes Agent was not found on PATH, and horneroctl never downloads it. Install it once, user-level, from the pinned source, then re-run setup:\n  git clone ${assistant_hermes_repo_url} ${assistant_hermes_src_dir()}\n  git -C ${assistant_hermes_src_dir()} checkout ${assistant_studied_hermes_commit}\n  python3 -m venv ${assistant_hermes_src_dir()}/.venv && ${assistant_hermes_src_dir()}/.venv/bin/pip install -e ${assistant_hermes_src_dir()}\n  point ${assistant_hermes_wrapper()} at ${assistant_hermes_src_dir()}/.venv/bin/hermes\nThen: horneroctl assistant setup --yes'
}

pub fn assistant_setup_report(dry_run bool, yes bool, remove bool) CommandResult {
	if remove {
		return assistant_setup_remove_report(dry_run, yes)
	}
	hermes := find_on_path('hermes')
	shown := if hermes.len > 0 { hermes } else { assistant_hermes_wrapper() }
	if dry_run {
		return ok_result('assistant setup', 'Dry run: would perform these steps, changing nothing:\n' +
			assistant_setup_plan(shown).join('\n'), {
			'dryRun': 'true'
		})
	}
	if !yes {
		return fail_result('assistant setup', 'Setup needs explicit consent. Preview with --dry-run, then run: horneroctl assistant setup --yes')
	}
	if hermes.len == 0 {
		return fail_result('assistant setup', assistant_setup_contract_text())
	}
	enable := assistant_enable_report(false, true)
	if !enable.ok {
		return enable
	}
	wrote_unit := assistant_gateway_ensure_unit(hermes) or {
		return fail_result('assistant setup', 'Cannot write the user unit ${assistant_gateway_unit_file()}: ${err.msg()}')
	}
	skill_file := assistant_skill_file()
	skill_text := assistant_skill_markdown()
	existing_skill := os.read_file(skill_file) or { '' }
	mut skill_state := 'already current'
	if existing_skill != skill_text {
		os.mkdir_all(os.dir(skill_file)) or {
			return fail_result('assistant setup', 'Cannot create the Hermes skills directory: ${err.msg()}')
		}
		os.write_file(skill_file, skill_text) or {
			return fail_result('assistant setup', 'Cannot install the Hornero skill at ${skill_file}: ${err.msg()}')
		}
		skill_state = 'installed'
	}
	settings := assistant_load_settings()
	reachable, compatible, _ := assistant_gateway_state(settings)
	state := assistant_gateway_classify(true, true, reachable, compatible)
	return ok_result('assistant setup', 'Assistant setup complete (state: ${state}). Unit ${if wrote_unit {
		'written'
	} else {
		'already current'
	}}, Hornero skill ${skill_state}. Start the gateway when ready: horneroctl assistant gateway start --yes', {
		'state': state
		'unit':  assistant_gateway_unit_name
		'skill': skill_file
	})
}

fn assistant_setup_remove_report(dry_run bool, yes bool) CommandResult {
	unit_file := assistant_gateway_unit_file()
	skill_file := assistant_skill_file()
	if dry_run {
		return ok_result('assistant setup', 'Dry run: would stop ${assistant_gateway_unit_name} if Hornero manages it, remove ${unit_file} and the Hornero-installed skill at ${skill_file}, and set enabled=false. The Hermes installation and the desktop stay untouched.', {
			'dryRun': 'true'
			'remove': 'true'
		})
	}
	if !yes {
		return fail_result('assistant setup', 'Removing the setup needs --yes (it changes assistant state). Preview with --dry-run first if unsure.')
	}
	mut lines := []string{}
	if assistant_gateway_unit_active() == 'active' {
		assistant_gateway_systemctl(['stop', assistant_gateway_unit_name])
		lines << 'stopped ${assistant_gateway_unit_name}'
	}
	if os.is_file(unit_file) {
		os.rm(unit_file) or {
			return fail_result('assistant setup', 'Cannot remove the user unit ${unit_file}: ${err.msg()}')
		}
		assistant_gateway_systemctl(['daemon-reload'])
		lines << 'removed ${unit_file}'
	}
	if os.is_file(skill_file) {
		installed := os.read_file(skill_file) or { '' }
		if installed == assistant_skill_markdown() {
			os.rm(skill_file) or {
				return fail_result('assistant setup', 'Cannot remove the Hornero skill at ${skill_file}: ${err.msg()}')
			}
			lines << 'removed ${skill_file}'
		} else {
			lines << 'kept ${skill_file} (modified after install; not Hornero-owned as-is)'
		}
	}
	mut settings := assistant_load_settings()
	if settings.enabled {
		settings.enabled = false
		assistant_save_settings(settings) or {
			return fail_result('assistant setup', 'Cannot write assistant settings: ${err.msg()}')
		}
		lines << 'assistant disabled'
	}
	if lines.len == 0 {
		lines << 'nothing Hornero-owned was installed; nothing removed'
	}
	lines << 'The Hermes installation itself is user-owned and was not touched. The desktop works exactly as before.'
	return ok_result('assistant setup', lines.join('\n'), {
		'removed': 'true'
	})
}
