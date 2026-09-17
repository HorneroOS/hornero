module hornero_core

import os

// Fixture-backed tests for the native performance reads: fake ps/zsh/
// free binaries plus a scratch log dir keep every run hermetic and fast.

const perf_test_keys = ['HORNERO_PERF_LOG_DIR', 'HORNERO_PS_BIN', 'HORNERO_ZSH_BIN',
	'HORNERO_FREE_BIN']

fn perf_test_save_env() map[string]string {
	mut saved := map[string]string{}
	for k in perf_test_keys {
		saved[k] = os.getenv(k)
	}
	return saved
}

fn perf_test_restore_env(saved map[string]string) {
	for k, v in saved {
		if v.len == 0 {
			os.unsetenv(k)
		} else {
			os.setenv(k, v, true)
		}
	}
}

fn perf_test_setup() {
	base := '/tmp/hx-perf-test/bin'
	os.mkdir_all(base) or { assert false }
	os.write_file(base + '/ps', '#!/bin/sh\nprintf "  100 Hyprland 102400\\n  200 kitty 51200\\n"\nexit 0\n') or {
		assert false
	}
	os.write_file(base + '/zsh', '#!/bin/sh\nexit 0\n') or { assert false }
	os.write_file(base + '/free', '#!/bin/sh\necho "Mem: 15Gi 8.0Gi 7.0Gi"\nexit 0\n') or {
		assert false
	}
	for b in ['ps', 'zsh', 'free'] {
		os.chmod(base + '/' + b, 0o755) or { assert false }
	}
	os.setenv('HORNERO_PS_BIN', base + '/ps', true)
	os.setenv('HORNERO_ZSH_BIN', base + '/zsh', true)
	os.setenv('HORNERO_FREE_BIN', base + '/free', true)
	os.setenv('HORNERO_PERF_LOG_DIR', '/tmp/hx-perf-test/logs', true)
	os.rmdir_all('/tmp/hx-perf-test/logs') or {}
	os.mkdir_all('/tmp/hx-perf-test/logs') or { assert false }
}

fn test_perf_memory_native_sums_rss() {
	saved := perf_test_save_env()
	perf_test_setup()
	r := performance_report(PerformanceOptions{ leaf: 'memory' })
	assert r.ok
	assert r.message.contains('Hyprland: 100.00 MB')
	assert r.message.contains('Kitty: 50.00 MB')
	assert r.message.contains('Quickshell: 0.00 MB')
	assert r.message.contains('Total stack memory: 150.00 MB')
	perf_test_restore_env(saved)
}

fn test_perf_startup_native_measures_and_logs() {
	saved := perf_test_save_env()
	perf_test_setup()
	r := performance_report(PerformanceOptions{ leaf: 'startup' })
	assert r.ok
	for i in 1 .. 6 {
		assert r.message.contains('Run ${i}:')
	}
	assert r.message.contains('Average startup time across 5 runs')
	assert r.message.contains('Without Powerlevel10k:')
	assert r.message.contains('Without plugins:')
	logs := os.ls('/tmp/hx-perf-test/logs') or { []string{} }
	mut found := false
	for e in logs {
		if e.starts_with('startup_') && e.ends_with('.log') {
			found = true
		}
	}
	assert found
	perf_test_restore_env(saved)
}

fn test_perf_benchmark_native_writes_log() {
	saved := perf_test_save_env()
	perf_test_setup()
	r := performance_report(PerformanceOptions{ leaf: 'benchmark' })
	assert r.ok
	assert r.message.contains('# HorneroConfig Performance Benchmark')
	assert r.message.contains('Script execution performance:')
	assert r.message.contains('Benchmark complete!')
	logs := os.ls('/tmp/hx-perf-test/logs') or { []string{} }
	mut found := false
	for e in logs {
		if e.starts_with('benchmark_') && e.ends_with('.log') {
			found = true
		}
	}
	assert found
	perf_test_restore_env(saved)
}

fn test_perf_report_native_writes_markdown() {
	saved := perf_test_save_env()
	perf_test_setup()
	r := performance_report(PerformanceOptions{ leaf: 'report' })
	assert r.ok
	assert r.message.contains('Report generated:')
	assert r.message.contains('Quick Summary:')
	logs := os.ls('/tmp/hx-perf-test/logs') or { []string{} }
	mut found := false
	for e in logs {
		if e.starts_with('performance_report_') && e.ends_with('.md') {
			found = true
			body := os.read_file('/tmp/hx-perf-test/logs/' + e) or { '' }
			assert body.contains('# HorneroConfig Performance Report')
			assert body.contains('## Recommendations')
		}
	}
	assert found
	perf_test_restore_env(saved)
}
