module hornero_cli

import os

const store_dispatch_test_root = '/tmp/hx-store-dispatch-test'

fn store_dispatch_setup() string {
	root := store_dispatch_test_root
	if os.exists(root) {
		os.rmdir_all(root) or {}
	}
	os.mkdir_all('${root}/config/hornero/hornero-apps') or { assert false }
	os.mkdir_all('${root}/data/applications') or { assert false }
	os.mkdir_all('${root}/state/hornero/store') or { assert false }
	os.setenv('XDG_CONFIG_HOME', '${root}/config', true)
	os.setenv('XDG_DATA_HOME', '${root}/data', true)
	os.setenv('XDG_STATE_HOME', '${root}/state', true)
	os.setenv('HORNERO_STORE_POLICY_FILE', '${root}/config/hornero/hornero-apps/policy.json',
		true)
	os.setenv('HORNERO_STORE_AUDIT_FILE', '${root}/state/hornero/store/audit.jsonl', true)
	os.setenv('HORNERO_STORE_APPIMAGES_DIR', '${root}/data/hornero/appimages', true)
	os.setenv('HORNERO_STORE_QUEUE_FILE', '${root}/config/hornero/store-onboarding-queue.json',
		true)
	os.setenv('HORNERO_PACMAN_LOCK', '${root}/nonexistent.lck', true)
	os.setenv('HORNERO_STORE_PACMAN_INSTALLED', 'firefox,ollama', true)
	os.setenv('HORNERO_STORE_FLATPAK_INSTALLED', 'ai.jan.Jan', true)
	os.setenv('HORNERO_PKEXEC_BIN', '/nonexistent-pkexec-test', true)
	os.setenv('HORNERO_PACMAN_BIN', '/nonexistent-pacman-test', true)
	os.setenv('HORNERO_FLATPAK_BIN', '/nonexistent-flatpak-test', true)
	os.setenv('HORNERO_AUR_HELPER_BIN', '/nonexistent-yay-test', true)
	os.setenv('HORNERO_QS_BIN', '/nonexistent-qs-test', true)
	return root
}

fn store_dispatch_teardown() {
	for k in ['XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'HORNERO_STORE_POLICY_FILE',
		'HORNERO_STORE_AUDIT_FILE', 'HORNERO_STORE_APPIMAGES_DIR', 'HORNERO_STORE_QUEUE_FILE',
		'HORNERO_PACMAN_LOCK', 'HORNERO_STORE_PACMAN_INSTALLED', 'HORNERO_STORE_FLATPAK_INSTALLED',
		'HORNERO_PKEXEC_BIN', 'HORNERO_PACMAN_BIN', 'HORNERO_FLATPAK_BIN', 'HORNERO_AUR_HELPER_BIN',
		'HORNERO_QS_BIN'] {
		os.unsetenv(k)
	}
	os.rmdir_all(store_dispatch_test_root) or {}
}

fn test_store_help_and_completions() {
	assert root_help().contains('store')
	assert bash_completion().contains('store')
	assert zsh_completion().contains('store')
	assert fish_completion().contains('-a store ')
	for topic in ['store', 'store search', 'store list', 'store show', 'store categories',
		'store collections', 'store profiles', 'store profile-show', 'store installed', 'store install',
		'store remove', 'store update', 'store launch', 'store sources', 'store permissions',
		'store appimage', 'store webapp', 'store policy', 'store manifest', 'store queue', 'store gui',
		'store doctor'] {
		h := command_help(topic)
		assert h.contains('Examples:'), '${topic} help missing Examples:'
	}
	assert dispatch(['horneroctl', 'store', '--help']) == 0
	assert dispatch(['horneroctl', 'store', 'install', '--help']) == 0
	assert dispatch(['horneroctl', 'help', 'store']) == 0
}

fn test_store_usage_errors_exit_two() {
	assert dispatch(['horneroctl', 'store']) == 2
	assert dispatch(['horneroctl', 'store', 'bogus']) == 2
	assert dispatch(['horneroctl', 'store', 'show']) == 2
	assert dispatch(['horneroctl', 'store', 'install']) == 2
	assert dispatch(['horneroctl', 'store', 'install', 'firefox', '--bogus']) == 2
	assert dispatch(['horneroctl', 'store', 'remove']) == 2
	assert dispatch(['horneroctl', 'store', 'update']) == 2
	assert dispatch(['horneroctl', 'store', 'launch']) == 2
	assert dispatch(['horneroctl', 'store', 'permissions']) == 2
	assert dispatch(['horneroctl', 'store', 'appimage']) == 2
	assert dispatch(['horneroctl', 'store', 'webapp']) == 2
	assert dispatch(['horneroctl', 'store', 'manifest']) == 2
}

fn test_store_dispatch_reads_dry_runs_and_yes_gates() {
	root := store_dispatch_setup()
	defer {
		store_dispatch_teardown()
	}
	assert dispatch(['horneroctl', '--json', 'store', 'categories']) == 0
	assert dispatch(['horneroctl', '--json', 'store', 'collections']) == 0
	assert dispatch(['horneroctl', '--json', 'store', 'profiles']) == 0
	assert dispatch(['horneroctl', '--json', 'store', 'profile-show', 'minimal']) == 0
	assert dispatch(['horneroctl', '--json', 'store', 'search', 'chatgpt']) == 0
	assert dispatch(['horneroctl', '--json', 'store', 'list', '--featured', '--limit', '10']) == 0
	assert dispatch(['horneroctl', '--json', 'store', 'show', 'claude-desktop']) == 0
	assert dispatch(['horneroctl', '--json', 'store', 'installed']) == 0
	assert dispatch(['horneroctl', '--json', 'store', 'sources']) == 0
	assert dispatch(['horneroctl', '--json', 'store', 'doctor']) == 0
	assert dispatch(['horneroctl', '--json', 'store', 'gui', 'firefox', '--dry-run']) == 0

	// Yes gates fail with 1 when omitted
	assert dispatch(['horneroctl', '--quiet', 'store', 'install', 'firefox']) == 1
	assert dispatch(['horneroctl', '--json', 'store', 'install', 'firefox', '--dry-run']) == 0
	assert dispatch(['horneroctl', '--quiet', 'store', 'remove', 'firefox']) == 1
	assert dispatch(['horneroctl', '--json', 'store', 'remove', 'firefox', '--dry-run']) == 0
	assert dispatch(['horneroctl', '--quiet', 'store', 'update', '--all']) == 1
	assert dispatch(['horneroctl', '--json', 'store', 'update', '--all', '--dry-run']) == 0

	// Policy & queue mutations
	assert dispatch(['horneroctl', '--json', 'store', 'policy', 'show']) == 0
	assert dispatch(['horneroctl', '--quiet', 'store', 'policy', 'set', '--verified-only', 'true']) == 1
	assert dispatch(['horneroctl', '--json', 'store', 'policy', 'set', '--verified-only', 'true',
		'--yes']) == 0
	assert dispatch(['horneroctl', '--json', 'store', 'policy', 'reset', '--yes']) == 0

	manifest := '${root}/manifest.json'
	assert dispatch(['horneroctl', '--json', 'store', 'manifest', 'export', manifest, '--yes']) == 0
	assert dispatch(['horneroctl', '--json', 'store', 'manifest', 'import', manifest]) == 0
	assert dispatch(['horneroctl', '--json', 'store', 'manifest', 'apply', manifest, '--dry-run']) == 0

	assert dispatch(['horneroctl', '--json', 'store', 'queue', 'add', 'firefox', '--yes']) == 0
	assert dispatch(['horneroctl', '--json', 'store', 'queue', 'list']) == 0
	assert dispatch(['horneroctl', '--json', 'store', 'queue', 'clear', '--yes']) == 0
}
