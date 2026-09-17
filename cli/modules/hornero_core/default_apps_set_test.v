module hornero_core

import os

fn default_apps_set_test_save_env(keys []string) map[string]string {
	mut saved := map[string]string{}
	for k in keys {
		saved[k] = os.getenv(k)
	}
	return saved
}

fn default_apps_set_test_restore_env(saved map[string]string) {
	for k, v in saved {
		if v.len == 0 {
			os.unsetenv(k)
		} else {
			os.setenv(k, v, true)
		}
	}
}

fn test_default_apps_set_needs_args() {
	r := default_apps_set_report(DefaultAppsSetOptions{
		dry_run: true
	})
	assert !r.ok
	assert r.message.contains('missing MIME type')
}

fn test_default_apps_set_rejects_bad_mime() {
	r := default_apps_set_report(DefaultAppsSetOptions{
		mime:    'not-a-mime'
		app:     'nvim.desktop'
		dry_run: true
	})
	assert !r.ok
	assert r.message.contains('invalid MIME type')
}

fn test_default_apps_set_rejects_bad_app() {
	r := default_apps_set_report(DefaultAppsSetOptions{
		mime:    'text/plain'
		app:     'nvim'
		dry_run: true
	})
	assert !r.ok
	assert r.message.contains('invalid application')
}

fn test_default_apps_set_needs_yes() {
	r := default_apps_set_report(DefaultAppsSetOptions{
		mime: 'text/plain'
		app:  'nvim.desktop'
	})
	assert !r.ok
	assert r.message.contains('--yes')
}

fn test_default_apps_set_dry_run_needs_no_backend() {
	// Hermetic: nonexistent backend; dry-run still previews.
	saved := default_apps_set_test_save_env(['HORNERO_XDG_MIME_BIN'])
	os.setenv('HORNERO_XDG_MIME_BIN', '/nonexistent-xdg-mime-hornero-test', true)
	r := default_apps_set_report(DefaultAppsSetOptions{
		mime:    'text/plain'
		app:     'nvim.desktop'
		dry_run: true
	})
	assert r.ok
	assert r.message.contains('would run:')
	assert r.message.contains('default nvim.desktop text/plain')
	default_apps_set_test_restore_env(saved)
}

fn test_default_apps_set_missing_backend() {
	// Hermetic: no override and an empty PATH, so nothing resolves and
	// the command fails with guidance instead of executing.
	saved := default_apps_set_test_save_env(['HORNERO_XDG_MIME_BIN', 'PATH'])
	os.unsetenv('HORNERO_XDG_MIME_BIN')
	os.setenv('PATH', '/nonexistent-hx-path-test', true)
	r := default_apps_set_report(DefaultAppsSetOptions{
		mime: 'text/plain'
		app:  'nvim.desktop'
		yes:  true
	})
	assert !r.ok
	assert r.message.contains('xdg-mime not found')
	default_apps_set_test_restore_env(saved)
}
