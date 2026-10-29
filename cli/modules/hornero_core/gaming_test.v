module hornero_core

import os

// Gaming selection/doctor contract tests. Everything lives under /tmp
// with HORNERO_GAMING_SELECTION_FILE overrides; each test unsets what it
// sets.

const gaming_test_root = '/tmp/hx-gaming-test'

fn gaming_set_file(tag string) string {
	dir := '${gaming_test_root}/${tag}'
	if os.exists(dir) {
		os.rmdir_all(dir) or {}
	}
	os.mkdir_all(dir) or { assert false }
	path := '${dir}/gaming-selection.json'
	os.setenv('HORNERO_GAMING_SELECTION_FILE', path, true)
	return path
}

fn gaming_unset_file() {
	os.unsetenv('HORNERO_GAMING_SELECTION_FILE')
}

fn test_gaming_selection_roundtrip() {
	path := gaming_set_file('roundtrip')
	defer {
		gaming_unset_file()
	}
	sel := GamingSelection{
		schema_version:  gaming_schema_version
		specializations: ['desktop-gaming']
		applications:    ['steam']
	}
	os.write_file(path, gaming_encode_selection(sel)) or { assert false }
	loaded, present := load_gaming_selection() or {
		assert false, err.msg()
		return
	}
	assert present
	assert loaded.specializations == ['desktop-gaming']
	assert loaded.applications == ['steam']
}

fn test_gaming_selection_fails_closed_on_unknown_ids() {
	path := gaming_set_file('unknown')
	defer {
		gaming_unset_file()
	}
	os.write_file(path, '{"schemaVersion": 1, "specializations": ["esports"], "applications": []}\n') or {
		assert false
	}
	load_gaming_selection() or {
		assert err.msg().contains('unknown gaming specialization')
		return
	}
	assert false, 'unknown specialization must fail closed'
}

fn test_gaming_selection_missing_file_is_empty_state() {
	gaming_set_file('missing')
	defer {
		gaming_unset_file()
	}
	_, present := load_gaming_selection() or {
		assert false, err.msg()
		return
	}
	assert !present
}

fn test_gaming_doctor_reports_selection_and_capability_checks() {
	gaming_set_file('doctor')
	defer {
		gaming_unset_file()
	}
	checks := gaming_doctor_checks()
	names := checks.map(it.name)
	assert 'gaming-selection' in names
	assert 'vulkan-icd' in names
	assert 'controllers' in names
	assert 'recovery-readiness' in names
	controllers := checks.filter(it.name == 'controllers')[0]
	assert controllers.ok
	assert controllers.detail.contains('not Handheld qualification') || controllers.detail.contains('Handheld')
	selection := checks.filter(it.name == 'gaming-selection')[0]
	assert selection.ok
	assert selection.detail.contains('planned')
}

fn test_gaming_doctor_continues_after_invalid_selection() {
	path := gaming_set_file('invalid-doctor')
	defer {
		gaming_unset_file()
	}
	os.write_file(path, '{"schemaVersion": 1, "specializations": ["esports"], "applications": []}\n') or {
		assert false
	}
	checks := gaming_doctor_checks()
	names := checks.map(it.name)
	selection := checks.filter(it.name == 'gaming-selection')[0]
	assert !selection.ok
	assert 'vulkan-icd' in names
	assert 'recovery-readiness' in names
	// With Steam unselected, a missing binary is informational and a
	// present one is fine: either way the check must not fail.
	steam := checks.filter(it.name == 'steam')[0]
	assert steam.ok
}

fn test_gaming_ids_cover_catalogue_model() {
	assert gaming_specialization_ids.len == 6
	assert 'desktop-gaming' in gaming_specialization_ids
	assert 'vr' in gaming_specialization_ids
	assert 'steam' in gaming_application_ids
	assert 'steam' in gaming_opt_in_application_ids
}
