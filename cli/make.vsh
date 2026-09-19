#!/usr/bin/env -S v run
// horneroctl build tasks (agent-toolkit make.vsh pattern).
// Usage: ./make.vsh [--tasks] [help|fmt|fmt-check|vet|test|build|build-cli|install-cli]
// Optional: ./make.vsh build-cli && ./build/horneroctl version

import build
import os

const mods = ['hornero_core', 'hornero_cli']

fn root() string {
	d := dir(@FILE)
	if is_dir(join_path(d, 'modules')) {
		return d
	}
	return getwd()
}

fn vbin() string {
	for k in ['V', 'VBIN'] {
		p := getenv(k)
		if p.len > 0 {
			return p
		}
	}
	return 'v'
}

fn vcmd(args string) int {
	return system('"${vbin()}" ${args}')
}

fn flag_value(name string) string {
	long := '--${name}'
	eq := '${long}='
	argv := os.args
	for i, a in argv {
		if a.starts_with(eq) {
			return a.all_after('=')
		}
		if a == long && i + 1 < argv.len && !argv[i + 1].starts_with('-') {
			return argv[i + 1]
		}
	}
	return ''
}

fn install_prefix() string {
	p := flag_value('prefix')
	if p.len > 0 {
		return p
	}
	return join_path(home_dir(), '.local')
}

fn each_mod(r string, label string, args string) {
	for m in mods {
		println('==> ${label} ${m}')
		rc := vcmd('${args} ${join_path(r, 'modules', m)}')
		if rc != 0 {
			exit(rc)
		}
	}
}

r := root()
setenv('VMODULES', join_path(r, 'modules'), true)

mut context := build.context(
	default: 'help'
)

context.task(
	name: 'help'
	help: 'Show targets (default); also: --tasks'
	run:  fn (_ build.Task) ! {
		println('horneroctl V targets (latest master) — ./make.vsh --tasks')
		println('  fmt | fmt-check | vet | test | build | build-cli | install-cli')
	}
)

context.task(
	name: 'fmt'
	help: 'Format V sources'
	run:  fn (_ build.Task) ! {
		// Local root on purpose: explicit captures were removed upstream,
		// so closures resolve it per call on every toolchain.
		r := root()
		each_mod(r, 'fmt', 'fmt -w')
	}
)

context.task(
	name: 'fmt-check'
	help: 'Verify formatting (CI)'
	run:  fn (_ build.Task) ! {
		r := root()
		each_mod(r, 'fmt-check', 'fmt -verify')
	}
)

context.task(
	name: 'vet'
	help: 'Vet V sources'
	run:  fn (_ build.Task) ! {
		r := root()
		each_mod(r, 'vet', 'vet')
	}
)

context.task(
	name: 'test'
	help: 'Run unit tests'
	run:  fn (_ build.Task) ! {
		r := root()
		each_mod(r, 'test', 'test')
	}
)

context.task(
	name: 'build'
	help: 'Type-check modules (no binary)'
	run:  fn (_ build.Task) ! {
		r := root()
		each_mod(r, 'build', 'build -o /dev/null')
	}
)

context.task(
	name: 'build-cli'
	help: 'Build build/horneroctl'
	run:  fn (_ build.Task) ! {
		r := root()
		mkdir_all(join_path(r, 'build')) or {}
		mut ver := 'dev'
		vres := execute('git -C ${r} describe --tags --always --dirty 2>/dev/null')
		if vres.exit_code == 0 && vres.output.trim_space().len > 0 {
			ver = vres.output.trim_space()
		}
		mut commit := 'unknown'
		cres := execute('git -C ${r} rev-parse --short HEAD')
		if cres.exit_code == 0 {
			commit = cres.output.trim_space()
		}
		// Release provenance for `horneroctl version`: scripts/compose.sh
		// exports the composition pins; every value defaults to unknown so
		// local builds need no manifest checkout.
		mut shell_sha := getenv('HX_SHELL_SHA')
		if shell_sha.len == 0 {
			shell_sha = 'unknown'
		}
		mut config_sha := getenv('HX_CONFIG_SHA')
		if config_sha.len == 0 {
			config_sha = 'unknown'
		}
		mut manifest := getenv('HX_MANIFEST')
		if manifest.len == 0 {
			manifest = 'unknown'
		}
		mut release := getenv('HX_RELEASE')
		if release.len == 0 {
			release = 'unknown'
		}
		out := join_path(r, 'build', 'horneroctl')
		rc := vcmd('-d version=${ver} -d commit=${commit} -d hx_shell_sha=${shell_sha} -d hx_config_sha=${config_sha} -d hx_manifest=${manifest} -d hx_release=${release} -o ${out} ${join_path(r, 'cmd', 'horneroctl')}')
		if rc != 0 {
			exit(rc)
		}
		println('built ${out} (${ver}@${commit})')
	}
)

context.task(
	name: 'install-cli'
	help: 'Install horneroctl to --prefix/bin (default ~/.local/bin)'
	run:  fn (_ build.Task) ! {
		r := root()
		bin := join_path(install_prefix(), 'bin')
		mkdir_all(bin) or { panic(err) }
		cp(join_path(r, 'build', 'horneroctl'), join_path(bin, 'horneroctl')) or { panic(err) }
		println('installed to ${join_path(bin, 'horneroctl')}')
	}
)

context.run()
