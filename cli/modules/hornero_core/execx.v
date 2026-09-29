module hornero_core

import os
import time

// ExecSpec describes one external invocation. With dry_run set, nothing is
// executed: callers get the exact command line back for preview.
// timeout_sec bounds wall-clock execution via GNU timeout when > 0;
// a 124 exit then means the backend hung and its output names the limit.
pub struct ExecSpec {
pub:
	prog        string
	args        []string
	dry_run     bool
	timeout_sec int
}

pub struct ExecReport {
pub:
	command_line string
	ok           bool
	output       string
	exit_code    int
	was_dry_run  bool
}

fn quote_arg(a string) string {
	if a.contains(' ') || a.contains('"') || a.contains("'") || a.len == 0 {
		return "'${a.replace("'", "'\\''")}'"
	}
	return a
}

pub fn command_line(prog string, args []string) string {
	mut parts := [prog]
	for a in args {
		parts << quote_arg(a)
	}
	return parts.join(' ')
}

// run_exec executes prog with args, or previews when dry_run is set.
// With timeout_sec > 0 the run is wrapped in `timeout -s KILL` so a hung
// backend fails loudly (exit 124) instead of blocking the CLI forever.
pub fn run_exec(spec ExecSpec) ExecReport {
	line := command_line(spec.prog, spec.args)
	if spec.dry_run {
		return ExecReport{
			command_line: line
			ok:           true
			output:       '(dry-run: not executed)'
			exit_code:    0
			was_dry_run:  true
		}
	}
	exec_line := if spec.timeout_sec > 0 {
		'timeout -s KILL ${spec.timeout_sec} ${line}'
	} else {
		line
	}
	t0 := time.now().unix()
	r := os.execute('${exec_line}')
	elapsed := time.now().unix() - t0
	// A wrapped run that never returns in time dies by our timeout's
	// hand: GNU timeout reports 124 (TERM) or 128+signal (137 with
	// `-s KILL`; raw signal numbers where os.execute passes them
	// through, e.g. 9 — all verified live). Any other failure that
	// still consumed the whole window also means the backend hung for
	// practical purposes, so it gets the timeout message too; fast
	// genuine failures keep their real exit and output below. The +1s
	// absorbs unix() truncation on short test windows.
	if spec.timeout_sec > 0 && r.exit_code != 0 && (r.exit_code == 124
		|| r.exit_code == 137 || elapsed + 1 >= spec.timeout_sec) {
		return ExecReport{
			command_line: line
			ok:           false
			output:       'backend timed out after ${spec.timeout_sec}s: ${line}'
			exit_code:    r.exit_code
			was_dry_run:  false
		}
	}
	return ExecReport{
		command_line: line
		ok:           r.exit_code == 0
		output:       r.output.trim_space()
		exit_code:    r.exit_code
		was_dry_run:  false
	}
}

// find_on_path resolves a bare program name via PATH, or '' when absent.
pub fn find_on_path(prog string) string {
	if prog.contains('/') {
		if os.is_file(prog) {
			return prog
		}
		return ''
	}
	return os.find_abs_path_of_executable(prog) or { '' }
}
