module hornero_core

import os
import time

// Native performance backend: mirrors the retired dots-performance
// legacy body. The four reads (startup, memory, benchmark, report)
// run natively; only `mode` still shells to powerprofilesctl.
// Seams (hermetic tests): HORNERO_PERF_LOG_DIR, HORNERO_PS_BIN,
// HORNERO_ZSH_BIN, HORNERO_FREE_BIN.

struct PerfPsRow {
	pid  string
	comm string
	rss  i64
}

// perf_log_dir resolves the performance log root.
pub fn perf_log_dir() string {
	env := os.getenv('HORNERO_PERF_LOG_DIR')
	if env.len > 0 {
		return env
	}
	return os.join_path(os.home_dir(), '.cache', 'dots', 'performance')
}

fn perf_ps_bin() string {
	env := os.getenv('HORNERO_PS_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('ps')
}

fn perf_zsh_bin() string {
	env := os.getenv('HORNERO_ZSH_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('zsh')
}

fn perf_free_bin() string {
	env := os.getenv('HORNERO_FREE_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('free')
}

// perf_format_mb formats KiB as `%.2f MB`, like the script's awk.
fn perf_format_mb(kib i64) string {
	return '${f64(kib) / 1024.0:.2f} MB'
}

// perf_format_time formats milliseconds as bash `time` real output
// (`0m0.123s`), which the script greps for.
fn perf_format_time(ms i64) string {
	m := ms / 60000
	rem := ms % 60000
	s := rem / 1000
	frac := rem % 1000
	return '${m}m${s}.${frac:03}s'
}

// perf_stamp builds %Y%m%d_%H%M%S via the stdlib custom_format.
fn perf_stamp(t time.Time) string {
	return t.custom_format('YYYYMMDD_HHmmss')
}

// perf_datestamp builds %Y%m%d via the stdlib custom_format.
fn perf_datestamp(t time.Time) string {
	return t.custom_format('YYYYMMDD')
}

// perf_stack_rows runs ps for the Wayland stack processes, like
// list_stack_processes (empty when ps is missing or matches nothing).
fn perf_stack_rows() []PerfPsRow {
	ps := perf_ps_bin()
	if ps.len == 0 {
		return []PerfPsRow{}
	}
	rep := run_exec(ExecSpec{
		prog: ps
		args: ['-C', 'Hyprland,quickshell,mako,hyprlock,kitty', '-o', 'pid=,comm=,rss=']
	})
	if !rep.ok {
		return []PerfPsRow{}
	}
	mut rows := []PerfPsRow{}
	for line in rep.output.split_into_lines() {
		parts := line.split(' ').filter(it.len > 0)
		if parts.len < 3 {
			continue
		}
		rows << PerfPsRow{
			pid:  parts[0]
			comm: parts[1]
			rss:  parts[2].i64()
		}
	}
	return rows
}

// perf_sum_rss totals RSS KiB for one process name, like sum_process_rss_mb.
fn perf_sum_rss(rows []PerfPsRow, name string) i64 {
	mut sum := i64(0)
	for r in rows {
		if r.comm == name {
			sum += r.rss
		}
	}
	return sum
}

// perf_memory_lines builds the check_memory_usage output.
fn perf_memory_lines(rows []PerfPsRow) []string {
	mut lines := ['💾 Analyzing memory usage (Wayland stack)...', '', 'Current relevant processes:']
	if rows.len == 0 {
		lines << '  (none)'
	} else {
		for r in rows {
			lines << '${r.pid} ${r.comm} ${r.rss}'
		}
	}
	lines << ''
	lines << 'Memory usage by component:'
	lines << '  Hyprland: ${perf_format_mb(perf_sum_rss(rows, 'Hyprland'))}'
	lines << '  Quickshell: ${perf_format_mb(perf_sum_rss(rows, 'quickshell'))}'
	lines << '  Mako: ${perf_format_mb(perf_sum_rss(rows, 'mako'))}'
	lines << '  Hyprlock: ${perf_format_mb(perf_sum_rss(rows, 'hyprlock'))}'
	lines << '  Kitty: ${perf_format_mb(perf_sum_rss(rows, 'kitty'))}'
	mut total := i64(0)
	for r in rows {
		total += r.rss
	}
	lines << '  Total stack memory: ${perf_format_mb(total)}'
	return lines
}

// perf_zsh_time runs zsh once and returns its wall time in bash format.
fn perf_zsh_time(zsh string, zshrun bool, no_rcs bool) !string {
	mut args := []string{}
	if no_rcs {
		args << '--no-rcs'
	} else {
		args << '-i'
	}
	args << '-c'
	args << 'exit'
	if zshrun {
		os.setenv('ZSHRUN', '1', true)
	}
	start := time.now()
	rep := run_exec(ExecSpec{
		prog: zsh
		args: args
	})
	ms := time.since(start).milliseconds()
	if zshrun {
		os.unsetenv('ZSHRUN')
	}
	if !rep.ok {
		return error('zsh run failed (exit ${rep.exit_code})')
	}
	return 'real\t${perf_format_time(ms)}'
}

// perf_startup_lines builds the measure_shell_startup output and
// returns it with the raw run times for the log file.
fn perf_startup_lines() !([]string, []string) {
	zsh := perf_zsh_bin()
	if zsh.len == 0 {
		return error('zsh not found on PATH. Set HORNERO_ZSH_BIN.')
	}
	mut lines := ['🚀 Measuring shell startup performance...']
	mut times := []string{}
	for i in 1 .. 6 {
		t := perf_zsh_time(zsh, false, false)!
		// strip the `real\t` prefix: the script keeps `$2` only.
		val := t.split('\t')[1]
		times << val
		lines << '  Run ${i}: ${val}'
	}
	lines << '  Average startup time across 5 runs'
	lines << ''
	lines << '🔧 Component startup analysis:'
	lines << '  Without Powerlevel10k:'
	lines << perf_zsh_time(zsh, true, false)!
	lines << '  Without plugins:'
	lines << perf_zsh_time(zsh, false, true)!
	return lines, times
}

// perf_mem_total reads total memory like `free -h | grep Mem`.
fn perf_mem_total() string {
	free_bin := perf_free_bin()
	if free_bin.len == 0 {
		return 'unknown'
	}
	rep := run_exec(ExecSpec{
		prog: free_bin
		args: ['-h']
	})
	if !rep.ok {
		return 'unknown'
	}
	for line in rep.output.split_into_lines() {
		fields := line.split(' ').filter(it.len > 0)
		if fields.len >= 2 && fields[0] == 'Mem:' {
			return fields[1]
		}
	}
	return 'unknown'
}

// perf_cpu_model reads the first model name from /proc/cpuinfo.
fn perf_cpu_model() string {
	raw := os.read_file('/proc/cpuinfo') or { return '' }
	for line in raw.split_into_lines() {
		if line.starts_with('model name') {
			parts := line.split(':')
			if parts.len >= 2 {
				return parts[1..].join(':').trim_space()
			}
		}
	}
	return ''
}

// perf_os_pretty reads PRETTY_NAME from /etc/os-release.
fn perf_os_pretty() string {
	raw := os.read_file('/etc/os-release') or { return '' }
	for line in raw.split_into_lines() {
		if line.starts_with('PRETTY_NAME=') {
			return line['PRETTY_NAME='.len..].trim('"')
		}
	}
	return ''
}

// perf_recent_benchmarks lists up to 3 benchmark logs, newest first,
// like recent_benchmark_files.
fn perf_recent_benchmarks(dir string) []string {
	entries := os.ls(dir) or { return []string{} }
	mut scored := []string{}
	for e in entries {
		if e.starts_with('benchmark_') && e.ends_with('.log') {
			ts := os.file_last_mod_unix(os.join_path(dir, e))
			scored << '${ts} ${e}'
		}
	}
	scored.sort()
	scored.reverse()
	mut out := []string{}
	for i, s in scored {
		if i >= 3 {
			break
		}
		out << '- ' + s.all_after(' ')
	}
	return out
}

// perf_startup_report implements `apps performance startup`: measure,
// log to startup_<timestamp>.log, and print.
fn perf_startup_report(dry_run bool) CommandResult {
	name := 'apps performance startup'
	dir := perf_log_dir()
	if dry_run {
		return ok_result(name, 'would measure zsh startup (5 runs) and write ${dir}/startup_<timestamp>.log',
			{
				'dry_run': 'true'
			})
	}
	os.mkdir_all(dir) or {}
	lines, times := perf_startup_lines() or { return fail_result(name, err.msg()) }
	stamp := perf_stamp(time.now())
	log := os.join_path(dir, 'startup_${stamp}.log')
	content := '# Shell Startup Performance - ${time.now()}\nStandard startup times: ${times.join(' ')}\nBaseline (no plugins): ${lines[lines.len - 1]}\n'
	os.write_file(log, content) or {}
	return ok_result(name, lines.join('\n'), {
		'log': log
	})
}

// perf_memory_report implements `apps performance memory`.
fn perf_memory_report(dry_run bool) CommandResult {
	name := 'apps performance memory'
	if dry_run {
		return ok_result(name, 'would sum RSS for the Wayland stack via ps', {
			'dry_run': 'true'
		})
	}
	os.mkdir_all(perf_log_dir()) or {}
	lines := perf_memory_lines(perf_stack_rows())
	return ok_result(name, lines.join('\n'), {})
}

// perf_script_time times one helper `--help` for the benchmark section.
fn perf_script_time(prog string) string {
	start := time.now()
	rep := run_exec(ExecSpec{
		prog: prog
		args: ['--help']
	})
	ms := time.since(start).milliseconds()
	if !rep.ok {
		return 'failed'
	}
	return perf_format_time(ms)
}

// perf_benchmark_report implements `apps performance benchmark`: full
// suite into benchmark_<timestamp>.log, printed and saved (tee).
fn perf_benchmark_report(dry_run bool) CommandResult {
	name := 'apps performance benchmark'
	dir := perf_log_dir()
	if dry_run {
		return ok_result(name, 'would run the benchmark suite and write ${dir}/benchmark_<timestamp>.log',
			{
				'dry_run': 'true'
			})
	}
	os.mkdir_all(dir) or {}
	mut body := ['# HorneroConfig Performance Benchmark', 'Date: ${time.now()}',
		'System: ${os.uname().sysname} ${os.uname().release} ${os.uname().machine}',
		'Memory: ${perf_mem_total()}', 'CPU: ${perf_cpu_model()}', '']
	body << 'Measuring shell startup...'
	startup, _ := perf_startup_lines() or { return fail_result(name, err.msg()) }
	body << startup.join('\n')
	body << ''
	body << 'Checking memory usage...'
	body << perf_memory_lines(perf_stack_rows()).join('\n')
	body << ''
	body << 'Script execution performance:'
	for script in ['brightness', 'check-network', 'monitor'] {
		bin := find_on_path('dots-${script}')
		home_bin := os.join_path(os.home_dir(), '.local', 'bin', 'dots-${script}')
		target := if os.is_file(home_bin) { home_bin } else { bin }
		if target.len > 0 && os.is_executable(target) {
			body << '  dots ${script}: ${perf_script_time(target)}'
		} else {
			body << '  dots ${script}: not installed'
		}
	}
	stamp := perf_stamp(time.now())
	log := os.join_path(dir, 'benchmark_${stamp}.log')
	os.write_file(log, body.join('\n') + '\n') or {
		return fail_result(name, 'cannot write benchmark log: ${err.msg()}')
	}
	body << ''
	body << '📊 Benchmark complete! Results saved to: ${log}'
	return ok_result(name, body.join('\n'), {
		'log': log
	})
}

// perf_report_report implements `apps performance report`: markdown to
// performance_report_<date>.md plus a quick summary.
fn perf_report_report(dry_run bool) CommandResult {
	name := 'apps performance report'
	dir := perf_log_dir()
	if dry_run {
		return ok_result(name, 'would write ${dir}/performance_report_<date>.md', {
			'dry_run': 'true'
		})
	}
	os.mkdir_all(dir) or {}
	startup, _ := perf_startup_lines() or { return fail_result(name, err.msg()) }
	mut kept := []string{}
	for l in startup {
		if l.contains('Run') || l.contains('Average') || l.contains('Without') {
			kept << l
		}
	}
	rows := perf_stack_rows()
	mem := perf_memory_lines(rows).join('\n')
	recent := perf_recent_benchmarks(dir)
	mut doc := ['# HorneroConfig Performance Report', '', 'Generated: ${time.now()}', '',
		'## System Information', '- OS: ${perf_os_pretty()}', '- Kernel: ${os.uname().release}',
		'- Memory: ${perf_mem_total()}', '- CPU: ${perf_cpu_model()}', '', '## Performance Metrics',
		'', '### Shell Startup Time', kept.join('\n'), '', '### Memory Usage', mem, '',
		'## Recommendations', '', 'Based on the analysis:',
		'- Shell startup time should be under 0.5s for optimal experience',
		'- Total memory usage should remain under 200MB for lightweight operation',
		'- Consider disabling heavy plugins if startup time exceeds 1s', '', '## Historical Data',
		'Recent benchmark files:']
	doc << recent.join('\n')
	stamp := perf_datestamp(time.now())
	log := os.join_path(dir, 'performance_report_${stamp}.md')
	os.write_file(log, doc.join('\n') + '\n') or {
		return fail_result(name, 'cannot write performance report: ${err.msg()}')
	}
	mut summary := ['', '📊 Quick Summary:']
	// Latest startup time: last time-like token of the newest startup log.
	logs := os.ls(dir) or { []string{} }
	mut newest := ''
	mut newest_ts := i64(0)
	for e in logs {
		if e.starts_with('startup_') && e.ends_with('.log') {
			ts := os.file_last_mod_unix(os.join_path(dir, e))
			if ts >= newest_ts {
				newest_ts = ts
				newest = e
			}
		}
	}
	latest := if newest.len > 0 {
		content := os.read_file(os.join_path(dir, newest)) or { '' }
		lines := content.split_into_lines()
		last := if lines.len > 0 { lines[lines.len - 1] } else { '' }
		mut tok := 'N/A'
		for w in last.split(' ') {
			t := w.trim(',;:')
			if t.ends_with('s') && t.len > 1 {
				tok = t
			}
		}
		tok
	} else {
		'N/A'
	}
	summary << '  Latest startup time: ${latest}'
	summary << '  Current memory usage: ${perf_format_mb(perf_sum_rss(rows, 'Hyprland') +
		perf_sum_rss(rows, 'quickshell') + perf_sum_rss(rows, 'mako') +
		perf_sum_rss(rows, 'hyprlock') + perf_sum_rss(rows, 'kitty'))}'
	msg := '📄 Report generated: ${log}\n' + summary.join('\n')
	return ok_result(name, msg, {
		'log': log
	})
}
