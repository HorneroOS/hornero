module hornero_core

import os

const refresh_hypr_test_factory_text = 'local here = "x"\ndofile(here .. "monitors.lua")\ndofile(here .. "monitors-user.lua")\ndofile(here .. "autostart.lua")\n'
const refresh_hypr_test_stale_text = 'local here = "x"\ndofile(here .. "monitors.lua")\ndofile(here .. "autostart.lua")\n-- mine\n'

fn refresh_hypr_test_save_env(keys []string) map[string]string {
	mut saved := map[string]string{}
	for k in keys {
		saved[k] = os.getenv(k)
	}
	return saved
}

fn refresh_hypr_test_restore_env(saved map[string]string) {
	for k, v in saved {
		if v.len == 0 {
			os.unsetenv(k)
		} else {
			os.setenv(k, v, true)
		}
	}
}

fn test_refresh_hypr_needs_yes_or_dry_run() {
	r := config_refresh_hypr_report(ConfigRefreshHyprOptions{})
	assert !r.ok
	assert r.message.contains('--yes')
}

fn test_refresh_hypr_missing_helper_is_actionable() {
	saved := refresh_hypr_test_save_env(['HORNERO_REFRESH_HYPR_HELPER', 'HOME'])
	os.setenv('HORNERO_REFRESH_HYPR_HELPER', '', true)
	os.setenv('HOME', '/nonexistent-home-hornero-test', true)
	r := config_refresh_hypr_report(ConfigRefreshHyprOptions{
		dry_run: true
	})
	assert !r.ok
	assert r.message.contains('refresh helper not installed')
	refresh_hypr_test_restore_env(saved)
}

fn test_refresh_hypr_dry_run_and_apply_with_fake_helper() {
	saved := refresh_hypr_test_save_env(['HORNERO_REFRESH_HYPR_HELPER', 'HORNERO_HYPR_FACTORY',
		'HORNERO_HYPR_TARGET'])
	dir := os.join_path(os.temp_dir(), 'hornero-refresh-hypr-test-${os.getpid()}')
	os.mkdir_all(dir) or { assert false, 'mkdir ${dir}' }
	helper := os.join_path(dir, 'helper.py')
	// Minimal stand-in with the same CLI contract as the real helper:
	// without --apply it only reports, with --apply it inserts the line.
	helper_lines := [
		'import sys',
		'args = sys.argv[1:]',
		'target = args[args.index("--target") + 1]',
		'if "--apply" in args:',
		'    lines = open(target).read().splitlines()',
		'    out = []',
		'    for line in lines:',
		'        out.append(line)',
		'        if "monitors.lua" in line and "monitors-user" not in line:',
		'            out.append(line.replace("monitors.lua", "monitors-user.lua"))',
		'    open(target, "w").write("\\n".join(out) + "\\n")',
		'    print("applied")',
		'else:',
		'    print("would insert monitors-user")',
	]
	os.write_file(helper, helper_lines.join('\n') + '\n') or { assert false, 'write helper' }
	factory := os.join_path(dir, 'factory.lua')
	target := os.join_path(dir, 'hyprland.lua')
	os.write_file(factory, refresh_hypr_test_factory_text) or { assert false }
	os.write_file(target, refresh_hypr_test_stale_text) or { assert false }
	os.setenv('HORNERO_REFRESH_HYPR_HELPER', helper, true)
	os.setenv('HORNERO_HYPR_FACTORY', factory, true)
	os.setenv('HORNERO_HYPR_TARGET', target, true)
	preview := config_refresh_hypr_report(ConfigRefreshHyprOptions{
		dry_run: true
	})
	assert preview.ok, preview.message
	assert preview.message.contains('preview only')
	assert (os.read_file(target) or { '' }) == refresh_hypr_test_stale_text
	applied := config_refresh_hypr_report(ConfigRefreshHyprOptions{
		yes: true
	})
	assert applied.ok, applied.message
	out := os.read_file(target) or { '' }
	assert out.contains('monitors-user.lua')
	assert out.contains('-- mine')
	os.rmdir_all(dir) or {}
	refresh_hypr_test_restore_env(saved)
}
