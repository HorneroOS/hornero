module hornero_core

import os

const hx_layout_root = '/tmp/hx-layout-set-test'

const hx_evdev_fixture = '<?xml version="1.0"?>
<xkbConfigRegistry>
  <layoutList>
    <layout>
      <configItem>
        <name>us</name>
        <description>English (US)</description>
      </configItem>
      <variantList>
        <variant>
          <configItem>
            <name>intl</name>
            <description>English (US, intl., with dead keys)</description>
          </configItem>
        </variant>
      </variantList>
    </layout>
    <layout>
      <configItem>
        <name>latam</name>
        <description>Spanish (Latin American)</description>
      </configItem>
    </layout>
  </layoutList>
</xkbConfigRegistry>
'

fn layout_test_setup() {
	os.mkdir_all(hx_layout_root + '/bin') or { assert false }
	os.mkdir_all(hx_layout_root + '/config') or { assert false }
	os.write_file(hx_layout_root + '/bin/hyprctl', '#!/bin/sh\nprintf "%s\\n" "$*" >> ' +
		hx_layout_root + '/calls\necho \'{"str":"us"}\'\nexit 0\n') or { assert false }
	os.chmod(hx_layout_root + '/bin/hyprctl', 0o755) or { assert false }
	os.rm(hx_layout_root + '/calls') or {}
	os.write_file(hx_layout_root + '/evdev.xml', hx_evdev_fixture) or { assert false }
	os.setenv('HORNERO_HYPRCTL_BIN', hx_layout_root + '/bin/hyprctl', true)
	os.setenv('XDG_CONFIG_HOME', hx_layout_root + '/config', true)
	os.setenv('HYPRLAND_INSTANCE_SIGNATURE', 'fixture', true)
	os.setenv('HORNERO_XKB_RULES_FILE', hx_layout_root + '/evdev.xml', true)
	os.setenv('HORNERO_KEYBOARD_LAYOUT_STATE_FILE', hx_layout_root + '/state', true)
	os.setenv('HORNERO_NOTIFY_BIN', '/nonexistent-notify-test', true)
	os.unsetenv('WAYLAND_DISPLAY')
	os.unsetenv('I3SOCK')
}

fn layout_test_teardown() {
	for k in ['HORNERO_HYPRCTL_BIN', 'XDG_CONFIG_HOME', 'HYPRLAND_INSTANCE_SIGNATURE',
		'HORNERO_XKB_RULES_FILE', 'HORNERO_KEYBOARD_LAYOUT_STATE_FILE', 'HORNERO_NOTIFY_BIN'] {
		os.unsetenv(k)
	}
	os.rmdir_all(hx_layout_root) or {}
}

fn test_layout_list_parses_evdev() {
	entries := parse_xkb_layouts(hx_evdev_fixture)
	assert entries.len == 2
	assert entries[0].name == 'us'
	assert entries[0].description == 'English (US)'
	assert entries[0].variants == ['intl']
	assert entries[1].name == 'latam'
	assert entries[1].variants.len == 0
	layout_test_setup()
	rep := keyboard_layout_list_report(false)
	assert rep.ok, rep.message
	assert rep.message.contains('us')
	assert rep.data['count'] == '2'
	layout_test_teardown()
}

fn test_layout_set_applies_and_persists() {
	layout_test_setup()
	rep := keyboard_layout_set_report(LayoutSetOptions{
		layouts: 'us,latam'
		variant: 'intl,'
		yes:     true
	})
	assert rep.ok, rep.message
	calls := os.read_file(hx_layout_root + '/calls') or { '' }
	assert calls.contains('keyword input:kb_layout us,latam')
	assert calls.contains('keyword input:kb_variant intl,')
	state := os.read_file(hx_layout_root + '/state') or { '' }
	assert state.contains('layout=us,latam')
	layout_test_teardown()
}

fn test_layout_set_rejects_bad_input() {
	layout_test_setup()
	bad := keyboard_layout_set_report(LayoutSetOptions{
		layouts: 'us;rm -rf'
		yes:     true
	})
	assert !bad.ok
	bad_variant_count := keyboard_layout_set_report(LayoutSetOptions{
		layouts: 'us,latam'
		variant: 'a,b,c'
		yes:     true
	})
	assert !bad_variant_count.ok
	no_yes := keyboard_layout_set_report(LayoutSetOptions{
		layouts: 'us'
	})
	assert !no_yes.ok
	assert !os.is_file(hx_layout_root + '/state')
	dry := keyboard_layout_set_report(LayoutSetOptions{
		layouts: 'es'
		dry_run: true
	})
	assert dry.ok, dry.message
	assert !os.is_file(hx_layout_root + '/state')
	layout_test_teardown()
}
