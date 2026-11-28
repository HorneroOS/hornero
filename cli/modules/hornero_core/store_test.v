module hornero_core

import os
import x.json2

fn store_test_setup(name string) string {
	root := os.join_path(os.temp_dir(), 'hornero_store_test_${name}_${os.getpid()}')
	os.rmdir_all(root) or {}
	os.mkdir_all(os.join_path(root, 'config', 'hornero', 'hornero-apps')) or { assert false }
	os.mkdir_all(os.join_path(root, 'data', 'applications')) or { assert false }
	os.mkdir_all(os.join_path(root, 'state', 'hornero', 'store')) or { assert false }
	os.setenv('XDG_CONFIG_HOME', os.join_path(root, 'config'), true)
	os.setenv('XDG_DATA_HOME', os.join_path(root, 'data'), true)
	os.setenv('XDG_STATE_HOME', os.join_path(root, 'state'), true)
	os.setenv('HORNERO_STORE_POLICY_FILE', os.join_path(root, 'config', 'hornero', 'hornero-apps',
		'policy.json'), true)
	os.setenv('HORNERO_STORE_AUDIT_FILE', os.join_path(root, 'state', 'hornero', 'store',
		'audit.jsonl'), true)
	os.setenv('HORNERO_STORE_APPIMAGES_DIR', os.join_path(root, 'data', 'hornero', 'appimages'),
		true)
	os.setenv('HORNERO_STORE_QUEUE_FILE', os.join_path(root, 'config', 'hornero',
		'store-onboarding-queue.json'), true)
	os.setenv('HORNERO_PACMAN_LOCK', os.join_path(root, 'nonexistent-db.lck'), true)
	os.setenv('HORNERO_STORE_PACMAN_INSTALLED', 'firefox,ollama', true)
	os.setenv('HORNERO_STORE_FLATPAK_INSTALLED', 'ai.jan.Jan', true)
	os.setenv('HORNERO_PKEXEC_BIN', '/nonexistent-pkexec', true)
	os.setenv('HORNERO_PACMAN_BIN', '/nonexistent-pacman', true)
	os.setenv('HORNERO_FLATPAK_BIN', '/nonexistent-flatpak', true)
	os.setenv('HORNERO_AUR_HELPER_BIN', '/nonexistent-yay', true)
	os.setenv('HORNERO_QS_BIN', '/nonexistent-qs', true)
	return root
}

fn store_test_teardown(root string) {
	for k in ['XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'HORNERO_STORE_POLICY_FILE',
		'HORNERO_STORE_AUDIT_FILE', 'HORNERO_STORE_APPIMAGES_DIR', 'HORNERO_STORE_QUEUE_FILE',
		'HORNERO_PACMAN_LOCK', 'HORNERO_STORE_PACMAN_INSTALLED', 'HORNERO_STORE_FLATPAK_INSTALLED',
		'HORNERO_PKEXEC_BIN', 'HORNERO_PACMAN_BIN', 'HORNERO_FLATPAK_BIN', 'HORNERO_AUR_HELPER_BIN',
		'HORNERO_QS_BIN', 'HORNERO_APP_CATALOG'] {
		os.unsetenv(k)
	}
	os.rmdir_all(root) or {}
}

fn test_catalog_loads_canonical_entries_and_claude_policy() {
	root := store_test_setup('cat')
	defer {
		store_test_teardown(root)
	}
	cat := load_app_catalog() or {
		assert false, 'load_app_catalog failed: ${err}'
		return
	}
	assert cat.apps.len >= 200
	assert cat.categories.len == 12
	assert cat.collections.len == 10
	assert cat.profiles.len == 9

	claude := find_catalog_app(cat, 'claude-desktop') or {
		assert false, 'claude-desktop missing'
		return
	}
	assert claude.recommended_source == 'webapp'
	assert claude.sources.any(it.backend == 'aur' && it.provenance == 'community_package')

	chatgpt := find_catalog_app(cat, 'chatgpt-desktop') or {
		assert false, 'chatgpt-desktop missing'
		return
	}
	assert chatgpt.recommended_source == 'vendor_repo'
}

fn test_store_search_show_categories_collections_profiles_and_installed() {
	root := store_test_setup('query')
	defer {
		store_test_teardown(root)
	}
	sres := store_search_result(StoreSearchOptions{
		query: 'firefox'
	})
	assert sres.ok
	assert sres.data['count'].int() >= 1
	assert sres.data['apps'].contains('"installed":true')

	show := store_show_result('claude-desktop')
	assert show.ok
	assert show.data['id'] == 'claude-desktop'
	assert show.data['policy_allowed'] == 'false' // proprietary requires opt-in

	cats := store_categories_result()
	assert cats.ok && cats.data['count'] == '12'

	cols := store_collections_result()
	assert cols.ok && cols.data['count'] == '10'

	profs := store_profiles_result()
	assert profs.ok && profs.data['count'] == '9'

	pshow := store_profile_show_result('ai-native-workstation')
	assert pshow.ok && pshow.data['total_count'].int() > 0

	inst := store_installed_result('')
	assert inst.ok && inst.data['count'].int() >= 3
}

fn test_store_policy_gates_and_install_dry_run() {
	root := store_test_setup('policy')
	defer {
		store_test_teardown(root)
	}
	// Proprietary app blocked without --accept-proprietary
	blocked := store_install_result(StoreInstallOptions{
		id:      'spotify'
		dry_run: true
	})
	assert !blocked.ok
	assert blocked.data['policy_blocked'] == 'true'

	// Proprietary app allowed with --accept-proprietary on dry-run (AUR also requires --allow-aur if AUR)
	// Spotify has flatpak (flathub_community) + aur; recommended is flatpak.
	ok_prop := store_install_result(StoreInstallOptions{
		id:                 'spotify'
		accept_proprietary: true
		dry_run:            true
	})
	assert ok_prop.ok
	assert ok_prop.data['dry_run'] == 'true'

	// AUR source blocked without --allow-aur
	aur_blocked := store_install_result(StoreInstallOptions{
		id:                 'claude-desktop'
		source:             'aur'
		accept_proprietary: true
		dry_run:            true
	})
	assert !aur_blocked.ok
	assert aur_blocked.data['policy_blocked'] == 'true'

	// AUR allowed with --allow-aur on dry-run
	os.setenv('HORNERO_AUR_HELPER_BIN', '/usr/bin/echo', true)
	aur_ok := store_install_result(StoreInstallOptions{
		id:                 'claude-desktop'
		source:             'aur'
		accept_proprietary: true
		allow_aur:          true
		dry_run:            true
	})
	assert aur_ok.ok

	// Mutating policy set requires --yes
	pol_no_yes := store_policy_set_result(StorePolicySetOptions{
		has_verified_only: true
		verified_only:     true
	})
	assert !pol_no_yes.ok

	pol_yes := store_policy_set_result(StorePolicySetOptions{
		has_verified_only: true
		verified_only:     true
		yes:               true
	})
	assert pol_yes.ok
	assert load_store_policy().verified_only == true

	// Verified-only blocks unverified flatpak (flathub_community)
	unver_blocked := store_install_result(StoreInstallOptions{
		id:                 'spotify'
		source:             'flatpak'
		accept_proprietary: true
		dry_run:            true
	})
	assert !unver_blocked.ok
}

fn test_store_webapp_profile_dir_and_appimage_lifecycle() {
	root := store_test_setup('appimg')
	defer {
		store_test_teardown(root)
	}
	profile_dir := os.join_path(root, 'browser-profile')
	wa := store_webapp_add_result(WebAppSpec{
		id:          'claude-web'
		name:        'Claude'
		url:         'https://claude.ai'
		profile_dir: profile_dir
	}, false, true)
	assert wa.ok
	assert wa.data['profile_dir'] == profile_dir
	desktop_txt := os.read_file(wa.data['file_path']) or { '' }
	assert desktop_txt.contains('--user-data-dir=${profile_dir}')

	wlist := store_webapp_list_result()
	assert wlist.ok && wlist.data['count'] == '1'

	wrm := store_webapp_remove_result('claude-web', false, true)
	assert wrm.ok

	// AppImage import + symlink rejection + remove
	src := os.join_path(root, 'demo.AppImage')
	os.write_file(src, 'fake-appimage-binary') or { assert false }
	link := os.join_path(root, 'link.AppImage')
	os.symlink(src, link) or {}
	if os.is_link(link) {
		bad_link := store_appimage_import_result(link, 'bad', 'Bad', '', '', false, true)
		assert !bad_link.ok
	}

	imp := store_appimage_import_result(src, 'demo-app', 'Demo App', '', '', false, true)
	assert imp.ok
	assert os.exists(imp.data['binary_path'])
	assert os.exists(imp.data['desktop_path'])
	assert imp.data['sha256'].len == 64

	alist := store_appimage_list_result()
	assert alist.ok && alist.data['count'] == '1'

	arm := store_appimage_remove_result('demo-app', false, true)
	assert arm.ok
	assert !os.exists(imp.data['binary_path'])
}

fn test_store_manifest_queue_sources_and_doctor() {
	root := store_test_setup('mq')
	defer {
		store_test_teardown(root)
	}
	manifest := os.join_path(root, 'apps.json')
	exp := store_manifest_export_result(manifest, false, true)
	assert exp.ok && exp.data['count'].int() >= 3

	imp := store_manifest_import_result(manifest)
	assert imp.ok

	apply_dry := store_manifest_apply_result(manifest, true, false, true, false)
	assert apply_dry.ok

	// Queue lifecycle
	qa := store_queue_add_result('firefox', 'arch_native', false, true)
	assert qa.ok && qa.data['count'] == '1'
	ql := store_queue_list_result()
	assert ql.ok && ql.data['count'] == '1'
	qr := store_queue_run_result(false, false, true, false)
	assert qr.ok
	qc := store_queue_clear_result(false, true)
	assert qc.ok && qc.data['count'] == '0'

	srcs := store_sources_result()
	assert srcs.ok
	parsed := json2.decode[[]json2.Any](srcs.data['sources']) or {
		assert false
		return
	}
	assert parsed.len == 7
	assert srcs.data['sources'].contains('"backend":"snap"')

	doc := store_doctor_result()
	assert doc.ok
	assert doc.data['failures'] == '0'
}
