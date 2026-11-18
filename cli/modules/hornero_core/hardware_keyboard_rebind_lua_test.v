module hornero_core

import os

const hx_lua_rebind_root = os.join_path(os.temp_dir(), 'hx-rebind-lua-test')

const hx_lua_keybindings = '-- ============================================================================
-- Essential Applications
-- ============================================================================
hl.bind("SUPER + Return", hl.dsp.exec_cmd("exo-open --launch TerminalEmulator"))
hl.bind("SUPER + slash", hl.dsp.exec_cmd("horneroctl hardware keyboard keys"))
-- ============================================================================
-- Focus Movement (Vim-like)
-- ============================================================================
hl.bind("SUPER + K", hl.dsp.focus({ direction = "up" }))
hl.bind("SUPER + J", hl.dsp.focus({ direction = "down" }))
hl.bind("SUPER + O", hl.dsp.exec_cmd("hyprctl dispatch scrolloverview:overview, toggle"))
-- ============================================================================
-- Window Resizing
-- ============================================================================
hl.bind("SUPER + R", hl.dsp.submap("resize"))
hl.define_submap("resize", function()
	hl.bind("escape", hl.dsp.submap("reset"))
end)
'

const hx_lua_user = '-- personal
hl.unbind("SUPER + O")
hl.bind("SUPER + O", hl.dsp.exec_cmd("horneroctl apps toggle dashboard --yes"))
'

// hyprctl binds -j as Hyprland 0.57 reports a Lua session: modmask 64
// is SUPER; the plugin bind (SUPER + Tab) is not in any config file.
const hx_lua_live = '[
{"modmask":64,"submap":"","key":"Return","dispatcher":"HL.Dispatcher(exec_cmd)","mouse":false},
{"modmask":64,"submap":"","key":"slash","dispatcher":"HL.Dispatcher(exec_cmd)","mouse":false},
{"modmask":64,"submap":"","key":"K","dispatcher":"HL.Dispatcher(focus)","mouse":false},
{"modmask":64,"submap":"","key":"J","dispatcher":"HL.Dispatcher(focus)","mouse":false},
{"modmask":64,"submap":"","key":"O","dispatcher":"HL.Dispatcher(exec_cmd)","mouse":false},
{"modmask":64,"submap":"","key":"R","dispatcher":"HL.Dispatcher(submap)","mouse":false},
{"modmask":0,"submap":"resize","key":"escape","dispatcher":"HL.Dispatcher(submap)","mouse":false},
{"modmask":64,"submap":"","key":"Tab","dispatcher":"function: 0x55","mouse":false}
]'

fn lua_rebind_setup() {
	root := hx_lua_rebind_root
	os.rmdir_all(root) or {}
	os.mkdir_all(root + '/bin') or { assert false }
	os.mkdir_all(root + '/config/hypr') or { assert false }
	os.write_file(root + '/config/hypr/hyprland.lua', '-- lua session marker\n') or {
		assert false
	}
	os.write_file(root + '/live.json', hx_lua_live) or { assert false }
	os.write_file(root + '/bin/hyprctl', '#!/bin/sh\nif [ "\$1" = binds ]; then cat ' + root +
		'/live.json; exit 0; fi\nprintf "%s\\n" "\$*" >> ' + root + '/calls\nexit 0\n') or {
		assert false
	}
	os.chmod(root + '/bin/hyprctl', 0o755) or { assert false }
	os.write_file(root + '/keybindings.lua', hx_lua_keybindings) or { assert false }
	os.write_file(root + '/keybindings-user.lua', hx_lua_user) or { assert false }
	os.setenv('XDG_CONFIG_HOME', root + '/config', true)
	os.setenv('XDG_STATE_HOME', root + '/state', true)
	os.setenv('HORNERO_HYPRCTL_BIN', root + '/bin/hyprctl', true)
	os.setenv('HORNERO_KEYBINDINGS_FILE', root + '/keybindings.lua', true)
	os.setenv('HORNERO_KEYBINDINGS_USER_LUA_FILE', root + '/keybindings-user.lua', true)
	os.unsetenv('HORNERO_KEYBINDS_OVERLAY_FILE')
	os.unsetenv('HORNERO_KEYBINDS_UNDO_DIR')
	os.unsetenv('HORNERO_KEYBINDS_NO_LIVE')
	os.unsetenv('HORNERO_KEYBINDS_NO_RELOAD')
}

fn lua_rebind_teardown() {
	for k in ['XDG_CONFIG_HOME', 'XDG_STATE_HOME', 'HORNERO_HYPRCTL_BIN', 'HORNERO_KEYBINDINGS_FILE',
		'HORNERO_KEYBINDINGS_USER_LUA_FILE', 'HORNERO_KEYBINDS_NO_LIVE'] {
		os.unsetenv(k)
	}
	os.rmdir_all(hx_lua_rebind_root) or {}
}

fn lua_overlay_text() string {
	return os.read_file(hx_lua_rebind_root + '/config/hypr/hornero-keybinds.lua') or { '' }
}

fn test_lua_canonical_combo_matches_loader() {
	assert canonical_combo('SUPER + CTRL + T') == canonical_combo('control + super + t')
	assert canonical_combo('SUPER + Return') == 'SUPER + return'
	assert canonical_combo('\$mainMod + slash') == canonical_combo('SUPER+slash')
	assert canonical_combo('') == ''
	assert modmask_mods(64 + 4 + 1) == 'CTRL + SHIFT + SUPER'
}

fn test_lua_overlay_render_parse_roundtrip() {
	remaps := [KeybindRemap{
		from: 'SUPER + Return'
		to:   'SUPER + X'
	}, KeybindRemap{
		from: 'SUPER + K'
		to:   ''
	}]
	text := render_keybinds_overlay(remaps)
	assert text.contains('return {')
	back := parse_keybinds_overlay(text)
	assert back.len == 2
	assert back[0].from == 'SUPER + Return' && back[0].to == 'SUPER + X'
	assert back[1].to == ''
}

fn test_lua_list_merges_live_binds_with_config_metadata() {
	lua_rebind_setup()
	defer {
		lua_rebind_teardown()
	}
	entries, live := keybind_entries()
	assert live
	assert entries.len == 8
	term := entries.filter(it.combo == 'SUPER + Return')[0]
	assert term.category == 'Essential Applications'
	assert term.action.contains('TerminalEmulator')
	assert term.dispatcher == 'exec_cmd'
	// keybindings-user.lua wins on SUPER + O.
	o := entries.filter(it.combo == 'SUPER + O')[0]
	assert o.source == 'personal'
	assert o.action.contains('dashboard')
	esc := entries.filter(it.submap == 'resize')[0]
	assert esc.combo == 'escape' && esc.category == 'Window Resizing'
	plugin := entries.filter(it.combo == 'SUPER + Tab')[0]
	assert plugin.source == 'live' && plugin.category == 'Other'
	res := keyboard_rebind_list_report()
	assert res.ok
	assert res.data['live'] == 'true'
	assert res.data['entries'].starts_with('[{"combo":')
}

fn test_lua_set_writes_overlay_reloads_and_undoes() {
	lua_rebind_setup()
	defer {
		lua_rebind_teardown()
	}
	status := keyboard_rebind_status_report()
	assert status.data['managed'] == 'true'
	assert status.data['overrides'] == '0'
	dry := keyboard_rebind_set_report(RebindSetOptions{
		old_combo: 'SUPER + Return'
		new_combo: 'SUPER + X'
		dry_run:   true
	})
	assert dry.ok
	assert lua_overlay_text() == ''
	no_yes := keyboard_rebind_set_report(RebindSetOptions{
		old_combo: 'SUPER + Return'
		new_combo: 'SUPER + X'
	})
	assert !no_yes.ok
	res := keyboard_rebind_set_report(RebindSetOptions{
		old_combo: 'SUPER + Return'
		new_combo: 'SUPER + X'
		yes:       true
	})
	assert res.ok, res.message
	assert lua_overlay_text().contains('{ from = "SUPER + Return", to = "SUPER + X" }')
	calls := os.read_file(hx_lua_rebind_root + '/calls') or { '' }
	assert calls.contains('reload')
	assert res.data['undo'] == '1'
	// The source view (no compositor) now shows the moved bind.
	os.setenv('HORNERO_KEYBINDS_NO_LIVE', '1', true)
	entries, live := keybind_entries()
	assert !live
	moved := entries.filter(it.combo == 'SUPER + X')
	assert moved.len == 1 && moved[0].remapped && moved[0].original == 'SUPER + Return'
	// Moving it back to the factory combo removes the remap entirely.
	back := keyboard_rebind_set_report(RebindSetOptions{
		old_combo: 'SUPER + X'
		new_combo: 'SUPER + Return'
		yes:       true
	})
	assert back.ok, back.message
	assert parse_keybinds_overlay(lua_overlay_text()).len == 0
	// Undo twice walks back through both writes.
	u1 := keyboard_rebind_undo_report(false, true)
	assert u1.ok, u1.message
	assert parse_keybinds_overlay(lua_overlay_text()).len == 1
	u2 := keyboard_rebind_undo_report(false, true)
	assert u2.ok
	assert parse_keybinds_overlay(lua_overlay_text()).len == 0
	assert !keyboard_rebind_undo_report(false, true).ok
}

fn test_lua_set_refuses_conflicts_and_swaps() {
	lua_rebind_setup()
	defer {
		lua_rebind_teardown()
	}
	os.setenv('HORNERO_KEYBINDS_NO_LIVE', '1', true)
	clash := keyboard_rebind_set_report(RebindSetOptions{
		old_combo: 'SUPER + K'
		new_combo: 'super + j'
		yes:       true
	})
	assert !clash.ok
	assert clash.data['conflict'] == 'SUPER + J'
	assert clash.data['conflict_category'] == 'Focus Movement (Vim-like)'
	assert clash.message.contains('--swap')
	assert lua_overlay_text() == ''
	swap := keyboard_rebind_set_report(RebindSetOptions{
		old_combo: 'SUPER + K'
		new_combo: 'SUPER + J'
		swap:      true
		yes:       true
	})
	assert swap.ok, swap.message
	assert swap.data['swap'] == 'true'
	remaps := parse_keybinds_overlay(lua_overlay_text())
	assert remaps.len == 2
	entries, _ := keybind_entries()
	up := entries.filter(it.action.contains('"up"'))[0]
	down := entries.filter(it.action.contains('"down"'))[0]
	assert up.combo == 'SUPER + J' && down.combo == 'SUPER + K'
	// A plugin-held combo cannot be taken.
	os.unsetenv('HORNERO_KEYBINDS_NO_LIVE')
	plugin := keyboard_rebind_set_report(RebindSetOptions{
		old_combo: 'SUPER + slash'
		new_combo: 'SUPER + Tab'
		swap:      true
		yes:       true
	})
	assert !plugin.ok
	unknown := keyboard_rebind_set_report(RebindSetOptions{
		old_combo: 'SUPER + F12'
		new_combo: 'SUPER + F11'
		yes:       true
	})
	assert !unknown.ok
}

fn test_lua_disable_reset_and_keys_view() {
	lua_rebind_setup()
	defer {
		lua_rebind_teardown()
	}
	os.setenv('HORNERO_KEYBINDS_NO_LIVE', '1', true)
	off := keyboard_rebind_set_report(RebindSetOptions{
		old_combo: 'SUPER + K'
		new_combo: 'none'
		yes:       true
	})
	assert off.ok, off.message
	assert lua_overlay_text().contains('to = ""')
	moved := keyboard_rebind_set_report(RebindSetOptions{
		old_combo: 'SUPER + slash'
		new_combo: 'SUPER + F1'
		yes:       true
	})
	assert moved.ok
	os.setenv('HORNERO_BYPASS_QUICKSHELL', '1', true)
	keys := keyboard_keys_report(KeyboardKeysOptions{})
	os.unsetenv('HORNERO_BYPASS_QUICKSHELL')
	assert keys.ok
	assert keys.message.contains('SUPER + F1 -> ')
	assert !keys.message.contains('SUPER + K -> ')
	assert !keyboard_rebind_reset_report(false, false).ok
	reset := keyboard_rebind_reset_report(false, true)
	assert reset.ok
	assert parse_keybinds_overlay(lua_overlay_text()).len == 0
	assert keyboard_rebind_undo_report(false, true).ok
	assert parse_keybinds_overlay(lua_overlay_text()).len == 2
}
