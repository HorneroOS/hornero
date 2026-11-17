module hornero_cli

import os

fn mode_fake_qs(label string, body string) (string, string) {
	dir := os.join_path(os.temp_dir(), 'hx-modecli-${label}-${os.getpid()}')
	os.mkdir_all(dir) or { panic(err) }
	bin := os.join_path(dir, 'qs')
	os.write_file(bin, body) or { panic(err) }
	os.chmod(bin, 0o755) or { panic(err) }
	return bin, dir
}

fn test_dispatch_mode_usage_errors_exit_2() {
	assert dispatch(['horneroctl', 'mode']) == 2
	assert dispatch(['horneroctl', 'mode', 'bogus']) == 2
	assert dispatch(['horneroctl', 'mode', 'get', '--bogus']) == 2
	assert dispatch(['horneroctl', 'mode', 'get', 'extra']) == 2
	assert dispatch(['horneroctl', 'mode', 'set']) == 2
	assert dispatch(['horneroctl', 'mode', 'set', 'signal', 'extra']) == 2
	assert dispatch(['horneroctl', 'mode', 'set', 'signal', '--yes']) == 2
	assert dispatch(['horneroctl', 'mode', 'list', '--yes']) == 2
}

fn test_dispatch_mode_validates_names_with_exit_1() {
	assert dispatch(['horneroctl', 'mode', 'set', 'turbo', '--dry-run']) == 1
	assert dispatch(['horneroctl', 'mode', 'set', 'Signal', '--dry-run']) == 1
}

fn test_dispatch_mode_dry_run_and_reset_gate() {
	assert dispatch(['horneroctl', 'mode', 'set', 'signal', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'mode', 'reset', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'mode', 'reset']) == 1
	assert dispatch(['horneroctl', '--json', 'mode', 'get', '--dry-run']) == 0
}

fn test_dispatch_mode_help_carries_examples() {
	for name in ['mode', 'mode list', 'mode get', 'mode set', 'mode reset', 'mode status'] {
		h := command_help(name)
		assert h.contains('Examples:'), name
		assert h.contains('horneroctl mode'), name
	}
	assert dispatch(['horneroctl', 'mode', '--help']) == 0
	assert dispatch(['horneroctl', 'mode', 'set', '--help']) == 0
	assert root_help().contains('  mode ')
	assert bash_completion().contains(' mode ')
	assert zsh_completion().contains(' mode ')
	assert fish_completion().contains('-a mode')
}

fn test_dispatch_mode_against_fake_shell() {
	bin, dir := mode_fake_qs('ok', '#!/bin/sh\ncase "\$4" in get) echo signal ;; set) echo "ok: \$5" ;; esac\n')
	defer { os.rmdir_all(dir) or {} }
	os.setenv('HORNERO_QS_BIN', bin, true)
	defer { os.unsetenv('HORNERO_QS_BIN') }
	assert dispatch(['horneroctl', 'mode', 'get']) == 0
	assert dispatch(['horneroctl', 'mode', 'set', 'gaming']) == 0
}

fn test_dispatch_mode_shell_down_exits_1() {
	bin, dir := mode_fake_qs('down', '#!/bin/sh\necho "no instances" >&2\nexit 1\n')
	defer { os.rmdir_all(dir) or {} }
	os.setenv('HORNERO_QS_BIN', bin, true)
	defer { os.unsetenv('HORNERO_QS_BIN') }
	assert dispatch(['horneroctl', 'mode', 'get']) == 1
	assert dispatch(['horneroctl', 'mode', 'status']) == 1
	assert dispatch(['horneroctl', 'mode', 'set', 'focus']) == 1
	assert dispatch(['horneroctl', 'mode', 'reset', '--yes']) == 1
}
