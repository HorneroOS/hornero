module hornero_core

import os

const extras_root = '/tmp/hx-gaming-extras-test'

fn test_map_count_floor() {
	assert map_count_check(1048576).ok
	assert map_count_check(2147483642).ok
	bad := map_count_check(65530)
	assert !bad.ok
	assert bad.detail.contains('doctor does not change it')
	unreadable := map_count_check(0)
	assert unreadable.ok && unreadable.warn
}

fn test_nvidia_modeset_only_matters_when_the_module_is_loaded() {
	assert nvidia_modeset_check(false, '').ok
	assert nvidia_modeset_check(true, 'Y\n').ok
	assert !nvidia_modeset_check(true, 'N').ok
	assert !nvidia_modeset_check(true, '').ok
	assert lib32_driver_check(false, false).ok
	assert lib32_driver_check(true, true).ok
	assert !lib32_driver_check(true, false).ok
}

fn test_proton_builds_scan_and_wording() {
	if os.exists(extras_root) {
		os.rmdir_all(extras_root) or {}
	}
	common := '${extras_root}/steamapps/common'
	compat := '${extras_root}/compatibilitytools.d'
	os.mkdir_all('${common}/Proton 9.0') or { assert false }
	os.mkdir_all('${common}/Not A Tool') or { assert false }
	os.mkdir_all('${compat}/GE-Proton9-27') or { assert false }
	os.write_file('${compat}/stray-file', 'x') or { assert false }
	builds := proton_builds([common], [compat])
	assert builds == ['GE-Proton9-27', 'Proton 9.0']
	ok := proton_check(true, builds)
	assert ok.ok && !ok.warn
	assert ok.detail.contains('not a per-game compatibility claim')
	missing := proton_check(true, [])
	assert missing.ok && missing.warn
	assert proton_check(false, []).warn
	os.rmdir_all(extras_root) or {}
}

fn test_launch_options_use_only_installed_tools() {
	all := {
		'gamemode':  true
		'mangohud':  true
		'gamescope': true
	}
	opts, notes := steam_launch_options(LaunchOptionsRequest{
		gamemode: true
	}, all)
	assert opts == 'gamemoderun %command%'
	assert notes.len == 0
	full, _ := steam_launch_options(LaunchOptionsRequest{
		gamemode:   true
		mangohud:   true
		gamescope:  true
		width:      2560
		height:     1440
		refresh:    144
		fullscreen: true
	}, all)
	assert full == 'gamescope -W 2560 -H 1440 -r 144 -f -- gamemoderun mangohud %command%'
	// Missing tools are omitted and reported, never silently invented.
	partial, pnotes := steam_launch_options(LaunchOptionsRequest{
		gamemode:  true
		mangohud:  true
		gamescope: true
	}, {
		'gamemode': true
	})
	assert partial == 'gamemoderun %command%'
	assert pnotes.len == 2
	bare, _ := steam_launch_options(LaunchOptionsRequest{}, all)
	assert bare == '%command%'
}

fn test_optional_tool_missing_is_a_warning_not_a_failure() {
	c := optional_bin_check('nothing', 'definitely-not-a-real-binary-hx', 'because')
	assert c.ok
	assert c.warn
	assert c.detail.contains('optional')
}

fn test_doctor_data_distinguishes_warn_from_ok_and_fail() {
	res := gaming_doctor_result()
	for _, v in res.data {
		assert v in ['ok', 'warn', 'fail']
	}
	assert 'vm-max-map-count' in res.data
	assert 'proton' in res.data
	assert 'gamemode-libs' in res.data
}
