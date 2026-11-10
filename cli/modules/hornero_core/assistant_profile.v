module hornero_core

import os
import time

// -- Hermes secure profile + user system prompt (SOUL.md) --------------------
// Hermes config.yaml is user-owned: horneroctl only reports drift by
// default, and `--fix --yes` applies the minimal fail-closed edits below
// after writing a timestamped backup next to the original. The secure
// profile is defence in depth (Hermes SECURITY.md: in-process settings
// are not containment); the kernel boundary is the bwrap gateway unit.

pub fn assistant_hermes_home() string {
	env := os.getenv('HERMES_HOME')
	if env.len > 0 {
		return env
	}
	return os.join_path(os.home_dir(), '.hermes')
}

pub fn assistant_hermes_config_file() string {
	return os.join_path(assistant_hermes_home(), 'config.yaml')
}

// assistant_yaml_section_value returns the value of `key:` under the
// top-level `section:` in simple YAML (2-space indent), '' when absent.
// It deliberately handles only the subset Hermes writes for these keys.
pub fn assistant_yaml_section_value(text string, section string, key string) string {
	mut in_section := false
	for line in text.split('\n') {
		if line.len > 0 && !line.starts_with(' ') && line.trim_space().ends_with(':') {
			in_section = line.trim_space().all_before(':') == section
			continue
		}
		if in_section && line.starts_with('  ') && !line.starts_with('    ') {
			trimmed := line.trim_space()
			if trimmed.starts_with('${key}:') {
				return trimmed.all_after(':').trim_space().trim('"').trim("'")
			}
		}
	}
	return ''
}

pub struct AssistantProfileFinding {
pub:
	key     string
	current string
	want    string
	ok      bool
}

pub fn assistant_profile_findings(config_text string) []AssistantProfileFinding {
	mode := assistant_yaml_section_value(config_text, 'approvals', 'mode')
	backend := assistant_yaml_section_value(config_text, 'terminal', 'backend')
	protected := assistant_yaml_section_value(config_text, 'security', 'protected_instruction_files')
	return [
		AssistantProfileFinding{'approvals.mode', if mode.len > 0 {
			mode
		} else {
			'(unset: Hermes default smart)'
		}, 'manual', mode == 'manual'},
		AssistantProfileFinding{'terminal.backend', if backend.len > 0 {
			backend
		} else {
			'(unset: local)'
		}, 'local inside bwrap sandbox, never docker socket', true},
		AssistantProfileFinding{'security.protected_instruction_files', if protected.len > 0 {
			protected
		} else {
			'(unset)'
		}, 'true', protected == 'true'},
	]
}

// assistant_profile_fixed_config applies the minimal edits: approvals.mode
// manual and protected_instruction_files true. Pure, for tests.
pub fn assistant_profile_fixed_config(text string) string {
	mut lines := text.split('\n')
	lines = assistant_yaml_set_section_value(lines, 'approvals', 'mode', 'manual')
	lines = assistant_yaml_set_section_value(lines, 'security', 'protected_instruction_files',
		'true')
	return lines.join('\n')
}

fn assistant_yaml_set_section_value(lines []string, section string, key string, value string) []string {
	mut out := []string{}
	mut in_section := false
	mut done := false
	for line in lines {
		if line.len > 0 && !line.starts_with(' ') && line.trim_space().ends_with(':') {
			if in_section && !done {
				out << '  ${key}: ${value}'
				done = true
			}
			in_section = line.trim_space().all_before(':') == section
			out << line
			continue
		}
		if in_section && !done && line.starts_with('  ') && !line.starts_with('    ')
			&& line.trim_space().starts_with('${key}:') {
			out << '  ${key}: ${value}'
			done = true
			continue
		}
		out << line
	}
	if !done {
		if in_section {
			out << '  ${key}: ${value}'
		} else {
			out << '${section}:'
			out << '  ${key}: ${value}'
		}
	}
	return out
}

pub fn assistant_profile_report(fix bool, dry_run bool, yes bool) CommandResult {
	path := assistant_hermes_config_file()
	text := os.read_file(path) or {
		return fail_result('assistant profile', 'No Hermes config at ${path}. Run: horneroctl assistant setup --dry-run')
	}
	findings := assistant_profile_findings(text)
	mut lines := []string{}
	mut all_ok := true
	for f in findings {
		if !f.ok {
			all_ok = false
		}
		lines << '${if f.ok { 'ok  ' } else { 'DRIFT' }} ${f.key}: ${f.current} (want ${f.want})'
	}
	if !fix {
		return CommandResult{
			command: 'assistant profile'
			ok:      all_ok
			message: 'Hermes secure profile at ${path}:\n' + lines.join('\n')
			data:    {
				'profileOk': all_ok.str()
				'isolation': assistant_gateway_isolation()
			}
		}
	}
	if dry_run {
		return ok_result('assistant profile', 'Dry run: would back up ${path} and set approvals.mode=manual, security.protected_instruction_files=true. Nothing written.', {
			'dryRun': 'true'
		})
	}
	if !yes {
		return fail_result('assistant profile', 'Fixing the Hermes profile needs --yes. Preview with --dry-run.')
	}
	stamp := time.now().custom_format('YYYYMMDDHHmmss')
	backup := '${path}.hornero-bak-${stamp}'
	os.cp(path, backup) or {
		return fail_result('assistant profile', 'Cannot back up ${path}: ${err.msg()}')
	}
	os.write_file(path, assistant_profile_fixed_config(text)) or {
		return fail_result('assistant profile', 'Cannot write ${path}: ${err.msg()} (backup at ${backup})')
	}
	assistant_log_append('profile.fix', '', backup, 'ok')
	return ok_result('assistant profile', 'Secure profile applied to ${path} (backup: ${backup}). Restart the gateway to apply: horneroctl assistant gateway stop --yes && horneroctl assistant gateway start --yes', {
		'backup': backup
	})
}

// -- User-configurable system prompt (Hermes SOUL.md) ------------------------
// SOUL.md in the Hermes home is Hermes' supported identity/system-prompt
// slot. Editing it changes behaviour only: it sits inside the agent
// sandbox and can never widen ABAC policy or the kernel boundary.
// horneroctl keeps timestamped versions under the assistant config dir
// (outside the sandbox) so the user can diff and roll back.

pub fn assistant_prompt_file() string {
	return os.join_path(assistant_hermes_home(), 'SOUL.md')
}

fn assistant_prompt_history_dir() string {
	return os.join_path(assistant_dir(), 'prompt-history')
}

fn assistant_prompt_snapshot() !string {
	current := os.read_file(assistant_prompt_file()) or { '' }
	os.mkdir_all(assistant_prompt_history_dir())!
	stamp := time.now().custom_format('YYYYMMDDHHmmss')
	path := os.join_path(assistant_prompt_history_dir(), '${stamp}.md')
	os.write_file(path, current)!
	return path
}

pub fn assistant_prompt_show_report() CommandResult {
	text := os.read_file(assistant_prompt_file()) or {
		return ok_result('assistant prompt', 'No SOUL.md at ${assistant_prompt_file()} yet; Hermes uses its built-in identity. Set one with: horneroctl assistant prompt set --yes (reads stdin) — behaviour only, never authorization.', {
			'file': assistant_prompt_file()
		})
	}
	return ok_result('assistant prompt', text, {
		'file': assistant_prompt_file()
	})
}

pub fn assistant_prompt_set_file_report(source string, dry_run bool, yes bool) CommandResult {
	content := os.read_file(source) or {
		return fail_result('assistant prompt', 'Cannot read prompt file ${source}: ${err.msg()}')
	}
	return assistant_prompt_set_report(content, dry_run, yes)
}

pub fn assistant_prompt_set_report(content string, dry_run bool, yes bool) CommandResult {
	if dry_run {
		return ok_result('assistant prompt', 'Dry run: would snapshot the current SOUL.md, then replace ${assistant_prompt_file()} (${content.len} bytes). Nothing written.', {
			'dryRun': 'true'
		})
	}
	if !yes {
		return fail_result('assistant prompt', 'Replacing the system prompt needs --yes. Preview with --dry-run.')
	}
	snap := assistant_prompt_snapshot() or {
		return fail_result('assistant prompt', 'Cannot snapshot current prompt: ${err.msg()}')
	}
	os.mkdir_all(os.dir(assistant_prompt_file())) or {}
	os.write_file(assistant_prompt_file(), content) or {
		return fail_result('assistant prompt', 'Cannot write SOUL.md: ${err.msg()} (previous version: ${snap})')
	}
	assistant_log_append('prompt.set', '', snap, 'ok')
	return ok_result('assistant prompt', 'System prompt replaced (${content.len} bytes). Previous version kept at ${snap}; roll back with: horneroctl assistant prompt rollback ${os.base(snap)} --yes. Behaviour only — ABAC policy and sandbox are unaffected.', {
		'previous': snap
	})
}

pub fn assistant_prompt_rollback_report(version string, yes bool) CommandResult {
	if !yes {
		return fail_result('assistant prompt rollback', 'Rollback needs --yes.')
	}
	path := os.join_path(assistant_prompt_history_dir(), os.base(version))
	text := os.read_file(path) or {
		return fail_result('assistant prompt rollback', 'No prompt version at ${path}.')
	}
	assistant_prompt_snapshot() or {}
	os.write_file(assistant_prompt_file(), text) or {
		return fail_result('assistant prompt rollback', 'Cannot write SOUL.md: ${err.msg()}')
	}
	assistant_log_append('prompt.rollback', '', version, 'ok')
	return ok_result('assistant prompt rollback', 'System prompt rolled back to ${version}.', {})
}

pub fn assistant_prompt_history_report() CommandResult {
	dir := assistant_prompt_history_dir()
	entries := os.ls(dir) or {
		return ok_result('assistant prompt history', 'No prompt versions yet.', {})
	}
	return ok_result('assistant prompt history', entries.join('\n'), {
		'count': entries.len.str()
	})
}

// -- Model selection ---------------------------------------------------------
// Hermes' own `hermes model` writes model.{provider,default} in
// config.yaml and applies to NEW sessions. horneroctl mirrors that
// contract (backup-first) instead of inventing a per-run override the
// gateway API does not support.

pub fn assistant_model_show_report() CommandResult {
	path := assistant_hermes_config_file()
	text := os.read_file(path) or {
		return fail_result('assistant model', 'No Hermes config at ${path}.')
	}
	provider := assistant_yaml_section_value(text, 'model', 'provider')
	model := assistant_yaml_section_value(text, 'model', 'default')
	return ok_result('assistant model', 'Current model: ${model} (provider ${provider}). Applies to new sessions; the gateway keeps its running sessions.', {
		'model':    model
		'provider': provider
	})
}

pub fn assistant_model_set_report(model string, provider string, dry_run bool, yes bool) CommandResult {
	clean := model.trim_space()
	if clean.len == 0 || clean.contains_any(' \t\n') {
		return fail_result('assistant model set', 'Model id must be a single token. Example: horneroctl assistant model set gpt-5 --yes')
	}
	path := assistant_hermes_config_file()
	text := os.read_file(path) or {
		return fail_result('assistant model set', 'No Hermes config at ${path}.')
	}
	if dry_run {
		return ok_result('assistant model set', 'Dry run: would back up ${path} and set model.default=${clean}${if provider.len > 0 {
			', model.provider=${provider}'
		} else {
			''
		}}. Nothing written.', {
			'dryRun': 'true'
		})
	}
	if !yes {
		return fail_result('assistant model set', 'Changing the model needs --yes. Preview with --dry-run.')
	}
	stamp := time.now().custom_format('YYYYMMDDHHmmss')
	backup := '${path}.hornero-bak-${stamp}'
	os.cp(path, backup) or {
		return fail_result('assistant model set', 'Cannot back up ${path}: ${err.msg()}')
	}
	mut lines := text.split('\n')
	lines = assistant_yaml_set_section_value(lines, 'model', 'default', clean)
	if provider.len > 0 {
		lines = assistant_yaml_set_section_value(lines, 'model', 'provider', provider.trim_space())
	}
	os.write_file(path, lines.join('\n')) or {
		return fail_result('assistant model set', 'Cannot write ${path}: ${err.msg()} (backup at ${backup})')
	}
	assistant_log_append('model.set', '', clean, 'ok')
	return ok_result('assistant model set', 'Model set to ${clean} (backup: ${backup}). Applies to new Hermes sessions; restart the gateway or start a new chat to use it.', {
		'model':  clean
		'backup': backup
	})
}
