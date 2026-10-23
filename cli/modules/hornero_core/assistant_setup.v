module hornero_core

import os
import crypto.sha256

// -- Assistant setup contract (hornero#191) ---------------------------------
// `assistant setup` performs the Hornero-owned, network-free half of
// standing Hermes up: enablement + 0600 key (via assistant enable),
// the gateway user unit, and the Hornero skill installed into the
// Hermes home. Hermes itself is installed by the user following the
// pinned contract below — horneroctl never downloads it, never runs
// a remote install script, and never needs root (the packaging
// decision stays with the installer track; hornero#174/#191).
// Files are removed only while their receipt still matches the current
// contents; external or locally modified files are preserved.

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

fn assistant_setup_receipt_file(kind string) string {
	paths := resolve_paths()
	return os.join_path(paths.state_dir, 'hornero', 'assistant-setup', '${kind}.sha256')
}

fn assistant_setup_valid_hash(value string) bool {
	if value.len != 64 {
		return false
	}
	for ch in value {
		if !((ch >= `0` && ch <= `9`) || (ch >= `a` && ch <= `f`)) {
			return false
		}
	}
	return true
}

fn assistant_setup_safe_receipt_file(kind string) !string {
	path := assistant_setup_receipt_file(kind)
	if os.is_link(path) {
		return error('ownership receipt path is a symbolic link; refusing to follow it')
	}
	if os.is_file(path) {
		receipt := os.read_file(path) or { return error('cannot read ownership receipt: ${err.msg()}') }
		if !assistant_setup_valid_hash(receipt.trim_space()) {
			return error('ownership receipt exists but has an invalid format; refusing to overwrite it')
		}
	}
	return path
}

fn assistant_setup_file_is_owned(kind string, path string) bool {
	if os.is_link(path) {
		return false
	}
	content := os.read_file(path) or { return false }
	receipt_path := assistant_setup_receipt_file(kind)
	if os.is_link(receipt_path) {
		return false
	}
	receipt := os.read_file(receipt_path) or { return false }
	receipt_hash := receipt.trim_space()
	return assistant_setup_valid_hash(receipt_hash) && receipt_hash == sha256.hexhash(content)
}

// Existing files can only be replaced when a receipt proves Hornero wrote
// the current contents. Identical unreceipted files are left in place and
// remain externally owned.
fn assistant_setup_can_write_file(kind string, path string, desired string) !bool {
	if os.is_link(path) {
		return error('existing path is a symbolic link; refusing to follow it')
	}
	if !os.is_file(path) {
		return true
	}
	existing := os.read_file(path) or { return error('cannot read existing file: ${err.msg()}') }
	if !assistant_setup_file_is_owned(kind, path) {
		return error('existing file is not Hornero-owned or changed since Hornero wrote it')
	}
	return existing != desired
}

fn assistant_setup_write_owned_file(kind string, path string, content string) !bool {
	receipt_file := assistant_setup_safe_receipt_file(kind)!
	should_write := assistant_setup_can_write_file(kind, path, content)!
	if !should_write {
		return false
	}
	os.mkdir_all(os.dir(path))!
	os.mkdir_all(os.dir(receipt_file))!
	os.write_file(path, content)!
	os.write_file(receipt_file, sha256.hexhash(content) + '\n')!
	os.chmod(receipt_file, 0o600)!
	return true
}

// assistant_setup_plan is pure text so tests can pin the contract:
// pinned upstream, expected layout, 0600 key, and the explicit next
// step. It must never promise a download or a privileged action.
pub fn assistant_setup_plan(hermes string) []string {
	return [
		'Hermes prerequisite: ${hermes} on PATH, from the pinned source ${assistant_hermes_repo_url} at ${assistant_studied_hermes_commit} (expected layout: ${assistant_hermes_src_dir()} with its .venv; horneroctl never downloads it)',
		'Enable the assistant and generate the local Bearer key at ${assistant_key_file()} (0600, contents never printed)',
		'Create or refresh the gateway unit ${assistant_gateway_unit_file()} only when missing or covered by a matching Hornero ownership receipt; preserve conflicting external files',
		'Install or refresh the Hornero skill at ${assistant_skill_file()} only when missing or covered by a matching ownership receipt; preserve conflicting external files',
		'Next step after setup: horneroctl assistant gateway start --yes',
	]
}

fn assistant_setup_contract_text() string {
	return 'Hermes Agent was not found on PATH, and horneroctl never downloads it. Install it once, user-level, from the pinned source, then re-run setup:\n  git clone ${assistant_hermes_repo_url} ${assistant_hermes_src_dir()}\n  git -C ${assistant_hermes_src_dir()} checkout ${assistant_studied_hermes_commit}\n  python3 -m venv ${assistant_hermes_src_dir()}/.venv && ${assistant_hermes_src_dir()}/.venv/bin/pip install -e ${assistant_hermes_src_dir()}\n  point ${assistant_hermes_wrapper()} at ${assistant_hermes_src_dir()}/.venv/bin/hermes\nThen: horneroctl assistant setup --yes'
}

// assistant_setup_report preflights managed targets before enabling Hermes,
// and uses ownership receipts for every gateway or skill file it writes.
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
	unit_file := assistant_gateway_unit_file()
	unit_content := assistant_gateway_unit_content(hermes)
	assistant_setup_safe_receipt_file('unit') or {
		return fail_result('assistant setup', 'Cannot manage the Hermes ownership receipt for ${unit_file}: ${err.msg()}. Reconcile the Hornero state path before retrying.')
	}
	assistant_setup_can_write_file('unit', unit_file, unit_content) or {
		return fail_result('assistant setup', 'Cannot manage the Hermes unit at ${unit_file}: ${err.msg()}. The existing file was preserved; reconcile its ownership with dotfiles or remove it yourself before retrying.')
	}
	skill_file := assistant_skill_file()
	skill_text := assistant_skill_markdown()
	assistant_setup_safe_receipt_file('skill') or {
		return fail_result('assistant setup', 'Cannot manage the Hornero ownership receipt for ${skill_file}: ${err.msg()}. Reconcile the Hornero state path before retrying.')
	}
	assistant_setup_can_write_file('skill', skill_file, skill_text) or {
		return fail_result('assistant setup', 'Cannot manage the Hornero skill at ${skill_file}: ${err.msg()}. The existing file was preserved; reconcile its ownership with dotfiles or remove it yourself before retrying.')
	}
	enable := assistant_enable_report(false, true)
	if !enable.ok {
		return enable
	}
	wrote_unit := assistant_gateway_ensure_unit(hermes) or {
		return fail_result('assistant setup', 'Cannot write the user unit ${assistant_gateway_unit_file()}: ${err.msg()}')
	}
	mut skill_state := 'already current (Hornero-owned)'
	wrote_skill := assistant_setup_write_owned_file('skill', skill_file, skill_text) or {
		return fail_result('assistant setup', 'Cannot install the Hornero skill at ${skill_file}: ${err.msg()}')
	}
	if wrote_skill {
		skill_state = 'installed'
	} else if !assistant_setup_file_is_owned('skill', skill_file) {
		skill_state = 'already present (externally managed)'
	}
	unit_state := if wrote_unit {
		'written'
	} else if assistant_setup_file_is_owned('unit', unit_file) {
		'already current (Hornero-owned)'
	} else {
		'already present (externally managed)'
	}
	settings := assistant_load_settings()
	reachable, compatible, _ := assistant_gateway_state(settings)
	state := assistant_gateway_classify(true, true, reachable, compatible)
	return ok_result('assistant setup', 'Assistant setup complete (state: ${state}). Unit ${unit_state}; Hornero skill ${skill_state}. Start the gateway when ready: horneroctl assistant gateway start --yes', {
		'state': state
		'unit':  assistant_gateway_unit_name
		'skill': skill_file
	})
}

fn assistant_setup_remove_report(dry_run bool, yes bool) CommandResult {
	unit_file := assistant_gateway_unit_file()
	skill_file := assistant_skill_file()
	if dry_run {
		return ok_result('assistant setup', 'Dry run: would stop and remove only unchanged files with Hornero ownership receipts (${unit_file} and ${skill_file}), then set enabled=false. Unowned or modified files are preserved. The Hermes installation and the desktop stay untouched.', {
			'dryRun': 'true'
			'remove': 'true'
		})
	}
	if !yes {
		return fail_result('assistant setup', 'Removing the setup needs --yes (it changes assistant state). Preview with --dry-run first if unsure.')
	}
	mut lines := []string{}
	unit_owned := assistant_setup_file_is_owned('unit', unit_file)
	if unit_owned {
		unit_state := assistant_gateway_unit_active()
		if unit_state == 'active' {
			stop := assistant_gateway_systemctl(['stop', assistant_gateway_unit_name])
			stopped_state := assistant_gateway_unit_active()
			if !stop.ok || (stopped_state != 'inactive' && stopped_state != 'failed') {
				return fail_result('assistant setup', 'Cannot safely remove ${unit_file}: systemd did not confirm that ${assistant_gateway_unit_name} stopped (state: ${stopped_state}). The unit and its ownership receipt were preserved.')
			}
			lines << 'stopped ${assistant_gateway_unit_name}'
		} else if unit_state != 'inactive' && unit_state != 'failed' {
			return fail_result('assistant setup', 'Cannot safely remove ${unit_file}: systemd could not confirm that ${assistant_gateway_unit_name} is stopped (state: ${unit_state}). The unit and its ownership receipt were preserved.')
		}
	} else if os.is_file(unit_file) && !unit_owned {
		lines << 'kept ${unit_file} (no matching Hornero ownership receipt; unit was not stopped)'
	}
	if os.is_file(unit_file) && unit_owned {
		os.rm(assistant_setup_receipt_file('unit')) or {
			return fail_result('assistant setup', 'Cannot clear the Hermes unit ownership receipt: ${err.msg()}. The unit file was preserved.')
		}
		os.rm(unit_file) or {
			return fail_result('assistant setup', 'Cannot remove the user unit ${unit_file}: ${err.msg()}. Its ownership receipt was cleared, so the preserved file is no longer treated as Hornero-owned.')
		}
		assistant_gateway_systemctl(['daemon-reload'])
		lines << 'removed ${unit_file}'
	}
	if os.is_file(skill_file) {
		if assistant_setup_file_is_owned('skill', skill_file) {
			os.rm(assistant_setup_receipt_file('skill')) or {
				return fail_result('assistant setup', 'Cannot clear the Hornero skill ownership receipt: ${err.msg()}. The skill file was preserved.')
			}
			os.rm(skill_file) or {
				return fail_result('assistant setup', 'Cannot remove the Hornero skill at ${skill_file}: ${err.msg()}. Its ownership receipt was cleared, so the preserved file is no longer treated as Hornero-owned.')
			}
			lines << 'removed ${skill_file}'
		} else {
			lines << 'kept ${skill_file} (no matching Hornero ownership receipt or changed since Hornero wrote it)'
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
