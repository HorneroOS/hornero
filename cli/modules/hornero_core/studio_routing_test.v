module hornero_core

import os
import x.json2

const routing_test_root = '/tmp/hx-studio-routing-test'

const routing_pactl_sinks_sample = 'Sink #35
	State: RUNNING
	Name: alsa_output.pci-0000_00_1f.3.analog-stereo
	Description: Built-in Audio Analog Stereo
	Driver: PipeWire

Sink #44
	State: IDLE
	Name: discord_call
	Description: Discord Call
	Driver: PipeWire
'

const routing_pactl_inputs_sample = 'Sink Input #101
	Driver: PipeWire
	Sink: 35
	Mute: no
	Volume: front-left: 0 /   0% / -inf dB,   front-right: 0 /   0% / -inf dB
	        balance 0.00
	Properties:
		media.name = "WEBRTC VoiceEngine"
		application.name = "Discord"
		application.process.binary = "Discord"

Sink Input #102
	Driver: PipeWire
	Sink: 44
	Mute: yes
	Volume: front-left: 49152 /  75% / -7.50 dB
	Properties:
		media.name = "Playback"
		application.name = "REAPER"
'

fn routing_setup(tag string) string {
	root := '${routing_test_root}/${tag}'
	if os.exists(root) {
		os.rmdir_all(root) or {}
	}
	os.mkdir_all('${root}/bin') or { assert false }
	os.mkdir_all('${root}/pw.conf.d') or { assert false }
	os.mkdir_all('${root}/jack.conf.d') or { assert false }
	os.setenv('HORNERO_PIPEWIRE_CONF_DIR', '${root}/pw.conf.d', true)
	os.setenv('HORNERO_JACK_CONF_DIR', '${root}/jack.conf.d', true)
	os.setenv('HORNERO_PACTL_BIN', '${root}/bin/pactl', true)
	os.setenv('HORNERO_SYSTEMCTL_BIN', '${root}/bin/systemctl', true)

	pactl_log := '${root}/pactl.log'
	pactl_script := '#!/bin/sh
echo "\$*" >> "${pactl_log}"
case "\$1 \$2" in
  "info ")
    echo "Default Sink: alsa_output.pci-0000_00_1f.3.analog-stereo"
    echo "Default Source: alsa_input.pci-0000_00_1f.3.analog-stereo"
    ;;
  "list sinks")
    cat << \'EOF\'
${routing_pactl_sinks_sample}EOF
    ;;
  "list sources")
    echo "Source #10"
    echo "\tName: alsa_input.pci-0000_00_1f.3.analog-stereo"
    echo "\tDescription: Built-in Mic"
    ;;
  "list sink-inputs")
    cat << \'EOF\'
${routing_pactl_inputs_sample}EOF
    ;;
  *)
    exit 0
    ;;
esac
'
	os.write_file('${root}/bin/pactl', pactl_script) or { assert false }
	os.chmod('${root}/bin/pactl', 0o755) or {}

	sys_log := '${root}/systemctl.log'
	os.write_file('${root}/bin/systemctl', '#!/bin/sh\necho "\$*" >> "${sys_log}"\nexit 0\n') or {
		assert false
	}
	os.chmod('${root}/bin/systemctl', 0o755) or {}
	return root
}

fn routing_teardown() {
	for k in ['HORNERO_PIPEWIRE_CONF_DIR', 'HORNERO_JACK_CONF_DIR', 'HORNERO_PACTL_BIN',
		'HORNERO_SYSTEMCTL_BIN'] {
		os.unsetenv(k)
	}
}

fn test_parse_pactl_sinks_and_webrtc_zero_volume_warning() {
	sinks, id_map := parse_pactl_devices(routing_pactl_sinks_sample, 'Sink #', 'alsa_output.pci-0000_00_1f.3.analog-stereo')
	assert sinks.len == 2
	assert sinks[0].is_default
	assert !sinks[1].is_default
	assert id_map['35'] == 'alsa_output.pci-0000_00_1f.3.analog-stereo'
	assert id_map['44'] == 'discord_call'

	streams := parse_pactl_sink_inputs(routing_pactl_inputs_sample, id_map)
	assert streams.len == 2
	assert streams[0].id == '101'
	assert streams[0].app == 'Discord'
	assert streams[0].media_name == 'WEBRTC VoiceEngine'
	assert streams[0].sink == 'alsa_output.pci-0000_00_1f.3.analog-stereo'
	assert streams[0].volume_pct == 0
	assert !streams[0].muted
	assert streams[0].zero_volume_warning

	assert streams[1].id == '102'
	assert streams[1].app == 'REAPER'
	assert streams[1].sink == 'discord_call'
	assert streams[1].volume_pct == 75
	assert streams[1].muted
	assert !streams[1].zero_volume_warning
}

fn test_routing_status_detects_external_dotfiles_and_streams() {
	root := routing_setup('external')
	defer {
		routing_teardown()
	}
	os.write_file('${root}/pw.conf.d/60-reaper-music-studio.conf', '# personal dotfiles\n') or {
		assert false
	}
	os.write_file('${root}/jack.conf.d/60-reaper-low-latency.conf', '# personal jack\n') or {
		assert false
	}
	res := studio_routing_status_result()
	assert res.ok
	kits := json2.decode[[]RoutingKitStatus](res.data['kits']) or {
		assert false, err.msg()
		return
	}
	assert kits.len == 3
	assert kits[0].id == 'live-call'
	assert kits[0].enabled
	assert kits[0].external
	assert kits[0].file.ends_with('60-reaper-music-studio.conf')

	assert kits[1].id == 'browser-backing'
	assert !kits[1].enabled
	assert !kits[1].external

	assert kits[2].id == 'reaper-low-latency'
	assert kits[2].enabled
	assert kits[2].external
	assert kits[2].file.ends_with('60-reaper-low-latency.conf')

	streams := json2.decode[[]AudioStreamInfo](res.data['streams']) or {
		assert false, err.msg()
		return
	}
	assert streams.len == 2
	assert streams[0].zero_volume_warning

	// Refuses to delete unmarked external file or duplicate it on enable.
	assert !studio_routing_enable_result('live-call', false, false, true).ok
	assert !studio_routing_disable_result('live-call', false, false, true).ok
	assert os.is_file('${root}/pw.conf.d/60-reaper-music-studio.conf')
}

fn test_routing_enable_disable_and_marker_protection() {
	root := routing_setup('enable-disable')
	defer {
		routing_teardown()
	}
	// Needs --yes unless --dry-run.
	assert !studio_routing_enable_result('live-call', false, false, false).ok
	dry := studio_routing_enable_result('live-call', false, true, false)
	assert dry.ok
	assert dry.data['dry_run'] == 'true'
	assert !os.is_file('${root}/pw.conf.d/70-hornero-routing-live-call.conf')

	// Enable live-call & reaper-low-latency.
	en := studio_routing_enable_result('live-call', false, false, true)
	assert en.ok
	assert en.data['pipewire_restarted'] == 'true'
	body := os.read_file('${root}/pw.conf.d/70-hornero-routing-live-call.conf') or { '' }
	assert body.contains(studio_routing_marker)
	assert body.contains('reaper_lesson_mic')
	assert body.contains('discord_call')
	assert body.contains('reaper_program')

	en_jack := studio_routing_enable_result('reaper-low-latency', true, false, true)
	assert en_jack.ok
	assert en_jack.data['pipewire_restarted'] == 'false'
	jack_body := os.read_file('${root}/jack.conf.d/70-hornero-routing-reaper-low-latency.conf') or {
		''
	}
	assert jack_body.contains(studio_routing_marker)
	assert jack_body.contains('node.latency = 256/48000')
	assert jack_body.contains('application.process.binary = "reaper"')

	// Disable live-call removes it and restarts PipeWire.
	dis := studio_routing_disable_result('live-call', false, false, true)
	assert dis.ok
	assert !os.is_file('${root}/pw.conf.d/70-hornero-routing-live-call.conf')
	sys_log := os.read_file('${root}/systemctl.log') or { '' }
	assert sys_log.contains('--user restart pipewire pipewire-pulse wireplumber')

	// Unmarked file at managed path is protected on both enable and disable.
	personal := '${root}/pw.conf.d/70-hornero-routing-browser-backing.conf'
	os.write_file(personal, '# personal file without hornero marker\n') or { assert false }
	assert !studio_routing_enable_result('browser-backing', true, false, true).ok
	assert !studio_routing_disable_result('browser-backing', true, false, true).ok
	assert os.is_file(personal)
}

fn test_routing_move_stream_and_fix_volume_dry_run_and_exec() {
	root := routing_setup('streams')
	defer {
		routing_teardown()
	}
	// Dry-run proves non-execution even with nonexistent pactl.
	os.setenv('HORNERO_PACTL_BIN', '/nonexistent-pactl-hornero-test', true)
	dry_move := studio_routing_move_stream_result('101', 'discord_call', true, false)
	assert dry_move.ok
	assert dry_move.data['dry_run'] == 'true'
	assert dry_move.data['command_line'].contains('move-sink-input 101 discord_call')

	dry_vol := studio_routing_fix_volume_result('101', 200, true, false)
	assert dry_vol.ok
	assert dry_vol.data['percent'] == '150'
	assert dry_vol.data['command_line'].contains('set-sink-input-mute 101 0')
	assert dry_vol.data['command_line'].contains('set-sink-input-volume 101 150%')

	// Real execution with mock pactl.
	os.setenv('HORNERO_PACTL_BIN', '${root}/bin/pactl', true)
	assert !studio_routing_move_stream_result('101', 'discord_call', false, false).ok
	mv := studio_routing_move_stream_result('101', 'discord_call', false, true)
	assert mv.ok
	fv := studio_routing_fix_volume_result('101', 100, false, true)
	assert fv.ok
	log := os.read_file('${root}/pactl.log') or { '' }
	assert log.contains('move-sink-input 101 discord_call')
	assert log.contains('set-sink-input-mute 101 0')
	assert log.contains('set-sink-input-volume 101 100%')
}
