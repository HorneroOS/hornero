module hornero_core

import os

// ExecSpec describes one external invocation. With dry_run set, nothing is
// executed: callers get the exact command line back for preview.
pub struct ExecSpec {
pub:
	prog    string
	args    []string
	dry_run bool
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
	if a.contains(' ') || a.contains('"') || a.len == 0 {
		return "'${a}'"
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
	r := os.execute('${line}')
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
