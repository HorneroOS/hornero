module hornero_core

import os
import x.json2

// Hornero Playground & Presenter domain module (HorneroOS/playground#1).
//
// Pure domain logic: canonical metadata for the 7 display profiles, 6 image
// profiles, and 10 demo studio / YouTube scenarios; strictly read-only host
// capability diagnostics (`playground_doctor`); safe XDG presenter state
// inspection (`presenter_status`); and deterministic command planning
// (`presenter_plan`) with dry-run, `--yes` confirmation gates, and paid
// cloud provider refusal.

pub const presenter_default_resolution = '1920x1080'
pub const presenter_default_fps = 60
pub const playground_default_provider = 'local'
pub const playground_default_image_profile = 'standard-vm'
pub const playground_cloud_docs_ref = 'https://github.com/HorneroOS/playground/tree/main/infra/terraform (local docs: infra/terraform/hetzner/README.md)'

pub struct DisplayProfile {
pub:
	id          string
	width       int
	height      int
	aspect      string
	scale       string
	fps         int
	is_default  bool
	description string
}

pub struct ResolvedResolution {
pub:
	profile_id string
	width      int
	height     int
	label      string
	aspect     string
}

pub struct ImageProfile {
pub:
	id          string
	name        string
	ram_mb      int
	vcpus       int
	disk_gb     int
	gpu         string
	description string
}

pub struct DemoScenario {
pub:
	id                 string
	order              int
	title              string
	summary            string
	default_resolution string
	default_fps        int
	bundle_dir         string
}

pub struct PlaygroundHostProbe {
pub:
	kvm_available     bool
	kvm_path          string
	render_nodes      []string
	qemu_bin          string
	qemu_img_bin      string
	ffmpeg_bin        string
	ffprobe_bin       string
	kdenlive_bin      string
	systemd_run_bin   string
	ovmf_code         string
	ovmf_vars         string
	ram_total_mib     i64
	ram_available_mib i64
	cpu_count         int
}

pub struct PresenterState {
pub:
	active         bool
	prior_dnd      bool
	scenario       string
	resolution     string
	fps            int
	recording      bool
	recording_file string
	present        bool
	state_file     string
}

pub struct PlaygroundUpOptions {
pub:
	provider              string = playground_default_provider
	profile               string = playground_default_image_profile
	resolution            string = presenter_default_resolution
	image                 string
	iso                   string
	ram                   string = '4G'
	cpus                  int    = 4
	confirm_paid_provider bool
	dry_run               bool
	yes                   bool
}

pub struct PresenterOptions {
pub:
	action     string
	resolution string = presenter_default_resolution
	scenario   string
	fps        int = presenter_default_fps
	output     string
	dry_run    bool
	yes        bool
}

pub struct PresenterPlan {
pub:
	action        string
	resolution    ResolvedResolution
	fps           int
	scenario      string
	bundle_root   string
	bundle_layout string
	bundle_paths  []string
	commands      []string
	command_line  string
	delegated_to  string
}

// playground_display_profiles returns the 7 canonical Display Profiles.
pub fn playground_display_profiles() []DisplayProfile {
	return [
		DisplayProfile{
			id:          'hd'
			width:       1280
			height:      720
			aspect:      '16:9'
			scale:       '1.0'
			fps:         60
			is_default:  false
			description: 'HD 720p (16:9) — lightweight capture and constrained VMs'
		},
		DisplayProfile{
			id:          'fhd'
			width:       1920
			height:      1080
			aspect:      '16:9'
			scale:       '1.0'
			fps:         60
			is_default:  true
			description: 'Full HD 1080p (16:9, default) — crisp 1x desktop and YouTube standard'
		},
		DisplayProfile{
			id:          'qhd'
			width:       2560
			height:      1440
			aspect:      '16:9'
			scale:       '1.0'
			fps:         60
			is_default:  false
			description: 'QHD 1440p (16:9) — high-density workstation and crisp downsampling'
		},
		DisplayProfile{
			id:          'uhd4k'
			width:       3840
			height:      2160
			aspect:      '16:9'
			scale:       '1.0'
			fps:         60
			is_default:  false
			description: '4K UHD 2160p (16:9) — mastering, showcase UI, and 4K YouTube capture'
		},
		DisplayProfile{
			id:          'ultrawide'
			width:       3440
			height:      1440
			aspect:      '21:9'
			scale:       '1.0'
			fps:         60
			is_default:  false
			description: 'Ultrawide WQHD (21:9) — multi-window tiling and creative studio demos'
		},
		DisplayProfile{
			id:          'vertical'
			width:       1080
			height:      1920
			aspect:      '9:16'
			scale:       '1.0'
			fps:         60
			is_default:  false
			description: 'Vertical 1080x1920 (9:16) — YouTube Shorts, Reels, and mobile walkthroughs'
		},
		DisplayProfile{
			id:          'custom'
			width:       0
			height:      0
			aspect:      'custom'
			scale:       '1.0'
			fps:         60
			is_default:  false
			description: 'Custom WxH resolution (supplied explicitly via --resolution <WxH>)'
		},
	]
}

// playground_image_profiles returns the 6 canonical Image Profiles.
pub fn playground_image_profiles() []ImageProfile {
	return [
		ImageProfile{
			id:          'standard-vm'
			name:        'Standard VM'
			ram_mb:      4096
			vcpus:       4
			disk_gb:     32
			gpu:         'auto'
			description: 'Preinstalled QCOW2 appliance for QEMU/KVM, Quickemu, libvirt, VMware, VirtualBox, and UTM'
		},
		ImageProfile{
			id:          'public-playground'
			name:        'Public Playground'
			ram_mb:      4096
			vcpus:       2
			disk_gb:     32
			gpu:         'virgl'
			description: 'Ephemeral browser streaming image with CoW overlay, 15m TTL, and restricted egress'
		},
		ImageProfile{
			id:          'presenter'
			name:        'Presenter'
			ram_mb:      4096
			vcpus:       4
			disk_gb:     32
			gpu:         'virgl'
			description: 'Live stage and recording overlay with autologin, idle-lock off, and DND IPC'
		},
		ImageProfile{
			id:          'qa'
			name:        'QA Acceptance'
			ram_mb:      4096
			vcpus:       4
			disk_gb:     32
			gpu:         'virgl'
			description: 'Headless QEMU/KVM acceptance profile aligned with HorneroOS/qa q35 + OVMF conventions'
		},
		ImageProfile{
			id:          'screenshot'
			name:        'Screenshot Capture'
			ram_mb:      4096
			vcpus:       4
			disk_gb:     32
			gpu:         'virgl'
			description: 'Deterministic crisp still-frame capture profile with scale 1.0 and clean workspace'
		},
		ImageProfile{
			id:          'video'
			name:        'Video Production'
			ram_mb:      6144
			vcpus:       4
			disk_gb:     40
			gpu:         'virgl'
			description: 'Studio 30/60 FPS capture profile tuned for lossless recording and YouTube bundle export'
		},
	]
}

// playground_scenarios returns the 10 canonical Demo Studio / YouTube Scenarios.
pub fn playground_scenarios() []DemoScenario {
	return [
		DemoScenario{
			id:                 'introducing-horneroos'
			order:              1
			title:              'Introducing HorneroOS'
			summary:            'Flagship overview of HorneroOS, Hyprland/Niri compositors, Hornero Shell, and Signal aesthetics'
			default_resolution: '1920x1080'
			default_fps:        60
			bundle_dir:         'hornero-introducing-horneroos'
		},
		DemoScenario{
			id:                 'installing-and-exploring'
			order:              2
			title:              'Installing and Exploring'
			summary:            'Booting the verified ISO or local VM, guided setup, and first desktop exploration'
			default_resolution: '1920x1080'
			default_fps:        60
			bundle_dir:         'hornero-installing-and-exploring'
		},
		DemoScenario{
			id:                 'first-flight'
			order:              3
			title:              'First Flight Onboarding'
			summary:            'Hornero Welcome first-login tour, keybindings, bar layouts, and quick health verification'
			default_resolution: '1920x1080'
			default_fps:        60
			bundle_dir:         'hornero-first-flight'
		},
		DemoScenario{
			id:                 'personalize-desktop'
			order:              4
			title:              'Personalize Your Desktop'
			summary:            'Signal Day/Night/Contrast themes, Chromatic adaptive colors, wallpapers, and night mode'
			default_resolution: '1920x1080'
			default_fps:        60
			bundle_dir:         'hornero-personalize-desktop'
		},
		DemoScenario{
			id:                 'hornero-apps'
			order:              5
			title:              'Hornero Verified Apps Store'
			summary:            'Unified store search, Flatpak/Arch/AppImage/WebApp policy gates, and curated profiles'
			default_resolution: '1920x1080'
			default_fps:        60
			bundle_dir:         'hornero-hornero-apps'
		},
		DemoScenario{
			id:                 'ai-native-workstation'
			order:              6
			title:              'AI-Native Workstation'
			summary:            'Agent registry, bubblewrap sandboxing, workspace projection, and Dev Pulse GitHub workflows'
			default_resolution: '1920x1080'
			default_fps:        60
			bundle_dir:         'hornero-ai-native-workstation'
		},
		DemoScenario{
			id:                 'meet-companion'
			order:              7
			title:              'Meet the Companion'
			summary:            'Opt-in Hermes assistant gateway, ABAC policy presets, typed broker tools, and audit logs'
			default_resolution: '1920x1080'
			default_fps:        60
			bundle_dir:         'hornero-meet-companion'
		},
		DemoScenario{
			id:                 'creative-studio'
			order:              8
			title:              'Creative Studio'
			summary:            'Low-latency PipeWire audio routing kits, studio render jobs, and 5-domain workspace profiles'
			default_resolution: '1920x1080'
			default_fps:        60
			bundle_dir:         'hornero-creative-studio'
		},
		DemoScenario{
			id:                 'extensions-marketplace'
			order:              9
			title:              'Extensions & Shell Plugins'
			summary:            'Community Quickshell plugin catalog, cryptographic trust verification, and live reload'
			default_resolution: '1920x1080'
			default_fps:        60
			bundle_dir:         'hornero-extensions-marketplace'
		},
		DemoScenario{
			id:                 'release-highlights'
			order:              10
			title:              'Release Highlights'
			summary:            'Preview release changelog walkthrough, performance improvements, and upgrade safety'
			default_resolution: '1920x1080'
			default_fps:        60
			bundle_dir:         'hornero-release-highlights'
		},
	]
}

pub fn playground_find_display_profile(id string) ?DisplayProfile {
	norm := id.trim_space().to_lower()
	for p in playground_display_profiles() {
		if p.id == norm {
			return p
		}
	}
	return none
}

pub fn playground_find_image_profile(id string) ?ImageProfile {
	norm := id.trim_space().to_lower()
	for p in playground_image_profiles() {
		if p.id == norm {
			return p
		}
	}
	return none
}

pub fn playground_find_scenario(id string) ?DemoScenario {
	norm := id.trim_space().to_lower()
	for s in playground_scenarios() {
		if s.id == norm {
			return s
		}
	}
	return none
}

fn is_digits_only(s string) bool {
	if s.len == 0 {
		return false
	}
	for c in s.bytes() {
		if c < `0` || c > `9` {
			return false
		}
	}
	return true
}

// playground_resolve_resolution validates a display profile ID (hd, fhd, qhd,
// uhd4k, ultrawide, vertical) or explicit WxH string (e.g. 1920x1080,
// 3840x2160, 1280x800). Passing bare "custom" without WxH fails cleanly.
pub fn playground_resolve_resolution(spec string) !ResolvedResolution {
	raw := spec.trim_space().to_lower()
	if raw.len == 0 {
		return error('resolution must not be empty (expected profile id or WxH such as 1920x1080)')
	}
	if raw == 'custom' {
		return error('custom display profile requires explicit dimensions (e.g. --resolution 1280x800)')
	}
	if prof := playground_find_display_profile(raw) {
		return ResolvedResolution{
			profile_id: prof.id
			width:      prof.width
			height:     prof.height
			label:      '${prof.width}x${prof.height}'
			aspect:     prof.aspect
		}
	}
	parts := raw.split('x')
	if parts.len != 2 || !is_digits_only(parts[0]) || !is_digits_only(parts[1]) {
		return error('invalid resolution "${spec}" (expected hd|fhd|qhd|uhd4k|ultrawide|vertical or WxH such as 1920x1080)')
	}
	w := parts[0].int()
	h := parts[1].int()
	if w < 320 || w > 7680 || h < 240 || h > 4320 {
		return error('resolution ${w}x${h} out of supported range (width 320..7680, height 240..4320)')
	}
	for prof in playground_display_profiles() {
		if prof.id != 'custom' && prof.width == w && prof.height == h {
			return ResolvedResolution{
				profile_id: prof.id
				width:      w
				height:     h
				label:      '${w}x${h}'
				aspect:     prof.aspect
			}
		}
	}
	return ResolvedResolution{
		profile_id: 'custom'
		width:      w
		height:     h
		label:      '${w}x${h}'
		aspect:     'custom'
	}
}

fn parse_meminfo_field_mib(content string, key string) i64 {
	for line in content.split_into_lines() {
		if line.starts_with(key) {
			fields := line.fields()
			if fields.len >= 2 {
				return fields[1].i64() / 1024
			}
		}
	}
	return 0
}

fn parse_cpuinfo_count(content string) int {
	mut count := 0
	for line in content.split_into_lines() {
		trimmed := line.trim_space()
		if trimmed.starts_with('processor') && trimmed.contains(':') {
			count++
		}
	}
	return count
}

fn first_existing_file(override_env string, candidates []string) string {
	if override_env.len > 0 {
		env := os.getenv(override_env)
		if env.len > 0 {
			return if os.is_file(env) { env } else { '' }
		}
	}
	for path in candidates {
		if os.is_file(path) {
			return path
		}
	}
	return ''
}

// playground_probe_host collects read-only host virtualization and presenter
// capabilities with zero external subprocess invocations.
pub fn playground_probe_host() PlaygroundHostProbe {
	kvm_path := '/dev/kvm'
	kvm_ok := os.exists(kvm_path) && os.is_readable(kvm_path)

	mut render_nodes := []string{}
	if os.is_dir('/dev/dri') {
		entries := os.ls('/dev/dri') or { []string{} }
		for entry in entries {
			if entry.starts_with('renderD') {
				render_nodes << os.join_path('/dev/dri', entry)
			}
		}
		render_nodes.sort()
	}

	ovmf_code := first_existing_file('HORNERO_OVMF_CODE', [
		'/usr/share/OVMF/x64/OVMF_CODE.4m.fd',
		'/usr/share/edk2/x64/OVMF_CODE.4m.fd',
		'/usr/share/edk2-ovmf/x64/OVMF_CODE.4m.fd',
		'/usr/share/OVMF/OVMF_CODE.fd',
	])
	ovmf_vars := first_existing_file('HORNERO_OVMF_VARS', [
		'/usr/share/OVMF/x64/OVMF_VARS.4m.fd',
		'/usr/share/edk2/x64/OVMF_VARS.4m.fd',
		'/usr/share/edk2-ovmf/x64/OVMF_VARS.4m.fd',
		'/usr/share/OVMF/OVMF_VARS.fd',
	])

	meminfo := os.read_file('/proc/meminfo') or { '' }
	cpuinfo := os.read_file('/proc/cpuinfo') or { '' }

	return PlaygroundHostProbe{
		kvm_available:     kvm_ok
		kvm_path:          if kvm_ok { kvm_path } else { '' }
		render_nodes:      render_nodes
		qemu_bin:          find_on_path('qemu-system-x86_64')
		qemu_img_bin:      find_on_path('qemu-img')
		ffmpeg_bin:        find_on_path('ffmpeg')
		ffprobe_bin:       find_on_path('ffprobe')
		kdenlive_bin:      find_on_path('kdenlive')
		systemd_run_bin:   find_on_path('systemd-run')
		ovmf_code:         ovmf_code
		ovmf_vars:         ovmf_vars
		ram_total_mib:     parse_meminfo_field_mib(meminfo, 'MemTotal:')
		ram_available_mib: parse_meminfo_field_mib(meminfo, 'MemAvailable:')
		cpu_count:         parse_cpuinfo_count(cpuinfo)
	}
}

pub fn playground_doctor_checks(probe PlaygroundHostProbe) []DoctorCheck {
	mut checks := []DoctorCheck{}
	checks << DoctorCheck{
		name:   'kvm'
		ok:     probe.kvm_available
		detail: if probe.kvm_available {
			'${probe.kvm_path} accessible for hardware KVM acceleration'
		} else {
			'/dev/kvm unavailable — hardware KVM disabled; TCG fallback is slow'
		}
	}
	checks << DoctorCheck{
		name:   'virgl-render-node'
		ok:     true
		warn:   probe.render_nodes.len == 0
		detail: if probe.render_nodes.len > 0 {
			'DRM render node(s): ${probe.render_nodes.join(', ')}'
		} else {
			'no /dev/dri/renderD* node found — optional; VirGL unavailable, falling back to virtio/software'
		}
	}
	checks << DoctorCheck{
		name:   'qemu-system-x86_64'
		ok:     probe.qemu_bin.len > 0
		detail: if probe.qemu_bin.len > 0 {
			probe.qemu_bin
		} else {
			'qemu-system-x86_64 not found on PATH'
		}
	}
	checks << DoctorCheck{
		name:   'qemu-img'
		ok:     probe.qemu_img_bin.len > 0
		detail: if probe.qemu_img_bin.len > 0 {
			probe.qemu_img_bin
		} else {
			'qemu-img not found on PATH'
		}
	}
	ovmf_ok := probe.ovmf_code.len > 0 && probe.ovmf_vars.len > 0
	checks << DoctorCheck{
		name:   'ovmf-firmware'
		ok:     ovmf_ok
		detail: if ovmf_ok {
			'code=${probe.ovmf_code}, vars=${probe.ovmf_vars}'
		} else {
			'OVMF 4M split flash firmware not found under /usr/share/{OVMF,edk2}/x64'
		}
	}
	checks << DoctorCheck{
		name:   'systemd-run'
		ok:     true
		warn:   probe.systemd_run_bin.len == 0
		detail: if probe.systemd_run_bin.len > 0 {
			'${probe.systemd_run_bin} (cgroup memory cap supported)'
		} else {
			'systemd-run not found on PATH — optional cgroup memory cap unavailable'
		}
	}
	checks << DoctorCheck{
		name:   'ffmpeg'
		ok:     true
		warn:   probe.ffmpeg_bin.len == 0
		detail: if probe.ffmpeg_bin.len > 0 {
			probe.ffmpeg_bin
		} else {
			'ffmpeg not found on PATH — optional, needed for presenter recording/export'
		}
	}
	checks << DoctorCheck{
		name:   'ffprobe'
		ok:     true
		warn:   probe.ffprobe_bin.len == 0
		detail: if probe.ffprobe_bin.len > 0 {
			probe.ffprobe_bin
		} else {
			'ffprobe not found on PATH — optional, needed for media metadata inspection'
		}
	}
	checks << DoctorCheck{
		name:   'kdenlive'
		ok:     true
		warn:   probe.kdenlive_bin.len == 0
		detail: if probe.kdenlive_bin.len > 0 {
			probe.kdenlive_bin
		} else {
			'kdenlive not found on PATH — optional, needed for editing exported YouTube bundles'
		}
	}
	res_ok := probe.ram_total_mib >= 4096 && probe.cpu_count >= 2
	checks << DoctorCheck{
		name:   'host-resources'
		ok:     res_ok
		detail: 'CPU=${probe.cpu_count} thread(s), RAM total=${probe.ram_total_mib} MiB, available=${probe.ram_available_mib} MiB (4096 MiB + 2 CPUs minimum recommended)'
	}
	return checks
}

pub fn playground_doctor_result(checks []DoctorCheck, probe PlaygroundHostProbe) CommandResult {
	mut lines := []string{}
	mut failed := 0
	mut warnings := 0
	mut data := map[string]string{}
	for c in checks {
		mark := if !c.ok {
			'FAIL'
		} else if c.warn {
			'warn'
		} else {
			'ok'
		}
		if !c.ok {
			failed++
		} else if c.warn {
			warnings++
		}
		lines << '${mark}  ${c.name}: ${redact_secrets(c.detail)}'
		data[c.name] = if !c.ok {
			'fail'
		} else if c.warn {
			'warn'
		} else {
			'ok'
		}
	}
	data['kvm_available'] = probe.kvm_available.str()
	data['render_nodes'] = probe.render_nodes.join(',')
	data['ovmf_code'] = probe.ovmf_code
	data['ovmf_vars'] = probe.ovmf_vars
	data['ram_total_mib'] = probe.ram_total_mib.str()
	data['ram_available_mib'] = probe.ram_available_mib.str()
	data['cpu_count'] = probe.cpu_count.str()
	data['failed'] = failed.str()
	data['warnings'] = warnings.str()
	data['passed'] = (checks.len - failed).str()
	if failed == 0 {
		lines << 'playground doctor: ${checks.len} checks passed (${warnings} warning(s))'
	} else {
		lines << 'playground doctor: ${failed}/${checks.len} checks failed (${warnings} warning(s))'
	}
	return CommandResult{
		command: 'playground doctor'
		ok:      failed == 0
		message: lines.join('\n')
		data:    data
	}
}

// playground_doctor runs strictly read-only host capability checks with zero
// external calls.
pub fn playground_doctor() CommandResult {
	probe := playground_probe_host()
	checks := playground_doctor_checks(probe)
	return playground_doctor_result(checks, probe)
}

pub fn playground_profiles_result(kind string) CommandResult {
	norm := if kind.len == 0 { 'all' } else { kind.trim_space().to_lower() }
	if norm !in ['all', 'display', 'image'] {
		return fail_result('playground profiles', 'unknown profile kind "${kind}" (expected all|display|image)')
	}
	display_list := playground_display_profiles()
	image_list := playground_image_profiles()
	mut lines := []string{}
	if norm in ['all', 'display'] {
		lines << 'Display profiles (${display_list.len}):'
		for p in display_list {
			dim := if p.width > 0 { '${p.width}x${p.height}' } else { 'WxH' }
			def_tag := if p.is_default { ' [default]' } else { '' }
			lines << '  ${p.id:-10s}  ${dim:-10s}  ${p.aspect:-6s}  ${p.fps}fps${def_tag}  ${p.description}'
		}
	}
	if norm in ['all', 'image'] {
		lines << 'Image profiles (${image_list.len}):'
		for p in image_list {
			lines << '  ${p.id:-18s}  ${p.ram_mb}MiB  ${p.vcpus}c  ${p.disk_gb}GiB  gpu=${p.gpu:-6s}  ${p.description}'
		}
	}
	mut data := {
		'kind':                    norm
		'display_count':           display_list.len.str()
		'image_count':             image_list.len.str()
		'default_display_profile': 'fhd'
		'default_resolution':      presenter_default_resolution
		'default_image_profile':   playground_default_image_profile
	}
	if norm in ['all', 'display'] {
		data['display_profiles'] = json2.encode(display_list, escape_unicode: true)
	}
	if norm in ['all', 'image'] {
		data['image_profiles'] = json2.encode(image_list, escape_unicode: true)
	}
	return ok_result('playground profiles', lines.join('\n'), data)
}

pub fn playground_scenarios_result() CommandResult {
	list := playground_scenarios()
	mut lines := ['Demo Studio / YouTube scenarios (${list.len}):']
	for s in list {
		lines << '  ${s.order:2d}. ${s.id:-25s}  ${s.default_resolution}@${s.default_fps}  ${s.title} — ${s.summary}'
	}
	return ok_result('playground scenarios', lines.join('\n'), {
		'count':     list.len.str()
		'scenarios': json2.encode(list, escape_unicode: true)
	})
}

fn strip_trailing_slashes(p string) string {
	mut out := p
	for out.len > 1 && out.ends_with('/') {
		out = out[..out.len - 1]
	}
	return out
}

fn ensure_no_symlink_path(path string, label string) ! {
	clean := strip_trailing_slashes(path)
	if clean.len == 0 {
		return error('${label} path must not be empty')
	}
	if os.is_link(clean) {
		return error('refusing symlinked ${label}: ${clean}')
	}
	parent := strip_trailing_slashes(os.dir(clean))
	if parent.len > 0 && parent != '/' && os.is_link(parent) {
		return error('refusing symlinked ${label} directory: ${parent}')
	}
}

pub fn playground_state_file() string {
	override := os.getenv('HORNERO_PLAYGROUND_STATE_DIR')
	if override.len > 0 {
		return os.join_path(override, 'state.json')
	}
	p := resolve_paths()
	return os.join_path(p.state_dir, 'hornero-playground', 'state.json')
}

pub fn presenter_state_file() string {
	override := os.getenv('HORNERO_PRESENTER_STATE_DIR')
	if override.len > 0 {
		return os.join_path(override, 'state.json')
	}
	p := resolve_paths()
	return os.join_path(p.state_dir, 'hornero-presenter', 'state.json')
}

fn read_json_object_safe(path string, label string) !(map[string]json2.Any, bool) {
	ensure_no_symlink_path(path, label)!
	if !os.is_file(path) {
		return map[string]json2.Any{}, false
	}
	raw := os.read_file(path) or { return error('cannot read ${path}: ${err.msg()}') }
	decoded := json2.decode[json2.Any](raw) or {
		return error('invalid JSON in ${path}: ${err.msg()}')
	}
	if decoded !is map[string]json2.Any {
		return error('invalid ${label} at ${path}: expected JSON object')
	}
	return decoded.as_map(), true
}

fn write_json_object_safe(path string, label string, payload string) ! {
	ensure_no_symlink_path(path, label)!
	dir := os.dir(path)
	os.mkdir_all(dir) or { return error('cannot create ${dir}: ${err.msg()}') }
	ensure_no_symlink_path(path, label)!
	os.chmod(dir, 0o700) or {}
	tmp := os.join_path(dir, '.${os.base(path)}.tmp.${os.getpid()}')
	if os.is_link(tmp) {
		return error('refusing symlinked temp file: ${tmp}')
	}
	os.write_file(tmp, payload) or { return error('cannot write ${tmp}: ${err.msg()}') }
	os.chmod(tmp, 0o600) or {}
	os.mv(tmp, path) or {
		os.rm(tmp) or {}
		return error('cannot replace ${path}: ${err.msg()}')
	}
	os.chmod(path, 0o600) or {}
}

pub fn presenter_status() !PresenterState {
	path := presenter_state_file()
	root, present := read_json_object_safe(path, 'presenter state')!
	if !present {
		return PresenterState{
			active:     false
			prior_dnd:  false
			resolution: presenter_default_resolution
			fps:        presenter_default_fps
			present:    false
			state_file: path
		}
	}
	fps_val := j_int(root, 'fps')
	res_val := j_str(root, 'resolution')
	return PresenterState{
		active:         j_bool(root, 'active')
		prior_dnd:      j_bool(root, 'prior_dnd')
		scenario:       j_str(root, 'scenario')
		resolution:     if res_val.len > 0 { res_val } else { presenter_default_resolution }
		fps:            if fps_val > 0 { fps_val } else { presenter_default_fps }
		recording:      j_bool(root, 'recording')
		recording_file: j_str(root, 'recording_file')
		present:        true
		state_file:     path
	}
}

fn presenter_encode_state(st PresenterState) string {
	enc := fn (v string) string {
		return json2.encode(v, escape_unicode: true)
	}
	lines := [
		'{',
		'  "active": ${st.active},',
		'  "prior_dnd": ${st.prior_dnd},',
		'  "scenario": ${enc(st.scenario)},',
		'  "resolution": ${enc(st.resolution)},',
		'  "fps": ${st.fps},',
		'  "recording": ${st.recording},',
		'  "recording_file": ${enc(st.recording_file)}',
		'}',
	]
	return lines.join('\n') + '\n'
}

pub fn playground_status_result() CommandResult {
	pg_path := playground_state_file()
	pg_root, pg_present := read_json_object_safe(pg_path, 'playground state') or {
		return fail_result('playground status', err.msg())
	}
	pres := presenter_status() or { return fail_result('playground status', err.msg()) }
	probe := playground_probe_host()

	pg_state := if pg_present { j_str(pg_root, 'state') } else { 'stopped' }
	provider := if pg_present && j_str(pg_root, 'provider').len > 0 {
		j_str(pg_root, 'provider')
	} else {
		playground_default_provider
	}
	profile := if pg_present && j_str(pg_root, 'profile').len > 0 {
		j_str(pg_root, 'profile')
	} else {
		playground_default_image_profile
	}
	resolution := if pg_present && j_str(pg_root, 'resolution').len > 0 {
		j_str(pg_root, 'resolution')
	} else {
		presenter_default_resolution
	}
	vm_pid := if pg_present { j_str(pg_root, 'vm_pid') } else { '' }
	msg := 'playground=${pg_state} provider=${provider} profile=${profile} resolution=${resolution} presenter_active=${pres.active} kvm=${probe.kvm_available} virgl=${probe.render_nodes.len > 0}'
	return ok_result('playground status', msg, {
		'state':            pg_state
		'present':          pg_present.str()
		'provider':         provider
		'profile':          profile
		'resolution':       resolution
		'vm_pid':           vm_pid
		'presenter_active': pres.active.str()
		'kvm_available':    probe.kvm_available.str()
		'virgl_available':  (probe.render_nodes.len > 0).str()
		'state_file':       pg_path
	})
}

fn resolve_vm_run_bin() string {
	env := os.getenv('HORNERO_VM_RUN_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('hornero-vm-run.sh')
}

fn resolve_presenter_bin() string {
	env := os.getenv('HORNERO_PRESENTER_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('hornero-presenter')
}

fn validate_ram_spec(raw string) !string {
	s := raw.trim_space().to_upper()
	if s.len == 0 {
		return error('ram must not be empty (expected e.g. 4G or 4096M)')
	}
	if s.ends_with('G') {
		num := s[..s.len - 1]
		if !is_digits_only(num) || num.int() < 1 {
			return error('invalid --ram value "${raw}" (expected e.g. 4G or 4096M)')
		}
		return s
	}
	if s.ends_with('M') {
		num := s[..s.len - 1]
		if !is_digits_only(num) || num.int() < 1024 {
			return error('invalid --ram value "${raw}" (minimum 1024M)')
		}
		return s
	}
	if is_digits_only(s) && s.int() >= 1024 {
		return '${s}M'
	}
	return error('invalid --ram value "${raw}" (expected e.g. 4G or 4096M)')
}

pub fn playground_up_result(opts PlaygroundUpOptions) CommandResult {
	cmd := 'playground up'
	provider := if opts.provider.len > 0 {
		opts.provider.trim_space().to_lower()
	} else {
		playground_default_provider
	}
	if provider != 'local' {
		refusal_msg := 'refusing non-local paid cloud provider "${provider}": cloud VMs incur external billing and require explicit manual Terraform confirmation. Use --provider local for zero-cost local KVM, or follow the Terraform IaC docs at ${playground_cloud_docs_ref}'
		if !opts.confirm_paid_provider {
			return fail_result_data(cmd, refusal_msg, {
				'provider':       provider
				'refused_reason': 'paid-cloud-provider-requires-confirmation'
				'docs':           playground_cloud_docs_ref
			})
		}
		// Even with explicit confirmation flag, horneroctl never runs terraform
		// apply directly; return an informational dry-run pointer to IaC.
		return fail_result_data(cmd, 'cloud provisioning is owned by HorneroOS/playground Terraform modules (horneroctl does not invoke terraform apply directly). Inspect and run manually: ${playground_cloud_docs_ref}',
			{
				'provider': provider
				'docs':     playground_cloud_docs_ref
			})
	}

	prof := playground_find_image_profile(opts.profile) or {
		return fail_result(cmd, 'unknown image profile "${opts.profile}" (valid: standard-vm, public-playground, presenter, qa, screenshot, video)')
	}
	res := playground_resolve_resolution(opts.resolution) or { return fail_result(cmd, err.msg()) }
	ram_spec := validate_ram_spec(opts.ram) or { return fail_result(cmd, err.msg()) }
	if opts.cpus < 1 || opts.cpus > 64 {
		return fail_result(cmd, 'invalid --cpus count ${opts.cpus} (expected 1..64)')
	}

	vm_runner := resolve_vm_run_bin()
	launcher_prog := if vm_runner.len > 0 { vm_runner } else { 'hornero-vm-run.sh' }
	mut vm_args := []string{}
	if opts.image.len > 0 {
		vm_args << ['--image', opts.image, '--ephemeral']
	} else if opts.iso.len > 0 {
		vm_args << ['--iso', opts.iso]
	} else {
		vm_args << ['--image', '/var/lib/hornero/horneroos-${prof.id}.qcow2', '--ephemeral']
	}
	vm_args << ['--ram', ram_spec, '--cpus', opts.cpus.str(), '--gpu', prof.gpu, '--resolution',
		res.label]
	if opts.dry_run {
		vm_args << '--dry-run'
	}
	planned_cmd := command_line(launcher_prog, vm_args)

	if opts.dry_run {
		return ok_result(cmd, 'Dry run: would launch local playground (${prof.id}, ${res.label}): ${planned_cmd}',
			{
				'dry_run':         'true'
				'provider':        'local'
				'profile':         prof.id
				'resolution':      res.label
				'display_profile': res.profile_id
				'ram':             ram_spec
				'cpus':            opts.cpus.str()
				'gpu':             prof.gpu
				'command_line':    planned_cmd
				'commands':        json2.encode([planned_cmd], escape_unicode: true)
			})
	}

	if !opts.yes {
		return fail_result(cmd, 'refusing to launch local playground VM without --yes (preview with --dry-run).\nExample: horneroctl playground up --provider local --dry-run')
	}

	if vm_runner.len == 0 || !capture_backend_present(vm_runner) {
		return fail_result(cmd, 'hornero-vm-run.sh not found on PATH (set HORNERO_VM_RUN_BIN or use launchers/qemu/hornero-vm-run.sh from HorneroOS/playground)')
	}
	if opts.image.len == 0 && opts.iso.len == 0 {
		return fail_result(cmd, 'provide --image <path.qcow2> or --iso <path.iso> for live local playground launch')
	}

	rep := run_exec(ExecSpec{
		prog:        vm_runner
		args:        vm_args
		dry_run:     false
		timeout_sec: 30
	})
	if !rep.ok {
		return fail_result(cmd, 'playground launch failed (exit ${rep.exit_code}): ${rep.output}')
	}
	pg_path := playground_state_file()
	state_payload := '{\n  "state": "running",\n  "provider": "local",\n  "profile": ${json2.encode(prof.id,
		escape_unicode: true
	)},\n  "resolution": ${json2.encode(res.label, escape_unicode: true)},\n  "vm_pid": ""\n}\n'
	write_json_object_safe(pg_path, 'playground state', state_payload) or {
		return fail_result(cmd, err.msg())
	}
	return ok_result(cmd, 'Launched local playground (${prof.id}, ${res.label}): ${rep.command_line}',
		{
			'provider':        'local'
			'profile':         prof.id
			'resolution':      res.label
			'display_profile': res.profile_id
			'command_line':    rep.command_line
			'state_file':      pg_path
		})
}

pub fn playground_down_result(dry_run bool, yes bool) CommandResult {
	cmd := 'playground down'
	pg_path := playground_state_file()
	pg_root, pg_present := read_json_object_safe(pg_path, 'playground state') or {
		return fail_result(cmd, err.msg())
	}
	vm_pid := if pg_present { j_str(pg_root, 'vm_pid') } else { '' }
	planned_cmd := if vm_pid.len > 0 {
		command_line('kill', ['-TERM', vm_pid])
	} else {
		'clear ${pg_path}'
	}
	if dry_run {
		return ok_result(cmd, 'Dry run: would stop local playground session (${planned_cmd}).',
			{
				'dry_run':      'true'
				'state_file':   pg_path
				'vm_pid':       vm_pid
				'command_line': planned_cmd
				'commands':     json2.encode([planned_cmd], escape_unicode: true)
			})
	}
	if !yes {
		return fail_result(cmd, 'refusing to stop local playground session without --yes (preview with --dry-run).\nExample: horneroctl playground down --dry-run')
	}
	if vm_pid.len > 0 && is_digits_only(vm_pid) {
		_ = run_exec(ExecSpec{
			prog:        'kill'
			args:        ['-TERM', vm_pid]
			dry_run:     false
			timeout_sec: 10
		})
	}
	if os.is_file(pg_path) {
		stopped := '{\n  "state": "stopped",\n  "provider": "local",\n  "profile": "",\n  "resolution": "",\n  "vm_pid": ""\n}\n'
		write_json_object_safe(pg_path, 'playground state', stopped) or {
			return fail_result(cmd, err.msg())
		}
	}
	return ok_result(cmd, 'Local playground session stopped.', {
		'state':      'stopped'
		'state_file': pg_path
	})
}

pub fn presenter_youtube_bundle_paths(bundle_root string) ([]string, map[string]string) {
	paths := [
		'${bundle_root}/recordings/desktop-master.mkv',
		'${bundle_root}/recordings/desktop-preview.mp4',
		'${bundle_root}/audio/system.flac',
		'${bundle_root}/audio/narration.flac',
		'${bundle_root}/screenshots/',
		'${bundle_root}/thumbnails/',
		'${bundle_root}/chapters.json',
		'${bundle_root}/subtitles.srt',
		'${bundle_root}/project.kdenlive',
		'${bundle_root}/manifest.json',
	]
	spec := {
		'recordings_master':  '${bundle_root}/recordings/desktop-master.mkv'
		'recordings_preview': '${bundle_root}/recordings/desktop-preview.mp4'
		'audio_system':       '${bundle_root}/audio/system.flac'
		'audio_narration':    '${bundle_root}/audio/narration.flac'
		'screenshots_dir':    '${bundle_root}/screenshots/'
		'thumbnails_dir':     '${bundle_root}/thumbnails/'
		'chapters':           '${bundle_root}/chapters.json'
		'subtitles':          '${bundle_root}/subtitles.srt'
		'kdenlive_project':   '${bundle_root}/project.kdenlive'
		'manifest':           '${bundle_root}/manifest.json'
	}
	return paths, spec
}

pub fn presenter_youtube_bundle_layout(bundle_root string) string {
	return '${bundle_root}/{recordings/{desktop-master.mkv,desktop-preview.mp4},audio/{system.flac,narration.flac},screenshots/,thumbnails/,chapters.json,subtitles.srt,project.kdenlive,manifest.json}'
}

// presenter_plan validates the resolution profile, fps, and optional scenario,
// and builds a deterministic command plan for start|stop|record|stop-recording|export.
pub fn presenter_plan(opts PresenterOptions) !PresenterPlan {
	if opts.action !in ['start', 'stop', 'record', 'stop-recording', 'export'] {
		return error('unknown presenter action "${opts.action}" (expected status|start|stop|record|stop-recording|export)')
	}
	res := playground_resolve_resolution(if opts.resolution.len > 0 {
		opts.resolution
	} else {
		presenter_default_resolution
	})!
	fps := if opts.fps == 0 { presenter_default_fps } else { opts.fps }
	if fps !in [30, 60] {
		return error('invalid --fps ${fps} (expected 30 or 60)')
	}

	mut scenario_id := opts.scenario.trim_space().to_lower()
	if scenario_id.len > 0 {
		_ := playground_find_scenario(scenario_id) or {
			valid := playground_scenarios().map(it.id).join(', ')
			return error('unknown scenario "${opts.scenario}" (valid: ${valid})')
		}
	} else if opts.action == 'export' {
		scenario_id = 'introducing-horneroos'
	}

	bundle_name := if scenario_id.len > 0 { 'hornero-${scenario_id}' } else { 'hornero-session' }
	bundle_root := if opts.output.len > 0 {
		os.join_path(opts.output, bundle_name)
	} else {
		bundle_name
	}
	bundle_paths, _ := presenter_youtube_bundle_paths(bundle_root)
	bundle_layout := presenter_youtube_bundle_layout(bundle_root)

	pres_bin := resolve_presenter_bin()
	qs_bin := resolve_qs_bin()
	pres_prog := if pres_bin.len > 0 { pres_bin } else { 'hornero-presenter' }
	qs_prog := if qs_bin.len > 0 { qs_bin } else { 'qs' }

	mut cmds := []string{}
	mut delegated := ''
	match opts.action {
		'start' {
			if pres_bin.len > 0 {
				cmds << command_line(pres_prog, ['on'])
				delegated = 'hornero-presenter'
			} else {
				cmds << command_line(qs_prog, ['ipc', 'call', 'notifs', 'isDndEnabled'])
				cmds << command_line(qs_prog, ['ipc', 'call', 'notifs', 'enableDnd'])
				delegated = 'qs'
			}
		}
		'stop' {
			if pres_bin.len > 0 {
				cmds << command_line(pres_prog, ['off'])
				delegated = 'hornero-presenter'
			} else {
				cmds << command_line(qs_prog, ['ipc', 'call', 'notifs', 'disableDnd'])
				delegated = 'qs'
			}
		}
		'record' {
			gsr := resolve_gsr_bin()
			rec_prog := if gsr.len > 0 { gsr } else { 'gpu-screen-recorder' }
			cmds << command_line(rec_prog, ['-w', 'screen', '-f', fps.str(), '-a', 'default_output',
				'-o', '${bundle_root}/recordings/desktop-master.mkv'])
			delegated = 'gpu-screen-recorder'
		}
		'stop-recording' {
			cmds << command_line('pkill', ['-INT', '-f', recorder_match()])
			cmds << command_line('ffmpeg', ['-hide_banner', '-nostdin', '-i',
				'${bundle_root}/recordings/desktop-master.mkv', '-vf',
				'scale=${res.width}:${res.height}', '-r', fps.str(), '-c:v', 'libx264', '-pix_fmt',
				'yuv420p', '-movflags', '+faststart', '${bundle_root}/recordings/desktop-preview.mp4'])
			delegated = 'ffmpeg'
		}
		'export' {
			cmds << command_line('ffprobe', ['-v', 'error', '-show_format', '-show_streams',
				'${bundle_root}/recordings/desktop-master.mkv'])
			cmds << command_line('ffmpeg', ['-hide_banner', '-nostdin', '-i',
				'${bundle_root}/recordings/desktop-master.mkv', '-vf',
				'scale=${res.width}:${res.height}', '-r', fps.str(), '-c:v', 'libx264', '-pix_fmt',
				'yuv420p', '-movflags', '+faststart', '${bundle_root}/recordings/desktop-preview.mp4'])
			cmds << command_line('ffmpeg', ['-hide_banner', '-nostdin', '-i',
				'${bundle_root}/recordings/desktop-master.mkv', '-vn', '-c:a', 'flac',
				'${bundle_root}/audio/system.flac'])
			delegated = 'ffmpeg+kdenlive'
		}
		else {}
	}

	return PresenterPlan{
		action:        opts.action
		resolution:    res
		fps:           fps
		scenario:      scenario_id
		bundle_root:   bundle_root
		bundle_layout: bundle_layout
		bundle_paths:  bundle_paths
		commands:      cmds
		command_line:  if cmds.len > 0 { cmds[0] } else { '' }
		delegated_to:  delegated
	}
}

fn query_live_dnd() string {
	if os.getenv('HORNERO_BYPASS_QUICKSHELL') == '1' {
		return 'unknown'
	}
	qs := resolve_qs_bin()
	if qs.len == 0 || !capture_backend_present(qs) {
		return 'unavailable'
	}
	rep := run_exec(ExecSpec{
		prog:        qs
		args:        ['ipc', 'call', 'notifs', 'isDndEnabled']
		dry_run:     false
		timeout_sec: 5
	})
	if !rep.ok {
		return 'unknown'
	}
	return if rep.output.to_lower().contains('true') { 'true' } else { 'false' }
}

pub fn presenter_status_result() CommandResult {
	st := presenter_status() or { return fail_result('presenter status', err.msg()) }
	live_dnd := query_live_dnd()
	msg := 'presenter_active=${st.active} prior_dnd=${st.prior_dnd} live_dnd=${live_dnd} resolution=${st.resolution} fps=${st.fps} scenario=${if st.scenario.len > 0 {
		st.scenario
	} else {
		'none'
	}} recording=${st.recording} state_file=${st.state_file}'
	return ok_result('presenter status', msg, {
		'active':         st.active.str()
		'prior_dnd':      st.prior_dnd.str()
		'live_dnd':       live_dnd
		'scenario':       st.scenario
		'resolution':     st.resolution
		'fps':            st.fps.str()
		'recording':      st.recording.str()
		'recording_file': st.recording_file
		'present':        st.present.str()
		'state_file':     st.state_file
	})
}

fn presenter_bundle_scaffold(plan PresenterPlan) ! {
	ensure_no_symlink_path(plan.bundle_root, 'presenter export bundle')!
	for sub in ['recordings', 'audio', 'screenshots', 'thumbnails'] {
		os.mkdir_all(os.join_path(plan.bundle_root, sub)) or {
			return error('cannot create ${sub} directory: ${err.msg()}')
		}
	}
	chapters_path := os.join_path(plan.bundle_root, 'chapters.json')
	if !os.exists(chapters_path) {
		chapters_doc := '{\n  "scenario": ${json2.encode(plan.scenario, escape_unicode: true)},\n  "chapters": []\n}\n'
		os.write_file(chapters_path, chapters_doc) or {
			return error('cannot write ${chapters_path}: ${err.msg()}')
		}
	}
	srt_path := os.join_path(plan.bundle_root, 'subtitles.srt')
	if !os.exists(srt_path) {
		os.write_file(srt_path, '1\n00:00:00,000 --> 00:00:03,000\nHorneroOS — ${plan.scenario}\n') or {
			return error('cannot write ${srt_path}: ${err.msg()}')
		}
	}
	kdenlive_path := os.join_path(plan.bundle_root, 'project.kdenlive')
	if !os.exists(kdenlive_path) {
		kdenlive_xml := '<mlt title="HorneroOS ${plan.scenario}" LC_NUMERIC="C">\n  <profile width="${plan.resolution.width}" height="${plan.resolution.height}" frame_rate_num="${plan.fps}" frame_rate_den="1"/>\n</mlt>\n'
		os.write_file(kdenlive_path, kdenlive_xml) or {
			return error('cannot write ${kdenlive_path}: ${err.msg()}')
		}
	}
	manifest_path := os.join_path(plan.bundle_root, 'manifest.json')
	_, bundle_spec := presenter_youtube_bundle_paths(plan.bundle_root)
	manifest_doc := json2.encode({
		'scenario':        json2.Any(plan.scenario)
		'resolution':      json2.Any(plan.resolution.label)
		'display_profile': json2.Any(plan.resolution.profile_id)
		'fps':             json2.Any(plan.fps)
		'bundle_layout':   json2.Any(plan.bundle_layout)
		'bundle':          json2.Any(bundle_spec.str())
	}, escape_unicode: true)
	os.write_file(manifest_path, manifest_doc + '\n') or {
		return error('cannot write ${manifest_path}: ${err.msg()}')
	}
}

pub fn presenter_execute_result(opts PresenterOptions) CommandResult {
	if opts.action == 'status' {
		return presenter_status_result()
	}
	cmd := 'presenter ${opts.action}'
	mut effective_opts := opts
	if effective_opts.scenario.len == 0 && opts.action in ['record', 'stop-recording', 'export'] {
		if st := presenter_status() {
			if st.scenario.len > 0 {
				effective_opts = PresenterOptions{
					...opts
					scenario: st.scenario
				}
			}
		}
	}
	plan := presenter_plan(effective_opts) or { return fail_result(cmd, err.msg()) }
	_, bundle_spec := presenter_youtube_bundle_paths(plan.bundle_root)

	mut data := {
		'action':          plan.action
		'resolution':      plan.resolution.label
		'width':           plan.resolution.width.str()
		'height':          plan.resolution.height.str()
		'display_profile': plan.resolution.profile_id
		'fps':             plan.fps.str()
		'scenario':        plan.scenario
		'delegated_to':    plan.delegated_to
		'command_line':    plan.command_line
		'commands':        json2.encode(plan.commands, escape_unicode: true)
	}
	if plan.action == 'export' || plan.action == 'record' || plan.action == 'stop-recording' {
		data['bundle_root'] = plan.bundle_root
		data['bundle_layout'] = plan.bundle_layout
		data['bundle_paths'] = json2.encode(plan.bundle_paths, escape_unicode: true)
		data['bundle_spec'] = json2.encode(bundle_spec, escape_unicode: true)
	}

	if opts.dry_run {
		data['dry_run'] = 'true'
		detail := if plan.action == 'export' {
			'Dry run: would export YouTube bundle ${plan.bundle_layout} (${plan.resolution.label} @ ${plan.fps}fps): ${plan.commands.join(' ; ')}'
		} else {
			'Dry run: would run presenter ${plan.action} (${plan.resolution.label} @ ${plan.fps}fps${if plan.scenario.len > 0 {
				', scenario=' + plan.scenario
			} else {
				''
			}}): ${plan.commands.join(' ; ')}'
		}
		return ok_result(cmd, detail, data)
	}

	if !opts.yes {
		return fail_result(cmd, 'refusing to execute presenter ${opts.action} without --yes (preview with --dry-run).\nExample: horneroctl presenter ${opts.action} --dry-run')
	}

	st_before := presenter_status() or { return fail_result(cmd, err.msg()) }
	state_path := presenter_state_file()

	match opts.action {
		'start' {
			pres_bin := resolve_presenter_bin()
			mut warning := ''
			if pres_bin.len > 0 && capture_backend_present(pres_bin) {
				rep := run_exec(ExecSpec{
					prog:        pres_bin
					args:        ['on']
					dry_run:     false
					timeout_sec: 15
				})
				if !rep.ok {
					return fail_result(cmd, 'hornero-presenter on failed: ${rep.output}')
				}
			} else {
				prior_dnd := if st_before.active {
					st_before.prior_dnd
				} else {
					query_live_dnd() == 'true'
				}
				qs := resolve_qs_bin()
				if qs.len > 0 && capture_backend_present(qs)
					&& os.getenv('HORNERO_BYPASS_QUICKSHELL') != '1' {
					rep := run_exec(ExecSpec{
						prog:        qs
						args:        ['ipc', 'call', 'notifs', 'enableDnd']
						dry_run:     false
						timeout_sec: 10
					})
					if !rep.ok {
						warning = ' (warning: qs ipc enableDnd failed: ${rep.output})'
					}
				} else {
					warning = ' (recorded state; qs CLI not active)'
				}
				new_state := PresenterState{
					active:         true
					prior_dnd:      prior_dnd
					scenario:       plan.scenario
					resolution:     plan.resolution.label
					fps:            plan.fps
					recording:      st_before.recording
					recording_file: st_before.recording_file
					present:        true
					state_file:     state_path
				}
				write_json_object_safe(state_path, 'presenter state', presenter_encode_state(new_state)) or {
					return fail_result(cmd, err.msg())
				}
			}
			data['state_file'] = state_path
			return ok_result(cmd, 'Presenter mode started (${plan.resolution.label} @ ${plan.fps}fps)${warning}.',
				data)
		}
		'stop' {
			pres_bin := resolve_presenter_bin()
			mut warning := ''
			if pres_bin.len > 0 && capture_backend_present(pres_bin) {
				rep := run_exec(ExecSpec{
					prog:        pres_bin
					args:        ['off']
					dry_run:     false
					timeout_sec: 15
				})
				if !rep.ok {
					return fail_result(cmd, 'hornero-presenter off failed: ${rep.output}')
				}
			} else {
				target_method := if st_before.prior_dnd { 'enableDnd' } else { 'disableDnd' }
				qs := resolve_qs_bin()
				if qs.len > 0 && capture_backend_present(qs)
					&& os.getenv('HORNERO_BYPASS_QUICKSHELL') != '1' {
					rep := run_exec(ExecSpec{
						prog:        qs
						args:        ['ipc', 'call', 'notifs', target_method]
						dry_run:     false
						timeout_sec: 10
					})
					if !rep.ok {
						warning = ' (warning: qs ipc ${target_method} failed: ${rep.output})'
					}
				} else {
					warning = ' (recorded state; qs CLI not active)'
				}
				new_state := PresenterState{
					active:         false
					prior_dnd:      st_before.prior_dnd
					scenario:       st_before.scenario
					resolution:     st_before.resolution
					fps:            st_before.fps
					recording:      false
					recording_file: st_before.recording_file
					present:        true
					state_file:     state_path
				}
				write_json_object_safe(state_path, 'presenter state', presenter_encode_state(new_state)) or {
					return fail_result(cmd, err.msg())
				}
			}
			data['state_file'] = state_path
			return ok_result(cmd, 'Presenter mode stopped (prior DND restored=${st_before.prior_dnd})${warning}.',
				data)
		}
		'record' {
			gsr := resolve_gsr_bin()
			if gsr.len == 0 || !capture_backend_present(gsr) {
				return fail_result(cmd, 'gpu-screen-recorder not found on PATH (set HORNERO_GPU_SCREEN_RECORDER_BIN or preview with --dry-run)')
			}
			master := '${plan.bundle_root}/recordings/desktop-master.mkv'
			ensure_no_symlink_path(plan.bundle_root, 'presenter recording dir') or {
				return fail_result(cmd, err.msg())
			}
			os.mkdir_all(os.dir(master)) or {
				return fail_result(cmd, 'cannot create recording dir: ${err.msg()}')
			}
			rep := run_exec(ExecSpec{
				prog:        gsr
				args:        ['-w', 'screen', '-f', plan.fps.str(), '-a', 'default_output', '-o',
					master]
				dry_run:     false
				timeout_sec: 15
			})
			if !rep.ok {
				return fail_result(cmd, 'presenter record failed: ${rep.output}')
			}
			new_state := PresenterState{
				active:         st_before.active
				prior_dnd:      st_before.prior_dnd
				scenario:       plan.scenario
				resolution:     plan.resolution.label
				fps:            plan.fps
				recording:      true
				recording_file: master
				present:        true
				state_file:     state_path
			}
			write_json_object_safe(state_path, 'presenter state', presenter_encode_state(new_state)) or {
				return fail_result(cmd, err.msg())
			}
			return ok_result(cmd, 'Presenter recording started: ${master}', data)
		}
		'stop-recording' {
			_ = run_exec(ExecSpec{
				prog:        'pkill'
				args:        ['-INT', '-f', recorder_match()]
				dry_run:     false
				timeout_sec: 10
			})
			new_state := PresenterState{
				active:         st_before.active
				prior_dnd:      st_before.prior_dnd
				scenario:       st_before.scenario
				resolution:     st_before.resolution
				fps:            st_before.fps
				recording:      false
				recording_file: st_before.recording_file
				present:        true
				state_file:     state_path
			}
			write_json_object_safe(state_path, 'presenter state', presenter_encode_state(new_state)) or {
				return fail_result(cmd, err.msg())
			}
			return ok_result(cmd, 'Presenter recording stopped.', data)
		}
		'export' {
			presenter_bundle_scaffold(plan) or { return fail_result(cmd, err.msg()) }
			return ok_result(cmd, 'Exported presenter YouTube bundle scaffold: ${plan.bundle_layout}',
				data)
		}
		else {
			return fail_result(cmd, 'unknown presenter action: ${opts.action}')
		}
	}
}
