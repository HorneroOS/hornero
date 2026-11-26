module hornero_core

fn test_parse_semver_handles_tags_and_prefixes() {
	v1 := parse_semver('0.2.0') or { panic(err) }
	assert v1.major == 0
	assert v1.minor == 2
	assert v1.patch == 0

	v2 := parse_semver('v0.2.0-preview54') or { panic(err) }
	assert v2.major == 0
	assert v2.minor == 2
	assert v2.patch == 0
	assert v2.prerelease == 'preview54'

	v3 := parse_semver('horneroctl-v0.2.0-preview55') or { panic(err) }
	assert v3.major == 0
	assert v3.minor == 2
	assert v3.patch == 0
	assert v3.prerelease == 'preview55'
}

fn test_compare_versions_and_is_newer() {
	assert (compare_versions('0.2.0-preview54', '0.2.0-preview55') or { panic(err) }) == -1
	assert (compare_versions('horneroctl-v0.2.0-preview55', 'v0.2.0-preview55') or { panic(err) }) == 0
	assert (compare_versions('0.2.0', '0.2.0-preview55') or { panic(err) }) == 1

	assert is_newer_version('0.2.0-preview54', '0.2.0-preview55')
	assert is_newer_version('0.2.0-preview55', '0.2.0')
	assert !is_newer_version('0.2.0', '0.2.0-preview55')
	assert !is_newer_version('dev', '0.2.0')
}

fn test_version_satisfies() {
	assert (version_satisfies('v0.2.5', '>=0.2.0 <1.0.0') or { panic(err) }) == true
	assert (version_satisfies('v1.0.0', '>=0.2.0 <1.0.0') or { panic(err) }) == false
}
