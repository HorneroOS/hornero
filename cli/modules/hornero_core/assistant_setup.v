module hornero_core

import os
import os.filelock
import crypto.sha256
import time

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
const assistant_dotfiles_legacy_unit_sha256 = 'fb25676f66a3db5644c056ef70346126dde098758c300df9ec49d9f68c7055f2'
const assistant_dotfiles_legacy_skill_sha256 = '98c037eaea144be4c265c424af289902e3e182fc267b9728828dff1e7dac9e64'

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

struct AssistantSetupReceipt {
	mode string
	hash string
}

fn assistant_setup_parse_receipt(raw string) !AssistantSetupReceipt {
	value := raw.trim_space()
	if assistant_setup_valid_hash(value) {
		return AssistantSetupReceipt{
			mode: 'generated'
			hash: value
		}
	}
	if value.starts_with('generated:') {
		digest := value['generated:'.len..]
		if assistant_setup_valid_hash(digest) {
			return AssistantSetupReceipt{
				mode: 'generated'
				hash: digest
			}
		}
	}
	if value.starts_with('adopted:') {
		digest := value['adopted:'.len..]
		if assistant_setup_valid_hash(digest) {
			return AssistantSetupReceipt{
				mode: 'adopted'
				hash: digest
			}
		}
	}
	return error('ownership receipt has an invalid format')
}

fn assistant_setup_lock_file() string {
	paths := resolve_paths()
	return os.join_path(paths.state_dir, 'hornero', 'assistant-setup', 'ownership.lock')
}

fn assistant_setup_acquire_lock() !filelock.FileLock {
	path := assistant_setup_lock_file()
	os.mkdir_all(os.dir(path)) or { return error('cannot create assistant ownership state directory: ${err.msg()}') }
	if os.is_link(path) {
		return error('assistant ownership lock is a symbolic link; refusing to follow it')
	}
	if !os.exists(path) {
		os.write_file(path, '') or { return error('cannot create assistant ownership lock: ${err.msg()}') }
	}
	if !os.is_file(path) {
		return error('assistant ownership lock is not a regular file')
	}
	os.chmod(path, 0o600) or { return error('cannot restrict assistant ownership lock permissions: ${err.msg()}') }
	mut file_lock := filelock.new_file(path, filelock.LockOptions{})
	if !file_lock.wait_acquire(5 * time.second) {
		return error('another horneroctl assistant setup operation is still running; retry shortly')
	}
	return file_lock
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

fn assistant_setup_receipt_hash(path string, content string) string {
	canonical_parent := os.real_path(os.dir(path))
	canonical_path := os.join_path(canonical_parent, os.file_name(path))
	return sha256.hexhash('${canonical_path.len}:${canonical_path}${content}')
}

fn assistant_setup_safe_receipt_file(kind string) !string {
	path := assistant_setup_receipt_file(kind)
	if os.is_link(path) {
		return error('ownership receipt path is a symbolic link; refusing to follow it')
	}
	if os.exists(path) && !os.is_file(path) {
		return error('ownership receipt path exists but is not a regular file; refusing to replace it')
	}
	if os.is_file(path) {
		receipt := os.read_file(path) or { return error('cannot read ownership receipt: ${err.msg()}') }
		assistant_setup_parse_receipt(receipt) or {
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
	parsed := assistant_setup_parse_receipt(receipt) or { return false }
	return parsed.hash == assistant_setup_receipt_hash(path, content)
}

fn assistant_setup_file_receipt_mode(kind string, path string) string {
	if !assistant_setup_file_is_owned(kind, path) {
		return ''
	}
	receipt_path := assistant_setup_receipt_file(kind)
	receipt := os.read_file(receipt_path) or { return '' }
	parsed := assistant_setup_parse_receipt(receipt) or { return '' }
	return parsed.mode
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
	mode := assistant_setup_file_receipt_mode(kind, path)
	if mode == '' {
		return error('existing file is not Hornero-owned or changed since Hornero wrote it')
	}
	if mode == 'adopted' {
		return false
	}
	return existing != desired
}

fn assistant_setup_write_temp_file(path string, content string) !string {
	dir := os.dir(path)
	os.mkdir_all(dir) or { return error('cannot create ${dir}: ${err.msg()}') }
	stage_dir := os.join_path(dir, '.${os.file_name(path)}.tmp.${os.getpid()}')
	os.mkdir(stage_dir, mode: 0o700) or {
		return error('cannot create private temporary directory ${stage_dir}: ${err.msg()}; inspect stale state before retrying')
	}
	tmp := os.join_path(stage_dir, 'payload')
	os.write_file(tmp, content) or {
		os.rmdir_all(stage_dir) or {}
		return error('cannot write ${tmp}: ${err.msg()}')
	}
	return tmp
}

fn assistant_setup_remove_temp_file(path string) {
	os.rm(path) or {}
	os.rmdir_all(os.dir(path)) or {}
}

// Detach a regular file into a private same-directory stage, then verify the
// inode contents. A concurrent atomic replacement is restored without
// replacing any path another writer created in the meantime.
fn assistant_setup_stage_matching_file(path string, expected string) !string {
	if os.is_link(path) || !os.is_file(path) {
		return error('target is not a regular file: ${path}')
	}
	current := os.read_file(path) or { return error('cannot read ${path}: ${err.msg()}') }
	if current != expected {
		return error('target changed before staging: ${path}')
	}
	// Keep detach stages separate from the pending publish file and from any
	// earlier stage retained for rollback.
	mut tmp := ''
	for attempt in 0 .. 100 {
		tmp = assistant_setup_write_temp_file('${path}.stage.${attempt}', '') or { continue }
		break
	}
	if tmp.len == 0 {
		return error('cannot allocate a private stage for ${path}')
	}
	os.rm(tmp) or {
		assistant_setup_remove_temp_file(tmp)
		return error('cannot prepare private file stage for ${path}: ${err.msg()}')
	}
	os.mv(path, tmp) or {
		assistant_setup_remove_temp_file(tmp)
		return error('cannot detach ${path} for revalidation: ${err.msg()}')
	}
	if os.is_link(tmp) {
		os.link(tmp, path) or {
			return error('symbolic link moved during staging and could not be restored without overwriting concurrent state; preserved at ${tmp}: ${err.msg()}')
		}
		assistant_setup_remove_temp_file(tmp)
		return error('target became a symbolic link during staging: ${path}')
	}
	staged := os.read_file(tmp) or {
		os.link(tmp, path) or {
			return error('cannot verify or restore staged target; preserved at ${tmp}: ${err.msg()}')
		}
		assistant_setup_remove_temp_file(tmp)
		return error('cannot verify staged target ${path}: ${err.msg()}')
	}
	if staged != expected {
		os.link(tmp, path) or {
			return error('target changed during staging and could not be restored without overwriting concurrent state; preserved at ${tmp}: ${err.msg()}')
		}
		assistant_setup_remove_temp_file(tmp)
		return error('target changed during staging; preserved ${path}')
	}
	return tmp
}

fn assistant_setup_restore_staged_file(path string, staged string) ! {
	os.link(staged, path) or {
		return error('cannot restore ${path} without overwriting concurrent state; preserved at ${staged}: ${err.msg()}')
	}
	assistant_setup_remove_temp_file(staged)
}

// Move a receipted file into a private same-directory staging directory before
// deleting it. This verifies the exact inode contents after the path is
// detached, so an external atomic replacement during systemd calls is kept.
fn assistant_setup_remove_owned_file(kind string, path string) !bool {
	if os.is_link(path) || !os.is_file(path) {
		return false
	}
	receipt_path := assistant_setup_receipt_file(kind)
	receipt_raw := os.read_file(receipt_path) or { return false }
	receipt := assistant_setup_parse_receipt(receipt_raw) or { return false }
	current := os.read_file(path) or { return false }
	if assistant_setup_receipt_hash(path, current) != receipt.hash {
		return false
	}
	tmp := assistant_setup_stage_matching_file(path, current) or {
		if (err.msg().contains('changed') || err.msg().contains('symbolic link'))
			&& !err.msg().contains('preserved at') {
			return false
		}
		return err
	}
	moved := os.read_file(tmp) or {
		assistant_setup_restore_staged_file(path, tmp) or {
			return error('cannot read or restore staged file ${tmp}: ${err.msg()}')
		}
		return false
	}
	if assistant_setup_receipt_hash(path, moved) != receipt.hash {
		assistant_setup_restore_staged_file(path, tmp) or {
			return error('file changed during removal and could not be restored: ${err.msg()}')
		}
		return false
	}
	current_receipt := os.read_file(receipt_path) or { '' }
	if current_receipt != receipt_raw {
		assistant_setup_restore_staged_file(path, tmp) or {
			return error('ownership receipt changed during removal and file could not be restored: ${err.msg()}')
		}
		return false
	}
	os.rm(receipt_path) or {
		assistant_setup_restore_staged_file(path, tmp) or {
			return error('cannot clear ownership receipt and file could not be restored: ${err.msg()}')
		}
		return error('cannot clear ownership receipt ${receipt_path}: ${err.msg()}')
	}
	assistant_setup_remove_temp_file(tmp)
	return true
}

fn assistant_setup_restore_file(path string, content string) ! {
	tmp := assistant_setup_write_temp_file(path, content)!
	os.link(tmp, path) or {
		assistant_setup_remove_temp_file(tmp)
		return error('cannot restore ${path}: ${err.msg()}')
	}
	assistant_setup_remove_temp_file(tmp)
}

fn assistant_setup_move_file(src string, dest string) ! {
	if !os.exists(dest) {
		os.link(src, dest)!
		os.rm(src) or {}
		return
	}
	os.mv(src, dest)!
}

fn assistant_setup_write_owned_file_with_move(kind string, path string, content string, move_file fn (string, string) !) !bool {
	return assistant_setup_write_owned_file_with_hooks(kind, path, content, move_file,
		assistant_setup_noop_before_publish)
}

fn assistant_setup_noop_before_publish(_path string) ! {}

fn assistant_setup_write_owned_file_with_hooks(kind string, path string, content string, move_file fn (string, string) !, before_publish fn (string) !) !bool {
	mut file_lock := assistant_setup_acquire_lock()!
	defer {
		file_lock.release()
	}
	return assistant_setup_write_owned_file_locked(kind, path, content, move_file, before_publish)
}

fn assistant_setup_write_owned_file_locked(kind string, path string, content string, move_file fn (string, string) !, before_publish fn (string) !) !bool {
	receipt_file := assistant_setup_safe_receipt_file(kind)!
	receipt_existed := os.is_file(receipt_file)
	previous_receipt := if receipt_existed {
		os.read_file(receipt_file) or { return error('cannot read existing ownership receipt: ${err.msg()}') }
	} else {
		''
	}
	should_write := assistant_setup_can_write_file(kind, path, content)!
	if !should_write {
		return false
	}
	had_existing_file := os.is_file(path)
	previous_content := if had_existing_file {
		os.read_file(path) or { return error('cannot read existing file ${path}: ${err.msg()}') }
	} else {
		''
	}
	file_tmp := assistant_setup_write_temp_file(path, content)!
	receipt_tmp := assistant_setup_write_temp_file(receipt_file,
		'generated:' + assistant_setup_receipt_hash(path, content) + '\n') or {
		assistant_setup_remove_temp_file(file_tmp)
		return err
	}
	os.chmod(receipt_tmp, 0o600) or {
		assistant_setup_remove_temp_file(file_tmp)
		assistant_setup_remove_temp_file(receipt_tmp)
		return error('cannot restrict ownership receipt permissions: ${err.msg()}')
	}
	// Recheck immediately before publishing. The stable advisory lock prevents
	// two horneroctl writers from invalidating each other's preflight.
	before_publish(path) or {
		assistant_setup_remove_temp_file(file_tmp)
		assistant_setup_remove_temp_file(receipt_tmp)
		return error('cannot recheck ${path} before publish: ${err.msg()}')
	}
	if had_existing_file {
		current := os.read_file(path) or {
			assistant_setup_remove_temp_file(file_tmp)
			assistant_setup_remove_temp_file(receipt_tmp)
			return error('cannot recheck ${path} before update: ${err.msg()}')
		}
		if current != previous_content || !assistant_setup_file_is_owned(kind, path) {
			assistant_setup_remove_temp_file(file_tmp)
			assistant_setup_remove_temp_file(receipt_tmp)
			return error('existing file changed during setup; preserving it')
		}
	} else if os.exists(path) {
		assistant_setup_remove_temp_file(file_tmp)
		assistant_setup_remove_temp_file(receipt_tmp)
		return error('target appeared during setup; preserving it')
	}
	mut previous_file_tmp := ''
	if had_existing_file {
		// Detach-before-publish leaves a brief missing-path window. This avoids
		// overwriting a non-cooperating writer that recreates the target.
		previous_file_tmp = assistant_setup_stage_matching_file(path, previous_content) or {
			assistant_setup_remove_temp_file(file_tmp)
			assistant_setup_remove_temp_file(receipt_tmp)
			return error('cannot safely stage existing file ${path}: ${err.msg()}')
		}
		staged_receipt := os.read_file(receipt_file) or { '' }
		staged_content := os.read_file(previous_file_tmp) or { '' }
		parsed_receipt := assistant_setup_parse_receipt(staged_receipt) or {
			assistant_setup_restore_staged_file(path, previous_file_tmp) or {
				return error('ownership receipt became invalid and ${path} could not be restored: ${err.msg()}')
			}
			assistant_setup_remove_temp_file(file_tmp)
			assistant_setup_remove_temp_file(receipt_tmp)
			return error('ownership receipt became invalid while staging ${path}; existing file restored')
		}
		if staged_receipt != previous_receipt
			|| assistant_setup_receipt_hash(path, staged_content) != parsed_receipt.hash {
			assistant_setup_restore_staged_file(path, previous_file_tmp) or {
				return error('ownership receipt changed while staging ${path}, and the file could not be restored: ${err.msg()}')
			}
			assistant_setup_remove_temp_file(file_tmp)
			assistant_setup_remove_temp_file(receipt_tmp)
			return error('ownership receipt or file changed while staging ${path}; existing file restored')
		}
	}
	// Publish with a no-clobber hard link. If an external writer recreated the
	// target after staging, its file stays in place and the previous inode is
	// restored only when the target is still absent.
	os.link(file_tmp, path) or {
		if previous_file_tmp.len > 0 {
			assistant_setup_restore_staged_file(path, previous_file_tmp) or {
				assistant_setup_remove_temp_file(file_tmp)
				assistant_setup_remove_temp_file(receipt_tmp)
				return error('cannot publish ${path}; concurrent target preserved and previous file remains at ${previous_file_tmp}: ${err.msg()}')
			}
		}
		assistant_setup_remove_temp_file(file_tmp)
		assistant_setup_remove_temp_file(receipt_tmp)
		return error('cannot publish ${path} without replacing a concurrent file: ${err.msg()}')
	}
	assistant_setup_remove_temp_file(file_tmp)
	if receipt_existed {
		current_receipt := os.read_file(receipt_file) or { '' }
		if current_receipt != previous_receipt {
			assistant_setup_remove_temp_file(receipt_tmp)
			return error('ownership receipt changed during setup; new target ${path} was preserved and the previous file remains at ${previous_file_tmp}')
		}
	}
	mut publish_error := ''
	if receipt_existed {
		move_file(receipt_tmp, receipt_file) or { publish_error = err.msg() }
	} else {
		os.link(receipt_tmp, receipt_file) or { publish_error = err.msg() }
	}
	if publish_error.len > 0 {
		assistant_setup_remove_temp_file(receipt_tmp)
		assistant_setup_rollback_after_receipt_failure(path, receipt_file, content,
			previous_file_tmp, had_existing_file, publish_error) or {
			return err
		}
	}
	assistant_setup_remove_temp_file(receipt_tmp)
	if previous_file_tmp.len > 0 {
		assistant_setup_remove_temp_file(previous_file_tmp)
	}
	return true
}

fn assistant_setup_rollback_after_receipt_failure(path string, receipt_file string, content string, previous_file_tmp string, had_existing_file bool, reason string) ! {
	current_tmp := assistant_setup_stage_matching_file(path, content) or {
		return error('cannot update ownership receipt ${receipt_file}: ${reason}; ${path} changed during rollback and was preserved. Previous content remains at ${previous_file_tmp}: ${err.msg()}')
	}
	if had_existing_file {
		os.link(previous_file_tmp, path) or {
			assistant_setup_restore_staged_file(path, current_tmp) or {
				return error('cannot restore previous content to ${path}; current and previous files remain at ${current_tmp} and ${previous_file_tmp}: ${err.msg()}')
			}
			return error('cannot restore previous content to ${path}; concurrent target preserved and previous file remains at ${previous_file_tmp}: ${err.msg()}')
		}
		assistant_setup_remove_temp_file(current_tmp)
		assistant_setup_remove_temp_file(previous_file_tmp)
		return error('cannot update ownership receipt ${receipt_file}: ${reason}; previous file content was restored')
	}
	assistant_setup_remove_temp_file(current_tmp)
	return error('cannot update ownership receipt ${receipt_file}: ${reason}; newly created file was removed')
}

fn assistant_setup_write_owned_file(kind string, path string, content string) !bool {
	return assistant_setup_write_owned_file_with_move(kind, path, content, assistant_setup_move_file)
}

struct AssistantSetupAdoptionTarget {
	kind        string
	path        string
	fingerprint string
}

struct AssistantSetupAdoptionPlan {
	lines   []string
	targets []AssistantSetupAdoptionTarget
}

struct AssistantSetupStagedAdoptionReceipt {
	path    string
	temp    string
	content string
}

fn assistant_setup_link_receipt(source string, destination string) ! {
	os.link(source, destination)!
}

fn assistant_setup_publish_adoption_receipts(receipts []AssistantSetupStagedAdoptionReceipt, publish fn (string, string) !) !int {
	mut published := []AssistantSetupStagedAdoptionReceipt{}
	for receipt in receipts {
		publish(receipt.temp, receipt.path) or {
			mut rollback_failures := []string{}
			for previous in published {
				if os.is_link(previous.path) || !os.is_file(previous.path) {
					rollback_failures << 'receipt changed during rollback and was preserved: ${previous.path}'
					continue
				}
				current := os.read_file(previous.path) or {
					rollback_failures << 'cannot verify receipt during rollback; preserved ${previous.path}: ${err.msg()}'
					continue
				}
				if current != previous.content {
					rollback_failures << 'receipt changed during rollback and was preserved: ${previous.path}'
					continue
				}
				os.rm(previous.path) or {
					rollback_failures << 'cannot remove partial receipt ${previous.path}: ${err.msg()}'
				}
			}
			if rollback_failures.len > 0 {
				return error('cannot publish ownership receipt ${receipt.path}: ${err.msg()}; partial adoption remains and needs reconciliation: ' + rollback_failures.join('; '))
			}
			return error('cannot publish ownership receipt ${receipt.path}: ${err.msg()}; earlier receipts were rolled back')
		}
		published << receipt
	}
	return published.len
}

fn assistant_setup_remove_staged_adoption_receipts(receipts []AssistantSetupStagedAdoptionReceipt) {
	for receipt in receipts {
		assistant_setup_remove_temp_file(receipt.temp)
	}
}

fn assistant_setup_dotfiles_adoption_targets() []AssistantSetupAdoptionTarget {
	return [
		AssistantSetupAdoptionTarget{
			kind:        'unit'
			path:        assistant_gateway_unit_file()
			fingerprint: assistant_dotfiles_legacy_unit_sha256
		},
		AssistantSetupAdoptionTarget{
			kind:        'skill'
			path:        assistant_skill_file()
			fingerprint: assistant_dotfiles_legacy_skill_sha256
		},
	]
}

fn assistant_setup_adoption_plan(targets []AssistantSetupAdoptionTarget) !AssistantSetupAdoptionPlan {
	mut lines := []string{}
	mut adoption_targets := []AssistantSetupAdoptionTarget{}
	for target in targets {
		if !os.exists(target.path) {
			lines << 'missing ${target.path}'
			continue
		}
		if os.is_link(target.path) || !os.is_file(target.path) {
			return error('${target.path} is not a regular file; it was preserved')
		}
		content := os.read_file(target.path) or { return error('cannot read ${target.path}: ${err.msg()}') }
		if sha256.hexhash(content) != target.fingerprint {
			return error('${target.path} does not match a supported dotfiles version; it was preserved. Move personal edits to a separately named Hermes skill or a systemd drop-in, then reconcile it manually')
		}
		if assistant_setup_file_is_owned(target.kind, target.path) {
			lines << 'already owned (${assistant_setup_file_receipt_mode(target.kind, target.path)}): ${target.path}'
			continue
		}
		receipt := assistant_setup_safe_receipt_file(target.kind)!
		if os.exists(receipt) {
			return error('an ownership receipt already exists for ${target.path} but does not match; it was preserved')
		}
		adoption_targets << target
		lines << 'adopt exact dotfiles file without rewriting it: ${target.path}'
	}
	return AssistantSetupAdoptionPlan{
		lines:   lines
		targets: adoption_targets
	}
}

pub fn assistant_setup_adopt_dotfiles_report(dry_run bool, yes bool) CommandResult {
	return assistant_setup_adopt_dotfiles_report_for_targets(dry_run, yes,
		assistant_setup_dotfiles_adoption_targets())
}

fn assistant_setup_adopt_dotfiles_report_for_targets(dry_run bool, yes bool, targets []AssistantSetupAdoptionTarget) CommandResult {
	if dry_run {
		plan := assistant_setup_adoption_plan(targets) or {
			return fail_result('assistant setup adopt-dotfiles', 'Cannot adopt legacy dotfiles files: ${err.msg()}')
		}
		lines := if plan.lines.len == 0 { ['no supported legacy files found'] } else { plan.lines }
		return ok_result('assistant setup adopt-dotfiles', 'Dry run: would only record ownership receipts; files, assistant settings, keys, and systemd state would not change:\n' + lines.join('\n'), {
			'dryRun': 'true'
		})
	}
	if !yes {
		return fail_result('assistant setup adopt-dotfiles', 'Adoption needs explicit consent. Preview with --dry-run, then run: horneroctl assistant setup --adopt-dotfiles --yes')
	}
	mut file_lock := assistant_setup_acquire_lock() or {
		return fail_result('assistant setup adopt-dotfiles', 'Cannot lock assistant ownership state: ${err.msg()}')
	}
	defer {
		file_lock.release()
	}
	plan := assistant_setup_adoption_plan(targets) or {
		return fail_result('assistant setup adopt-dotfiles', 'Cannot adopt legacy dotfiles files: ${err.msg()}')
	}
	mut staged_receipts := []AssistantSetupStagedAdoptionReceipt{}
	for target in plan.targets {
		receipt := assistant_setup_receipt_file(target.kind)
		content := os.read_file(target.path) or {
			assistant_setup_remove_staged_adoption_receipts(staged_receipts)
			return fail_result('assistant setup adopt-dotfiles', 'Cannot recheck ${target.path}: ${err.msg()}')
		}
		if sha256.hexhash(content) != target.fingerprint || os.is_link(target.path) {
			assistant_setup_remove_staged_adoption_receipts(staged_receipts)
			return fail_result('assistant setup adopt-dotfiles', '${target.path} changed during adoption; preserving it')
		}
		tmp := assistant_setup_write_temp_file(receipt,
			'adopted:' + assistant_setup_receipt_hash(target.path, content) + '\n') or {
			assistant_setup_remove_staged_adoption_receipts(staged_receipts)
			return fail_result('assistant setup adopt-dotfiles', 'Cannot stage the ownership receipt for ${target.path}: ${err.msg()}')
		}
		os.chmod(tmp, 0o600) or {
			assistant_setup_remove_temp_file(tmp)
			assistant_setup_remove_staged_adoption_receipts(staged_receipts)
			return fail_result('assistant setup adopt-dotfiles', 'Cannot restrict ownership receipt permissions: ${err.msg()}')
		}
		staged_receipts << AssistantSetupStagedAdoptionReceipt{
			path:    receipt
			temp:    tmp
			content: 'adopted:' + assistant_setup_receipt_hash(target.path, content) + '\n'
		}
	}
	adopted := assistant_setup_publish_adoption_receipts(staged_receipts,
		assistant_setup_link_receipt) or {
		assistant_setup_remove_staged_adoption_receipts(staged_receipts)
		return fail_result('assistant setup adopt-dotfiles', err.msg())
	}
	assistant_setup_remove_staged_adoption_receipts(staged_receipts)
	message := if adopted == 0 {
		'No new supported dotfiles files needed adoption.'
	} else {
		'Adopted ${adopted} exact legacy dotfiles file(s) without changing their contents. No settings, keys, or systemd state changed. Next: horneroctl assistant setup --yes'
	}
	return ok_result('assistant setup adopt-dotfiles', message, {
		'adopted': adopted.str()
	})
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
	mut file_lock := assistant_setup_acquire_lock() or {
		return fail_result('assistant setup', 'Cannot lock assistant ownership state: ${err.msg()}')
	}
	defer {
		file_lock.release()
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
	wrote_unit := assistant_gateway_ensure_unit_locked(hermes) or {
		return fail_result('assistant setup', 'Cannot write the user unit ${assistant_gateway_unit_file()}: ${err.msg()}')
	}
	mut skill_state := 'already current (Hornero-owned)'
	wrote_skill := assistant_setup_write_owned_file_locked('skill', skill_file, skill_text,
		assistant_setup_move_file, assistant_setup_noop_before_publish) or {
		return fail_result('assistant setup', 'Cannot install the Hornero skill at ${skill_file}: ${err.msg()}')
	}
	enable := assistant_enable_report(false, true)
	if !enable.ok {
		return CommandResult{
			command: enable.command
			ok:      enable.ok
			message: enable.message + '\nAssistant setup did not complete. Any unit or skill files written during this attempt remain tracked by Hornero ownership receipts; pre-existing external files were preserved. Resolve the reported assistant error before retrying setup.'
			data:    enable.data
		}
	}
	if wrote_skill {
		skill_state = 'installed'
	} else if assistant_setup_file_receipt_mode('skill', skill_file) == 'adopted' {
		skill_state = 'adopted and preserved'
	} else if !assistant_setup_file_is_owned('skill', skill_file) {
		skill_state = 'already present (externally managed)'
	}
	unit_state := if wrote_unit {
		'written'
	} else if assistant_setup_file_receipt_mode('unit', unit_file) == 'adopted' {
		'adopted and preserved'
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
	if dry_run || !yes {
		return assistant_setup_remove_report_locked(dry_run, yes)
	}
	mut file_lock := assistant_setup_acquire_lock() or {
		return fail_result('assistant setup', 'Cannot lock assistant ownership state: ${err.msg()}')
	}
	defer {
		file_lock.release()
	}
	return assistant_setup_remove_report_locked(dry_run, yes)
}

fn assistant_setup_remove_report_locked(dry_run bool, yes bool) CommandResult {
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
	unit_adopted := assistant_setup_file_receipt_mode('unit', unit_file) == 'adopted'
	if unit_owned && !unit_adopted {
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
	if os.is_file(unit_file) && unit_adopted {
		os.rm(assistant_setup_receipt_file('unit')) or {
			return fail_result('assistant setup', 'Cannot clear the adopted unit ownership receipt: ${err.msg()}. The unit file was preserved.')
		}
		lines << 'kept adopted ${unit_file}; systemd was not stopped'
	} else if os.is_file(unit_file) && unit_owned {
		removed := assistant_setup_remove_owned_file('unit', unit_file) or {
			if err.msg().contains('cannot clear ownership receipt') {
				return fail_result('assistant setup', 'Cannot clear the Hermes unit ownership receipt: ${err.msg()}. The unit file was preserved.')
			}
			return fail_result('assistant setup', 'Cannot safely remove the Hermes unit ${unit_file}: ${err.msg()}. Its receipt was preserved.')
		}
		if removed {
			assistant_gateway_systemctl(['daemon-reload'])
			lines << 'removed ${unit_file}'
		} else {
			lines << 'kept ${unit_file} (it changed or lost its ownership receipt during removal)'
		}
	}
	if os.is_file(skill_file) {
		if assistant_setup_file_receipt_mode('skill', skill_file) == 'adopted' {
			os.rm(assistant_setup_receipt_file('skill')) or {
				return fail_result('assistant setup', 'Cannot clear the adopted Hornero skill ownership receipt: ${err.msg()}. The skill file was preserved.')
			}
			lines << 'kept adopted ${skill_file}'
		} else if assistant_setup_file_is_owned('skill', skill_file) {
			removed := assistant_setup_remove_owned_file('skill', skill_file) or {
				if err.msg().contains('cannot clear ownership receipt') {
					return fail_result('assistant setup', 'Cannot clear the Hornero skill ownership receipt: ${err.msg()}. The skill file was preserved.')
				}
				return fail_result('assistant setup', 'Cannot safely remove the Hornero skill at ${skill_file}: ${err.msg()}. Its receipt was preserved.')
			}
			if removed {
				lines << 'removed ${skill_file}'
			} else {
				lines << 'kept ${skill_file} (it changed or lost its ownership receipt during removal)'
			}
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
