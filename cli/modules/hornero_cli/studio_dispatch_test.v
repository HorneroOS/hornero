module hornero_cli

import os

fn test_studio_help_is_discoverable() {
	assert command_help('studio').contains('horneroctl studio selection set')
	assert command_help('studio doctor').contains('Read-only')
	assert command_help('studio selection').contains('--dry-run')
	assert root_help().contains('studio')
}

fn test_studio_completions_include_studio() {
	assert bash_completion().contains('studio')
	assert zsh_completion().contains('studio')
	assert fish_completion().contains('studio')
}

fn test_studio_unknown_subcommand_fails() {
	assert dispatch(['horneroctl', 'studio', 'nope']) != 0
	assert dispatch(['horneroctl', 'studio']) != 0
}

fn test_studio_jobs_help_is_discoverable() {
	assert command_help('studio jobs').contains('studio jobs submit')
	assert command_help('studio jobs').contains('ffmpeg-export')
	assert command_help('studio jobs').contains('kdenlive-render')
	assert command_help('studio jobs').contains('melt-render')
	assert command_help('studio').contains('jobs')
}

fn test_studio_jobs_unknown_subcommand_fails() {
	assert dispatch(['horneroctl', 'studio', 'jobs', 'nope']) != 0
	assert dispatch(['horneroctl', 'studio', 'jobs', 'status']) != 0
}

fn test_studio_mode_help_is_discoverable() {
	assert command_help('studio mode').contains('studio mode restore')
	assert command_help('studio').contains('mode')
}

fn test_studio_mode_unknown_subcommand_fails() {
	assert dispatch(['horneroctl', 'studio', 'mode', 'nope']) != 0
	assert dispatch(['horneroctl', 'studio', 'mode', 'audio']) != 0
}

fn test_studio_audio_help_is_discoverable() {
	h := command_help('studio audio')
	assert h.contains('Examples:')
	assert h.contains('studio audio revert')
	assert h.contains('not physical round-trip latency')
	assert command_help('studio').contains('audio')
}

fn test_studio_audio_usage_errors() {
	assert dispatch(['horneroctl', 'studio', 'audio', 'nope']) != 0
	assert dispatch(['horneroctl', 'studio', 'audio', 'apply', '--bogus']) != 0
	// apply without --yes is refused before touching anything.
	assert dispatch(['horneroctl', 'studio', 'audio', 'apply']) != 0
}

fn test_studio_routing_help_and_dispatch() {
	root := '/tmp/hx-studio-routing-dtest'
	if os.exists(root) {
		os.rmdir_all(root) or {}
	}
	os.mkdir_all('${root}/pw.conf.d') or { assert false }
	os.mkdir_all('${root}/jack.conf.d') or { assert false }
	os.setenv('HORNERO_PIPEWIRE_CONF_DIR', '${root}/pw.conf.d', true)
	os.setenv('HORNERO_JACK_CONF_DIR', '${root}/jack.conf.d', true)
	os.setenv('HORNERO_PACTL_BIN', '/nonexistent-pactl-dtest', true)
	defer {
		os.unsetenv('HORNERO_PIPEWIRE_CONF_DIR')
		os.unsetenv('HORNERO_JACK_CONF_DIR')
		os.unsetenv('HORNERO_PACTL_BIN')
	}
	h := command_help('studio routing')
	assert h.contains('Examples:')
	assert h.contains('live-call')
	assert h.contains('browser-backing')
	assert h.contains('reaper-low-latency')
	assert command_help('studio').contains('routing')
	assert dispatch(['horneroctl', 'studio', 'routing', '--help']) == 0
	assert dispatch(['horneroctl', '--json', 'studio', 'routing', 'status']) == 0
	assert dispatch(['horneroctl', 'studio', 'routing', 'nope']) == 2
	assert dispatch(['horneroctl', 'studio', 'routing', 'enable']) == 2
	assert dispatch(['horneroctl', 'studio', 'routing', 'enable', 'live-call', '--bogus']) == 2
	assert dispatch(['horneroctl', 'studio', 'routing', 'fix-volume', '42', 'notanumber']) == 2
	assert dispatch(['horneroctl', 'studio', 'routing', 'enable', 'live-call']) == 1
	assert dispatch(['horneroctl', 'studio', 'routing', 'enable', 'live-call', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'studio', 'routing', 'disable', 'live-call', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'studio', 'routing', 'move-stream', '42', 'discord_call', '--dry-run']) == 0
	assert dispatch(['horneroctl', 'studio', 'routing', 'fix-volume', '42', '100', '--dry-run']) == 0
}
