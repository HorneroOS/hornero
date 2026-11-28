module hornero_core

import os
import x.json2

const playground_test_root = '/tmp/hx-playground-core-test'

fn playground_test_setup() string {
	if os.exists(playground_test_root) {
		os.rmdir_all(playground_test_root) or {}
	}
	os.mkdir_all('${playground_test_root}/state/hornero-presenter') or { assert false }
	os.mkdir_all('${playground_test_root}/state/hornero-playground') or { assert false }
	os.setenv('XDG_STATE_HOME', '${playground_test_root}/state', true)
	os.setenv('HORNERO_PRESENTER_STATE_DIR', '${playground_test_root}/state/hornero-presenter',
		true)
	os.setenv('HORNERO_PLAYGROUND_STATE_DIR', '${playground_test_root}/state/hornero-playground',
		true)
	os.setenv('HORNERO_BYPASS_QUICKSHELL', '1', true)
	os.setenv('HORNERO_QS_BIN', '/nonexistent-qs-playground-test', true)
	os.setenv('HORNERO_PRESENTER_BIN', '/nonexistent-presenter-playground-test', true)
	os.setenv('HORNERO_VM_RUN_BIN', '/nonexistent-vm-run-playground-test', true)
	os.setenv('HORNERO_GPU_SCREEN_RECORDER_BIN', '/nonexistent-gsr-playground-test', true)
	return playground_test_root
}

fn playground_test_teardown() {
	for k in ['XDG_STATE_HOME', 'HORNERO_PRESENTER_STATE_DIR', 'HORNERO_PLAYGROUND_STATE_DIR',
		'HORNERO_BYPASS_QUICKSHELL', 'HORNERO_QS_BIN', 'HORNERO_PRESENTER_BIN', 'HORNERO_VM_RUN_BIN',
		'HORNERO_GPU_SCREEN_RECORDER_BIN'] {
		os.unsetenv(k)
	}
	if os.exists(playground_test_root) {
		os.rmdir_all(playground_test_root) or {}
	}
}

fn test_seven_display_profiles_canonical() {
	profiles := playground_display_profiles()
	assert profiles.len == 7
	ids := profiles.map(it.id)
	assert ids == ['hd', 'fhd', 'qhd', 'uhd4k', 'ultrawide', 'vertical', 'custom']

	mut default_count := 0
	for p in profiles {
		if p.is_default {
			default_count++
			assert p.id == 'fhd'
			assert p.width == 1920 && p.height == 1080
		}
	}
	assert default_count == 1

	assert playground_find_display_profile('hd') or { panic('missing hd') }.width == 1280
	assert playground_find_display_profile('qhd') or { panic('missing qhd') }.height == 1440
	assert playground_find_display_profile('uhd4k') or { panic('missing uhd4k') }.width == 3840
	assert playground_find_display_profile('ultrawide') or { panic('missing ultrawide') }.width == 3440
	assert playground_find_display_profile('vertical') or { panic('missing vertical') }.height == 1920
	assert playground_find_display_profile('custom') or { panic('missing custom') }.width == 0
}

fn test_six_image_profiles_canonical() {
	profiles := playground_image_profiles()
	assert profiles.len == 6
	ids := profiles.map(it.id)
	assert ids == ['standard-vm', 'public-playground', 'presenter', 'qa', 'screenshot', 'video']
	for id in ids {
		p := playground_find_image_profile(id) or {
			assert false, 'missing image profile ${id}'
			return
		}
		assert p.ram_mb >= 4096
		assert p.vcpus >= 2
		assert p.disk_gb >= 32
	}
}

fn test_ten_scenarios_canonical() {
	scenarios := playground_scenarios()
	assert scenarios.len == 10
	ids := scenarios.map(it.id)
	assert ids == [
		'introducing-horneroos',
		'installing-and-exploring',
		'first-flight',
		'personalize-desktop',
		'hornero-apps',
		'ai-native-workstation',
		'meet-companion',
		'creative-studio',
		'extensions-marketplace',
		'release-highlights',
	]
	for idx, s in scenarios {
		assert s.order == idx + 1
		assert s.bundle_dir == 'hornero-${s.id}'
		assert s.default_resolution == '1920x1080'
		assert s.default_fps == 60
	}
}

fn test_resolution_validation() {
	fhd := playground_resolve_resolution('fhd') or { panic(err) }
	assert fhd.profile_id == 'fhd' && fhd.label == '1920x1080'

	uhd := playground_resolve_resolution('3840x2160') or { panic(err) }
	assert uhd.profile_id == 'uhd4k' && uhd.width == 3840 && uhd.height == 2160

	custom := playground_resolve_resolution('1280x800') or { panic(err) }
	assert custom.profile_id == 'custom' && custom.label == '1280x800'

	for bad in ['', 'custom', 'bogus', '0x0', '1920', '100x100', '99999x99999', '-1920x1080'] {
		if _ := playground_resolve_resolution(bad) {
			assert false, 'invalid resolution "${bad}" must fail'
		}
	}
}

fn test_playground_doctor_checks_and_read_only_probe() {
	full := PlaygroundHostProbe{
		kvm_available:     true
		kvm_path:          '/dev/kvm'
		render_nodes:      ['/dev/dri/renderD128']
		qemu_bin:          '/usr/bin/qemu-system-x86_64'
		qemu_img_bin:      '/usr/bin/qemu-img'
		ffmpeg_bin:        '/usr/bin/ffmpeg'
		ffprobe_bin:       '/usr/bin/ffprobe'
		kdenlive_bin:      '/usr/bin/kdenlive'
		systemd_run_bin:   '/usr/bin/systemd-run'
		ovmf_code:         '/usr/share/OVMF/x64/OVMF_CODE.4m.fd'
		ovmf_vars:         '/usr/share/OVMF/x64/OVMF_VARS.4m.fd'
		ram_total_mib:     16384
		ram_available_mib: 8192
		cpu_count:         8
	}
	res_full := playground_doctor_result(playground_doctor_checks(full), full)
	assert res_full.ok
	assert res_full.data['failed'] == '0'
	assert res_full.data['warnings'] == '0'

	// Missing optional tools warn but still pass.
	opt_missing := PlaygroundHostProbe{
		...full
		render_nodes:    []string{}
		ffmpeg_bin:      ''
		ffprobe_bin:     ''
		kdenlive_bin:    ''
		systemd_run_bin: ''
	}
	res_warn := playground_doctor_result(playground_doctor_checks(opt_missing), opt_missing)
	assert res_warn.ok
	assert res_warn.data['failed'] == '0'
	assert res_warn.data['warnings'] == '5'

	// Missing KVM / QEMU fails cleanly.
	no_kvm := PlaygroundHostProbe{
		...full
		kvm_available: false
		qemu_bin:      ''
	}
	res_fail := playground_doctor_result(playground_doctor_checks(no_kvm), no_kvm)
	assert !res_fail.ok
	assert res_fail.data['failed'] == '2'

	// Real read-only host doctor must execute cleanly without panicking.
	live := playground_doctor()
	assert live.command == 'playground doctor'
	assert live.data['cpu_count'].len > 0
}

fn test_playground_up_local_dry_run_and_paid_cloud_refusal() {
	playground_test_setup()
	defer {
		playground_test_teardown()
	}

	// Nonexistent HORNERO_VM_RUN_BIN + --dry-run proves non-execution.
	dry := playground_up_result(PlaygroundUpOptions{
		provider:   'local'
		profile:    'presenter'
		resolution: '1920x1080'
		dry_run:    true
	})
	assert dry.ok
	assert dry.data['dry_run'] == 'true'
	assert dry.data['provider'] == 'local'
	assert dry.data['profile'] == 'presenter'
	assert dry.data['resolution'] == '1920x1080'
	assert dry.data['command_line'].contains('--resolution 1920x1080')

	// Refuses live local without --yes.
	no_yes := playground_up_result(PlaygroundUpOptions{
		provider: 'local'
	})
	assert !no_yes.ok

	// Refuses non-local paid cloud providers with docs pointer.
	for cloud in ['hetzner', 'gcp', 'aws'] {
		refused := playground_up_result(PlaygroundUpOptions{
			provider: cloud
			dry_run:  true
		})
		assert !refused.ok
		assert refused.message.contains('infra/terraform')
		assert refused.data['refused_reason'] == 'paid-cloud-provider-requires-confirmation'
	}
}

fn test_presenter_status_safe_read_and_symlink_refusal() {
	root := playground_test_setup()
	defer {
		playground_test_teardown()
	}

	// Missing state.json yields valid inactive defaults.
	st0 := presenter_status() or {
		assert false, err.msg()
		return
	}
	assert !st0.present && !st0.active && st0.resolution == '1920x1080'

	// Valid state.json round-trips cleanly.
	state_file := presenter_state_file()
	os.write_file(state_file, '{"active": true, "prior_dnd": false, "scenario": "first-flight", "resolution": "3840x2160", "fps": 60}\n') or {
		assert false
	}
	st1 := presenter_status() or {
		assert false, err.msg()
		return
	}
	assert st1.present && st1.active && !st1.prior_dnd
	assert st1.scenario == 'first-flight'
	assert st1.resolution == '3840x2160'
	assert st1.fps == 60

	// Symlinked state.json must be refused.
	victim := '${root}/victim.txt'
	os.write_file(victim, 'secret') or { assert false }
	os.rm(state_file) or { assert false }
	os.symlink(victim, state_file) or { assert false }
	if _ := presenter_status() {
		assert false, 'symlinked state.json must be refused'
	}
}

fn test_presenter_plan_and_youtube_export_bundle() {
	root := playground_test_setup()
	defer {
		playground_test_teardown()
	}

	plan := presenter_plan(PresenterOptions{
		action:     'start'
		resolution: '3840x2160'
		scenario:   'first-flight'
		fps:        60
		dry_run:    true
	}) or {
		assert false, err.msg()
		return
	}
	assert plan.resolution.profile_id == 'uhd4k'
	assert plan.resolution.label == '3840x2160'
	assert plan.fps == 60
	assert plan.scenario == 'first-flight'
	assert plan.commands.len >= 1

	// Invalid scenario, resolution, and fps must fail.
	if _ := presenter_plan(PresenterOptions{
		action:     'start'
		resolution: '1920x1080'
		scenario:   'unknown-scenario'
	}) {
		assert false, 'unknown scenario must fail'
	}
	if _ := presenter_plan(PresenterOptions{
		action:     'start'
		resolution: 'not-a-res'
	}) {
		assert false, 'invalid resolution must fail'
	}
	if _ := presenter_plan(PresenterOptions{
		action:     'start'
		resolution: '1920x1080'
		fps:        24
	}) {
		assert false, 'invalid fps must fail'
	}

	// Export emits canonical YouTube bundle structure in JSON data and scaffolds cleanly.
	export_dry := presenter_execute_result(PresenterOptions{
		action:     'export'
		scenario:   'first-flight'
		resolution: '3840x2160'
		fps:        60
		output:     '${root}/bundles'
		dry_run:    true
	})
	assert export_dry.ok
	expected_layout := '${root}/bundles/hornero-first-flight/{recordings/{desktop-master.mkv,desktop-preview.mp4},audio/{system.flac,narration.flac},screenshots/,thumbnails/,chapters.json,subtitles.srt,project.kdenlive,manifest.json}'
	assert export_dry.data['bundle_layout'] == expected_layout
	paths := json2.decode[[]string](export_dry.data['bundle_paths']) or {
		assert false, err.msg()
		return
	}
	assert '${root}/bundles/hornero-first-flight/recordings/desktop-master.mkv' in paths
	assert '${root}/bundles/hornero-first-flight/recordings/desktop-preview.mp4' in paths
	assert '${root}/bundles/hornero-first-flight/audio/system.flac' in paths
	assert '${root}/bundles/hornero-first-flight/audio/narration.flac' in paths
	assert '${root}/bundles/hornero-first-flight/chapters.json' in paths
	assert '${root}/bundles/hornero-first-flight/subtitles.srt' in paths
	assert '${root}/bundles/hornero-first-flight/project.kdenlive' in paths
	assert '${root}/bundles/hornero-first-flight/manifest.json' in paths
	assert !os.exists('${root}/bundles/hornero-first-flight')

	// Live export with --yes scaffolds the bundle safely.
	export_live := presenter_execute_result(PresenterOptions{
		action:     'export'
		scenario:   'first-flight'
		resolution: '3840x2160'
		fps:        60
		output:     '${root}/bundles'
		yes:        true
	})
	assert export_live.ok
	assert os.is_dir('${root}/bundles/hornero-first-flight/recordings')
	assert os.is_dir('${root}/bundles/hornero-first-flight/audio')
	assert os.is_dir('${root}/bundles/hornero-first-flight/screenshots')
	assert os.is_dir('${root}/bundles/hornero-first-flight/thumbnails')
	assert os.is_file('${root}/bundles/hornero-first-flight/chapters.json')
	assert os.is_file('${root}/bundles/hornero-first-flight/subtitles.srt')
	assert os.is_file('${root}/bundles/hornero-first-flight/project.kdenlive')
	assert os.is_file('${root}/bundles/hornero-first-flight/manifest.json')
}
