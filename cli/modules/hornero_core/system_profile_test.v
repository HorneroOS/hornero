module hornero_core

import os

fn system_profile_test_save_env() map[string]string {
	mut saved := map[string]string{}
	for key in ['HORNERO_SYSTEM_PROFILE_FILE', 'NIRI_SOCKET', 'HYPRLAND_INSTANCE_SIGNATURE'] {
		saved[key] = os.getenv(key)
	}
	return saved
}

fn system_profile_test_restore_env(saved map[string]string) {
	for key, value in saved {
		if value.len == 0 {
			os.unsetenv(key)
		} else {
			os.setenv(key, value, true)
		}
	}
}

fn test_system_profile_reports_installed_edition_and_active_compositor_separately() {
	saved := system_profile_test_save_env()
	path := '/tmp/hornero-system-profile-test.json'
	os.setenv('HORNERO_SYSTEM_PROFILE_FILE', path, true)
	os.setenv('NIRI_SOCKET', '/run/user/test/niri.sock', true)
	os.setenv('HYPRLAND_INSTANCE_SIGNATURE', 'inherited-parent-session', true)
	os.write_file(path, '{"apiVersion":"hornero.os/v1","kind":"InstalledProfile","sourceRevision":"0123456789abcdef0123456789abcdef01234567","profilePackage":"hornero-profile-desktop-niri","edition":{"edition":"desktop","title":"HorneroOS Desktop","role":"desktop","maturity":"preview","compositor":"niri","compositorMaturity":"experimental","packageSets":["base","desktop","compositor:niri"]}}') or {
		assert false, err.msg()
	}

	result := system_profile_result()
	assert result.ok
	assert result.data['edition'] == 'desktop'
	assert result.data['compositor'] == 'niri'
	assert result.data['compositorMaturity'] == 'experimental'
	assert result.data['activeCompositor'] == 'niri'
	assert result.data['packageSets'] == 'base,desktop,compositor:niri'
	assert result.data['sourceRevision'] == '0123456789abcdef0123456789abcdef01234567'
	assert result.message.contains('Configured compositor: niri (experimental)')
	os.rm(path) or {}
	system_profile_test_restore_env(saved)
}

fn test_system_profile_does_not_guess_edition_when_record_is_absent() {
	saved := system_profile_test_save_env()
	os.setenv('HORNERO_SYSTEM_PROFILE_FILE', '/tmp/hornero-no-such-profile.json', true)
	os.unsetenv('NIRI_SOCKET')
	os.unsetenv('HYPRLAND_INSTANCE_SIGNATURE')
	result := system_profile_result()
	assert result.ok
	assert result.data['profileRecorded'] == 'false'
	assert result.data['edition'] == 'unrecorded'
	assert result.data['activeCompositor'] == 'unknown'
	assert result.message.contains('No installed edition profile is recorded')
	system_profile_test_restore_env(saved)
}

fn test_system_profile_rejects_invalid_metadata() {
	saved := system_profile_test_save_env()
	path := '/tmp/hornero-system-profile-invalid-test.json'
	os.setenv('HORNERO_SYSTEM_PROFILE_FILE', path, true)
	os.write_file(path, '{"apiVersion":"wrong"}') or { assert false, err.msg() }
	result := system_profile_result()
	assert !result.ok
	assert result.message.contains('unsupported format')
	os.rm(path) or {}
	system_profile_test_restore_env(saved)
}

fn test_system_profile_rejects_existing_non_file_path() {
	saved := system_profile_test_save_env()
	path := '/tmp/hornero-system-profile-directory-test-${os.getpid()}'
	os.mkdir(path) or { assert false, err.msg() }
	os.setenv('HORNERO_SYSTEM_PROFILE_FILE', path, true)
	result := system_profile_result()
	assert !result.ok
	assert result.message.contains('not a regular file')
	os.rmdir(path) or {}
	system_profile_test_restore_env(saved)
}

fn test_system_profile_rejects_wrong_types_and_empty_package_set_names() {
	saved := system_profile_test_save_env()
	path := '/tmp/hornero-system-profile-malformed-fields-test.json'
	os.setenv('HORNERO_SYSTEM_PROFILE_FILE', path, true)
	malformed_profiles := [
		'{"apiVersion":"hornero.os/v1","kind":"InstalledProfile","sourceRevision":"0123456789abcdef0123456789abcdef01234567","profilePackage":"hornero-profile-desktop-hyprland","edition":{"edition":7,"title":"HorneroOS Desktop","role":"desktop","maturity":"preview","packageSets":["base"]}}',
		'{"apiVersion":"hornero.os/v1","kind":"InstalledProfile","sourceRevision":"0123456789abcdef0123456789abcdef01234567","profilePackage":"hornero-profile-desktop-hyprland","edition":{"edition":"desktop","title":123,"role":"desktop","maturity":"preview","packageSets":["base"]}}',
		'{"apiVersion":"hornero.os/v1","kind":"InstalledProfile","sourceRevision":"0123456789abcdef0123456789abcdef01234567","profilePackage":"hornero-profile-desktop-hyprland","edition":{"edition":"desktop","title":"HorneroOS Desktop","role":"desktop","maturity":"preview","packageSets":[""]}}',
	]
	for profile in malformed_profiles {
		os.write_file(path, profile) or { assert false, err.msg() }
		result := system_profile_result()
		assert !result.ok
	}
	os.rm(path) or {}
	system_profile_test_restore_env(saved)
}
