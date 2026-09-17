module hornero_core

import os
import strconv
import time
import x.json2

// Native security-audit backend: mirrors the retired dots-security-audit
// checks (full/permissions/secrets/system) plus --fix (chmod/history
// scrub), --report (markdown), and --json. HOME redirection scopes
// every verb (tests); leaf tools resolve via PATH with
// HORNERO_STAT_BIN / HORNERO_FIND_BIN seams.

fn audit_stat_bin() string {
	env := os.getenv('HORNERO_STAT_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('stat')
}

fn audit_find_bin() string {
	env := os.getenv('HORNERO_FIND_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('find')
}

// strict_exec_wrap runs prog/args with every word single-quoted (find
// predicates carry parens, globs, and bangs the shared quote_arg
// leaves bare for the shell).
fn strict_exec_wrap(spec ExecSpec) ExecReport {
	line := strict_command_line(spec.prog, spec.args)
	if spec.dry_run {
		return ExecReport{
			command_line: line
			ok:           true
			output:       '(dry-run: not executed)'
			exit_code:    0
			was_dry_run:  true
		}
	}
	r := os.execute(line)
	return ExecReport{
		command_line: line
		ok:           r.exit_code == 0
		output:       r.output.trim_space()
		exit_code:    r.exit_code
		was_dry_run:  false
	}
}

// audit_stat_mode returns `stat -c %a` for one path, '' on failure.
fn audit_stat_mode(path string) string {
	stat := audit_stat_bin()
	if stat.len == 0 {
		return ''
	}
	rep := strict_exec_wrap(ExecSpec{
		prog: stat
		args: ['-c', '%a', path]
	})
	if !rep.ok {
		return ''
	}
	return rep.output.trim_space()
}

// audit_find runs find with the given argv, one path per line.
fn audit_find(args []string) []string {
	find := audit_find_bin()
	if find.len == 0 {
		return []string{}
	}
	rep := strict_exec_wrap(ExecSpec{
		prog: find
		args: args
	})
	if !rep.ok {
		return []string{}
	}
	return rep.output.split_into_lines().filter(it.trim_space().len > 0)
}

// audit_permissions_native mirrors check_file_permissions: returns the
// output lines plus the issue count (SUID/SGID hits warn, like the
// script, without counting as issues).
fn audit_permissions_native() ([]string, int) {
	home := os.home_dir()
	mut lines := ['🔒 Checking file permissions across system...']
	mut issues := 0
	ssh_dir := os.join_path(home, '.ssh')
	if os.is_dir(ssh_dir) {
		perms := audit_stat_mode(ssh_dir)
		if perms != '700' {
			lines << '❌ SSH directory has incorrect permissions: ${perms} (should be 700)'
			issues++
		} else {
			lines << '✅ SSH directory permissions correct'
		}
		for key in audit_find([ssh_dir, '-type', 'f', '(', '-name', 'id_*', '-o', '-name', '*_rsa',
			'-o', '-name', '*_ed25519', '-o', '-name', '*_ecdsa', ')', '!', '-name', '*.pub']) {
			kp := audit_stat_mode(key)
			if kp != '600' {
				lines << '❌ SSH private key has incorrect permissions: ${os.file_name(key)} (${kp}, should be 600)'
				issues++
			}
		}
		cfg := os.join_path(ssh_dir, 'config')
		if os.is_file(cfg) {
			cp := audit_stat_mode(cfg)
			if cp != '600' {
				lines << '❌ SSH config has incorrect permissions: ${cp} (should be 600)'
				issues++
			}
		}
	}
	xdg := os.getenv('XDG_CONFIG_HOME')
	cfg_base := if xdg.len > 0 { xdg } else { os.join_path(home, '.config') }
	cred_dir := os.join_path(cfg_base, 'private_credentials')
	if os.is_dir(cred_dir) {
		for f in audit_find([cred_dir, '-type', 'f']) {
			fp := audit_stat_mode(f)
			if fp != '600' {
				lines << '❌ Credential file has incorrect permissions: ${os.file_name(f)} (${fp}, should be 600)'
				issues++
			}
		}
	}
	lines << '  Checking for world-readable sensitive files...'
	for f in audit_find([home, '-maxdepth', '3', '-type', 'f', '(', '-name', '*.key', '-o', '-name',
		'*.pem', '-o', '-name', '*.p12', '-o', '-name', '*.pfx', '-o', '-name', '*password*', '-o',
		'-name', '*secret*', ')', '-perm', '/o+r']) {
		lines << '❌ Sensitive file is world-readable: ${f}'
		issues++
	}
	for s in audit_find([os.join_path(home, '.local', 'bin'), '-name', 'executable_dots-*', '-perm',
		'/o+w']) {
		lines << '❌ Script is world-writable: ${os.file_name(s)}'
		issues++
	}
	home_perms := audit_stat_mode(home)
	if home_perms.len > 0 && home_perms[home_perms.len - 1..].int() > 5 {
		lines << '❌ Home directory is world-writable: ${home_perms}'
		issues++
	}
	lines << '  Checking for suspicious SUID/SGID files...'
	for f in audit_find([os.join_path(home, '.local'), cfg_base, '-type', 'f', '(', '-perm', '-4000',
		'-o', '-perm', '-2000', ')']) {
		lines << '⚠️  Found SUID/SGID file in user directory: ${f}'
	}
	return lines, issues
}

// audit_secrets_native mirrors scan_for_secrets live behavior: the deep
// scan is unreachable in the script (early return), so the native port
// reports the same simplified lines and zero issues.
fn audit_secrets_native() ([]string, int) {
	return ['🔍 Secret scan simplified; skipping deep inspection.',
		'   Review .config, .local/share, .gitconfig, .npmrc, and shell history manually if needed.'], 0
}

// audit_system_native mirrors check_system_security: output lines plus
// the warning count.
fn audit_system_native() ([]string, int) {
	mut lines := ['🛡️  Checking system security settings...']
	mut warnings := 0
	ufw := backend_or_empty('HORNERO_UFW_BIN', 'ufw')
	fw := backend_or_empty('HORNERO_FIREWALL_CMD_BIN', 'firewall-cmd')
	ipt := backend_or_empty('HORNERO_IPTABLES_BIN', 'iptables')
	if ufw.len > 0 {
		rep := strict_exec_wrap(ExecSpec{
			prog: ufw
			args: ['status']
		})
		if rep.ok && rep.output.contains('Status: active') {
			lines << '✅ UFW firewall is active'
		} else {
			lines << '⚠️  UFW firewall is not active'
			warnings++
		}
	} else if fw.len > 0 {
		rep := strict_exec_wrap(ExecSpec{
			prog: fw
			args: ['--state']
		})
		if rep.ok && rep.output.contains('running') {
			lines << '✅ Firewalld is running'
		} else {
			lines << '⚠️  Firewalld is not running'
			warnings++
		}
	} else if ipt.len > 0 {
		rep := strict_exec_wrap(ExecSpec{
			prog: ipt
			args: ['-L']
		})
		if rep.ok && rep.output.split_into_lines().len > 10 {
			lines << '✅ iptables rules configured'
		} else {
			lines << '⚠️  No firewall rules detected'
			warnings++
		}
	} else {
		lines << '⚠️  No firewall management tool detected'
		warnings++
	}
	sysctl := backend_or_empty('HORNERO_SYSTEMCTL_BIN', 'systemctl')
	apt_timer := os.is_file('/etc/systemd/system/timers.target.wants/apt-daily.timer')
	mut dnf_on := false
	mut arch_reflector := false
	if sysctl.len > 0 {
		d := strict_exec_wrap(ExecSpec{
			prog: sysctl
			args: ['is-enabled', 'dnf-automatic.timer']
		})
		dnf_on = d.ok
		if backend_or_empty('HORNERO_PACMAN_BIN', 'pacman').len > 0 {
			r := strict_exec_wrap(ExecSpec{
				prog: sysctl
				args: ['is-enabled', '--quiet', 'reflector.timer']
			})
			arch_reflector = r.ok
		}
	}
	if apt_timer {
		lines << '✅ Automatic updates configured (apt)'
	} else if dnf_on {
		lines << '✅ Automatic updates configured (dnf)'
	} else if arch_reflector {
		lines << '✅ Automatic mirror updates configured (arch)'
	} else {
		lines << '⚠️  Automatic updates not detected'
		warnings++
	}
	mut sshd_path := os.getenv('HORNERO_SSHD_CONFIG')
	if sshd_path.len == 0 {
		sshd_path = '/etc/ssh/sshd_config'
	}
	sshd := os.read_file(sshd_path) or { '' }
	if sshd.len > 0 {
		if sshd.contains('PermitRootLogin no') {
			lines << '✅ SSH root login disabled'
		} else {
			lines << '⚠️  SSH root login not explicitly disabled'
			warnings++
		}
		if sshd.contains('PasswordAuthentication no') {
			lines << '✅ SSH password authentication disabled'
		} else {
			lines << '⚠️  SSH password authentication not disabled'
			warnings++
		}
		mut has_proto := false
		mut proto2 := false
		for line in sshd.split_into_lines() {
			t := line.trim_space()
			if t.starts_with('Protocol') {
				has_proto = true
				if t == 'Protocol 2' || t.starts_with('Protocol 2,') || t.starts_with('Protocol 2 ') {
					proto2 = true
				}
			}
		}
		if proto2 || !has_proto {
			lines << '✅ SSH using secure protocol'
		} else {
			lines << '❌ SSH not using protocol 2'
			warnings++
		}
	}
	if sysctl.len > 0 {
		f2b := strict_exec_wrap(ExecSpec{
			prog: sysctl
			args: ['is-active', '--quiet', 'fail2ban']
		})
		if f2b.ok {
			lines << '✅ fail2ban is running'
		} else {
			lines << '⚠️  fail2ban not running'
			warnings++
		}
	} else {
		lines << '⚠️  fail2ban not running'
		warnings++
	}
	aa := backend_or_empty('HORNERO_APPARMOR_BIN', 'apparmor_status')
	se := backend_or_empty('HORNERO_SESTATUS_BIN', 'sestatus')
	if aa.len > 0 {
		rep := strict_exec_wrap(ExecSpec{
			prog: aa
			args: []string{}
		})
		if rep.ok {
			lines << '✅ AppArmor is active'
		} else {
			lines << '⚠️  AppArmor not active'
			warnings++
		}
	} else if se.len > 0 {
		rep := strict_exec_wrap(ExecSpec{
			prog: se
			args: []string{}
		})
		if rep.ok && rep.output.contains('enabled') {
			lines << '✅ SELinux is enabled'
		} else {
			lines << '⚠️  SELinux not enabled'
			warnings++
		}
	} else {
		lines << '⚠️  No Mandatory Access Control system detected'
		warnings++
	}
	ss := backend_or_empty('HORNERO_SS_BIN', 'ss')
	nstat := backend_or_empty('HORNERO_NETSTAT_BIN', 'netstat')
	sock_bin := if ss.len > 0 { ss } else { nstat }
	if sock_bin.len > 0 {
		rep := strict_exec_wrap(ExecSpec{
			prog: sock_bin
			args: ['-tulnp']
		})
		if rep.ok {
			mut suspicious := 0
			for line in rep.output.split_into_lines() {
				if line.contains(':22') || line.contains(':31') || line.contains(':44') {
					// Port-range check like :22xx/:31xx/:44xx.
					for token in line.split(' ') {
						t := token.trim_space()
						for prefix in [':22', ':31', ':44'] {
							if t.contains(prefix) {
								rest := t.all_after(prefix)
								if rest.len >= 2 && rest[0].is_digit() && rest[1].is_digit() {
									suspicious++
									break
								}
							}
						}
					}
					break
				}
			}
			if suspicious > 0 {
				lines << '⚠️  Found ${suspicious} potentially suspicious listening port(s)'
			}
		}
	}
	auto_up := os.read_file('/etc/apt/apt.conf.d/20auto-upgrades') or { '' }
	if auto_up.contains('APT::Periodic::Unattended-Upgrade "1"') {
		lines << '✅ Unattended security upgrades enabled'
	}
	return lines, warnings
}

// audit_utc_now formats UTC like `date -u +%Y-%m-%dT%H:%M:%SZ`.
fn audit_utc_now() string {
	t := time.now().local_to_utc()
	return t.custom_format('YYYY-MM-DDTHH:mm:ss') + 'Z'
}

// audit_full_native mirrors run_security_audit: header, the three
// sections, a log file under $HOME/.cache/dots, and the failures
// summary. Sections with issues count as failures, like the script.
fn audit_full_native() CommandResult {
	name := 'apps audit'
	home := os.home_dir()
	log := os.join_path(home, '.cache', 'dots', 'security_audit_${perf_datestamp(time.now())}.log')
	os.mkdir_all(os.dir(log)) or {}
	mut body := ['🔐 Running comprehensive security audit...', '']
	mut failures := 0
	perm, perm_issues := audit_permissions_native()
	body << perm.join('\n')
	if perm_issues > 0 {
		failures++
	}
	body << ''
	sec, sec_issues := audit_secrets_native()
	body << sec.join('\n')
	if sec_issues > 0 {
		failures++
	}
	body << ''
	sys, sys_issues := audit_system_native()
	body << sys.join('\n')
	if sys_issues > 0 {
		failures++
	}
	os.write_file(log, 'Timestamp: ${audit_utc_now()}\n' + body.join('\n') + '\n') or {}
	body << ''
	body << '📄 Security audit completed. Log saved to: ${log}'
	if failures > 0 {
		body << '❌ ${failures} section(s) with issues'
		return fail_result(name, body.join('\n'))
	}
	return ok_result(name, body.join('\n'), {
		'check': 'full'
		'log':   log
	})
}

// audit_section_native runs one read-only check by name.
fn audit_section_native(check string) CommandResult {
	name := 'apps audit'
	if check == 'permissions' {
		lines, issues := audit_permissions_native()
		if issues > 0 {
			return fail_result(name, lines.join('\n'))
		}
		return ok_result(name, lines.join('\n'), {
			'check': check
		})
	}
	if check == 'secrets' {
		lines, _ := audit_secrets_native()
		return ok_result(name, lines.join('\n'), {
			'check': check
		})
	}
	lines, issues := audit_system_native()
	if issues > 0 {
		return fail_result(name, lines.join('\n'))
	}
	return ok_result(name, lines.join('\n'), {
		'check': check
	})
}

// audit_history_keep reports whether a shell-history line survives the
// scrub: drop lines that set password/token/secret/key values before any
// comment marker. Mirrors `grep -vEi "^[^#]*(password|token|secret|key).*="`
// (vlib regex has no case-insensitive mode, so the predicate lowers first).
fn audit_history_keep(line string) bool {
	lower := line.to_lower()
	code := if lower.contains('#') { lower.all_before('#') } else { lower }
	for w in ['password', 'token', 'secret', 'key'] {
		if idx := code.index(w) {
			if code[idx..].contains('=') {
				return false
			}
		}
	}
	return true
}

// audit_chmod flips one path (dry-run returns the would-do line instead
// of touching disk).
fn audit_chmod(path string, mode int, dry_run bool) !string {
	if dry_run {
		return 'would chmod 0o' + strconv.format_int(mode, 8) + ' ' + path
	}
	os.chmod(path, mode) or { return error('cannot chmod ${path}: ${err.msg()}') }
	return ''
}

// audit_octal_tail parses the last three `%a` digits (setuid-style leading
// digits are ignored, like the script's `${perms: -1}` tail check).
fn audit_octal_tail(perms string) int {
	t := if perms.len > 3 { perms[perms.len - 3..] } else { perms }
	if t.len != 3 {
		return -1
	}
	mut mode := 0
	for c in t {
		d := c.str().int()
		if d < 0 || d > 7 || d.str() != c.str() {
			return -1
		}
		mode = mode * 8 + d
	}
	return mode
}

// audit_fix_native mirrors apply_security_fixes: SSH/credential/script
// file modes, home world-bit strip, shell-history scrub. Mutating: needs
// --yes; --dry-run only previews.
fn audit_fix_native(dry_run bool, yes bool) CommandResult {
	name := 'apps audit --fix'
	if !yes && !dry_run {
		return fail_result(name, 'refusing to apply fixes without --yes (preview with --dry-run).\nExample: horneroctl apps audit --fix --dry-run')
	}
	home := os.home_dir()
	mut lines := ['🔧 Applying security fixes...']
	mut preview := []string{}
	ssh_dir := os.join_path(home, '.ssh')
	if os.is_dir(ssh_dir) {
		for f in audit_find([ssh_dir, '-type', 'f', '(', '-name', 'id_*', '-o', '-name', '*_rsa',
			'-o', '-name', '*_ed25519', '-o', '-name', '*_ecdsa', ')', '!', '-name', '*.pub']) {
			msg := audit_chmod(f, 0o600, dry_run) or { return fail_result(name, err.msg()) }
			if dry_run {
				preview << msg
			}
		}
		msg := audit_chmod(ssh_dir, 0o700, dry_run) or { return fail_result(name, err.msg()) }
		if dry_run {
			preview << msg
		}
		lines << '✅ Fixed SSH directory permissions (700)'
		lines << '✅ Fixed SSH private key permissions (600)'
		cfg := os.join_path(ssh_dir, 'config')
		if os.is_file(cfg) {
			msg2 := audit_chmod(cfg, 0o600, dry_run) or { return fail_result(name, err.msg()) }
			if dry_run {
				preview << msg2
			}
			lines << '✅ Fixed SSH config permissions (600)'
		}
		for p in audit_find([ssh_dir, '-name', '*.pub']) {
			msg3 := audit_chmod(p, 0o644, dry_run) or { return fail_result(name, err.msg()) }
			if dry_run {
				preview << msg3
			}
		}
		lines << '✅ Fixed SSH public key permissions (644)'
	}
	xdg := os.getenv('XDG_CONFIG_HOME')
	cfg_base := if xdg.len > 0 { xdg } else { os.join_path(home, '.config') }
	cred_dir := os.join_path(cfg_base, 'private_credentials')
	if os.is_dir(cred_dir) {
		for f in audit_find([cred_dir, '-type', 'f']) {
			msg := audit_chmod(f, 0o600, dry_run) or { return fail_result(name, err.msg()) }
			if dry_run {
				preview << msg
			}
		}
		msg := audit_chmod(cred_dir, 0o700, dry_run) or { return fail_result(name, err.msg()) }
		if dry_run {
			preview << msg
		}
		lines << '✅ Fixed credential file permissions'
	}
	bin_dir := os.join_path(home, '.local', 'bin')
	for s in audit_find([bin_dir, '-name', 'executable_dots-*']) {
		msg := audit_chmod(s, 0o755, dry_run) or { return fail_result(name, err.msg()) }
		if dry_run {
			preview << msg
		}
	}
	lines << '✅ Fixed script permissions'
	for f in audit_find([home, '-maxdepth', '3', '-type', 'f', '(', '-name', '*.key', '-o', '-name',
		'*.pem', '-o', '-name', '*.p12', '-o', '-name', '*.pfx', ')']) {
		msg := audit_chmod(f, 0o600, dry_run) or { return fail_result(name, err.msg()) }
		if dry_run {
			preview << msg
		}
	}
	lines << '✅ Fixed sensitive file permissions'
	home_perms := audit_stat_mode(home)
	if home_perms.len > 0 {
		mode := audit_octal_tail(home_perms)
		if mode >= 0 && mode & 0o007 > 5 {
			if dry_run {
				preview << 'would chmod o-rwx ${home}'
			} else {
				os.chmod(home, mode & ~0o007) or {
					return fail_result(name, 'cannot chmod ${home}: ${err.msg()}')
				}
			}
			lines << '✅ Removed world permissions from home directory'
		}
	}
	for hist in [os.join_path(home, '.zsh_history'), os.join_path(home, '.bash_history')] {
		if os.is_file(hist) {
			if dry_run {
				preview << 'would scrub sensitive entries in ${hist}'
			} else {
				raw := os.read_file(hist) or { '' }
				kept := raw.split_into_lines().filter(fn (line string) bool {
					return audit_history_keep(line)
				})
				ending := if raw.ends_with('\n') { '\n' } else { '' }
				os.write_file(hist, kept.join('\n') + ending) or {
					return fail_result(name, 'cannot scrub ${hist}: ${err.msg()}')
				}
			}
			lines << '✅ Cleaned sensitive entries from ${os.file_name(hist)}'
		}
	}
	lines << ''
	lines << '🔒 Security fixes applied.'
	lines << "⚠️  Review the cleaned history files to ensure legitimate content wasn't removed."
	if dry_run {
		return ok_result(name, 'would apply fixes:\n  ' + preview.join('\n  '), {
			'mode':    'fix'
			'dry_run': 'true'
		})
	}
	return ok_result(name, lines.join('\n'), {
		'mode': 'fix'
	})
}

// audit_report_native mirrors generate_security_report: the three sections
// plus static recommendations, written to a markdown file under
// $HOME/.cache/dots.
fn audit_report_native(dry_run bool) CommandResult {
	name := 'apps audit --report'
	home := os.home_dir()
	stamp := perf_datestamp(time.now())
	report := os.join_path(home, '.cache', 'dots', 'security_report_${stamp}.md')
	if dry_run {
		return ok_result(name, 'would write ${report} (permissions, secrets, system sections)',
			{
			'mode':    'report'
			'dry_run': 'true'
		})
	}
	os.mkdir_all(os.dir(report)) or {}
	perm, _ := audit_permissions_native()
	sec, _ := audit_secrets_native()
	sys, _ := audit_system_native()
	doc := ['# horneroctl Security Audit Report', '', '_Generated: ${audit_utc_now()}_', '',
		'## File Permissions', '', perm.join('\n'), '', '## Secrets Scan', '', sec.join('\n'),
		'', '## System Security', '', sys.join('\n'), '', '## Recommendations', '',
		'### High Priority', '- Ensure all SSH keys have 600 permissions',
		'- Review any files flagged above for hardcoded secrets',
		'- Enable firewall if not already active', '', '### Medium Priority',
		'- Set up automatic security updates', '- Review SSH configuration for hardening',
		'- Run monthly security audits', '', '### Security Checklist',
		'- [ ] SSH keys properly secured', '- [ ] No plain-text secrets in config files',
		'- [ ] Firewall configured', '- [ ] Automatic updates enabled', '', '## Next Steps', '',
		'Run `horneroctl apps audit --fix` to apply permission fixes and scrub shell history.',
		'']
	os.write_file(report, doc.join('\n')) or {
		return fail_result(name, 'cannot write report: ${err.msg()}')
	}
	return ok_result(name, '📋 Security report generated: ${report}', {
		'mode':   'report'
		'report': report
	})
}

pub struct AuditJsonSection {
pub:
	output string
	ok     bool
}

pub struct AuditJsonReport {
pub:
	timestamp    string
	total_checks int
	failures     int
	compliant    bool
	permissions  AuditJsonSection
	secrets      AuditJsonSection
	system       AuditJsonSection
}

// audit_json_native mirrors run_security_audit_json: machine-readable
// summary over the three native sections.
fn audit_json_native() CommandResult {
	name := 'apps audit --json'
	perm, perm_issues := audit_permissions_native()
	sec, sec_issues := audit_secrets_native()
	sys, sys_issues := audit_system_native()
	mut failures := 0
	if perm_issues > 0 {
		failures++
	}
	if sec_issues > 0 {
		failures++
	}
	if sys_issues > 0 {
		failures++
	}
	body := json2.encode(AuditJsonReport{
		timestamp:    audit_utc_now()
		total_checks: 3
		failures:     failures
		compliant:    failures == 0
		permissions:  AuditJsonSection{
			output: perm.join('\n')
			ok:     perm_issues == 0
		}
		secrets:      AuditJsonSection{
			output: sec.join('\n')
			ok:     sec_issues == 0
		}
		system:       AuditJsonSection{
			output: sys.join('\n')
			ok:     sys_issues == 0
		}
	})
	if failures > 0 {
		return fail_result(name, body)
	}
	return ok_result(name, body, {
		'mode': 'json'
	})
}
