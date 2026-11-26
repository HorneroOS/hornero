module hornero_core

import semver

// Version is baked in at build time: v -d version=x.y.z -d commit=sha ....
// Release provenance (shell/config pins, manifest, release name) arrives
// the same way via make.vsh build-cli, which maps the HX_SHELL_SHA,
// HX_CONFIG_SHA, HX_MANIFEST and HX_RELEASE environment values to the
// hx_shell_sha, hx_config_sha, hx_manifest and hx_release defines
// (scripts/compose.sh exports the pins; every define defaults to
// "unknown" so no .git checkout is needed at runtime).
pub fn cli_version() string {
	return $d('version', 'dev')
}

pub fn cli_commit() string {
	return $d('commit', 'unknown')
}

// shell_pin_sha is the HorneroOS/shell SHA the binary was built against.
pub fn shell_pin_sha() string {
	return $d('hx_shell_sha', 'unknown')
}

// config_pin_sha is the HorneroOS/config SHA the binary was built against.
pub fn config_pin_sha() string {
	return $d('hx_config_sha', 'unknown')
}

// release_manifest names the composition manifest the pins came from.
pub fn release_manifest() string {
	return $d('hx_manifest', 'unknown')
}

// release_name names the release the binary was built for.
pub fn release_name() string {
	return $d('hx_release', 'unknown')
}

pub fn version_result() CommandResult {
	ver := cli_version()
	lines := [
		'horneroctl ${ver} (${cli_commit()})',
		'shell: ${shell_pin_sha()}',
		'config: ${config_pin_sha()}',
		'manifest: ${release_manifest()}',
		'release: ${release_name()}',
	]
	return ok_result('version', lines.join('\n'), {
		'version':    ver
		'commit':     cli_commit()
		'horneroctl': ver
		'shell_sha':  shell_pin_sha()
		'config_sha': config_pin_sha()
		'manifest':   release_manifest()
		'release':    release_name()
	})
}

// normalize_semver_input strips common release tag prefixes (`horneroctl-v`, `v`)
// so both raw semver strings and GitHub release tags parse cleanly with vlib `semver`.
fn normalize_semver_input(raw string) string {
	trimmed := raw.trim_space()
	if trimmed.starts_with('horneroctl-v') {
		return trimmed.all_after('horneroctl-v')
	}
	if trimmed.starts_with('v') && trimmed.len > 1 && trimmed[1].is_digit() {
		return trimmed[1..]
	}
	return trimmed
}

// parse_semver parses a version or Hornero release tag using native `vlib/semver`.
pub fn parse_semver(raw string) !semver.Version {
	return semver.from(normalize_semver_input(raw))
}

// compare_versions compares two semver strings, returning -1 if a < b, 0 if a == b, 1 if a > b.
pub fn compare_versions(a string, b string) !int {
	va := parse_semver(a)!
	vb := parse_semver(b)!
	if va == vb {
		return 0
	}
	if va < vb {
		return -1
	}
	return 1
}

// is_newer_version reports whether candidate is strictly newer than current.
// Returns false if either version is not valid semver (e.g. 'dev').
pub fn is_newer_version(current string, candidate string) bool {
	cmp := compare_versions(current, candidate) or { return false }
	return cmp < 0
}

// version_satisfies evaluates a semver range constraint (e.g. '>=0.2.0') using vlib `semver`.
pub fn version_satisfies(ver string, constraint string) !bool {
	v := parse_semver(ver)!
	return v.satisfies_or_error(constraint)
}
