module hornero_core

import os
import x.json2

// Studio Live Routing Kits & Stream Routing (`horneroctl studio routing`).
//
// Manages opt-in, reversible PipeWire/JACK virtual routing drop-ins marked
// with `# Managed by horneroctl studio routing` so personal user dotfiles
// are never overwritten or deleted, and provides live stream routing and
// volume recovery via `pactl`.

pub const studio_routing_marker = '# Managed by horneroctl studio routing'

pub const studio_routing_kit_ids = ['live-call', 'browser-backing', 'reaper-low-latency']

pub struct RoutingKitSpec {
pub:
	id            string
	name          string
	description   string
	is_jack       bool
	managed_file  string
	external_file string
}

pub struct RoutingKitStatus {
pub:
	id          string
	name        string
	description string
	enabled     bool
	external    bool
	file        string
}

pub struct AudioStreamInfo {
pub:
	id                  string
	app                 string
	media_name          string
	sink                string
	volume_pct          int
	muted               bool
	zero_volume_warning bool
}

pub struct AudioDeviceInfo {
pub:
	index       string
	name        string
	description string
	is_default  bool
}

pub struct AudioSinkJson {
pub:
	name        string
	description string
	is_default  bool
}

pub fn resolve_pactl_bin() string {
	return leaf_bin('HORNERO_PACTL_BIN', 'pactl')
}

pub fn resolve_pw_link_bin() string {
	return leaf_bin('HORNERO_PW_LINK_BIN', 'pw-link')
}

pub fn studio_jack_dropin_dir() string {
	override := os.getenv('HORNERO_JACK_CONF_DIR')
	if override.len > 0 {
		return override
	}
	return os.join_path(resolve_paths().config_dir, 'pipewire', 'jack.conf.d')
}

pub fn studio_routing_kits() []RoutingKitSpec {
	return [
		RoutingKitSpec{
			id:            'live-call'
			name:          'Live Call (REAPER + Discord)'
			description:   'Virtual Audio/Source (REAPER Lesson Mic) and virtual Audio/Sinks (Discord Call, REAPER Program)'
			is_jack:       false
			managed_file:  '70-hornero-routing-live-call.conf'
			external_file: '60-reaper-music-studio.conf'
		},
		RoutingKitSpec{
			id:            'browser-backing'
			name:          'Browser Backing (Browser -> DAW)'
			description:   'Virtual Audio/Sink (Browser Backing) for routing browser audio into a DAW'
			is_jack:       false
			managed_file:  '70-hornero-routing-browser-backing.conf'
			external_file: '65-browser-backing.conf'
		},
		RoutingKitSpec{
			id:            'reaper-low-latency'
			name:          'REAPER Low Latency (JACK)'
			description:   'Sets node.latency = 256/48000 only for REAPER JACK clients'
			is_jack:       true
			managed_file:  '70-hornero-routing-reaper-low-latency.conf'
			external_file: '60-reaper-low-latency.conf'
		},
	]
}

pub fn studio_routing_kit_by_id(id string) ?RoutingKitSpec {
	for k in studio_routing_kits() {
		if k.id == id {
			return k
		}
	}
	return none
}

fn studio_routing_kit_dir(spec RoutingKitSpec) string {
	return if spec.is_jack { studio_jack_dropin_dir() } else { studio_pipewire_dropin_dir() }
}

pub fn studio_routing_kit_content(id string) string {
	return match id {
		'live-call' {
			[
				studio_routing_marker,
				'# Virtual routing devices for live lessons/calls between REAPER and Discord.',
				'# Uses libpipewire-module-adapter with support.null-audio-sink.',
				'context.objects = [',
				'    { factory = adapter',
				'        args = {',
				'            factory.name     = support.null-audio-sink',
				'            node.name        = "reaper_lesson_mic"',
				'            node.description = "REAPER Lesson Mic"',
				'            media.class      = Audio/Source/Virtual',
				'            audio.position   = [ FL FR ]',
				'            object.linger    = true',
				'            monitor.channel-volumes = true',
				'        }',
				'    }',
				'    { factory = adapter',
				'        args = {',
				'            factory.name     = support.null-audio-sink',
				'            node.name        = "discord_call"',
				'            node.description = "Discord Call"',
				'            media.class      = Audio/Sink',
				'            audio.position   = [ FL FR ]',
				'            object.linger    = true',
				'            monitor.channel-volumes = true',
				'        }',
				'    }',
				'    { factory = adapter',
				'        args = {',
				'            factory.name     = support.null-audio-sink',
				'            node.name        = "reaper_program"',
				'            node.description = "REAPER Program"',
				'            media.class      = Audio/Sink',
				'            audio.position   = [ FL FR ]',
				'            object.linger    = true',
				'            monitor.channel-volumes = true',
				'        }',
				'    }',
				']',
				'',
			].join('\n')
		}
		'browser-backing' {
			[
				studio_routing_marker,
				'# Virtual sink for routing browser playback into a DAW.',
				'# Uses libpipewire-module-adapter with support.null-audio-sink.',
				'context.objects = [',
				'    { factory = adapter',
				'        args = {',
				'            factory.name     = support.null-audio-sink',
				'            node.name        = "browser_backing"',
				'            node.description = "Browser Backing (Browser -> DAW)"',
				'            media.class      = Audio/Sink',
				'            audio.position   = [ FL FR ]',
				'            object.linger    = true',
				'            monitor.channel-volumes = true',
				'        }',
				'    }',
				']',
				'',
			].join('\n')
		}
		'reaper-low-latency' {
			[
				studio_routing_marker,
				'# Per-app PipeWire JACK latency rule for REAPER.',
				'jack.rules = [',
				'    {',
				'        matches = [',
				'            {',
				'                application.process.binary = "reaper"',
				'            }',
				'        ]',
				'        actions = {',
				'            update-props = {',
				'                node.latency = 256/48000',
				'            }',
				'        }',
				'    }',
				']',
				'',
			].join('\n')
		}
		else {
			''
		}
	}
}

fn routing_file_is_managed(path string) bool {
	body := os.read_file(path) or { return false }
	return body.contains(studio_routing_marker)
}

pub fn read_routing_kit_status(spec RoutingKitSpec) RoutingKitStatus {
	dir := studio_routing_kit_dir(spec)
	managed_path := os.join_path(dir, spec.managed_file)
	external_path := os.join_path(dir, spec.external_file)
	if os.is_file(managed_path) {
		is_managed := routing_file_is_managed(managed_path)
		return RoutingKitStatus{
			id:          spec.id
			name:        spec.name
			description: spec.description
			enabled:     true
			external:    !is_managed
			file:        managed_path
		}
	}
	if spec.external_file.len > 0 && os.is_file(external_path) {
		return RoutingKitStatus{
			id:          spec.id
			name:        spec.name
			description: spec.description
			enabled:     true
			external:    true
			file:        external_path
		}
	}
	return RoutingKitStatus{
		id:          spec.id
		name:        spec.name
		description: spec.description
		enabled:     false
		external:    false
		file:        managed_path
	}
}

pub fn read_all_routing_kits() []RoutingKitStatus {
	mut out := []RoutingKitStatus{}
	for spec in studio_routing_kits() {
		out << read_routing_kit_status(spec)
	}
	return out
}

// parse_pactl_info extracts Default Sink and Default Source from `pactl info`.
pub fn parse_pactl_info(raw string) (string, string) {
	mut sink := ''
	mut source := ''
	for line in raw.split_into_lines() {
		t := line.trim_space()
		if t.starts_with('Default Sink:') {
			sink = t.all_after('Default Sink:').trim_space()
		} else if t.starts_with('Default Source:') {
			source = t.all_after('Default Source:').trim_space()
		}
	}
	return sink, source
}

fn append_pactl_device(mut devices []AudioDeviceInfo, mut id_to_name map[string]string, default_name string, idx string, name string, desc string) {
	if name.len == 0 {
		return
	}
	d := if desc.len > 0 { desc } else { name }
	devices << AudioDeviceInfo{
		index:       idx
		name:        name
		description: d
		is_default:  default_name.len > 0 && name == default_name
	}
	if idx.len > 0 {
		id_to_name[idx] = name
	}
}

// parse_pactl_devices parses `pactl list sinks` or `pactl list sources` output.
pub fn parse_pactl_devices(raw string, header_prefix string, default_name string) ([]AudioDeviceInfo, map[string]string) {
	mut devices := []AudioDeviceInfo{}
	mut id_to_name := map[string]string{}
	mut cur_idx := ''
	mut cur_name := ''
	mut cur_desc := ''
	mut in_block := false
	for line in raw.split_into_lines() {
		trimmed := line.trim_space()
		if trimmed.starts_with(header_prefix) {
			if in_block {
				append_pactl_device(mut devices, mut id_to_name, default_name, cur_idx,
					cur_name, cur_desc)
			}
			in_block = true
			cur_idx = trimmed.all_after('#').trim_space()
			cur_name = ''
			cur_desc = ''
			continue
		}
		if !in_block {
			continue
		}
		if trimmed.starts_with('Name:') && cur_name.len == 0 {
			cur_name = trimmed.all_after('Name:').trim_space()
		} else if trimmed.starts_with('Description:') && cur_desc.len == 0 {
			cur_desc = trimmed.all_after('Description:').trim_space()
		}
	}
	if in_block {
		append_pactl_device(mut devices, mut id_to_name, default_name, cur_idx, cur_name,
			cur_desc)
	}
	return devices, id_to_name
}

fn unquote_pactl_prop(val string) string {
	t := val.trim_space()
	if t.len >= 2 && t.starts_with('"') && t.ends_with('"') {
		return t[1..t.len - 1]
	}
	return t
}

fn parse_pactl_volume_pct(line string) int {
	// Example: "Volume: front-left: 65536 / 100% / 0.00 dB,   front-right: 65536 / 100% / 0.00 dB"
	// or "Volume: mono: 0 /   0% / -inf dB"
	mut best := -1
	for part in line.split('/') {
		t := part.trim_space()
		if t.ends_with('%') {
			num_str := t[..t.len - 1].trim_space()
			if num_str.len > 0 && num_str.bytes().all(it.is_digit()) {
				val := num_str.int()
				if best < 0 || val > best {
					best = val
				}
			}
		}
	}
	if best < 0 {
		return 100
	}
	return best
}

fn append_pactl_sink_input(mut streams []AudioStreamInfo, sink_id_map map[string]string, id string, sink string, muted bool, vol int, app string, bin string, node string, media string) {
	if id.len == 0 {
		return
	}
	resolved_sink := sink_id_map[sink] or { sink }
	resolved_app := if app.len > 0 {
		app
	} else if bin.len > 0 {
		bin
	} else if node.len > 0 {
		node
	} else {
		'unknown'
	}
	streams << AudioStreamInfo{
		id:                  id
		app:                 resolved_app
		media_name:          media
		sink:                resolved_sink
		volume_pct:          vol
		muted:               muted
		zero_volume_warning: vol == 0
	}
}

// parse_pactl_sink_inputs parses `pactl list sink-inputs` output into AudioStreamInfo entries.
pub fn parse_pactl_sink_inputs(raw string, sink_id_map map[string]string) []AudioStreamInfo {
	mut streams := []AudioStreamInfo{}
	mut in_block := false
	mut cur_id := ''
	mut cur_sink := ''
	mut cur_muted := false
	mut cur_vol := 100
	mut cur_app := ''
	mut cur_bin := ''
	mut cur_node := ''
	mut cur_media := ''
	for line in raw.split_into_lines() {
		trimmed := line.trim_space()
		if trimmed.starts_with('Sink Input #') {
			if in_block {
				append_pactl_sink_input(mut streams, sink_id_map, cur_id, cur_sink, cur_muted,
					cur_vol, cur_app, cur_bin, cur_node, cur_media)
			}
			in_block = true
			cur_id = trimmed.all_after('#').trim_space()
			cur_sink = ''
			cur_muted = false
			cur_vol = 100
			cur_app = ''
			cur_bin = ''
			cur_node = ''
			cur_media = ''
			continue
		}
		if !in_block {
			continue
		}
		if trimmed.starts_with('Sink:') {
			cur_sink = trimmed.all_after('Sink:').trim_space()
		} else if trimmed.starts_with('Mute:') {
			cur_muted = trimmed.all_after('Mute:').trim_space().to_lower() == 'yes'
		} else if trimmed.starts_with('Volume:') {
			cur_vol = parse_pactl_volume_pct(trimmed)
		} else if trimmed.starts_with('application.name =') {
			cur_app = unquote_pactl_prop(trimmed.all_after('='))
		} else if trimmed.starts_with('application.process.binary =') {
			cur_bin = unquote_pactl_prop(trimmed.all_after('='))
		} else if trimmed.starts_with('node.name =') {
			cur_node = unquote_pactl_prop(trimmed.all_after('='))
		} else if trimmed.starts_with('media.name =') {
			cur_media = unquote_pactl_prop(trimmed.all_after('='))
		}
	}
	if in_block {
		append_pactl_sink_input(mut streams, sink_id_map, cur_id, cur_sink, cur_muted,
			cur_vol, cur_app, cur_bin, cur_node, cur_media)
	}
	return streams
}

// parse_pw_links parses `pw-link -l` output into sorted deduplicated `"out_port -> in_port"` pairs.
pub fn parse_pw_links(raw string) []string {
	mut links := []string{}
	mut seen := map[string]bool{}
	mut current_port := ''
	for line in raw.split_into_lines() {
		trimmed := line.trim_space()
		if trimmed.len == 0 {
			continue
		}
		if trimmed.starts_with('|->') {
			if current_port.len > 0 {
				target := trimmed.all_after('|->').trim_space()
				if target.len > 0 {
					pair := '${current_port} -> ${target}'
					if pair !in seen {
						seen[pair] = true
						links << pair
					}
				}
			}
			continue
		}
		if trimmed.starts_with('|<-') || trimmed.starts_with('|') {
			continue
		}
		current_port = trimmed
	}
	links.sort()
	return links
}

pub struct LiveAudioSnapshot {
pub:
	pactl_available bool
	default_sink    string
	default_source  string
	sinks           []AudioDeviceInfo
	sources         []AudioDeviceInfo
	streams         []AudioStreamInfo
}

pub fn read_live_audio_snapshot() LiveAudioSnapshot {
	pactl := resolve_pactl_bin()
	if pactl.len == 0 {
		return LiveAudioSnapshot{}
	}
	info_rep := run_exec(ExecSpec{
		prog:        pactl
		args:        ['info']
		timeout_sec: 5
	})
	if !info_rep.ok {
		return LiveAudioSnapshot{}
	}
	def_sink, def_source := parse_pactl_info(info_rep.output)
	sinks_rep := run_exec(ExecSpec{
		prog:        pactl
		args:        ['list', 'sinks']
		timeout_sec: 5
	})
	sinks, sink_id_map := if sinks_rep.ok {
		parse_pactl_devices(sinks_rep.output, 'Sink #', def_sink)
	} else {
		[]AudioDeviceInfo{}, map[string]string{}
	}
	sources_rep := run_exec(ExecSpec{
		prog:        pactl
		args:        ['list', 'sources']
		timeout_sec: 5
	})
	sources, _ := if sources_rep.ok {
		parse_pactl_devices(sources_rep.output, 'Source #', def_source)
	} else {
		[]AudioDeviceInfo{}, map[string]string{}
	}
	inputs_rep := run_exec(ExecSpec{
		prog:        pactl
		args:        ['list', 'sink-inputs']
		timeout_sec: 5
	})
	streams := if inputs_rep.ok {
		parse_pactl_sink_inputs(inputs_rep.output, sink_id_map)
	} else {
		[]AudioStreamInfo{}
	}
	return LiveAudioSnapshot{
		pactl_available: true
		default_sink:    def_sink
		default_source:  def_source
		sinks:           sinks
		sources:         sources
		streams:         streams
	}
}

pub fn restart_user_pipewire() (bool, string) {
	sysctl := resolve_systemctl_bin()
	if sysctl.len == 0 {
		return false, 'systemctl not found on PATH; restart user PipeWire services manually'
	}
	rep := run_exec(ExecSpec{
		prog:        sysctl
		args:        ['--user', 'restart', 'pipewire', 'pipewire-pulse', 'wireplumber']
		timeout_sec: 15
	})
	if !rep.ok {
		detail := if rep.output.len > 0 { rep.output } else { 'exit ${rep.exit_code}' }
		return false, 'systemctl --user restart pipewire pipewire-pulse wireplumber failed: ${detail}'
	}
	return true, ''
}

pub fn studio_routing_status_result() CommandResult {
	kits := read_all_routing_kits()
	audio := read_live_audio_snapshot()
	mut sink_json := []AudioSinkJson{}
	for s in audio.sinks {
		sink_json << AudioSinkJson{
			name:        s.name
			description: s.description
			is_default:  s.is_default
		}
	}
	mut lines := ['Routing kits:']
	for k in kits {
		state := if k.enabled {
			if k.external { 'enabled (external)' } else { 'enabled (hornero)' }
		} else {
			'disabled'
		}
		lines << '  ${k.id}: ${state} [${k.file}]'
	}
	if audio.pactl_available {
		lines << 'Default sink: ${if audio.default_sink.len > 0 {
			audio.default_sink
		} else {
			'(none)'
		}}'
		lines << 'Sinks (${audio.sinks.len}):'
		for s in audio.sinks {
			mark := if s.is_default { '*' } else { ' ' }
			lines << '  ${mark} ${s.name} — ${s.description}'
		}
		lines << 'Active streams (${audio.streams.len}):'
		for st in audio.streams {
			warn := if st.zero_volume_warning { ' [WARNING: 0% volume]' } else { '' }
			mute := if st.muted { ' [MUTED]' } else { '' }
			lines << '  #${st.id} ${st.app} (${st.media_name}) -> ${st.sink} (${st.volume_pct}%)${mute}${warn}'
		}
	} else {
		lines << 'Live streams/sinks: unavailable (pactl not found or PipeWire pulse server unreachable)'
	}
	return ok_result('studio routing status', lines.join('\n'), {
		'kits':            json2.encode(kits, escape_unicode: true)
		'streams':         json2.encode(audio.streams, escape_unicode: true)
		'sinks':           json2.encode(sink_json, escape_unicode: true)
		'default_sink':    audio.default_sink
		'pactl_available': audio.pactl_available.str()
	})
}

pub fn studio_routing_enable_result(id string, no_restart bool, dry_run bool, yes bool) CommandResult {
	cmd := 'studio routing enable'
	spec := studio_routing_kit_by_id(id) or {
		return fail_result(cmd, 'unknown routing kit: ${id}. Available: ${studio_routing_kit_ids.join(', ')}\nExample: horneroctl studio routing enable live-call --dry-run')
	}
	if !yes && !dry_run {
		return fail_result(cmd, 'enabling routing kit ${id} requires --yes (preview with --dry-run).\nExample: horneroctl studio routing enable ${id} --dry-run')
	}
	dir := studio_routing_kit_dir(spec)
	managed_path := os.join_path(dir, spec.managed_file)
	external_path := os.join_path(dir, spec.external_file)
	if os.is_file(managed_path) && !routing_file_is_managed(managed_path) {
		return fail_result(cmd, '${managed_path} already exists and was not written by horneroctl; refusing to overwrite a personal PipeWire file.')
	}
	if spec.external_file.len > 0 && os.is_file(external_path) {
		return fail_result(cmd, 'routing kit ${id} is already provided by external file ${external_path}; refusing to duplicate PipeWire configuration.')
	}
	if dry_run {
		restart_note := if no_restart {
			'without restarting PipeWire (--no-restart)'
		} else {
			'and restart user PipeWire services (pipewire, pipewire-pulse, wireplumber)'
		}
		return ok_result(cmd, 'Dry run: would write ${managed_path} ${restart_note}. Nothing was changed.',
			{
				'dry_run':    'true'
				'id':         id
				'file':       managed_path
				'no_restart': no_restart.str()
			})
	}
	content := studio_routing_kit_content(id)
	write_file_atomic(managed_path, content) or {
		return fail_result(cmd, 'cannot write ${managed_path}: ${err.msg()}')
	}
	mut restarted := false
	mut warning := ''
	if !no_restart {
		restarted, warning = restart_user_pipewire()
	}
	mut msg := 'Enabled routing kit ${id} at ${managed_path}.'
	if no_restart {
		msg += ' PipeWire restart skipped (--no-restart).'
	} else if restarted {
		msg += ' Restarted user PipeWire services.'
	} else if warning.len > 0 {
		msg += ' Warning: ${warning}.'
	}
	return ok_result(cmd, msg, {
		'id':                 id
		'file':               managed_path
		'pipewire_restarted': restarted.str()
		'warning':            warning
	})
}

pub fn studio_routing_disable_result(id string, no_restart bool, dry_run bool, yes bool) CommandResult {
	cmd := 'studio routing disable'
	spec := studio_routing_kit_by_id(id) or {
		return fail_result(cmd, 'unknown routing kit: ${id}. Available: ${studio_routing_kit_ids.join(', ')}\nExample: horneroctl studio routing disable live-call --dry-run')
	}
	if !yes && !dry_run {
		return fail_result(cmd, 'disabling routing kit ${id} requires --yes (preview with --dry-run).\nExample: horneroctl studio routing disable ${id} --dry-run')
	}
	dir := studio_routing_kit_dir(spec)
	managed_path := os.join_path(dir, spec.managed_file)
	external_path := os.join_path(dir, spec.external_file)
	if os.is_file(managed_path) {
		if !routing_file_is_managed(managed_path) {
			return fail_result(cmd, '${managed_path} was not written by horneroctl; refusing to delete a personal PipeWire file.')
		}
	} else if spec.external_file.len > 0 && os.is_file(external_path) {
		return fail_result(cmd, 'routing kit ${id} is provided by external file ${external_path}; Hornero will not delete unmarked personal dotfiles.')
	} else {
		return ok_result(cmd, 'Routing kit ${id} is already disabled.', {
			'id':                 id
			'file':               managed_path
			'pipewire_restarted': 'false'
		})
	}
	if dry_run {
		restart_note := if no_restart {
			'without restarting PipeWire (--no-restart)'
		} else {
			'and restart user PipeWire services (pipewire, pipewire-pulse, wireplumber)'
		}
		return ok_result(cmd, 'Dry run: would remove ${managed_path} ${restart_note}. Nothing was changed.',
			{
				'dry_run':    'true'
				'id':         id
				'file':       managed_path
				'no_restart': no_restart.str()
			})
	}
	os.rm(managed_path) or {
		return fail_result(cmd, 'cannot remove ${managed_path}: ${err.msg()}')
	}
	mut restarted := false
	mut warning := ''
	if !no_restart {
		restarted, warning = restart_user_pipewire()
	}
	mut msg := 'Disabled routing kit ${id} (removed ${managed_path}).'
	if no_restart {
		msg += ' PipeWire restart skipped (--no-restart).'
	} else if restarted {
		msg += ' Restarted user PipeWire services.'
	} else if warning.len > 0 {
		msg += ' Warning: ${warning}.'
	}
	return ok_result(cmd, msg, {
		'id':                 id
		'file':               managed_path
		'pipewire_restarted': restarted.str()
		'warning':            warning
	})
}

fn valid_stream_id(id string) bool {
	return id.len > 0 && id.bytes().all(it.is_digit())
}

fn valid_sink_name(name string) bool {
	if name.len == 0 || name.starts_with('-') {
		return false
	}
	for c in name.bytes() {
		if c <= 32 || c == 127 {
			return false
		}
	}
	return true
}

pub fn studio_routing_move_stream_result(stream_id string, sink_name string, dry_run bool, yes bool) CommandResult {
	cmd := 'studio routing move-stream'
	if !valid_stream_id(stream_id) {
		return fail_result(cmd, 'invalid stream id: ${stream_id} (expected numeric sink-input id).\nExample: horneroctl studio routing move-stream 42 discord_call --dry-run')
	}
	if !valid_sink_name(sink_name) {
		return fail_result(cmd, 'invalid sink name: ${sink_name}.\nExample: horneroctl studio routing move-stream 42 discord_call --dry-run')
	}
	if !yes && !dry_run {
		return fail_result(cmd, 'moving stream ${stream_id} requires --yes (preview with --dry-run).\nExample: horneroctl studio routing move-stream ${stream_id} ${sink_name} --dry-run')
	}
	bin := resolve_pactl_bin()
	prog := if bin.len > 0 { bin } else { 'pactl' }
	args := ['move-sink-input', stream_id, sink_name]
	if dry_run {
		line := command_line(prog, args)
		return ok_result(cmd, 'would run: ${line}', {
			'dry_run':      'true'
			'stream_id':    stream_id
			'sink':         sink_name
			'command_line': line
		})
	}
	if bin.len == 0 {
		return fail_result(cmd, 'pactl not found on PATH. Set HORNERO_PACTL_BIN.')
	}
	rep := run_exec(ExecSpec{
		prog:        bin
		args:        args
		timeout_sec: 5
	})
	if !rep.ok {
		return fail_result(cmd, 'pactl move-sink-input failed (exit ${rep.exit_code}): ${rep.output}')
	}
	return ok_result(cmd, 'Moved stream #${stream_id} to ${sink_name}.', {
		'stream_id':    stream_id
		'sink':         sink_name
		'command_line': rep.command_line
	})
}

pub fn clamp_stream_volume_percent(pct int) int {
	if pct < 0 {
		return 0
	}
	if pct > 150 {
		return 150
	}
	return pct
}

pub fn studio_routing_fix_volume_result(stream_id string, percent int, dry_run bool, yes bool) CommandResult {
	cmd := 'studio routing fix-volume'
	if !valid_stream_id(stream_id) {
		return fail_result(cmd, 'invalid stream id: ${stream_id} (expected numeric sink-input id).\nExample: horneroctl studio routing fix-volume 42 100 --dry-run')
	}
	if !yes && !dry_run {
		return fail_result(cmd, 'changing stream ${stream_id} volume requires --yes (preview with --dry-run).\nExample: horneroctl studio routing fix-volume ${stream_id} 100 --dry-run')
	}
	clamped := clamp_stream_volume_percent(percent)
	bin := resolve_pactl_bin()
	prog := if bin.len > 0 { bin } else { 'pactl' }
	unmute_args := ['set-sink-input-mute', stream_id, '0']
	vol_args := ['set-sink-input-volume', stream_id, '${clamped}%']
	if dry_run {
		line := '${command_line(prog, unmute_args)} && ${command_line(prog, vol_args)}'
		return ok_result(cmd, 'would run: ${line}', {
			'dry_run':      'true'
			'stream_id':    stream_id
			'percent':      '${clamped}'
			'command_line': line
		})
	}
	if bin.len == 0 {
		return fail_result(cmd, 'pactl not found on PATH. Set HORNERO_PACTL_BIN.')
	}
	unmute_rep := run_exec(ExecSpec{
		prog:        bin
		args:        unmute_args
		timeout_sec: 5
	})
	if !unmute_rep.ok {
		return fail_result(cmd, 'pactl set-sink-input-mute failed (exit ${unmute_rep.exit_code}): ${unmute_rep.output}')
	}
	vol_rep := run_exec(ExecSpec{
		prog:        bin
		args:        vol_args
		timeout_sec: 5
	})
	if !vol_rep.ok {
		return fail_result(cmd, 'pactl set-sink-input-volume failed (exit ${vol_rep.exit_code}): ${vol_rep.output}')
	}
	return ok_result(cmd, 'Unmuted stream #${stream_id} and set volume to ${clamped}%.', {
		'stream_id':    stream_id
		'percent':      '${clamped}'
		'command_line': '${unmute_rep.command_line} && ${vol_rep.command_line}'
	})
}
