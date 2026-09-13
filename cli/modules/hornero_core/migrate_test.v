module hornero_core

import os

// Preview-1 migrate fixtures: everything lives under /tmp, env overrides
// isolate HOME/PATH, and each test unsets what it sets (no network, no
// compositor, no real backends).

const mig_root = '/tmp/hx-migrate-test'

fn mig_write(path string, content string) {
	os.mkdir_all(os.dir(path)) or { assert false }
	os.write_file(path, content) or { assert false }
	os.chmod(path, 0o755) or { assert false }
}

fn mig_setup_backend() {
	mig_write('${mig_root}/bin/migrate-to-hornero.sh', '#!/bin/sh\nif [ "\$1" = "--dry-run" ]; then printf "ROW themes dry-run 2 pack(s)\\nROW presets dry-run 1 preset(s)\\n"; exit 0; fi\nprintf "ROW themes copied 2 pack(s)\\nROW presets copied 1 preset(s)\\nROW preset-pointer already-canonical\\nROW scheme copied\\nROW scheme-state copied\\nROW wallpaper-pointer absent-source\\nROW notifs copied\\n";\nexit 0\n')
	os.setenv('HORNERO_MIGRATE_BIN', '${mig_root}/bin/migrate-to-hornero.sh', true)
}

fn mig_teardown_backend() {
	os.unsetenv('HORNERO_MIGRATE_BIN')
}

fn mig_isolate_resolution() (string, string) {
	old_home := os.getenv('HOME')
	old_path := os.getenv('PATH')
	os.setenv('HOME', mig_root, true)
	os.setenv('PATH', '/nonexistent-path-hornero-test', true)
	os.unsetenv('HORNERO_MIGRATE_BIN')
	return old_home, old_path
}

fn mig_restore_resolution(old_home string, old_path string) {
	os.setenv('HOME', old_home, true)
	os.setenv('PATH', old_path, true)
}

fn test_migrate_needs_yes_and_previews() {
	mig_setup_backend()
	r := migrate_report(MigrateOptions{})
	assert !r.ok
	assert r.command == 'config migrate'
	assert r.message.contains('--yes')
	d := migrate_report(MigrateOptions{
		dry_run: true
	})
	assert d.ok
	assert d.data['dry_run'] == 'true'
	assert d.message.contains('migrate-to-hornero.sh')
	assert d.message.contains('--dry-run')
	mig_teardown_backend()
}

fn test_migrate_dry_run_needs_no_backend() {
	os.setenv('HORNERO_MIGRATE_BIN', '/nonexistent-migrate-hornero-test', true)
	d := migrate_report(MigrateOptions{
		dry_run: true
	})
	assert d.ok
	assert d.data['dry_run'] == 'true'
	os.unsetenv('HORNERO_MIGRATE_BIN')
}

fn test_migrate_forwards_yes_to_backend() {
	// The backend requires --yes itself: --yes must reach it, not just
	// gate the CLI call (regression: --yes was swallowed, backend exited
	// 2 with "pass --dry-run to preview or --yes to migrate").
	mig_write('${mig_root}/bin/migrate-to-hornero.sh', '#!/bin/sh\nprintf "%s\\n" "$@" > "' +
		mig_root + '/argv.txt"\nprintf "ROW themes copied 1 pack(s)\\n"\nexit 0\n')
	os.setenv('HORNERO_MIGRATE_BIN', '${mig_root}/bin/migrate-to-hornero.sh', true)
	r := migrate_report(MigrateOptions{
		yes: true
	})
	assert r.ok
	argv := os.read_file('${mig_root}/argv.txt') or { '' }
	assert argv.contains('--yes'), argv
	os.unsetenv('HORNERO_MIGRATE_BIN')
}

fn test_migrate_runs_backend_and_parses_rows() {
	mig_setup_backend()
	r := migrate_report(MigrateOptions{
		yes: true
	})
	assert r.ok
	assert r.command == 'config migrate'
	assert r.data['rows'] == '7'
	assert r.data['row.themes'] == 'copied: 2 pack(s)'
	assert r.data['row.presets'] == 'copied: 1 preset(s)'
	assert r.data['row.preset-pointer'] == 'already-canonical'
	assert r.data['row.wallpaper-pointer'] == 'absent-source'
	assert r.message.contains('copied  themes: 2 pack(s)')
	assert r.message.contains('7 row(s) reported')
	mig_teardown_backend()
}

fn test_migrate_helper_override_wins() {
	mig_write('${mig_root}/bin/other-migrate.sh', '#!/bin/sh\nprintf "ROW themes copied\\n";\nexit 0\n')
	r := migrate_report(MigrateOptions{
		yes:    true
		helper: '${mig_root}/bin/other-migrate.sh'
	})
	assert r.ok
	assert r.data['rows'] == '1'
	assert r.data['row.themes'] == 'copied'
	mig_teardown_backend()
}

fn test_migrate_unparsed_output_passes_through() {
	mig_write('${mig_root}/bin/plain-migrate.sh', '#!/bin/sh\necho "all done";\nexit 0\n')
	os.setenv('HORNERO_MIGRATE_BIN', '${mig_root}/bin/plain-migrate.sh', true)
	r := migrate_report(MigrateOptions{
		yes: true
	})
	assert r.ok
	assert r.data['rows'] == '0'
	assert r.message.contains('all done')
	mig_teardown_backend()
}

fn test_migrate_backend_failure_reports_exit() {
	mig_write('${mig_root}/bin/failing-migrate.sh', '#!/bin/sh\necho "boom";\nexit 3\n')
	os.setenv('HORNERO_MIGRATE_BIN', '${mig_root}/bin/failing-migrate.sh', true)
	r := migrate_report(MigrateOptions{
		yes: true
	})
	assert !r.ok
	assert r.command == 'config migrate'
	assert r.message.contains('exit 3')
	assert r.message.contains('boom')
	mig_teardown_backend()
}

fn test_migrate_missing_backend_fails_cleanly() {
	old_home, old_path := mig_isolate_resolution()
	r := migrate_report(MigrateOptions{
		yes: true
	})
	assert r.command == 'config migrate'
	assert !r.ok
	assert r.message.contains('HORNERO_MIGRATE_BIN')
	mig_restore_resolution(old_home, old_path)
}

fn test_parse_migrate_rows_accepts_both_forms() {
	rows := parse_migrate_rows('ROW themes copied 2 pack(s)\nROW bogus-domain copied\nROW schemes\nnote: human chatter\npresets: already-canonical\nwallpaper-pointer: absent-source\nunknown-thing: ignored\n')
	assert rows.len == 3
	assert rows[0].domain == 'themes'
	assert rows[0].status == 'copied'
	assert rows[0].detail == '2 pack(s)'
	assert rows[1].domain == 'presets'
	assert rows[1].status == 'already-canonical'
	assert rows[2].domain == 'wallpaper-pointer'
	assert rows[2].status == 'absent-source'
}

fn test_migrate_resolver_honors_override() {
	os.setenv('HORNERO_MIGRATE_BIN', '/tmp/hx-mig-ov/migrate-to-hornero.sh', true)
	assert resolve_migrate_bin() == '/tmp/hx-mig-ov/migrate-to-hornero.sh'
	mig_teardown_backend()
}

fn test_migrate_resolver_never_hardcodes_dots_paths() {
	// Path-contract binding: with no override and no backend on PATH/HOME,
	// the resolver returns '' (callers fail cleanly naming the override)
	// instead of a hardcoded `dots/*` path that bypasses resolution.
	old_home, old_path := mig_isolate_resolution()
	assert resolve_migrate_bin() == ''
	assert !resolve_migrate_bin().contains('/dots/')
	mig_restore_resolution(old_home, old_path)
}
