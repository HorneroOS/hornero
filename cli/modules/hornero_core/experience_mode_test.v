module hornero_core

import os

// fake_qs writes a stand-in `qs` that records its argv and answers the
// experience IPC verbs from a tiny state file next to it.
fn fake_qs(label string, unreachable bool) (string, string) {
	dir := os.join_path(os.temp_dir(), 'hx-mode-${label}-${os.getpid()}')
	os.mkdir_all(dir) or { panic(err) }
	log := os.join_path(dir, 'calls.log')
	state := os.join_path(dir, 'mode')
	os.write_file(state, 'everyday') or { panic(err) }
	body := if unreachable {
		'#!/bin/sh\necho "\$@" >> "${log}"\necho "No running Quickshell instances." >&2\nexit 1\n'
	} else {
		'#!/bin/sh
echo "\$@" >> "${log}"
verb="\$4"
case "\$verb" in
  get) cat "${state}" ;;
  set)
    case "\$5" in
      focus|everyday|signal|gaming|studio) echo "\$5" > "${state}"; echo "ok: \$5" ;;
      *) echo "error: unknown mode: \$5" ;;
    esac ;;
  reset) echo everyday > "${state}"; echo "ok: everyday + cockpit + hornero-signal-night" ;;
  list)
    cur=\$(cat "${state}")
    printf "[{\\"id\\":\\"focus\\",\\"label\\":\\"Focus\\",\\"description\\":\\"quiet\\",\\"active\\":false,\\"customised\\":[]},{\\"id\\":\\"everyday\\",\\"label\\":\\"Everyday\\",\\"description\\":\\"default\\",\\"active\\":true,\\"customised\\":[\\"motion\\"]}]" ;;
  status)
    cur=\$(cat "${state}")
    printf "{\\"schemaVersion\\":1,\\"mode\\":\\"%s\\",\\"previous\\":\\"everyday\\",\\"source\\":\\"cli\\",\\"auto\\":false,\\"autoEnabled\\":true,\\"changedAt\\":\\"2026-11-16T20:00:00.000Z\\",\\"statePath\\":\\"/state/experience.json\\"}" "\$cur" ;;
  deck) printf "{\\"mode\\":\\"%s\\",\\"instruments\\":[{\\"id\\":\\"a\\"},{\\"id\\":\\"b\\"}],\\"catalogue\\":[\\"a\\",\\"b\\",\\"c\\"],\\"hidden\\":[\\"c\\"],\\"customised\\":false}" "\$5" ;;
  *) echo "error: no such function" ;;
esac
'
	}
	bin := os.join_path(dir, 'qs')
	os.write_file(bin, body) or { panic(err) }
	os.chmod(bin, 0o755) or { panic(err) }
	return bin, dir
}

fn fake_calls(dir string) string {
	return os.read_file(os.join_path(dir, 'calls.log')) or { '' }
}

fn test_mode_ids_are_the_five_rfc_modes() {
	assert experience_modes == ['focus', 'everyday', 'signal', 'gaming', 'studio']
	assert valid_experience_mode('signal')
	assert !valid_experience_mode('Signal')
	assert !valid_experience_mode('game')
	assert !valid_experience_mode('')
}

fn test_mode_set_validates_before_touching_the_shell() {
	bin, dir := fake_qs('validate', false)
	defer { os.rmdir_all(dir) or {} }
	r := mode_report(ModeOptions{ action: 'set', mode: 'turbo', qs_bin: bin })
	assert !r.ok
	assert r.message.contains('unknown mode: turbo')
	assert r.message.contains('Example:')
	assert fake_calls(dir) == ''
}

fn test_mode_dry_run_never_executes() {
	r := mode_report(ModeOptions{
		action:  'set'
		mode:    'gaming'
		dry_run: true
		qs_bin:  '/nonexistent-qs-hornero-test'
	})
	assert r.ok
	assert r.message.ends_with('/nonexistent-qs-hornero-test ipc call experience set gaming')
	assert r.data['dry_run'] == 'true'
	rr := mode_report(ModeOptions{
		action:  'reset'
		dry_run: true
		qs_bin:  '/nonexistent-qs-hornero-test'
	})
	assert rr.ok
	assert rr.message.ends_with('ipc call experience reset')
}

fn test_mode_reset_needs_yes() {
	bin, dir := fake_qs('resetyes', false)
	defer { os.rmdir_all(dir) or {} }
	r := mode_report(ModeOptions{ action: 'reset', qs_bin: bin })
	assert !r.ok
	assert r.message.contains('--yes')
	assert fake_calls(dir) == ''
}

fn test_mode_get_set_roundtrip_with_fake_shell() {
	bin, dir := fake_qs('roundtrip', false)
	defer { os.rmdir_all(dir) or {} }
	g := mode_report(ModeOptions{ action: 'get', qs_bin: bin })
	assert g.ok
	assert g.data['mode'] == 'everyday'
	s := mode_report(ModeOptions{ action: 'set', mode: 'signal', qs_bin: bin })
	assert s.ok
	assert s.data['mode'] == 'signal'
	g2 := mode_report(ModeOptions{ action: 'get', qs_bin: bin })
	assert g2.data['mode'] == 'signal'
	assert fake_calls(dir).contains('ipc call experience set signal')
}

fn test_mode_reset_returns_to_everyday_and_reports_kept_customisations() {
	bin, dir := fake_qs('reset', false)
	defer { os.rmdir_all(dir) or {} }
	assert mode_report(ModeOptions{ action: 'set', mode: 'gaming', qs_bin: bin }).ok
	r := mode_report(ModeOptions{ action: 'reset', yes: true, qs_bin: bin })
	assert r.ok
	assert r.data['mode'] == 'everyday'
	assert r.message.contains('customisations kept')
	// Reset goes through the shell's own reset, never resetCustomisations.
	assert !fake_calls(dir).contains('resetCustomisations')
	assert mode_report(ModeOptions{ action: 'get', qs_bin: bin }).data['mode'] == 'everyday'
}

fn test_mode_list_parses_shell_reply() {
	bin, dir := fake_qs('list', false)
	defer { os.rmdir_all(dir) or {} }
	r := mode_report(ModeOptions{ action: 'list', qs_bin: bin })
	assert r.ok
	assert r.data['modes'] == 'focus,everyday'
	assert r.data['active'] == 'everyday'
	assert r.message.contains('* everyday')
	assert r.message.contains('[customised: motion]')
}

fn test_mode_status_includes_auto_flag_and_deck() {
	bin, dir := fake_qs('status', false)
	defer { os.rmdir_all(dir) or {} }
	r := mode_report(ModeOptions{ action: 'status', qs_bin: bin })
	assert r.ok
	assert r.data['mode'] == 'everyday'
	assert r.data['auto_switch'] == 'true'
	assert r.message.contains('auto-switch: on')
	assert r.message.contains('deck: 2 instrument(s), hidden: c')
	assert fake_calls(dir).contains('ipc call experience deck everyday')
}

fn test_mode_shell_down_fails_honestly_for_every_verb() {
	bin, dir := fake_qs('down', true)
	defer { os.rmdir_all(dir) or {} }
	for action in ['get', 'list', 'status', 'reset'] {
		r := mode_report(ModeOptions{ action: action, yes: true, qs_bin: bin })
		assert !r.ok
		assert r.message.contains('cannot reach the Hornero Shell')
		assert r.message.contains('No running Quickshell instances')
		assert r.data.len == 0
	}
	s := mode_report(ModeOptions{ action: 'set', mode: 'focus', qs_bin: bin })
	assert !s.ok
	assert s.data.len == 0
}

fn test_mode_shell_error_reply_is_a_failure() {
	bin, dir := fake_qs('errreply', false)
	defer { os.rmdir_all(dir) or {} }
	// Forge an error reply for a valid id by pointing at a verb the fake
	// does not know: `reset` is fine, so use a wrapper script instead.
	os.write_file(bin, '#!/bin/sh\necho "error: unknown mode: signal"\n') or { panic(err) }
	r := mode_report(ModeOptions{ action: 'set', mode: 'signal', qs_bin: bin })
	assert !r.ok
}

fn test_mode_get_rejects_unknown_reply_instead_of_echoing_it() {
	bin, dir := fake_qs('garbage', false)
	defer { os.rmdir_all(dir) or {} }
	os.write_file(bin, '#!/bin/sh\necho "weird"\n') or { panic(err) }
	r := mode_report(ModeOptions{ action: 'get', qs_bin: bin })
	assert !r.ok
	assert r.message.contains('unknown mode: weird')
}
