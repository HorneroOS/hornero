module hornero_core

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
