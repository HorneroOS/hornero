module hornero_core

import os

// Studio low-latency profile tests. PipeWire is faked with a stateful
// pw-metadata and a canned pw-top; all paths live under a temp root and
// the real ~/.config is never touched.

const audio_test_root = '/tmp/hx-studio-audio-test'

const pw_top_sample = 'S   ID  QUANT   RATE    WAIT    BUSY   W/Q   B/Q  ERR FORMAT           NAME
C   32      0      0    ---     ---   ---   ---     0                  Dummy-Driver
S   41      0      0    ---     ---   ---   ---     0                  idle_node
S   41      0      0    ---     ---   ---   ---     0                  idle_node
S   ID  QUANT   RATE    WAIT    BUSY   W/Q   B/Q  ERR FORMAT           NAME
R   50    128  48000   10.0us  60.0us  0.01  0.04     0  S32LE 2 48000  alsa_output.usb-interface
R   51    128  48000   5.0us   9.0us  0.00  0.01     3  S16LE 2 48000  reaper
'

fn audio_setup(tag string, with_pw bool) string {
	root := '${audio_test_root}/${tag}'
	if os.exists(root) {
		os.rmdir_all(root) or {}
	}
	os.mkdir_all(root) or { assert false }
	state := '${root}/pw-state.txt'
	os.write_file(state, "update: id:0 key:'clock.rate' value:'48000' type:''\nupdate: id:0 key:'clock.quantum' value:'1024' type:''\nupdate: id:0 key:'clock.min-quantum' value:'32' type:''\nupdate: id:0 key:'clock.max-quantum' value:'2048' type:''\nupdate: id:0 key:'clock.force-quantum' value:'0' type:''\n") or {
		assert false
	}
	meta := '#!/bin/sh\nS="${state}"\nif [ "\$#" -ge 5 ]; then\n  grep -v "key:\'\$4\'" "\$S" > "\$S.n"\n  printf "update: id:0 key:\'%s\' value:\'%s\' type:\'\'\\n" "\$4" "\$5" >> "\$S.n"\n  mv "\$S.n" "\$S"\nelse\n  echo \'Found "settings" metadata 34\'\n  cat "\$S"\nfi\n'
	os.write_file('${root}/pw-metadata', meta) or { assert false }
	os.chmod('${root}/pw-metadata', 0o755) or {}
	os.write_file('${root}/pw-top-out.txt', pw_top_sample) or { assert false }
	os.write_file('${root}/pw-top', '#!/bin/sh\ncat "${root}/pw-top-out.txt"\n') or { assert false }
	os.chmod('${root}/pw-top', 0o755) or {}
	if with_pw {
		os.setenv('HORNERO_PW_METADATA_BIN', '${root}/pw-metadata', true)
		os.setenv('HORNERO_PW_TOP_BIN', '${root}/pw-top', true)
	} else {
		os.setenv('HORNERO_PW_METADATA_BIN', '${root}/no-such-bin', true)
		os.setenv('HORNERO_PW_TOP_BIN', '${root}/no-such-bin', true)
	}
	os.setenv('HORNERO_PIPEWIRE_CONF_DIR', '${root}/conf.d', true)
	os.setenv('HORNERO_STUDIO_AUDIO_APPLIED_FILE', '${root}/applied.txt', true)
	os.setenv('HORNERO_STUDIO_MODE_FILE', '${root}/studio-mode.json', true)
	return root
}

fn audio_teardown() {
	for k in ['HORNERO_PW_METADATA_BIN', 'HORNERO_PW_TOP_BIN', 'HORNERO_PIPEWIRE_CONF_DIR',
		'HORNERO_STUDIO_AUDIO_APPLIED_FILE', 'HORNERO_STUDIO_MODE_FILE'] {
		os.unsetenv(k)
	}
}

fn test_parse_pw_settings_reads_keys_and_values() {
	s := parse_pw_settings("update: id:0 key:'clock.quantum' value:'1024' type:''\nnoise\nupdate: id:0 key:'clock.rate' value:'48000' type:''\n")
	assert s['clock.quantum'] == '1024'
	assert s['clock.rate'] == '48000'
	assert s.len == 2
}

fn test_parse_pw_top_uses_last_iteration_and_counts_xruns() {
	rows := parse_pw_top(pw_top_sample)
	assert rows.len == 2
	load := summarise_pw_top(rows)
	assert load.active == 2
	assert load.max_quant == 128
	assert load.xruns == 3
	assert load.xrun_node == 'reaper'
	assert load.max_b_q > 0.03 && load.max_b_q < 0.05
	assert parse_pw_top('garbage\n').len == 0
}

fn test_dropin_content_matches_the_config_template_values() {
	c := studio_lowlat_dropin_content()
	assert c.contains(studio_lowlat_marker)
	assert c.contains('default.clock.rate = 48000')
	assert c.contains('default.clock.quantum = 128')
	assert c.contains('default.clock.min-quantum = 64')
	assert c.contains('default.clock.max-quantum = 256')
	// No privilege, kernel or governor tuning, ever.
	for bad in ['rtprio', 'nice', 'governor', 'irq', 'sudo'] {
		assert !c.to_lower().contains(bad)
	}
}

fn test_apply_needs_yes_and_dry_run_changes_nothing() {
	root := audio_setup('dry', true)
	defer {
		audio_teardown()
	}
	assert !studio_audio_apply_result(false, false).ok
	dry := studio_audio_apply_result(false, true)
	assert dry.ok
	assert dry.data['dry_run'] == 'true'
	assert !os.exists('${root}/conf.d')
	assert read_pw_runtime().settings['clock.quantum'] == '1024'
}

fn test_apply_then_revert_restores_exact_previous_state() {
	root := audio_setup('cycle', true)
	defer {
		audio_teardown()
	}
	res := studio_audio_apply_result(true, false)
	assert res.ok
	assert res.data['runtime_applied'] == 'true'
	assert os.is_file('${root}/conf.d/${studio_lowlat_dropin_name}')
	live := read_pw_runtime().settings
	assert live['clock.quantum'] == '128'
	assert live['clock.min-quantum'] == '64'
	assert live['clock.max-quantum'] == '256'
	assert studio_audio_status_result().data['dropin'] == 'applied'
	// A second apply keeps the original restore target.
	assert studio_audio_apply_result(true, false).ok
	assert applied_decode(os.read_file('${root}/applied.txt') or { '' })['clock.quantum'] == '1024'
	mode := studio_mode_show_result()
	assert mode.data['audio_mode'] == 'low-latency'
	rev := studio_audio_revert_result()
	assert rev.ok
	assert !os.exists('${root}/conf.d/${studio_lowlat_dropin_name}')
	back := read_pw_runtime().settings
	assert back['clock.quantum'] == '1024'
	assert back['clock.min-quantum'] == '32'
	assert back['clock.max-quantum'] == '2048'
	assert studio_mode_show_result().data['audio_mode'] == 'balanced'
	// Reverting again is a successful no-op.
	assert studio_audio_revert_result().ok
}

fn test_apply_never_overwrites_a_personal_file_and_revert_leaves_it() {
	root := audio_setup('foreign', true)
	defer {
		audio_teardown()
	}
	os.mkdir_all('${root}/conf.d') or { assert false }
	path := '${root}/conf.d/${studio_lowlat_dropin_name}'
	os.write_file(path, 'context.properties = { default.clock.quantum = 32 }\n') or { assert false }
	assert !studio_audio_apply_result(true, false).ok
	assert !studio_audio_revert_result().ok
	assert (os.read_file(path) or { '' }).contains('quantum = 32')
	assert read_pw_runtime().settings['clock.quantum'] == '1024'
}

fn test_without_pipewire_tools_states_are_honest() {
	root := audio_setup('nopw', false)
	defer {
		audio_teardown()
	}
	st := studio_audio_status_result()
	assert st.ok
	assert st.data['runtime'] == 'unavailable'
	assert st.data['xruns'] == 'unavailable'
	assert st.message.contains('unavailable')
	res := studio_audio_apply_result(true, false)
	assert res.ok
	assert res.data['runtime_applied'] == 'false'
	assert res.message.contains('drop-in only')
	assert os.is_file('${root}/conf.d/${studio_lowlat_dropin_name}')
	assert studio_audio_revert_result().ok
	assert !os.exists('${root}/conf.d/${studio_lowlat_dropin_name}')
}

fn test_status_reports_xruns_and_load_from_pw_top() {
	audio_setup('status', true)
	defer {
		audio_teardown()
	}
	st := studio_audio_status_result()
	assert st.data['xruns'] == '3'
	assert st.message.contains('not physical round-trip latency')
}
