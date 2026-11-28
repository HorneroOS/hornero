module hornero_core

import os
import strings
import x.json2

// Store backend capability matrix, live installation detection, AppImage/WebApp
// user-space management, Flatpak permissions, and doctor checks.

pub fn resolve_flatpak_bin() string {
	return leaf_bin('HORNERO_FLATPAK_BIN', 'flatpak')
}

pub fn resolve_flatseal_bin() string {
	return leaf_bin('HORNERO_FLATSEAL_BIN', 'flatseal')
}

pub fn resolve_gearlever_bin() string {
	return leaf_bin('HORNERO_GEARLEVER_BIN', 'gearlever')
}

pub fn resolve_appstreamcli_bin() string {
	return leaf_bin('HORNERO_APPSTREAMCLI_BIN', 'appstreamcli')
}

pub fn resolve_fusermount_bin() string {
	env := os.getenv('HORNERO_FUSERMOUNT_BIN').trim_space()
	if env.len > 0 {
		return env
	}
	f3 := find_on_path('fusermount3')
	if f3.len > 0 {
		return f3
	}
	return find_on_path('fusermount')
}

pub fn resolve_gtk_launch_bin() string {
	return leaf_bin('HORNERO_GTK_LAUNCH_BIN', 'gtk-launch')
}

pub fn resolve_curl_bin() string {
	return leaf_bin('HORNERO_CURL_BIN', 'curl')
}

pub fn resolve_store_qs_bin() string {
	return leaf_bin('HORNERO_QS_BIN', 'qs')
}

pub fn resolve_store_appimages_dir() string {
	env := os.getenv('HORNERO_STORE_APPIMAGES_DIR').trim_space()
	if env.len > 0 {
		return env
	}
	return os.join_path(resolve_paths().data_dir, 'hornero', 'appimages')
}

pub fn resolve_store_queue_file() string {
	env := os.getenv('HORNERO_STORE_QUEUE_FILE').trim_space()
	if env.len > 0 {
		return env
	}
	return os.join_path(resolve_paths().config_dir, 'hornero', 'store-onboarding-queue.json')
}

pub struct StoreAppImageEntry {
pub:
	id           string
	name         string
	binary_path  string
	desktop_path string
	sha256       string
}

pub struct StoreInstalledSnapshot {
pub:
	pacman_pkgs []string
	flatpak_ids []string
	appimages   []StoreAppImageEntry
	webapps     []DesktopAppEntry
}

pub struct StoreSourceCapability {
pub:
	backend     string
	enabled     bool
	available   bool
	binary      string
	scope       string
	sandboxed   bool
	description string
	reason      string
}

fn split_nonempty_lines(raw string) []string {
	mut out := []string{}
	for line in raw.split_into_lines() {
		t := line.trim_space()
		if t.len > 0 && t !in out {
			out << t
		}
	}
	return out
}

fn detect_installed_pacman() []string {
	if override := os.getenv_opt('HORNERO_STORE_PACMAN_INSTALLED') {
		return split_nonempty_lines(override.replace(',', '\n'))
	}
	pacman := resolve_pacman_bin()
	if pacman.len == 0 {
		return []string{}
	}
	rep := run_exec(ExecSpec{
		prog:        pacman
		args:        ['-Qq']
		timeout_sec: 10
	})
	if !rep.ok {
		return []string{}
	}
	return split_nonempty_lines(rep.output)
}

fn detect_installed_flatpak() []string {
	if override := os.getenv_opt('HORNERO_STORE_FLATPAK_INSTALLED') {
		return split_nonempty_lines(override.replace(',', '\n'))
	}
	fp := resolve_flatpak_bin()
	if fp.len == 0 {
		return []string{}
	}
	rep := run_exec(ExecSpec{
		prog:        fp
		args:        ['list', '--app', '--columns=application']
		timeout_sec: 10
	})
	if !rep.ok {
		return []string{}
	}
	return split_nonempty_lines(rep.output)
}

pub fn appimage_desktop_path(id string) !string {
	safe := validate_app_id(id)!
	return os.join_path(applications_dir(), 'hornero-appimage-${safe}.desktop')
}

pub fn store_appimage_list_entries() []StoreAppImageEntry {
	dir := applications_dir()
	entries := os.ls(dir) or { return []StoreAppImageEntry{} }
	mut out := []StoreAppImageEntry{}
	for f in entries {
		if f.starts_with('hornero-appimage-') && f.ends_with('.desktop') {
			path := os.join_path(dir, f)
			raw := os.read_file(path) or { continue }
			mut id := ''
			mut name := ''
			mut exec_path := ''
			mut digest := ''
			for line in raw.split_into_lines() {
				if line.starts_with('X-Hornero-Id=') {
					id = line['X-Hornero-Id='.len..].trim_space()
				} else if line.starts_with('Name=') {
					name = line['Name='.len..].trim_space()
				} else if line.starts_with('Exec=') {
					exec_path = line['Exec='.len..].trim_space()
				} else if line.starts_with('X-Hornero-Sha256=') {
					digest = line['X-Hornero-Sha256='.len..].trim_space()
				}
			}
			if id.len > 0 {
				out << StoreAppImageEntry{
					id:           id
					name:         if name.len > 0 { name } else { id }
					binary_path:  exec_path
					desktop_path: path
					sha256:       digest
				}
			}
		}
	}
	out.sort(a.id < b.id)
	return out
}

// detect_installed_snapshot probes native, Flatpak, AppImage, and WebApp state.
pub fn detect_installed_snapshot() StoreInstalledSnapshot {
	return StoreInstalledSnapshot{
		pacman_pkgs: detect_installed_pacman()
		flatpak_ids: detect_installed_flatpak()
		appimages:   store_appimage_list_entries()
		webapps:     webapp_list()
	}
}

pub fn app_install_status(app StoreApp, snap StoreInstalledSnapshot) (bool, string) {
	for s in app.sources {
		match s.backend {
			'arch_native', 'vendor_repo', 'aur' {
				if s.package_id in snap.pacman_pkgs {
					return true, s.backend
				}
			}
			'flatpak' {
				if s.package_id in snap.flatpak_ids {
					return true, 'flatpak'
				}
			}
			'appimage' {
				for ai in snap.appimages {
					if ai.id == app.id || ai.id == s.package_id {
						return true, 'appimage'
					}
				}
			}
			'webapp' {
				for wa in snap.webapps {
					if wa.id == app.id {
						return true, 'webapp'
					}
				}
			}
			else {}
		}
	}
	return false, ''
}

pub fn store_sources_result() CommandResult {
	pacman := resolve_pacman_bin()
	flatpak := resolve_flatpak_bin()
	aur := resolve_aur_helper_bin()
	fuse := resolve_fusermount_bin()
	caps := [
		StoreSourceCapability{
			backend:     'arch_native'
			enabled:     true
			available:   pacman.len > 0
			binary:      pacman
			scope:       'system'
			sandboxed:   false
			description: 'Official Arch Linux [core]/[extra]/[multilib] packages via pkexec pacman'
			reason:      if pacman.len > 0 { 'pacman available' } else { 'pacman binary not found' }
		},
		StoreSourceCapability{
			backend:     'flatpak'
			enabled:     true
			available:   flatpak.len > 0
			binary:      flatpak
			scope:       'user'
			sandboxed:   true
			description: 'Sandboxed desktop applications via Flathub (user-scope default)'
			reason:      if flatpak.len > 0 {
				'flatpak available'
			} else {
				'flatpak binary not found'
			}
		},
		StoreSourceCapability{
			backend:     'appimage'
			enabled:     true
			available:   fuse.len > 0
			binary:      fuse
			scope:       'user'
			sandboxed:   false
			description: 'User-space AppImages under \$XDG_DATA_HOME/hornero/appimages with SHA-256 verification'
			reason:      if fuse.len > 0 {
				'FUSE runtime available'
			} else {
				'fuse2/fusermount runtime not detected'
			}
		},
		StoreSourceCapability{
			backend:     'webapp'
			enabled:     true
			available:   true
			binary:      'horneroctl webapp'
			scope:       'user'
			sandboxed:   true
			description: 'Isolated browser WebApps managed via XDG desktop entries'
			reason:      'built-in via webapp.v'
		},
		StoreSourceCapability{
			backend:     'vendor_repo'
			enabled:     true
			available:   pacman.len > 0
			binary:      pacman
			scope:       'system'
			sandboxed:   false
			description: 'Signed vendor-hosted Arch repositories with explicit GPG trust verification'
			reason:      if pacman.len > 0 {
				'pacman available for vendor repos'
			} else {
				'pacman binary not found'
			}
		},
		StoreSourceCapability{
			backend:     'aur'
			enabled:     true
			available:   aur.len > 0
			binary:      aur
			scope:       'system'
			sandboxed:   false
			description: 'Community AUR packages (opt-in --allow-aur, never run as root)'
			reason:      if aur.len > 0 {
				'AUR helper available: ${aur}'
			} else {
				'no AUR helper (yay/paru) installed'
			}
		},
		StoreSourceCapability{
			backend:     'snap'
			enabled:     false
			available:   false
			binary:      ''
			scope:       'system'
			sandboxed:   true
			description: 'Canonical Snap Store backend'
			reason:      'Disabled by design on Arch/HorneroOS; see ADR'
		},
	]
	mut lines := ['Store source backends:']
	for c in caps {
		state := if !c.enabled {
			'disabled'
		} else if c.available {
			'ready'
		} else {
			'unavailable'
		}
		lines << '  ${c.backend:-12s}  ${state:-12s}  (${c.scope}) — ${c.reason}'
	}
	return ok_result('store sources', lines.join('\n'), {
		'count':   caps.len.str()
		'sources': json2.encode(caps, escape_unicode: true)
	})
}

pub fn store_appimage_list_result() CommandResult {
	entries := store_appimage_list_entries()
	gearlever := resolve_gearlever_bin()
	snap := detect_installed_snapshot()
	gearlever_flatpak := 'it.mijorus.gearlever' in snap.flatpak_ids
	gearlever_available := gearlever.len > 0 || gearlever_flatpak
	mut lines := []string{}
	for e in entries {
		lines << '${e.id}\t${e.name}\t${e.binary_path}\tsha256:${e.sha256}'
	}
	if entries.len == 0 {
		lines << 'No Hornero-managed AppImages installed (${resolve_store_appimages_dir()}).'
	}
	lines << 'Gear Lever detected: ${gearlever_available}'
	return ok_result('store appimage list', lines.join('\n'), {
		'count':               entries.len.str()
		'dir':                 resolve_store_appimages_dir()
		'gearlever_available': gearlever_available.str()
		'appimages':           json2.encode(entries, escape_unicode: true)
	})
}

pub fn store_appimage_import_result(src_path string, id string, name string, icon string, expected_sha256 string, dry_run bool, yes bool) CommandResult {
	cmd := 'store appimage import'
	if !yes && !dry_run {
		return fail_result(cmd, 'refusing to import AppImage without --yes (preview with --dry-run).\nExample: horneroctl store appimage import ./MyApp.AppImage --id my-app --dry-run')
	}
	safe_id := validate_app_id(id) or {
		return fail_result(cmd, err.msg())
	}
	src := src_path.trim_space()
	if src.len == 0 || src.contains('..') || src.contains('\0') {
		return fail_result(cmd, 'invalid AppImage source path (path traversal is forbidden)')
	}
	if os.is_link(src) {
		return fail_result(cmd, 'refusing symlink AppImage source: ${src}')
	}
	if !os.is_file(src) {
		return fail_result(cmd, 'AppImage file not found: ${src}')
	}
	validate_desktop_field('name', name) or { return fail_result(cmd, err.msg()) }
	validate_desktop_field('icon', icon) or { return fail_result(cmd, err.msg()) }
	if expected_sha256.len > 0 {
		matched := verify_file_sha256(src, expected_sha256) or {
			return fail_result(cmd, err.msg())
		}
		if !matched {
			return fail_result(cmd, 'SHA-256 verification failed for ${src}')
		}
	}
	digest := sha256_file_hex(src) or {
		return fail_result(cmd, 'cannot hash ${src}: ${err.msg()}')
	}
	dest_dir := resolve_store_appimages_dir()
	dest_bin := os.join_path(dest_dir, '${safe_id}.AppImage')
	desktop_path := appimage_desktop_path(safe_id) or {
		return fail_result(cmd, err.msg())
	}
	display_name := if name.trim_space().len > 0 { name.trim_space() } else { safe_id }
	if dry_run {
		return ok_result(cmd, 'Dry run: would import ${src} -> ${dest_bin} (sha256:${digest}) and write ${desktop_path}.',
			{
				'dry_run':      'true'
				'id':           safe_id
				'binary_path':  dest_bin
				'desktop_path': desktop_path
				'sha256':       digest
			})
	}
	os.mkdir_all(dest_dir) or { return fail_result(cmd, 'cannot create ${dest_dir}: ${err.msg()}') }
	os.mkdir_all(applications_dir()) or { return fail_result(cmd, 'cannot create applications dir: ${err.msg()}') }
	os.cp(src, dest_bin) or { return fail_result(cmd, 'cannot copy AppImage: ${err.msg()}') }
	os.chmod(dest_bin, 0o755) or { return fail_result(cmd, 'cannot chmod ${dest_bin}: ${err.msg()}') }

	mut sb := strings.new_builder(256)
	sb.write_string('[Desktop Entry]\n')
	sb.write_string('Version=1.0\n')
	sb.write_string('Type=Application\n')
	sb.write_string('Name=${display_name}\n')
	sb.write_string('Exec=${dest_bin}\n')
	if icon.trim_space().len > 0 {
		sb.write_string('Icon=${icon.trim_space()}\n')
	}
	sb.write_string('Terminal=false\n')
	sb.write_string('Categories=Utility;\n')
	sb.write_string('StartupNotify=true\n')
	sb.write_string('X-Hornero-Kind=appimage\n')
	sb.write_string('X-Hornero-Id=${safe_id}\n')
	sb.write_string('X-Hornero-Sha256=${digest}\n')
	write_file_atomic(desktop_path, sb.str()) or {
		return fail_result(cmd, 'cannot write desktop file ${desktop_path}: ${err.msg()}')
	}
	record_store_audit('appimage-import', safe_id, 'appimage', true, dest_bin)
	return ok_result(cmd, 'Imported AppImage "${display_name}" -> ${dest_bin} (sha256:${digest}).', {
		'id':           safe_id
		'name':         display_name
		'binary_path':  dest_bin
		'desktop_path': desktop_path
		'sha256':       digest
	})
}

pub fn store_appimage_remove_result(id string, dry_run bool, yes bool) CommandResult {
	cmd := 'store appimage remove'
	if !yes && !dry_run {
		return fail_result(cmd, 'refusing to remove AppImage without --yes (preview with --dry-run).\nExample: horneroctl store appimage remove ${id} --dry-run')
	}
	safe_id := validate_app_id(id) or { return fail_result(cmd, err.msg()) }
	desktop_path := appimage_desktop_path(safe_id) or { return fail_result(cmd, err.msg()) }
	bin_path := os.join_path(resolve_store_appimages_dir(), '${safe_id}.AppImage')
	if !os.exists(desktop_path) && !os.exists(bin_path) {
		return fail_result(cmd, 'managed AppImage not found: ${safe_id}')
	}
	if dry_run {
		return ok_result(cmd, 'Dry run: would remove ${bin_path} and ${desktop_path} (user config/data preserved).',
			{
				'dry_run':      'true'
				'id':           safe_id
				'binary_path':  bin_path
				'desktop_path': desktop_path
			})
	}
	if os.exists(bin_path) {
		os.rm(bin_path) or { return fail_result(cmd, 'cannot remove ${bin_path}: ${err.msg()}') }
	}
	if os.exists(desktop_path) {
		os.rm(desktop_path) or { return fail_result(cmd, 'cannot remove ${desktop_path}: ${err.msg()}') }
	}
	record_store_audit('appimage-remove', safe_id, 'appimage', true, bin_path)
	return ok_result(cmd, 'Removed managed AppImage "${safe_id}" (user config/data preserved).', {
		'id':           safe_id
		'binary_path':  bin_path
		'desktop_path': desktop_path
	})
}

// store_appimage_install downloads an HTTPS AppImage (never as root) and
// delegates to store_appimage_import_result for optional SHA-256 verification
// and .desktop registration, or imports a local file directly.
pub fn store_appimage_install(id string, name string, url_or_path string, icon string, expected_sha256 string, dry_run bool, yes bool) CommandResult {
	cmd := 'store install'
	if os.geteuid() == 0 {
		return fail_result(cmd, 'refusing to install user-space AppImage as root')
	}
	if !yes && !dry_run {
		return fail_result(cmd, 'refusing to install AppImage without --yes (preview with --dry-run)')
	}
	src := url_or_path.trim_space()
	if !src.starts_with('https://') {
		return store_appimage_import_result(src, id, name, icon, expected_sha256, dry_run, yes)
	}
	safe_id := validate_app_id(id) or { return fail_result(cmd, err.msg()) }
	curl := resolve_curl_bin()
	if curl.len == 0 && !dry_run {
		return fail_result(cmd, 'curl binary not found; cannot download AppImage')
	}
	stage_path := os.join_path(os.temp_dir(), 'hornero-appimage-${safe_id}-${os.getpid()}.AppImage')
	rep := run_exec(ExecSpec{
		prog:        if curl.len > 0 { curl } else { 'curl' }
		args:        ['-fsSL', '-o', stage_path, src]
		dry_run:     dry_run
		timeout_sec: 300
	})
	if dry_run {
		return ok_result(cmd, 'Dry run: would run ${rep.command_line} and import as ${safe_id}.AppImage',
			{
				'dry_run':      'true'
				'id':           safe_id
				'backend':      'appimage'
				'command_line': rep.command_line
			})
	}
	defer {
		os.rm(stage_path) or {}
	}
	if !rep.ok {
		return fail_result(cmd, 'AppImage download failed: ${rep.output}')
	}
	return store_appimage_import_result(stage_path, safe_id, name, icon, expected_sha256,
		false, true)
}

pub fn store_permissions_result(id string, open_flatseal bool, dry_run bool) CommandResult {
	cmd := 'store permissions'
	if id.trim_space().len == 0 {
		return fail_result(cmd, 'missing app or flatpak id.\nExample: horneroctl store permissions org.mozilla.firefox')
	}
	mut flatpak_id := id.trim_space()
	if cat := load_app_catalog() {
		if app := find_catalog_app(cat, id) {
			for s in app.sources {
				if s.backend == 'flatpak' {
					flatpak_id = s.package_id
					break
				}
			}
		}
	}
	if open_flatseal {
		flatseal := resolve_flatseal_bin()
		fp := resolve_flatpak_bin()
		prog := if flatseal.len > 0 { flatseal } else { fp }
		args := if flatseal.len > 0 { []string{} } else { ['run', 'com.github.tchx84.Flatseal'] }
		if prog.len == 0 && !dry_run {
			return fail_result(cmd, 'Flatseal and flatpak are not installed; install com.github.tchx84.Flatseal via `horneroctl store install flatseal --yes`')
		}
		line := command_line(if prog.len > 0 { prog } else { 'flatseal' }, args)
		if dry_run {
			return ok_result(cmd, 'Dry run: would launch Flatseal (${line}).', {
				'dry_run':      'true'
				'flatpak_id':   flatpak_id
				'command_line': line
			})
		}
		mut proc := os.new_process(prog)
		proc.set_args(args)
		proc.run()
		return ok_result(cmd, 'Launched Flatseal (${line}).', {
			'flatpak_id':   flatpak_id
			'command_line': line
		})
	}
	fp := resolve_flatpak_bin()
	if fp.len == 0 && !dry_run {
		return fail_result(cmd, 'flatpak binary not found')
	}
	rep := run_exec(ExecSpec{
		prog:        if fp.len > 0 { fp } else { 'flatpak' }
		args:        ['info', '--show-permissions', flatpak_id]
		dry_run:     dry_run
		timeout_sec: 10
	})
	if dry_run {
		return ok_result(cmd, 'Dry run: would run ${rep.command_line}', {
			'dry_run':      'true'
			'flatpak_id':   flatpak_id
			'command_line': rep.command_line
		})
	}
	if !rep.ok {
		return fail_result(cmd, 'flatpak info failed for ${flatpak_id}: ${rep.output}')
	}
	return ok_result(cmd, rep.output, {
		'flatpak_id':   flatpak_id
		'command_line': rep.command_line
		'permissions':  rep.output
	})
}

pub struct StoreDoctorCheck {
pub:
	name   string
	status string // pass | warn | fail
	detail string
}

fn store_portal_installed(name string) bool {
	if find_on_path(name).len > 0 {
		return true
	}
	root := os.getenv_opt('HORNERO_DEPENDENCY_ROOT') or { '/usr' }
	return os.is_file(os.join_path(root, 'lib', name))
}

pub fn store_doctor_result() CommandResult {
	mut checks := []StoreDoctorCheck{}
	mut fail_count := 0
	mut warn_count := 0

	if cat := load_app_catalog() {
		checks << StoreDoctorCheck{
			name:   'catalog'
			status: 'pass'
			detail: 'loaded ${cat.apps.len} verified apps (schemaVersion=${cat.schema_version}, verifiedAt=${cat.verified_at})'
		}
	} else {
		checks << StoreDoctorCheck{
			name:   'catalog'
			status: 'fail'
			detail: err.msg()
		}
		fail_count++
	}

	lock_path := resolve_pacman_lock_path()
	if os.exists(lock_path) {
		checks << StoreDoctorCheck{
			name:   'pacman-lock'
			status: 'fail'
			detail: 'pacman lock held at ${lock_path}'
		}
		fail_count++
	} else {
		checks << StoreDoctorCheck{
			name:   'pacman-lock'
			status: 'pass'
			detail: 'no active pacman lock (${lock_path})'
		}
	}

	fp := resolve_flatpak_bin()
	if fp.len > 0 {
		checks << StoreDoctorCheck{'flatpak', 'pass', fp}
		rem := run_exec(ExecSpec{
			prog:        fp
			args:        ['remotes', '--columns=name']
			timeout_sec: 5
		})
		if rem.ok && rem.output.contains('flathub') {
			checks << StoreDoctorCheck{'flathub-remote', 'pass', 'flathub remote configured'}
		} else {
			checks << StoreDoctorCheck{'flathub-remote', 'warn', 'flathub remote not configured (run: flatpak remote-add --if-not-exists --user flathub https://flathub.org/repo/flathub.flatpakrepo)'}
			warn_count++
		}
	} else {
		checks << StoreDoctorCheck{'flatpak', 'warn', 'flatpak not found on PATH'}
		warn_count++
	}

	appstream := resolve_appstreamcli_bin()
	if appstream.len > 0 {
		checks << StoreDoctorCheck{'appstream', 'pass', appstream}
	} else {
		checks << StoreDoctorCheck{'appstream', 'warn', 'appstreamcli not found on PATH'}
		warn_count++
	}

	fuse := resolve_fusermount_bin()
	fuse_lib := os.is_file('/usr/lib/libfuse.so.2')
	if fuse.len > 0 || fuse_lib {
		checks << StoreDoctorCheck{'fuse2', 'pass', if fuse.len > 0 {
			fuse
		} else {
			'/usr/lib/libfuse.so.2'
		}}
	} else {
		checks << StoreDoctorCheck{'fuse2', 'warn', 'fuse2 / fusermount runtime not detected'}
		warn_count++
	}

	pkexec := resolve_pkexec_bin()
	if pkexec.len > 0 {
		checks << StoreDoctorCheck{'pkexec', 'pass', pkexec}
	} else {
		checks << StoreDoctorCheck{'pkexec', 'warn', 'pkexec (polkit) not found'}
		warn_count++
	}

	gearlever := resolve_gearlever_bin()
	if gearlever.len > 0 {
		checks << StoreDoctorCheck{'gearlever', 'pass', gearlever}
	} else {
		checks << StoreDoctorCheck{'gearlever', 'warn', 'optional Gear Lever not installed on PATH'}
		warn_count++
	}

	flatseal := resolve_flatseal_bin()
	if flatseal.len > 0 {
		checks << StoreDoctorCheck{'flatseal', 'pass', flatseal}
	} else {
		checks << StoreDoctorCheck{'flatseal', 'warn', 'optional Flatseal not installed on PATH'}
		warn_count++
	}

	portal := store_portal_installed('xdg-desktop-portal')
	portal_gtk := store_portal_installed('xdg-desktop-portal-gtk')
	if portal && portal_gtk {
		checks << StoreDoctorCheck{'xdg-portals', 'pass', 'xdg-desktop-portal and xdg-desktop-portal-gtk present'}
	} else {
		checks << StoreDoctorCheck{'xdg-portals', 'warn', 'portal=${portal}, portal-gtk=${portal_gtk}'}
		warn_count++
	}

	mut lines := ['Store Doctor:']
	for c in checks {
		lines << '  [${c.status.to_upper()}] ${c.name}: ${c.detail}'
	}
	data := {
		'ok':       (fail_count == 0).str()
		'failures': fail_count.str()
		'warnings': warn_count.str()
		'checks':   json2.encode(checks, escape_unicode: true)
	}
	if fail_count > 0 {
		return fail_result_data('store doctor', lines.join('\n'), data)
	}
	return ok_result('store doctor', lines.join('\n'), data)
}
