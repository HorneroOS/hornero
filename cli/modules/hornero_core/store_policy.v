module hornero_core

import os
import time
import x.json2

// Store policy & audit log for `horneroctl store`.
//
// Policy controls which backends, verification tiers, AUR packages, and
// proprietary licenses are permitted by default. Overrides via
// HORNERO_STORE_POLICY_FILE and HORNERO_STORE_AUDIT_FILE keep unit tests
// completely hermetic.

pub const store_all_backends = ['arch_native', 'flatpak', 'appimage', 'webapp', 'vendor_repo',
	'aur', 'guided']
pub const store_aur_policies = ['disabled', 'opt-in', 'allowed']
pub const store_proprietary_policies = ['block', 'opt-in', 'allow']

pub struct StorePolicy {
pub mut:
	allowed_sources    []string = ['arch_native', 'flatpak', 'appimage', 'webapp', 'vendor_repo',
		'aur', 'guided']
	verified_only      bool
	open_source_only   bool
	aur_policy         string = 'opt-in'
	proprietary_policy string = 'opt-in'
	source_file        string
}

pub struct StorePolicySetOptions {
pub:
	has_verified_only    bool
	verified_only        bool
	has_open_source_only bool
	open_source_only     bool
	aur_policy           string
	proprietary_policy   string
	has_allowed_sources  bool
	allowed_sources      []string
	dry_run              bool
	yes                  bool
}

struct StorePolicyDisk {
	allowed_sources    []string @[json: 'allowedSources']
	verified_only      bool     @[json: 'verifiedOnly']
	open_source_only   bool     @[json: 'openSourceOnly']
	aur_policy         string   @[json: 'aurPolicy']
	proprietary_policy string   @[json: 'proprietaryPolicy']
}

struct StoreAuditEntry {
	at      string
	action  string
	app_id  string
	backend string
	ok      bool
	detail  string
}

// resolve_store_policy_write_path returns the writable user policy file path.
pub fn resolve_store_policy_write_path() string {
	env := os.getenv('HORNERO_STORE_POLICY_FILE').trim_space()
	if env.len > 0 {
		return env
	}
	return os.join_path(resolve_paths().config_dir, 'hornero', 'hornero-apps', 'policy.json')
}

// resolve_store_policy_read_path resolves the active policy file path:
// HORNERO_STORE_POLICY_FILE -> ~/.config/hornero/hornero-apps/policy.json -> /etc/hornero/hornero-apps/policy.json.
pub fn resolve_store_policy_read_path() string {
	env := os.getenv('HORNERO_STORE_POLICY_FILE').trim_space()
	if env.len > 0 {
		return env
	}
	user_path := os.join_path(resolve_paths().config_dir, 'hornero', 'hornero-apps', 'policy.json')
	if os.is_file(user_path) {
		return user_path
	}
	sys_path := os.getenv('HORNERO_STORE_SYSTEM_POLICY_FILE').trim_space()
	if sys_path.len > 0 && os.is_file(sys_path) {
		return sys_path
	}
	etc_path := '/etc/hornero/hornero-apps/policy.json'
	if os.is_file(etc_path) {
		return etc_path
	}
	return user_path
}

// resolve_store_audit_path returns the store transaction audit JSONL file path.
pub fn resolve_store_audit_path() string {
	env := os.getenv('HORNERO_STORE_AUDIT_FILE').trim_space()
	if env.len > 0 {
		return env
	}
	return os.join_path(resolve_paths().state_dir, 'hornero', 'store', 'audit.jsonl')
}

// default_store_policy returns HorneroOS's safe default store policy.
pub fn default_store_policy() StorePolicy {
	return StorePolicy{
		allowed_sources:    store_all_backends.clone()
		verified_only:      false
		open_source_only:   false
		aur_policy:         'opt-in'
		proprietary_policy: 'opt-in'
		source_file:        resolve_store_policy_read_path()
	}
}

// load_store_policy reads the effective store policy, falling back to safe defaults.
pub fn load_store_policy() StorePolicy {
	path := resolve_store_policy_read_path()
	mut pol := default_store_policy()
	pol.source_file = path
	if !os.is_file(path) {
		return pol
	}
	raw := os.read_file(path) or { return pol }
	parsed := json2.decode[json2.Any](raw) or { return pol }
	m := parsed.as_map()
	if 'verifiedOnly' in m {
		pol.verified_only = m['verifiedOnly'] or { json2.Any(false) }.bool()
	} else if 'verified_only' in m {
		pol.verified_only = m['verified_only'] or { json2.Any(false) }.bool()
	}
	if 'openSourceOnly' in m {
		pol.open_source_only = m['openSourceOnly'] or { json2.Any(false) }.bool()
	} else if 'open_source_only' in m {
		pol.open_source_only = m['open_source_only'] or { json2.Any(false) }.bool()
	}
	aur := (m['aurPolicy'] or { m['aur_policy'] or { json2.Any('') } }).str().trim_space()
	if aur in store_aur_policies {
		pol.aur_policy = aur
	}
	prop := (m['proprietaryPolicy'] or { m['proprietary_policy'] or { json2.Any('') } }).str().trim_space()
	if prop in store_proprietary_policies {
		pol.proprietary_policy = prop
	}
	srcs_any := m['allowedSources'] or { m['allowed_sources'] or { json2.Any('') } }
	if srcs_any is []json2.Any {
		mut cleaned := []string{}
		for item in srcs_any.as_array() {
			b := item.str().trim_space()
			if b in store_all_backends && b !in cleaned {
				cleaned << b
			}
		}
		if cleaned.len > 0 {
			pol.allowed_sources = cleaned
		}
	}
	return pol
}

fn encode_store_policy(p StorePolicy) string {
	disk := StorePolicyDisk{
		allowed_sources:    p.allowed_sources
		verified_only:      p.verified_only
		open_source_only:   p.open_source_only
		aur_policy:         p.aur_policy
		proprietary_policy: p.proprietary_policy
	}
	return json2.encode(disk, escape_unicode: true) + '\n'
}

// save_store_policy writes policy atomically to the user policy path.
pub fn save_store_policy(p StorePolicy) !string {
	path := resolve_store_policy_write_path()
	write_file_atomic(path, encode_store_policy(p))!
	return path
}

// evaluate_store_policy checks whether an app + source complies with policy and flags.
pub fn evaluate_store_policy(app StoreApp, source StoreSource, policy StorePolicy, accept_proprietary bool, allow_aur bool) (bool, string) {
	if source.backend !in policy.allowed_sources {
		return false, 'backend "${source.backend}" is disallowed by store policy'
	}
	if policy.verified_only && !source.verified {
		return false, 'source "${source.backend}" (${source.provenance}) is unverified and store policy sets verifiedOnly=true'
	}
	if policy.open_source_only && !app.is_open_source {
		return false, '"${app.id}" (${app.license}) is proprietary and store policy sets openSourceOnly=true'
	}
	if !app.is_open_source {
		if policy.proprietary_policy == 'block' {
			return false, '"${app.id}" is proprietary and store policy blocks proprietary installs'
		}
		if policy.proprietary_policy == 'opt-in' && !accept_proprietary {
			return false, '"${app.id}" has proprietary license (${app.license}); pass --accept-proprietary to confirm'
		}
	}
	if source.backend == 'aur' {
		if policy.aur_policy == 'disabled' {
			return false, 'AUR installs are disabled by store policy'
		}
		if policy.aur_policy == 'opt-in' && !allow_aur {
			return false, 'AUR package "${source.package_id}" is community-maintained; pass --allow-aur to confirm'
		}
	}
	return true, 'allowed'
}

// record_store_audit appends one structured JSONL transaction record (best-effort).
pub fn record_store_audit(action string, app_id string, backend string, ok bool, detail string) {
	path := resolve_store_audit_path()
	dir := os.dir(path)
	os.mkdir_all(dir) or { return }
	entry := StoreAuditEntry{
		at:      time.utc().custom_format('YYYY-MM-DDTHH:mm:ss') + 'Z'
		action:  action
		app_id:  app_id
		backend: backend
		ok:      ok
		detail:  detail
	}
	line := json2.encode(entry, escape_unicode: true)
	mut f := os.open_append(path) or { return }
	defer {
		f.close()
	}
	f.writeln(line) or { return }
}

fn store_policy_data(p StorePolicy) map[string]string {
	return {
		'path':               p.source_file
		'verified_only':      p.verified_only.str()
		'open_source_only':   p.open_source_only.str()
		'aur_policy':         p.aur_policy
		'proprietary_policy': p.proprietary_policy
		'allowed_sources':    json2.encode(p.allowed_sources, escape_unicode: true)
		'policy':             encode_store_policy(p).trim_space()
	}
}

pub fn store_policy_show_result() CommandResult {
	p := load_store_policy()
	msg := [
		'Store policy (${p.source_file}):',
		'  allowedSources:    ${p.allowed_sources.join(', ')}',
		'  verifiedOnly:      ${p.verified_only}',
		'  openSourceOnly:    ${p.open_source_only}',
		'  aurPolicy:         ${p.aur_policy}',
		'  proprietaryPolicy: ${p.proprietary_policy}',
	].join('\n')
	return ok_result('store policy show', msg, store_policy_data(p))
}

pub fn store_policy_set_result(opts StorePolicySetOptions) CommandResult {
	cmd := 'store policy set'
	if !opts.yes && !opts.dry_run {
		return fail_result(cmd, 'refusing to modify store policy without --yes (preview with --dry-run).\nExample: horneroctl store policy set --verified-only true --dry-run')
	}
	mut p := load_store_policy()
	if opts.has_verified_only {
		p.verified_only = opts.verified_only
	}
	if opts.has_open_source_only {
		p.open_source_only = opts.open_source_only
	}
	if opts.aur_policy.len > 0 {
		if opts.aur_policy !in store_aur_policies {
			return fail_result(cmd, 'invalid aur-policy "${opts.aur_policy}" (expected: ${store_aur_policies.join(', ')})')
		}
		p.aur_policy = opts.aur_policy
	}
	if opts.proprietary_policy.len > 0 {
		if opts.proprietary_policy !in store_proprietary_policies {
			return fail_result(cmd, 'invalid proprietary-policy "${opts.proprietary_policy}" (expected: ${store_proprietary_policies.join(', ')})')
		}
		p.proprietary_policy = opts.proprietary_policy
	}
	if opts.has_allowed_sources {
		if opts.allowed_sources.len == 0 {
			return fail_result(cmd, 'allowed-sources must not be empty')
		}
		for s in opts.allowed_sources {
			if s !in store_all_backends {
				return fail_result(cmd, 'unknown source backend "${s}" (expected: ${store_all_backends.join(', ')})')
			}
		}
		p.allowed_sources = opts.allowed_sources.clone()
	}
	target := resolve_store_policy_write_path()
	p.source_file = target
	if opts.dry_run {
		mut data := store_policy_data(p)
		data['dry_run'] = 'true'
		return ok_result(cmd, 'Dry run: would write store policy to ${target}.', data)
	}
	written := save_store_policy(p) or {
		return fail_result(cmd, 'failed to write store policy: ${err.msg()}')
	}
	record_store_audit('policy-set', '', '', true, written)
	return ok_result(cmd, 'Updated store policy at ${written}.', store_policy_data(p))
}

pub fn store_policy_reset_result(dry_run bool, yes bool) CommandResult {
	cmd := 'store policy reset'
	if !yes && !dry_run {
		return fail_result(cmd, 'refusing to reset store policy without --yes (preview with --dry-run).\nExample: horneroctl store policy reset --dry-run')
	}
	mut p := default_store_policy()
	target := resolve_store_policy_write_path()
	p.source_file = target
	if dry_run {
		mut data := store_policy_data(p)
		data['dry_run'] = 'true'
		return ok_result(cmd, 'Dry run: would reset store policy at ${target} to defaults.', data)
	}
	written := save_store_policy(p) or {
		return fail_result(cmd, 'failed to reset store policy: ${err.msg()}')
	}
	record_store_audit('policy-reset', '', '', true, written)
	return ok_result(cmd, 'Reset store policy at ${written} to defaults.', store_policy_data(p))
}
