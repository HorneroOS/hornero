module hornero_core

fn test_parse_pending_update_names() {
	names := parse_pending_update_names('curl 8.22.0-1 -> 8.23.0-1\nhornero-shell 1.2.25-1 -> 1.2.44-1 [19m]\n\nlinux 6.11-1 -> 6.12-1')
	assert names == ['curl', 'hornero-shell', 'linux']
	assert parse_pending_update_names('').len == 0
}

fn test_classify_update_lanes() {
	hornero_pending, system_pending := classify_update_lanes('curl 1 -> 2\nhornero-config 0.3.9-1 -> 0.4.0-1',
		'hornero-shell 1.2.25-1 -> 1.2.44-1\npamac-aur 1 -> 2')
	assert hornero_pending == ['hornero-config', 'hornero-shell']
	assert system_pending == ['curl', 'pamac-aur']
}

fn test_hornero_owned_names_cover_published_packages() {
	names := hornero_owned_package_names()
	assert 'hornero-shell' in names
	assert 'hornero-config' in names
	assert 'horneroctl-bin' in names
	assert 'hornero-greeter' in names
}

fn test_snapshot_status_is_honest_about_missing_backend() {
	// The status lane must never imply OS rollback exists: backend stays
	// 'none' until a backend actually ships (hornero#179), and the prose
	// must not claim the contract itself is missing (it merged already).
	assert snapshot_backend_name == 'none'
	assert snapshot_unavailable_status.contains('SNAPSHOT_BACKEND_CONTRACT')
	assert !snapshot_unavailable_status.contains('contract yet')
	assert snapshot_unavailable_line.contains('not OS rollback')
}
