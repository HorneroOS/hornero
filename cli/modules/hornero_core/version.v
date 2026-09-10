module hornero_core

// Version is baked in at build time: v -d version=x.y.z -d commit=sha ....
pub fn cli_version() string {
	return $d('version', 'dev')
}

pub fn cli_commit() string {
	return $d('commit', 'unknown')
}

pub fn version_result() CommandResult {
	ver := cli_version()
	return ok_result('version', 'horneroctl ${ver} (${cli_commit()})', {
		'version': ver
		'commit':  cli_commit()
	})
}
