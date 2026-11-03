module hornero_core

import os
import time

// Update safety: preflight checks before a system upgrade, reboot
// detection after one, and an append-only JSONL history of upgrade
// attempts. Everything here is read-only except the history append;
// the privileged transaction itself stays in package_ops.v.

// resolve_pacman_lock_path locates pacman's transaction lock.
// Override with HORNERO_PACMAN_LOCK for isolated environments.
pub fn resolve_pacman_lock_path() string {
	env := os.getenv('HORNERO_PACMAN_LOCK')
	if env.len > 0 {
		return env
	}
	return '/var/lib/pacman/db.lck'
}

// resolve_df_bin locates df for the free-space preflight.
// Override with HORNERO_DF_BIN for isolated environments.
pub fn resolve_df_bin() string {
	env := os.getenv('HORNERO_DF_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('df')
}

// resolve_kernel_release_file locates the running-kernel release file.
// Override with HORNERO_KERNEL_RELEASE_FILE for isolated environments.
pub fn resolve_kernel_release_file() string {
	env := os.getenv('HORNERO_KERNEL_RELEASE_FILE')
	if env.len > 0 {
		return env
	}
	return '/proc/sys/kernel/osrelease'
}

// resolve_modules_root locates the installed kernel modules root.
// Override with HORNERO_MODULES_ROOT for isolated environments.
pub fn resolve_modules_root() string {
	env := os.getenv('HORNERO_MODULES_ROOT')
	if env.len > 0 {
		return env
	}
	return '/usr/lib/modules'
}

// resolve_update_history_path locates the append-only upgrade history.
// Override with HORNERO_UPDATE_HISTORY for isolated environments.
pub fn resolve_update_history_path() string {
	env := os.getenv('HORNERO_UPDATE_HISTORY')
	if env.len > 0 {
		return env
	}
	mut base := os.getenv('XDG_STATE_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.local', 'state')
	}
	return os.join_path(base, 'hornero', 'update-history.jsonl')
}

// free_space_kb returns available KiB on the filesystem holding path,
// or -1 when it cannot be determined (preflight then stays silent
// rather than blocking an upgrade on a guess).
pub fn free_space_kb(path string) i64 {
	df := resolve_df_bin()
	if df.len == 0 {
		return -1
	}
	result := os.execute('${df} -Pk ${path}')
	if result.exit_code != 0 {
		return -1
	}
	return parse_df_available_kb(result.output)
}

// parse_df_available_kb extracts the Available column (KiB) from
// `df -Pk` output. Pure: hermetically testable.
pub fn parse_df_available_kb(output string) i64 {
	lines := output.split_into_lines()
	if lines.len < 2 {
		return -1
	}
	fields := lines[1].fields()
	if fields.len < 4 {
		return -1
	}
	return fields[3].i64()
}

// upgrade_preflight_blocker returns a human reason the upgrade must
// not start, or '' when it may proceed. Blocking on a held pacman
// lock is deliberate: starting pkexec into a locked database only
// produces a raw pacman error, and deleting the lock for the user
// would be unsafe while another transaction runs.
pub fn upgrade_preflight_blocker() string {
	lock_path := resolve_pacman_lock_path()
	if os.exists(lock_path) {
		return 'pacman database is locked (${lock_path} exists): another package operation may be running. Wait for it to finish; do not delete the lock while pacman runs.'
	}
	free_kb := free_space_kb('/')
	if free_kb >= 0 && free_kb < 512 * 1024 {
		return 'less than 512 MiB free on / (${free_kb / 1024} MiB): free disk space before upgrading or the transaction can fail mid-download.'
	}
	return ''
}

// upgrade_preflight_warnings returns non-blocking advisories worth
// showing before a transaction starts.
pub fn upgrade_preflight_warnings() []string {
	mut warnings := []string{}
	free_kb := free_space_kb('/')
	if free_kb >= 512 * 1024 && free_kb < 2 * 1024 * 1024 {
		warnings << 'low free space on /: ${free_kb / 1024} MiB available'
	}
	return warnings
}

// reboot_required reports whether the running kernel's modules are
// gone (the classic post-upgrade state where the loaded kernel was
// replaced on disk). Pure paths are injectable for tests.
pub fn reboot_required() (bool, string) {
	raw_release := os.read_file(resolve_kernel_release_file()) or { '' }
	release := raw_release.trim_space()
	if release.len == 0 {
		return false, ''
	}
	modules := os.join_path(resolve_modules_root(), release)
	if os.is_dir(modules) {
		return false, ''
	}
	return true, 'running kernel ${release} has no modules on disk (replaced by an upgrade): reboot to load the installed kernel'
}

fn json_escape(value string) string {
	return value.replace('\\', '\\\\').replace('"', '\\"').replace('\n', ' ')
}

// update_history_line renders one history record as a JSON object.
// Pure: hermetically testable. Keys are stable for the Shell.
pub fn update_history_line(at_unix i64, at_iso string, action string, ok bool, command_line string) string {
	return '{"at_unix":${at_unix},"at":"${json_escape(at_iso)}","action":"${json_escape(action)}","ok":${ok},"command":"${json_escape(command_line)}"}'
}

// record_update_history appends one upgrade attempt to the history
// file. Best-effort: a history write failure never fails the upgrade
// itself, but the attempt is always made for real (non-dry) runs.
pub fn record_update_history(action string, ok bool, command_line string) {
	path := resolve_update_history_path()
	dir := os.dir(path)
	os.mkdir_all(dir) or { return }
	line := update_history_line(time.now().unix(), time.now().local_to_utc().custom_format('YYYY-MM-DDTHH:mm:ss') +
		'Z', action, ok, command_line)
	mut file := os.open_append(path) or { return }
	defer {
		file.close()
	}
	file.writeln(line) or { return }
}

// read_update_history returns history lines newest-first, capped.
pub fn read_update_history(limit int) []string {
	content := os.read_file(resolve_update_history_path()) or { return []string{} }
	mut lines := content.split_into_lines().filter(it.trim_space().len > 0)
	lines.reverse_in_place()
	if limit > 0 && lines.len > limit {
		lines = lines[..limit]
	}
	return lines
}

// package_history_report implements `package history` (read-only):
// the append-only record of system upgrade attempts.
pub fn package_history_report() CommandResult {
	lines := read_update_history(20)
	if lines.len == 0 {
		return ok_result('package history', 'No recorded HorneroOS upgrade attempts yet (history: ${resolve_update_history_path()}).',
			{
				'entries': '0'
			})
	}
	return ok_result('package history', lines.join('\n'), {
		'entries': lines.len.str()
		'path':    resolve_update_history_path()
	})
}
