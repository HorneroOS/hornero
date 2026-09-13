module hornero_cli

import os

// Preview-1 migrate dispatch fixtures reuse the core /tmp tree; each test
// sets the overrides it needs and unsets them afterwards.
fn mig_dispatch_setup() {
	os.mkdir_all('/tmp/hx-migrate-dtest/bin') or { assert false }
	os.write_file('/tmp/hx-migrate-dtest/bin/migrate-to-hornero.sh', '#!/bin/sh\nif [ "\$1" = "--dry-run" ]; then printf "ROW themes dry-run\\n"; exit 0; fi\nprintf "ROW themes copied 2 pack(s)\\nROW presets copied\\n";\nexit 0\n') or {
		assert false
	}
	os.chmod('/tmp/hx-migrate-dtest/bin/migrate-to-hornero.sh', 0o755) or { assert false }
	os.setenv('HORNERO_MIGRATE_BIN', '/tmp/hx-migrate-dtest/bin/migrate-to-hornero.sh',
		true)
}

fn mig_dispatch_teardown() {
	os.unsetenv('HORNERO_MIGRATE_BIN')
}

fn test_dispatch_config_migrate() {
	mig_dispatch_setup()
	assert dispatch(['horneroctl', 'config', 'migrate', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'config', 'migrate', '--yes']) == 0
	assert dispatch(['horneroctl', 'config', 'migrate', '--dry-run', '--yes']) == 0
	assert dispatch(['horneroctl', 'config', 'migrate', '--dry-run', '--helper',
		'/tmp/hx-migrate-dtest/bin/migrate-to-hornero.sh']) == 0
	assert dispatch(['horneroctl', 'config', 'migrate', '--dry-run',
		'--helper=/tmp/hx-migrate-dtest/bin/migrate-to-hornero.sh']) == 0
	// Mutating without --yes refuses (exit 1), never runs the backend.
	assert dispatch(['horneroctl', 'config', 'migrate']) == 1
	assert dispatch(['horneroctl', 'config', 'migrate', '--helper',
		'/tmp/hx-migrate-dtest/bin/migrate-to-hornero.sh']) == 1
	assert dispatch(['horneroctl', 'config', 'migrate', '--bogus']) == 2
	assert dispatch(['horneroctl', 'config', 'migrate', '--helper']) == 2
	assert dispatch(['horneroctl', 'config', 'migrate', '--helper=']) == 2
	assert dispatch(['horneroctl', 'config', 'migrate', 'extra']) == 2
	assert dispatch(['horneroctl', 'config', 'migrate', '--help']) == 0
	mig_dispatch_teardown()
}

fn test_migrate_dry_run_needs_no_backend() {
	// Hermetic: nonexistent backend; dry-run previews must still pass.
	os.setenv('HORNERO_MIGRATE_BIN', '/nonexistent-migrate-hornero-test', true)
	assert dispatch(['horneroctl', 'config', 'migrate', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'config', 'migrate', '--dry-run', '--helper',
		'/nonexistent-migrate-hornero-test']) == 0
	os.unsetenv('HORNERO_MIGRATE_BIN')
}

fn test_migrate_help_has_examples() {
	h := command_help('config migrate')
	assert h.contains('Examples:')
	assert h.contains('horneroctl config migrate --dry-run')
	assert h.contains('horneroctl config migrate --yes')
}

fn test_migrate_json_and_quiet_modes() {
	mig_dispatch_setup()
	assert dispatch(['horneroctl', '--json', 'config', 'migrate', '--dry-run']) == 0
	assert dispatch(['horneroctl', '--quiet', 'config', 'migrate', '--dry-run']) == 0
	assert dispatch(['horneroctl', '--json', 'config', 'migrate', '--yes']) == 0
	assert dispatch(['horneroctl', '--quiet', 'config', 'migrate', '--yes']) == 0
	mig_dispatch_teardown()
}
