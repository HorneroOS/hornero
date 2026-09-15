module hornero_core

import os

// Welcome state contract tests. Everything lives under /tmp with
// HORNERO_WELCOME_STATE_FILE overrides (no HOME mutation, no network).
// Each test unsets what it sets.

const wx_root = '/tmp/hx-welcome-test'

fn wx_set_state(tag string) string {
	if os.exists('${wx_root}/${tag}') {
		os.rmdir_all('${wx_root}/${tag}') or {}
	}
	os.mkdir_all('${wx_root}/${tag}') or { assert false }
	path := '${wx_root}/${tag}/state.json'
	os.setenv('HORNERO_WELCOME_STATE_FILE', path, true)
	return path
}

fn wx_unset_state() {
	os.unsetenv('HORNERO_WELCOME_STATE_FILE')
}

fn test_welcome_missing_state_means_show() {
	wx_set_state('missing')
	defer {
		wx_unset_state()
	}
	st := welcome_read()
	assert st.show_on_login == true
	assert st.source == 'defaults'
	assert st.schema_version == welcome_schema_version
	assert st.content_revision == welcome_content_revision
	rep := welcome_status_report()
	assert rep.ok == true
	assert rep.data['show_on_login'] == 'true'
}

fn test_welcome_set_false_persists() {
	wx_set_state('setfalse')
	defer {
		wx_unset_state()
	}
	rep := welcome_set_show_report(WelcomeSetOptions{
		value:   false
		dry_run: false
		yes:     true
	})
	assert rep.ok == true
	st := welcome_read()
	assert st.show_on_login == false
	assert st.source == 'file'
	raw := os.read_file(resolve_welcome_state_file()) or { '' }
	assert raw.contains('"showOnLogin": false')
}

fn test_welcome_close_keeps_preference() {
	// Closing the window is not a mutation: the file only changes via
	// explicit set/mark/reset. Re-reading proves stability.
	wx_set_state('stable')
	defer {
		wx_unset_state()
	}
	assert welcome_set_show_report(WelcomeSetOptions{
		value:   false
		dry_run: false
		yes:     true
	}).ok == true
	first := welcome_read()
	second := welcome_read()
	assert first.show_on_login == false
	assert second.show_on_login == false
}

fn test_welcome_set_needs_yes() {
	wx_set_state('needsyes')
	defer {
		wx_unset_state()
	}
	rep := welcome_set_show_report(WelcomeSetOptions{
		value:   false
		dry_run: false
		yes:     false
	})
	assert rep.ok == false
	assert !os.exists(resolve_welcome_state_file())
}

fn test_welcome_dry_run_writes_nothing() {
	wx_set_state('dryrun')
	defer {
		wx_unset_state()
	}
	rep := welcome_set_show_report(WelcomeSetOptions{
		value:   false
		dry_run: true
		yes:     false
	})
	assert rep.ok == true
	assert !os.exists(resolve_welcome_state_file())
}

fn test_welcome_set_is_idempotent() {
	wx_set_state('idem')
	defer {
		wx_unset_state()
	}
	assert welcome_set_show_report(WelcomeSetOptions{
		value:   true
		dry_run: false
		yes:     true
	}).ok == true
	// Setting the current value is a no-op success.
	rep := welcome_set_show_report(WelcomeSetOptions{
		value:   true
		dry_run: false
		yes:     true
	})
	assert rep.ok == true
	assert rep.data['unchanged'] == 'true'
}

fn test_welcome_mark_seen_never_flips_opt_out() {
	wx_set_state('seen')
	defer {
		wx_unset_state()
	}
	assert welcome_set_show_report(WelcomeSetOptions{
		value:   false
		dry_run: false
		yes:     true
	}).ok == true
	rep := welcome_mark_seen_report(WelcomeSeenOptions{
		revision: ''
		dry_run:  false
		yes:      true
	})
	assert rep.ok == true
	st := welcome_read()
	assert st.show_on_login == false
	assert st.last_seen_content_revision == welcome_content_revision
	assert st.first_opened_at.len > 0
	assert st.last_opened_at.len > 0
}

fn test_welcome_reset_restores_defaults() {
	wx_set_state('reset')
	defer {
		wx_unset_state()
	}
	assert welcome_set_show_report(WelcomeSetOptions{
		value:   false
		dry_run: false
		yes:     true
	}).ok == true
	rep := welcome_reset_report(false, true)
	assert rep.ok == true
	st := welcome_read()
	assert st.show_on_login == true
	assert st.source == 'file'
}

fn test_welcome_malformed_recovers() {
	path := wx_set_state('malformed')
	defer {
		wx_unset_state()
	}
	os.write_file(path, '{not json') or { assert false }
	st := welcome_read()
	assert st.show_on_login == true
	assert st.source == 'defaults'
	// Wrong schema version also recovers.
	os.write_file(path, '{"schemaVersion": 99, "showOnLogin": false}') or { assert false }
	st2 := welcome_read()
	assert st2.show_on_login == true
	// Wrong field type also recovers.
	os.write_file(path, '{"schemaVersion": 1, "showOnLogin": "maybe"}') or { assert false }
	st3 := welcome_read()
	assert st3.show_on_login == true
}

fn test_welcome_encode_is_deterministic() {
	wx_set_state('encode')
	defer {
		wx_unset_state()
	}
	st := welcome_defaults()
	a := welcome_encode(st)
	b := welcome_encode(st)
	assert a == b
	assert a.contains('"schemaVersion": 1')
	assert a.contains('"showOnLogin": true')
	assert !a.contains('source')
	// Round-trip: encode then parse preserves every field.
	parsed := welcome_parse(a)
	assert parsed.schema_version == 1
	assert parsed.show_on_login == true
	assert parsed.content_revision == welcome_content_revision
}

fn test_welcome_parse_cli_bool() {
	assert welcome_parse_cli_bool('true') or { false } == true
	assert welcome_parse_cli_bool('FALSE') or { false } == false
	assert welcome_parse_cli_bool('1') or { false } == true
	assert welcome_parse_cli_bool('0') or { false } == false
	// 'maybe' must not parse as a boolean.
	if b := welcome_parse_cli_bool('maybe') {
		_ = b
		assert false
	}
}
