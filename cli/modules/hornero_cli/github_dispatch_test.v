module hornero_cli

import os

fn test_github_help_is_discoverable() {
	assert command_help('github').contains('horneroctl github status --json')
	assert command_help('github').contains('Examples:')
	assert command_help('github stats').contains('Read-only')
	assert command_help('github inbox').contains('Read-only')
	assert command_help('github export').contains('--public-only')
	assert dispatch(['horneroctl', 'github', 'status', '--help']) == 0
	assert dispatch(['horneroctl', 'github', '--help']) == 0
	assert root_help().contains('github')
}

fn test_github_completions_include_github() {
	assert bash_completion().contains('github')
	assert zsh_completion().contains('github')
	assert fish_completion().contains('github')
}

fn test_github_unknown_and_usage_fail() {
	assert dispatch(['horneroctl', 'github']) != 0
	assert dispatch(['horneroctl', 'github', 'nope']) == 2
	assert dispatch(['horneroctl', 'github', 'stats', '--days', '0']) == 2
	assert dispatch(['horneroctl', 'github', 'stats', '--repo', 'noslash']) == 2
	assert dispatch(['horneroctl', 'github', 'stats', '--visibility', 'secret']) == 2
	assert dispatch(['horneroctl', 'github', 'stats', '--org=-evil']) == 2
}

fn test_github_offline_reports_unavailable_not_zero() {
	// Hermetic: isolated homes + offline mode. The command must fail
	// (exit 1) with an unavailable record, never zeroed metrics.
	tmp := '/tmp/hx-github-dispatch-test'
	os.rmdir_all(tmp) or {}
	os.mkdir_all(tmp) or { assert false }
	prev := {
		'HOME':                   os.getenv('HOME')
		'XDG_CACHE_HOME':         os.getenv('XDG_CACHE_HOME')
		'HORNERO_GITHUB_OFFLINE': os.getenv('HORNERO_GITHUB_OFFLINE')
		'HORNERO_GITHUB_BIN':     os.getenv('HORNERO_GITHUB_BIN')
	}
	os.setenv('HOME', tmp, true)
	os.setenv('XDG_CACHE_HOME', tmp + '/cache', true)
	os.setenv('HORNERO_GITHUB_OFFLINE', '1', true)
	os.setenv('HORNERO_GITHUB_BIN', '/nonexistent/gh', true)
	defer {
		for k, v in prev {
			if v.len > 0 {
				os.setenv(k, v, true)
			} else {
				os.unsetenv(k)
			}
		}
		os.rmdir_all(tmp) or {}
	}
	assert dispatch(['horneroctl', 'github', 'status', '--json']) != 0
	assert dispatch(['horneroctl', 'github', 'stats', '--json']) != 0
}

fn test_github_dry_run_previews_without_executing() {
	// A nonexistent gh + --dry-run must succeed: nothing executed.
	prev := os.getenv('HORNERO_GITHUB_BIN')
	os.setenv('HORNERO_GITHUB_BIN', '/nonexistent/gh', true)
	defer {
		if prev.len > 0 {
			os.setenv('HORNERO_GITHUB_BIN', prev, true)
		} else {
			os.unsetenv('HORNERO_GITHUB_BIN')
		}
	}
	assert dispatch(['horneroctl', 'github', 'stats', '--dry-run', '--json']) == 0
}
