module hornero_core

import os

const hx_input_root = '/tmp/hx-input-test'

fn input_test_setup() {
	os.mkdir_all(hx_input_root + '/bin') or { assert false }
	os.write_file(hx_input_root + '/bin/hyprctl', '#!/bin/sh\nprintf "%s\\n" "$*" >> ' +
		hx_input_root + '/calls\n' +
		'if [ "$1" = "getoption" ]; then\n' +
		'  case "$2" in\n' +
		'    input:sensitivity) echo \'{"float": 0.25}\' ;;\n' +
		'    input:accel_profile) echo \'{"str": "adaptive"}\' ;;\n' +
		'    input:repeat_rate) echo \'{"int": 40}\' ;;\n' +
		'    input:repeat_delay) echo \'{"int": 250}\' ;;\n' +
		'    input:touchpad:natural_scroll) echo \'{"int": 0}\' ;;\n' +
		'    input:touchpad:tap-to-click) echo \'{"int": 1}\' ;;\n' +
		'  esac\nfi\nexit 0\n') or { assert false }
	os.chmod(hx_input_root + '/bin/hyprctl', 0o755) or { assert false }
	os.rm(hx_input_root + '/calls') or {}
	os.setenv('HORNERO_HYPRCTL_BIN', hx_input_root + '/bin/hyprctl', true)
	os.setenv('HORNERO_HYPR_INPUT_STATE_FILE', hx_input_root + '/current', true)
	os.rm(hx_input_root + '/current') or {}
}

fn input_test_teardown() {
	os.unsetenv('HORNERO_HYPRCTL_BIN')
	os.unsetenv('HORNERO_HYPR_INPUT_STATE_FILE')
	os.rmdir_all(hx_input_root) or {}
}

fn test_input_settings_bounds() {
	assert input_settings_valid(InputSettings{})
	assert !input_settings_valid(InputSettings{ sensitivity: 1.5 })
	assert !input_settings_valid(InputSettings{ sensitivity: -1.5 })
	assert !input_settings_valid(InputSettings{ accel_profile: 'custom' })
	assert !input_settings_valid(InputSettings{ repeat_rate: 0 })
	assert !input_settings_valid(InputSettings{ repeat_rate: 500 })
	assert !input_settings_valid(InputSettings{ repeat_delay: 10 })
}

fn test_input_keyword_pairs_cover_all_settings() {
	pairs := input_keyword_pairs(InputSettings{
		sensitivity:    -0.5
		accel_profile:  'flat'
		repeat_rate:    30
		repeat_delay:   400
		natural_scroll: true
		tap_to_click:   false
	})
	joined := pairs.map('${it[0]}=${it[1]}').join(' ')
	assert joined.contains('input:sensitivity=-0.5')
	assert joined.contains('input:accel_profile=flat')
	assert joined.contains('input:repeat_rate=30')
	assert joined.contains('input:repeat_delay=400')
	assert joined.contains('input:touchpad:natural_scroll=true')
	assert joined.contains('input:touchpad:tap-to-click=false')
}

fn test_input_status_reads_live_values() {
	input_test_setup()
	rep := input_status_report()
	assert rep.ok, rep.message
	assert rep.data['sensitivity'] == '0.25'
	assert rep.data['accel_profile'] == 'adaptive'
	assert rep.data['repeat_rate'] == '40'
	assert rep.data['repeat_delay'] == '250'
	assert rep.data['natural_scroll'] == 'false'
	assert rep.data['tap_to_click'] == 'true'
	assert rep.data['compositor'] == 'hyprland'
	input_test_teardown()
}

fn test_input_apply_persists_and_calls_keywords() {
	input_test_setup()
	rep := input_apply_report(InputApplyOptions{
		settings: InputSettings{
			sensitivity:    0.5
			accel_profile:  'flat'
			repeat_rate:    50
			repeat_delay:   300
			natural_scroll: true
			tap_to_click:   true
		}
		yes:      true
	})
	assert rep.ok, rep.message
	calls := os.read_file(hx_input_root + '/calls') or { '' }
	assert calls.contains('keyword input:sensitivity 0.5')
	assert calls.contains('keyword input:touchpad:natural_scroll true')
	saved := input_persisted()
	assert saved.sensitivity == 0.5 && saved.repeat_rate == 50 && saved.natural_scroll
	input_test_teardown()
}

fn test_input_apply_needs_yes_and_validates() {
	input_test_setup()
	rep := input_apply_report(InputApplyOptions{
		settings: InputSettings{}
	})
	assert !rep.ok
	assert rep.message.contains('--yes')
	bad := input_apply_report(InputApplyOptions{
		settings: InputSettings{ sensitivity: 9.0 }
		yes:      true
	})
	assert !bad.ok
	input_test_teardown()
}

fn test_input_apply_dry_run_previews_without_persisting() {
	input_test_setup()
	rep := input_apply_report(InputApplyOptions{
		settings: InputSettings{ sensitivity: 0.1 }
		dry_run:  true
	})
	assert rep.ok, rep.message
	assert rep.message.contains('keyword input:sensitivity 0.1')
	assert !os.is_file(hx_input_root + '/current')
	input_test_teardown()
}
