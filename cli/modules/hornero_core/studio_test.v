module hornero_core

import os

// Studio selection contract tests. Everything lives under /tmp with
// HORNERO_STUDIO_SELECTION_FILE overrides; each test unsets what it sets.

const studio_test_root = '/tmp/hx-studio-test'

fn studio_set_file(tag string) string {
	dir := '${studio_test_root}/${tag}'
	if os.exists(dir) {
		os.rmdir_all(dir) or {}
	}
	os.mkdir_all(dir) or { assert false }
	path := '${dir}/studio-selection.json'
	os.setenv('HORNERO_STUDIO_SELECTION_FILE', path, true)
	return path
}

fn studio_unset_file() {
	os.unsetenv('HORNERO_STUDIO_SELECTION_FILE')
}

fn test_studio_selection_roundtrip() {
	path := studio_set_file('roundtrip')
	defer {
		studio_unset_file()
	}
	sel := StudioSelection{
		schema_version:  studio_schema_version
		specializations: ['audio-music-production']
		applications:    ['krita', 'reaper']
	}
	written := write_studio_selection(sel) or {
		assert false, err.msg()
		return
	}
	assert written == path
	loaded, present := load_studio_selection() or {
		assert false, err.msg()
		return
	}
	assert present
	assert loaded == sel
	result := studio_selection_result()
	assert result.ok
	assert result.data['state'] == 'recorded'
	assert result.data['package_apply'] == 'not-executed'
}

fn test_studio_selection_missing_is_not_an_error() {
	studio_set_file('missing')
	defer {
		studio_unset_file()
	}
	result := studio_selection_result()
	assert result.ok
	assert result.data['state'] == 'not-selected'
}

fn test_studio_selection_rejects_unknown_ids_and_bad_schema() {
	studio_set_file('invalid')
	defer {
		studio_unset_file()
	}
	unknown := studio_selection_set_result(['nope'], [], true)
	assert !unknown.ok
	unknown_app := studio_selection_set_result([], ['nope'], true)
	assert !unknown_app.ok
	parse_studio_selection('{"schemaVersion": 99, "specializations": [], "applications": []}') or {
		assert err.msg().contains('schemaVersion')
		return
	}
	assert false, 'wrong schema must fail'
}

fn test_studio_selection_parse_fails_closed_on_malformed_input() {
	parse_studio_selection('not json') or {
		assert err.msg().contains('invalid JSON')
		return
	}
	assert false, 'malformed JSON must fail'
}

fn test_studio_selection_set_dry_run_writes_nothing() {
	path := studio_set_file('dry-run')
	defer {
		studio_unset_file()
	}
	result := studio_selection_set_result(['streaming-content-creation'], [], true)
	assert result.ok
	assert !os.is_file(path)
}

fn test_studio_doctor_reports_selection_and_audio_default() {
	studio_set_file('doctor')
	defer {
		studio_unset_file()
	}
	checks := studio_doctor_checks()
	names := checks.map(it.name)
	assert 'studio-selection' in names
	assert 'studio-audio-mode' in names
	audio := checks.filter(it.name == 'studio-audio-mode')[0]
	assert audio.ok
	assert audio.detail.contains('Balanced')
}
