module hornero_core

import os
import x.json2

const profile_test_root = '/tmp/hx-profile-test'

fn profile_test_setup(tag string) string {
	root := '${profile_test_root}/${tag}'
	if os.exists(root) {
		os.rmdir_all(root) or {}
	}
	os.mkdir_all('${root}/bin') or { assert false }
	os.mkdir_all('${root}/config/hornero') or { assert false }
	os.mkdir_all('${root}/config/pipewire/pipewire.conf.d') or { assert false }
	os.mkdir_all('${root}/config/pipewire/jack.conf.d') or { assert false }
	os.mkdir_all('${root}/state/hornero/signal') or { assert false }
	os.mkdir_all('${root}/state/hornero/plugins/receipts') or { assert false }
	os.mkdir_all('${root}/data/hornero/plugins/example-clock') or { assert false }
	os.mkdir_all('${root}/profiles') or { assert false }
	os.mkdir_all('${root}/profiles-state') or { assert false }

	os.setenv('XDG_CONFIG_HOME', '${root}/config', true)
	os.setenv('XDG_STATE_HOME', '${root}/state', true)
	os.setenv('XDG_DATA_HOME', '${root}/data', true)
	os.setenv('HORNERO_PROFILES_DIR', '${root}/profiles', true)
	os.setenv('HORNERO_PROFILES_STATE_DIR', '${root}/profiles-state', true)
	os.setenv('HORNERO_PIPEWIRE_CONF_DIR', '${root}/config/pipewire/pipewire.conf.d', true)
	os.setenv('HORNERO_JACK_CONF_DIR', '${root}/config/pipewire/jack.conf.d', true)
	os.setenv('HORNERO_STUDIO_MODE_FILE', '${root}/config/hornero/studio-mode.json', true)
	os.setenv('HORNERO_BYPASS_QUICKSHELL', '0', true)
	os.setenv('HORNERO_PROFILE_RUNNING_PROCS', 'reaper\ndiscord\npipewire\nbash\n', true)
	os.setenv('PATH', '${root}/bin:/usr/bin:/bin', true)

	// Experience, scheme, shell.json, plugin receipt
	os.write_file('${root}/state/hornero/experience.json', '{"mode":"studio"}\n') or { assert false }
	os.write_file('${root}/state/hornero/signal/scheme.json', '{"schemaVersion":2,"id":"hornero-signal-night","mode":"dark"}\n') or {
		assert false
	}
	os.write_file('${root}/config/hornero/shell.json', '{"layoutPreset":"cockpit"}\n') or {
		assert false
	}
	os.write_file('${root}/data/hornero/plugins/example-clock/manifest.json', '{"schemaVersion":1,"id":"example-clock"}\n') or {
		assert false
	}
	os.write_file('${root}/state/hornero/plugins/receipts/example-clock.json', '{"schema_version":1,"id":"example-clock","enabled":true,"source":"https://github.com/HorneroOS/plugins.git","revision":"0123456789abcdef0123456789abcdef01234567"}\n') or {
		assert false
	}

	// Stateful pw-metadata
	pw_state := '${root}/pw-state.txt'
	os.write_file(pw_state, "update: id:0 key:'clock.rate' value:'48000' type:''\nupdate: id:0 key:'clock.quantum' value:'128' type:''\nupdate: id:0 key:'clock.min-quantum' value:'64' type:''\nupdate: id:0 key:'clock.max-quantum' value:'256' type:''\n") or {
		assert false
	}
	os.write_file('${root}/bin/pw-metadata', '#!/bin/sh
S="${pw_state}"
if [ "\$#" -ge 5 ]; then
  grep -v "key:\'\$4\'" "\$S" > "\$S.n"
  printf "update: id:0 key:\'%s\' value:\'%s\' type:\'\'\\n" "\$4" "\$5" >> "\$S.n"
  mv "\$S.n" "\$S"
else
  cat "\$S"
fi
') or {
		assert false
	}
	os.chmod('${root}/bin/pw-metadata', 0o755) or {}
	os.setenv('HORNERO_PW_METADATA_BIN', '${root}/bin/pw-metadata', true)

	// Stateful powerprofilesctl
	pp_state := '${root}/pp-state.txt'
	os.write_file(pp_state, 'performance\n') or { assert false }
	os.write_file('${root}/bin/powerprofilesctl', '#!/bin/sh
if [ "\$1" = "get" ]; then cat "${pp_state}"; exit 0; fi
if [ "\$1" = "set" ]; then echo "\$2" > "${pp_state}"; exit 0; fi
') or {
		assert false
	}
	os.chmod('${root}/bin/powerprofilesctl', 0o755) or {}
	os.setenv('HORNERO_POWERPROFILESCTL_BIN', '${root}/bin/powerprofilesctl', true)

	// Mock pactl
	pactl_state := '${root}/pactl-default-sink.txt'
	os.write_file(pactl_state, 'alsa_output.usb-focusrite\n') or { assert false }
	os.write_file('${root}/bin/pactl', '#!/bin/sh
echo "\$*" >> "${root}/pactl.log"
SINK=\$(cat "${pactl_state}")
case "\$1 \$2" in
  "info ")
    echo "Default Sink: \$SINK"
    echo "Default Source: alsa_input.usb-focusrite"
    ;;
  "list sinks")
    echo "Sink #1"
    echo "\tName: alsa_output.usb-focusrite"
    echo "\tDescription: Focusrite Scarlett"
    echo "Sink #2"
    echo "\tName: alsa_output.builtin"
    echo "\tDescription: Built-in Audio"
    ;;
  "list sources")
    echo "Source #1"
    echo "\tName: alsa_input.usb-focusrite"
    echo "\tDescription: Focusrite Mic"
    ;;
  "list sink-inputs")
    echo "Sink Input #9"
    echo "\tSink: 1"
    echo "\tMute: no"
    echo "\tVolume: front-left: 65536 / 100% / 0.00 dB"
    echo "\tProperties:"
    echo "\t\tapplication.name = \\"REAPER\\""
    ;;
  "set-default-sink "*)
    echo "\$2" > "${pactl_state}"
    ;;
esac
') or {
		assert false
	}
	os.chmod('${root}/bin/pactl', 0o755) or {}
	os.setenv('HORNERO_PACTL_BIN', '${root}/bin/pactl', true)

	// Mock pw-link
	os.write_file('${root}/bin/pw-link', '#!/bin/sh
if [ "\$1" = "-l" ]; then
  echo "reaper:out_FL"
  echo "  |-> alsa_output.usb-focusrite:playback_FL"
else
  echo "\$*" >> "${root}/pw-link.log"
fi
') or {
		assert false
	}
	os.chmod('${root}/bin/pw-link', 0o755) or {}
	os.setenv('HORNERO_PW_LINK_BIN', '${root}/bin/pw-link', true)

	// Mock qs
	idle_state := '${root}/idle.txt'
	os.write_file(idle_state, 'true\n') or { assert false }
	os.write_file('${root}/bin/qs', '#!/bin/sh
echo "\$*" >> "${root}/qs.log"
if [ "\$5" = "idleInhibitor" ] && [ "\$6" = "isEnabled" ]; then
  cat "${idle_state}"
elif [ "\$5" = "idleInhibitor" ] && [ "\$6" = "disable" ]; then
  echo "false" > "${idle_state}"
elif [ "\$5" = "idleInhibitor" ] && [ "\$6" = "enable" ]; then
  echo "true" > "${idle_state}"
fi
') or {
		assert false
	}
	os.chmod('${root}/bin/qs', 0o755) or {}
	os.setenv('HORNERO_QS_BIN', '${root}/bin/qs', true)

	// Mock systemctl & systemd-run & installed binaries
	os.write_file('${root}/bin/systemctl', '#!/bin/sh\necho "\$*" >> "${root}/systemctl.log"\nexit 0\n') or {
		assert false
	}
	os.chmod('${root}/bin/systemctl', 0o755) or {}
	os.setenv('HORNERO_SYSTEMCTL_BIN', '${root}/bin/systemctl', true)

	os.write_file('${root}/bin/systemd-run', '#!/bin/sh\necho "\$*" >> "${root}/systemd-run.log"\nexit 0\n') or {
		assert false
	}
	os.chmod('${root}/bin/systemd-run', 0o755) or {}
	os.setenv('HORNERO_SYSTEMD_RUN_BIN', '${root}/bin/systemd-run', true)

	for app_bin in ['reaper', 'discord', 'qpwgraph'] {
		os.write_file('${root}/bin/${app_bin}', '#!/bin/sh\nexit 0\n') or { assert false }
		os.chmod('${root}/bin/${app_bin}', 0o755) or {}
	}
	return root
}

fn profile_test_teardown(saved_path string) {
	for k in ['XDG_CONFIG_HOME', 'XDG_STATE_HOME', 'XDG_DATA_HOME', 'HORNERO_PROFILES_DIR',
		'HORNERO_PROFILES_STATE_DIR', 'HORNERO_PIPEWIRE_CONF_DIR', 'HORNERO_JACK_CONF_DIR',
		'HORNERO_STUDIO_MODE_FILE', 'HORNERO_BYPASS_QUICKSHELL', 'HORNERO_PROFILE_RUNNING_PROCS',
		'HORNERO_PW_METADATA_BIN', 'HORNERO_POWERPROFILESCTL_BIN', 'HORNERO_PACTL_BIN',
		'HORNERO_PW_LINK_BIN', 'HORNERO_QS_BIN', 'HORNERO_SYSTEMCTL_BIN', 'HORNERO_SYSTEMD_RUN_BIN'] {
		os.unsetenv(k)
	}
	os.setenv('PATH', saved_path, true)
}

fn test_profile_id_validation() {
	assert valid_profile_id('music-prod')
	assert valid_profile_id('a1_b2')
	assert !valid_profile_id('')
	assert !valid_profile_id('Music')
	assert !valid_profile_id('-bad')
	assert !valid_profile_id('../escape')
	assert !valid_profile_id('a/b')
	assert !valid_profile_id('a'.repeat(65))
}

fn test_profile_capture_auto_baseline_list_show_and_daemon_filter() {
	saved_path := os.getenv('PATH')
	root := profile_test_setup('capture')
	defer {
		profile_test_teardown(saved_path)
	}
	os.write_file('${root}/config/pipewire/pipewire.conf.d/70-hornero-routing-live-call.conf', '# Managed by horneroctl studio routing\ncontext.objects = []\n') or {
		assert false
	}

	// Capture rejects system daemons passed via --app.
	bad := profile_capture_result(ProfileCaptureOptions{
		id:   'music-prod'
		apps: ['pipewire']
		yes:  true
	})
	assert !bad.ok

	// Capture creates baseline automatically + saves music-prod + copies drop-in.
	cap := profile_capture_result(ProfileCaptureOptions{
		id:          'music-prod'
		name:        'Music Production'
		description: 'REAPER + Scarlett'
		apps:        ['qpwgraph']
		activate:    true
		yes:         true
	})
	assert cap.ok, cap.message
	assert cap.data['baseline_created'] == 'true'
	assert os.is_file('${root}/profiles-state/baseline/profile.json')
	assert os.is_file('${root}/profiles/music-prod/profile.json')
	assert os.is_file('${root}/profiles/music-prod/pipewire/pipewire.conf.d/70-hornero-routing-live-call.conf')

	// List returns baseline + music-prod with accurate counts and active flag.
	lst := profile_list_result()
	assert lst.ok
	assert lst.data['active'] == 'music-prod'
	assert lst.data['has_baseline'] == 'true'
	assert lst.data['count'] == '2'
	items := json2.decode[[]ProfileSummaryItem](lst.data['profiles']) or {
		assert false, err.msg()
		return
	}
	assert items[0].id == 'baseline'
	assert items[0].is_baseline
	assert items[1].id == 'music-prod'
	assert items[1].is_active
	assert items[1].apps_count == 3 // discord, qpwgraph, reaper (never pipewire/bash)
	assert items[1].apps_running == 2 // reaper, discord
	assert items[1].apps_missing == 1 // qpwgraph
	assert items[1].hardware_status == 'ok'

	// Show returns full details & live app states.
	sh := profile_show_result('music-prod')
	assert sh.ok
	detail := json2.decode[ProfileShowDetail](sh.data['profile']) or {
		assert false, err.msg()
		return
	}
	assert detail.api_version == profile_api_version
	assert detail.kind == profile_kind
	assert detail.experience.mode == 'studio'
	assert detail.experience.theme == 'hornero-signal-night'
	assert detail.experience.layout_preset == 'cockpit'
	assert detail.audio.clock_quantum == '128'
	assert detail.audio.default_sink == 'alsa_output.usb-focusrite'
	assert detail.audio.links == ['reaper:out_FL -> alsa_output.usb-focusrite:playback_FL']
	assert detail.power.profile == 'performance'
	assert detail.power.idle_inhibitor
	assert detail.extensions.enabled == ['example-clock']
}

fn test_profile_diff_apply_revert_and_delete_protection() {
	saved_path := os.getenv('PATH')
	root := profile_test_setup('apply-revert')
	defer {
		profile_test_teardown(saved_path)
	}
	// 1. Capture "everyday" first (auto-creates baseline in everyday state).
	os.write_file('${root}/state/hornero/experience.json', '{"mode":"everyday"}\n') or {
		assert false
	}
	os.write_file('${root}/pp-state.txt', 'balanced\n') or { assert false }
	os.write_file('${root}/idle.txt', 'false\n') or { assert false }
	os.write_file('${root}/pactl-default-sink.txt', 'alsa_output.builtin\n') or { assert false }
	os.setenv('HORNERO_PROFILE_RUNNING_PROCS', 'firefox\n', true)
	cap_ev := profile_capture_result(ProfileCaptureOptions{
		id:       'everyday'
		name:     'Everyday'
		activate: true
		yes:      true
	})
	assert cap_ev.ok, cap_ev.message

	// 2. Mutate system to studio state + drop-in, then capture "studio-rig".
	os.write_file('${root}/state/hornero/experience.json', '{"mode":"studio"}\n') or { assert false }
	os.write_file('${root}/pp-state.txt', 'performance\n') or { assert false }
	os.write_file('${root}/idle.txt', 'true\n') or { assert false }
	os.write_file('${root}/pactl-default-sink.txt', 'alsa_output.usb-focusrite\n') or {
		assert false
	}
	os.write_file('${root}/config/pipewire/pipewire.conf.d/70-hornero-routing-live-call.conf', '# Managed by horneroctl studio routing\ncontext.objects = []\n') or {
		assert false
	}
	os.setenv('HORNERO_PROFILE_RUNNING_PROCS', 'reaper\n', true)
	cap_st := profile_capture_result(ProfileCaptureOptions{
		id:   'studio-rig'
		name: 'Studio Rig'
		yes:  true
	})
	assert cap_st.ok, cap_st.message

	// 3. Switch live system back to everyday, then diff & apply studio-rig.
	os.write_file('${root}/state/hornero/experience.json', '{"mode":"everyday"}\n') or {
		assert false
	}
	os.write_file('${root}/pp-state.txt', 'balanced\n') or { assert false }
	os.write_file('${root}/idle.txt', 'false\n') or { assert false }
	os.write_file('${root}/pactl-default-sink.txt', 'alsa_output.builtin\n') or { assert false }
	os.rm('${root}/config/pipewire/pipewire.conf.d/70-hornero-routing-live-call.conf') or {}
	os.setenv('HORNERO_PROFILE_RUNNING_PROCS', '', true)

	df := profile_diff_result('studio-rig')
	assert df.ok
	assert df.data['will_restart_pipewire'] == 'true'
	assert df.data['changes_count'].int() >= 4
	missing_before := json2.decode[[]ProfileMissingAppItem](df.data['missing_apps']) or {
		assert false
		return
	}
	assert missing_before.len == 1 && missing_before[0].id == 'reaper'

	// Apply studio-rig without --launch-apps: returns missing_apps, restarts PipeWire, sets power/sink.
	ap := profile_apply_result(ProfileApplyOptions{
		id:  'studio-rig'
		yes: true
	})
	assert ap.ok, ap.message
	assert ap.data['previous_saved'] == 'true'
	assert ap.data['pipewire_restarted'] == 'true'
	assert os.is_file('${root}/config/pipewire/pipewire.conf.d/70-hornero-routing-live-call.conf')
	assert (os.read_file('${root}/pp-state.txt') or { '' }).trim_space() == 'performance'
	assert (os.read_file('${root}/pactl-default-sink.txt') or { '' }).trim_space() == 'alsa_output.usb-focusrite'
	assert read_active_profile_id() == 'studio-rig'

	// Revert to previous (everyday) removes studio drop-in and restores balanced power & builtin sink.
	rev := profile_revert_result(ProfileRevertOptions{
		to:  'previous'
		yes: true
	})
	assert rev.ok, rev.message
	assert !os.is_file('${root}/config/pipewire/pipewire.conf.d/70-hornero-routing-live-call.conf')
	assert (os.read_file('${root}/pp-state.txt') or { '' }).trim_space() == 'balanced'
	assert (os.read_file('${root}/pactl-default-sink.txt') or { '' }).trim_space() == 'alsa_output.builtin'

	// Revert to baseline works too.
	rev_base := profile_revert_result(ProfileRevertOptions{
		to:  'baseline'
		yes: true
	})
	assert rev_base.ok

	// Delete refuses baseline & previous, deletes user profile.
	assert !profile_delete_result('baseline', false, true).ok
	assert !profile_delete_result('previous', false, true).ok
	assert os.is_file('${root}/profiles-state/baseline/profile.json')
	assert profile_delete_result('studio-rig', false, true).ok
	assert !os.is_dir('${root}/profiles/studio-rig')
}

fn test_profile_launch_apps_dry_run_and_portable_export_import() {
	saved_path := os.getenv('PATH')
	root := profile_test_setup('export-launch')
	defer {
		profile_test_teardown(saved_path)
	}
	os.write_file('${root}/config/pipewire/pipewire.conf.d/70-hornero-routing-browser-backing.conf', '# Managed by horneroctl studio routing\ncontext.objects = []\n') or {
		assert false
	}
	os.setenv('HORNERO_PROFILE_RUNNING_PROCS', 'reaper\ndiscord\n', true)
	assert profile_capture_result(ProfileCaptureOptions{
		id:   'lesson'
		name: 'Lesson'
		yes:  true
	}).ok

	// Clear running procs so reaper & discord are missing; dry-run launch works even without systemd-run!
	os.setenv('HORNERO_PROFILE_RUNNING_PROCS', '', true)
	os.setenv('HORNERO_SYSTEMD_RUN_BIN', '/nonexistent/systemd-run', true)
	dry_launch := profile_launch_apps_result('lesson', '', true, false)
	assert dry_launch.ok
	assert dry_launch.data['dry_run'] == 'true'
	cmds := json2.decode[[]string](dry_launch.data['commands']) or {
		assert false
		return
	}
	assert cmds.len == 2
	assert cmds[0].contains('systemd-run --user --scope --no-block')

	// Export portable bundle and import as new id.
	bundle_file := '${root}/lesson-portable.json'
	exp := profile_export_result('lesson', bundle_file, true, false, true)
	assert exp.ok, exp.message
	bundle_raw := os.read_file(bundle_file) or { '' }
	bundle := json2.decode[WorkspaceProfileBundle](bundle_raw) or {
		assert false, err.msg()
		return
	}
	assert bundle.portable
	assert bundle.profile.hostname == ''
	assert '70-hornero-routing-browser-backing.conf' in bundle.pipewire_dropin_files

	imp := profile_import_result(bundle_file, 'lesson-clone', false, true)
	assert imp.ok, imp.message
	assert os.is_file('${root}/profiles/lesson-clone/profile.json')
	assert os.is_file('${root}/profiles/lesson-clone/pipewire/pipewire.conf.d/70-hornero-routing-browser-backing.conf')
}
