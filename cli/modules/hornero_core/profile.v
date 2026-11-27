module hornero_core

import os
import time
import x.json2

// Universal 5-domain HorneroOS Workspace Profiles & Snapshots (`horneroctl profile`).
//
// Captures, diffs, applies, reverts, launches companion apps for, and
// exports/imports composable workspace profiles spanning 5 domains:
// experience, audio, power, extensions, apps.

pub const profile_api_version = 'hornero.os/v1'
pub const profile_kind = 'WorkspaceProfile'
pub const profile_bundle_kind = 'WorkspaceProfileBundle'

pub const profile_all_domains = ['experience', 'audio', 'power', 'extensions', 'apps']

const profile_reserved_ids = ['baseline', 'previous']

const profile_blocked_daemons = [
	'pipewire',
	'pipewire-pulse',
	'wireplumber',
	'systemd',
	'quickshell',
	'qs',
	'bash',
	'sh',
	'zsh',
	'fish',
	'dbus-daemon',
	'dbus-broker',
	'hyprland',
	'niri',
	'xwayland',
]

pub struct ProfileStreamRoute {
pub:
	app  string
	sink string
}

pub struct ProfileExperience {
pub mut:
	mode          string
	theme         string
	layout_preset string
}

pub struct ProfileAudio {
pub mut:
	studio_audio_mode   string
	clock_rate          string
	clock_quantum       string
	clock_min_quantum   string
	clock_max_quantum   string
	default_sink        string
	default_sink_desc   string
	default_source      string
	default_source_desc string
	pipewire_dropins    []string
	jack_dropins        []string
	links               []string
	stream_routes       []ProfileStreamRoute
	qpwgraph_patchbay   string
}

pub struct ProfilePower {
pub mut:
	profile        string
	idle_inhibitor bool
}

pub struct ProfileExtensions {
pub mut:
	enabled []string
}

pub struct ProfileApp {
pub:
	id            string
	name          string
	exec          []string
	process_match string
	category      string
}

pub struct WorkspaceProfile {
pub mut:
	api_version string = profile_api_version
	kind        string = profile_kind
	id          string
	name        string
	description string
	hostname    string
	created_at  string
	updated_at  string
	domains     []string
	experience  ProfileExperience
	audio       ProfileAudio
	power       ProfilePower
	extensions  ProfileExtensions
	apps        []ProfileApp
}

pub struct WorkspaceProfileBundle {
pub:
	api_version           string = profile_api_version
	kind                  string = profile_bundle_kind
	portable              bool
	profile               WorkspaceProfile
	pipewire_dropin_files map[string]string
	jack_dropin_files     map[string]string
}

pub struct ProfileAppLive {
pub:
	id        string
	name      string
	exec      []string
	category  string
	installed bool
	running   bool
}

pub struct ProfileSummaryItem {
pub:
	id               string
	name             string
	description      string
	created_at       string
	updated_at       string
	is_baseline      bool
	is_active        bool
	domains          []string
	apps_count       int
	apps_running     int
	apps_missing     int
	hardware_status  string
	hardware_missing []string
}

pub struct ProfileShowDetail {
pub:
	api_version      string
	kind             string
	id               string
	name             string
	description      string
	hostname         string
	created_at       string
	updated_at       string
	is_baseline      bool
	is_active        bool
	domains          []string
	experience       ProfileExperience
	audio            ProfileAudio
	power            ProfilePower
	extensions       ProfileExtensions
	apps             []ProfileApp
	apps_live        []ProfileAppLive
	hardware_status  string
	hardware_missing []string
}

pub struct ProfileDiffEntry {
pub:
	domain  string
	field   string
	current string
	target  string
}

pub struct ProfileMissingAppItem {
pub:
	id        string
	name      string
	exec      []string
	category  string
	installed bool
}

pub struct ProfileCaptureOptions {
pub:
	id          string
	name        string
	description string
	domains     []string
	apps        []string
	no_apps     bool
	activate    bool
	dry_run     bool
	yes         bool
}

pub struct ProfileApplyOptions {
pub:
	id                  string
	domains             []string
	no_restart_pipewire bool
	launch_apps         bool
	dry_run             bool
	yes                 bool
}

pub struct ProfileRevertOptions {
pub:
	to                  string = 'previous'
	no_restart_pipewire bool
	dry_run             bool
	yes                 bool
}

struct CompanionCatalogEntry {
	id            string
	name          string
	exec          []string
	process_match string
	aliases       []string
	category      string
}

fn companion_app_catalog() []CompanionCatalogEntry {
	return [
		CompanionCatalogEntry{
			id:            'reaper'
			name:          'REAPER'
			exec:          ['reaper']
			process_match: 'reaper'
			aliases:       ['reaper']
			category:      'audio'
		},
		CompanionCatalogEntry{
			id:            'qpwgraph'
			name:          'qpwgraph'
			exec:          ['qpwgraph']
			process_match: 'qpwgraph'
			aliases:       ['qpwgraph']
			category:      'audio'
		},
		CompanionCatalogEntry{
			id:            'discord'
			name:          'Discord'
			exec:          ['discord']
			process_match: 'discord'
			aliases:       ['discord', 'discordcanary', 'discordptb']
			category:      'comms'
		},
		CompanionCatalogEntry{
			id:            'obs'
			name:          'OBS Studio'
			exec:          ['obs']
			process_match: 'obs'
			aliases:       ['obs', 'obs-studio']
			category:      'studio'
		},
		CompanionCatalogEntry{
			id:            'zen-browser'
			name:          'Zen Browser'
			exec:          ['zen-browser']
			process_match: 'zen'
			aliases:       ['zen', 'zen-browser', 'zen-bin']
			category:      'browser'
		},
		CompanionCatalogEntry{
			id:            'firefox'
			name:          'Firefox'
			exec:          ['firefox']
			process_match: 'firefox'
			aliases:       ['firefox', 'firefox-bin']
			category:      'browser'
		},
		CompanionCatalogEntry{
			id:            'chromium'
			name:          'Chromium'
			exec:          ['chromium']
			process_match: 'chromium'
			aliases:       ['chromium', 'chromium-bin']
			category:      'browser'
		},
		CompanionCatalogEntry{
			id:            'ardour'
			name:          'Ardour'
			exec:          ['ardour8']
			process_match: 'ardour'
			aliases:       ['ardour', 'ardour8', 'ardour7']
			category:      'audio'
		},
		CompanionCatalogEntry{
			id:            'carla'
			name:          'Carla'
			exec:          ['carla']
			process_match: 'carla'
			aliases:       ['carla']
			category:      'audio'
		},
		CompanionCatalogEntry{
			id:            'guitarix'
			name:          'Guitarix'
			exec:          ['guitarix']
			process_match: 'guitarix'
			aliases:       ['guitarix']
			category:      'audio'
		},
		CompanionCatalogEntry{
			id:            'blender'
			name:          'Blender'
			exec:          ['blender']
			process_match: 'blender'
			aliases:       ['blender']
			category:      'creative'
		},
		CompanionCatalogEntry{
			id:            'krita'
			name:          'Krita'
			exec:          ['krita']
			process_match: 'krita'
			aliases:       ['krita']
			category:      'creative'
		},
		CompanionCatalogEntry{
			id:            'kdenlive'
			name:          'Kdenlive'
			exec:          ['kdenlive']
			process_match: 'kdenlive'
			aliases:       ['kdenlive']
			category:      'video'
		},
		CompanionCatalogEntry{
			id:            'gimp'
			name:          'GIMP'
			exec:          ['gimp']
			process_match: 'gimp'
			aliases:       ['gimp']
			category:      'creative'
		},
		CompanionCatalogEntry{
			id:            'inkscape'
			name:          'Inkscape'
			exec:          ['inkscape']
			process_match: 'inkscape'
			aliases:       ['inkscape']
			category:      'creative'
		},
		CompanionCatalogEntry{
			id:            'godot'
			name:          'Godot'
			exec:          ['godot']
			process_match: 'godot'
			aliases:       ['godot', 'godot4']
			category:      'dev'
		},
		CompanionCatalogEntry{
			id:            'audacity'
			name:          'Audacity'
			exec:          ['audacity']
			process_match: 'audacity'
			aliases:       ['audacity']
			category:      'audio'
		},
		CompanionCatalogEntry{
			id:            'pavucontrol'
			name:          'PulseAudio Volume Control'
			exec:          ['pavucontrol']
			process_match: 'pavucontrol'
			aliases:       ['pavucontrol']
			category:      'audio'
		},
		CompanionCatalogEntry{
			id:            'helvum'
			name:          'Helvum'
			exec:          ['helvum']
			process_match: 'helvum'
			aliases:       ['helvum']
			category:      'audio'
		},
		CompanionCatalogEntry{
			id:            'kitty'
			name:          'Kitty'
			exec:          ['kitty']
			process_match: 'kitty'
			aliases:       ['kitty']
			category:      'dev'
		},
		CompanionCatalogEntry{
			id:            'alacritty'
			name:          'Alacritty'
			exec:          ['alacritty']
			process_match: 'alacritty'
			aliases:       ['alacritty']
			category:      'dev'
		},
		CompanionCatalogEntry{
			id:            'ghostty'
			name:          'Ghostty'
			exec:          ['ghostty']
			process_match: 'ghostty'
			aliases:       ['ghostty']
			category:      'dev'
		},
	]
}

pub fn resolve_profiles_dir() string {
	env := os.getenv('HORNERO_PROFILES_DIR')
	if env.len > 0 {
		return env
	}
	return os.join_path(resolve_paths().config_dir, 'hornero', 'profiles')
}

pub fn resolve_profiles_state_dir() string {
	env := os.getenv('HORNERO_PROFILES_STATE_DIR')
	if env.len > 0 {
		return env
	}
	return os.join_path(resolve_paths().state_dir, 'hornero', 'profiles')
}

pub fn resolve_systemd_run_bin() string {
	return leaf_bin('HORNERO_SYSTEMD_RUN_BIN', 'systemd-run')
}

fn profile_active_file() string {
	return os.join_path(resolve_profiles_state_dir(), 'active.txt')
}

fn profile_baseline_dir() string {
	return os.join_path(resolve_profiles_state_dir(), 'baseline')
}

fn profile_previous_dir() string {
	return os.join_path(resolve_profiles_state_dir(), 'previous')
}

fn profile_managed_dropins_receipt() string {
	return os.join_path(resolve_profiles_state_dir(), 'applied-dropins.json')
}

// valid_profile_id validates lowercase [a-z0-9][a-z0-9_-]*, max 64 chars, no path escapes.
pub fn valid_profile_id(id string) bool {
	if id.len == 0 || id.len > 64 || id.contains('/') || id.contains('..') || id.contains('\x00') {
		return false
	}
	first := id[0]
	if !((first >= `a` && first <= `z`) || (first >= `0` && first <= `9`)) {
		return false
	}
	for c in id.bytes() {
		if !((c >= `a` && c <= `z`) || (c >= `0` && c <= `9`) || c == `_` || c == `-`) {
			return false
		}
	}
	return true
}

pub fn normalize_profile_domains(raw []string) ![]string {
	if raw.len == 0 {
		return profile_all_domains.clone()
	}
	mut out := []string{}
	for item in raw {
		for part in item.split(',') {
			d := part.trim_space()
			if d.len == 0 {
				continue
			}
			if d !in profile_all_domains {
				return error('unknown domain "${d}" (expected: ${profile_all_domains.join(', ')})')
			}
			if d !in out {
				out << d
			}
		}
	}
	if out.len == 0 {
		return profile_all_domains.clone()
	}
	return out
}

fn profile_iso_now() string {
	return time.utc().custom_format('YYYY-MM-DDTHH:mm:ss') + 'Z'
}

fn read_active_profile_id() string {
	raw := os.read_file(profile_active_file()) or { return '' }
	return raw.trim_space()
}

fn write_active_profile_id(id string) ! {
	write_file_atomic(profile_active_file(), id + '\n')!
}

fn resolve_profile_dir_for_id(id string) string {
	if id == 'baseline' {
		return profile_baseline_dir()
	}
	if id == 'previous' {
		return profile_previous_dir()
	}
	return os.join_path(resolve_profiles_dir(), id)
}

fn read_profile_from_dir(dir string) !WorkspaceProfile {
	path := os.join_path(dir, 'profile.json')
	if !os.is_file(path) {
		return error('profile not found at ${path}')
	}
	raw := os.read_file(path) or { return error('cannot read ${path}: ${err.msg()}') }
	p := json2.decode[WorkspaceProfile](raw) or {
		return error('invalid profile JSON at ${path}: ${err.msg()}')
	}
	if p.id.len == 0 {
		return error('profile at ${path} is missing id')
	}
	return p
}

fn profile_running_proc_names() []string {
	mut lines := []string{}
	if env := os.getenv_opt('HORNERO_PROFILE_RUNNING_PROCS') {
		for part in env.replace(',', '\n').split_into_lines() {
			t := part.trim_space()
			if t.len > 0 {
				lines << t
			}
		}
	} else {
		lines = collect_proc_cmdlines()
	}
	mut names := []string{}
	for c in lines {
		base := c.split(' ').first().all_after_last('/').trim_space().to_lower()
		if base.len > 0 && base !in names {
			names << base
		}
	}
	return names
}

fn proc_matches_entry(proc_names []string, entry CompanionCatalogEntry) bool {
	for p in proc_names {
		if p == entry.process_match || p in entry.aliases || p == entry.id {
			return true
		}
	}
	return false
}

fn proc_matches_app(proc_names []string, app ProfileApp) bool {
	pm := app.process_match.to_lower()
	id_l := app.id.to_lower()
	exec0 := if app.exec.len > 0 { app.exec[0].all_after_last('/').to_lower() } else { '' }
	for cat in companion_app_catalog() {
		if cat.id == app.id {
			return proc_matches_entry(proc_names, cat)
		}
	}
	for p in proc_names {
		if (pm.len > 0 && p == pm) || (id_l.len > 0 && p == id_l)
			|| (exec0.len > 0 && p == exec0) {
			return true
		}
	}
	return false
}

fn app_exec_installed(app ProfileApp) (bool, []string) {
	if app.exec.len > 0 && find_on_path(app.exec[0]).len > 0 {
		return true, app.exec
	}
	for cat in companion_app_catalog() {
		if cat.id == app.id {
			for alias in cat.aliases {
				if find_on_path(alias).len > 0 {
					return true, [alias]
				}
			}
		}
	}
	return false, app.exec
}

fn is_blocked_daemon(name string) bool {
	base := name.trim_space().all_after_last('/').to_lower()
	return base in profile_blocked_daemons
}

fn sanitize_custom_app_id(raw string) string {
	base := raw.trim_space().all_after_last('/').to_lower()
	mut out := []u8{}
	for c in base.bytes() {
		if (c >= `a` && c <= `z`) || (c >= `0` && c <= `9`) || c == `-` || c == `_` {
			out << c
		} else {
			out << `-`
		}
	}
	res := out.bytestr().trim('-')
	if res.len > 64 {
		return res[..64]
	}
	return res
}

fn resolve_profile_app_spec(spec string) !ProfileApp {
	t := spec.trim_space()
	if t.len == 0 {
		return error('empty --app value')
	}
	if is_blocked_daemon(t) {
		return error('refusing to capture system daemon "${t}" as a companion app')
	}
	tl := t.to_lower()
	for cat in companion_app_catalog() {
		if tl == cat.id || tl == cat.process_match || tl in cat.aliases {
			_, exec_cmd := app_exec_installed(ProfileApp{
				id:   cat.id
				exec: cat.exec
			})
			return ProfileApp{
				id:            cat.id
				name:          cat.name
				exec:          exec_cmd
				process_match: cat.process_match
				category:      cat.category
			}
		}
	}
	id := sanitize_custom_app_id(t)
	if id.len == 0 {
		return error('invalid --app value "${t}"')
	}
	return ProfileApp{
		id:            id
		name:          t
		exec:          [t]
		process_match: t.all_after_last('/').to_lower()
		category:      'custom'
	}
}

fn read_live_experience() ProfileExperience {
	paths := resolve_paths()
	mut mode := ''
	exp_file := os.join_path(paths.state_dir, 'hornero', 'experience.json')
	if raw := os.read_file(exp_file) {
		if decoded := json2.decode[map[string]json2.Any](raw) {
			if 'mode' in decoded && decoded['mode'] is string {
				mode = decoded['mode'].str().trim_space()
			}
		}
	}
	if mode.len == 0 && !shell_ipc_bypassed() {
		qs := resolve_qs_bin()
		if qs.len > 0 {
			rep := run_exec(ExecSpec{
				prog:        qs
				args:        ['-c', 'hornero', 'ipc', 'call', 'experience', 'get']
				timeout_sec: 4
			})
			if rep.ok && valid_experience_mode(rep.output.trim_space()) {
				mode = rep.output.trim_space()
			}
		}
	}
	mut theme := ''
	scheme_path := signal_scheme_file()
	if os.is_file(scheme_path) {
		if s := read_signal_scheme() {
			theme = s.id
		} else {
			theme = scheme_json_field(scheme_path, 'id')
		}
	} else if os.is_file(scheme_state_file()) {
		theme = resolve_signal_selection().id
	}
	mut layout_preset := ''
	sc := shell_config_file(paths)
	if raw := os.read_file(sc) {
		if decoded := json2.decode[map[string]json2.Any](raw) {
			for k in ['layoutPreset', 'layout_preset', 'preset'] {
				if k in decoded && decoded[k] is string && decoded[k].str().trim_space().len > 0 {
					layout_preset = decoded[k].str().trim_space()
					break
				}
			}
		}
	}
	if layout_preset.len == 0 {
		layout_preset = current_preset_name()
	}
	return ProfileExperience{
		mode:          mode
		theme:         theme
		layout_preset: layout_preset
	}
}

fn list_conf_files(dir string) []string {
	if !os.is_dir(dir) {
		return []
	}
	entries := os.ls(dir) or { return [] }
	mut out := []string{}
	for e in entries {
		if !e.ends_with('.conf') {
			continue
		}
		p := os.join_path(dir, e)
		if os.is_file(p) && !os.is_link(p) {
			out << e
		}
	}
	out.sort()
	return out
}

fn find_qpwgraph_patchbay() string {
	dir := os.join_path(resolve_paths().config_dir, 'qpwgraph')
	if !os.is_dir(dir) {
		return ''
	}
	mut entries := os.ls(dir) or { return '' }
	entries.sort()
	for e in entries {
		if e.ends_with('.qpwgraph') {
			p := os.join_path(dir, e)
			if os.is_file(p) {
				return p
			}
		}
	}
	return ''
}

fn read_live_pw_links() []string {
	bin := resolve_pw_link_bin()
	if bin.len == 0 {
		return []
	}
	rep := run_exec(ExecSpec{
		prog:        bin
		args:        ['-l']
		timeout_sec: 5
	})
	if !rep.ok {
		return []
	}
	return parse_pw_links(rep.output)
}

fn read_live_power() ProfilePower {
	mut prof := ''
	pp := resolve_powerprofilesctl_bin()
	if pp.len > 0 {
		rep := run_exec(ExecSpec{
			prog:        pp
			args:        ['get']
			timeout_sec: 4
		})
		if rep.ok {
			prof = rep.output.trim_space()
		}
	}
	mut idle := false
	if !shell_ipc_bypassed() {
		qs := resolve_qs_bin()
		if qs.len > 0 {
			rep := run_exec(ExecSpec{
				prog:        qs
				args:        ['-c', 'hornero', 'ipc', 'call', 'idleInhibitor', 'isEnabled']
				timeout_sec: 4
			})
			if rep.ok {
				v := rep.output.trim_space().to_lower()
				idle = v in ['true', '1', 'enabled', 'yes']
			}
		}
	}
	return ProfilePower{
		profile:        prof
		idle_inhibitor: idle
	}
}

fn read_live_extensions() ProfileExtensions {
	_, receipts := community_plugin_roots()
	if !os.is_dir(receipts) {
		return ProfileExtensions{}
	}
	entries := os.ls(receipts) or { return ProfileExtensions{} }
	mut enabled := []string{}
	for e in entries {
		if !e.ends_with('.json') {
			continue
		}
		p := os.join_path(receipts, e)
		if !os.is_file(p) || os.is_link(p) {
			continue
		}
		raw := os.read_file(p) or { continue }
		rec := json2.decode[CommunityPluginReceipt](raw) or { continue }
		if rec.enabled && rec.id.len > 0 && rec.id !in enabled {
			enabled << rec.id
		}
	}
	enabled.sort()
	return ProfileExtensions{
		enabled: enabled
	}
}

fn read_live_apps(proc_names []string, extra_apps []string, no_apps bool) ![]ProfileApp {
	mut apps := []ProfileApp{}
	mut seen := map[string]bool{}
	if !no_apps {
		for cat in companion_app_catalog() {
			if proc_matches_entry(proc_names, cat) {
				_, exec_cmd := app_exec_installed(ProfileApp{
					id:   cat.id
					exec: cat.exec
				})
				apps << ProfileApp{
					id:            cat.id
					name:          cat.name
					exec:          exec_cmd
					process_match: cat.process_match
					category:      cat.category
				}
				seen[cat.id] = true
			}
		}
	}
	for raw in extra_apps {
		app := resolve_profile_app_spec(raw)!
		if app.id !in seen {
			apps << app
			seen[app.id] = true
		}
	}
	apps.sort(a.id < b.id)
	return apps
}

struct LiveSystemState {
	experience        ProfileExperience
	audio             ProfileAudio
	audio_snapshot    LiveAudioSnapshot
	pw_dropin_files   map[string]string
	jack_dropin_files map[string]string
	power             ProfilePower
	extensions        ProfileExtensions
	proc_names        []string
}

fn read_dropin_file_map(dir string, names []string) map[string]string {
	mut out := map[string]string{}
	for n in names {
		p := os.join_path(dir, n)
		if body := os.read_file(p) {
			out[n] = body
		}
	}
	return out
}

fn capture_live_system_state() LiveSystemState {
	exp := read_live_experience()
	st_mode, _ := load_studio_mode() or { StudioModeState{}, false }
	pw_rt := read_pw_runtime()
	audio_snap := read_live_audio_snapshot()
	mut sink_desc := ''
	for s in audio_snap.sinks {
		if s.name == audio_snap.default_sink {
			sink_desc = s.description
			break
		}
	}
	mut source_desc := ''
	for s in audio_snap.sources {
		if s.name == audio_snap.default_source {
			source_desc = s.description
			break
		}
	}
	pw_dir := studio_pipewire_dropin_dir()
	jack_dir := studio_jack_dropin_dir()
	pw_names := list_conf_files(pw_dir)
	jack_names := list_conf_files(jack_dir)
	mut routes := []ProfileStreamRoute{}
	mut route_seen := map[string]bool{}
	for st in audio_snap.streams {
		key := '${st.app}=>${st.sink}'
		if st.app.len > 0 && st.sink.len > 0 && key !in route_seen {
			route_seen[key] = true
			routes << ProfileStreamRoute{
				app:  st.app
				sink: st.sink
			}
		}
	}
	audio := ProfileAudio{
		studio_audio_mode:   st_mode.audio_mode
		clock_rate:          pw_rt.settings['clock.rate'] or { '' }
		clock_quantum:       pw_rt.settings['clock.quantum'] or { '' }
		clock_min_quantum:   pw_rt.settings['clock.min-quantum'] or { '' }
		clock_max_quantum:   pw_rt.settings['clock.max-quantum'] or { '' }
		default_sink:        audio_snap.default_sink
		default_sink_desc:   sink_desc
		default_source:      audio_snap.default_source
		default_source_desc: source_desc
		pipewire_dropins:    pw_names
		jack_dropins:        jack_names
		links:               read_live_pw_links()
		stream_routes:       routes
		qpwgraph_patchbay:   find_qpwgraph_patchbay()
	}
	return LiveSystemState{
		experience:        exp
		audio:             audio
		audio_snapshot:    audio_snap
		pw_dropin_files:   read_dropin_file_map(pw_dir, pw_names)
		jack_dropin_files: read_dropin_file_map(jack_dir, jack_names)
		power:             read_live_power()
		extensions:        read_live_extensions()
		proc_names:        profile_running_proc_names()
	}
}

fn build_profile_from_live(id string, name string, desc string, domains []string, live LiveSystemState, apps []ProfileApp, existing_created string) WorkspaceProfile {
	now := profile_iso_now()
	created := if existing_created.len > 0 { existing_created } else { now }
	host := os.hostname() or { '' }
	mut p := WorkspaceProfile{
		api_version: profile_api_version
		kind:        profile_kind
		id:          id
		name:        if name.len > 0 { name } else { id }
		description: desc
		hostname:    host
		created_at:  created
		updated_at:  now
		domains:     domains
	}
	if 'experience' in domains {
		p.experience = live.experience
	}
	if 'audio' in domains {
		p.audio = live.audio
	}
	if 'power' in domains {
		p.power = live.power
	}
	if 'extensions' in domains {
		p.extensions = live.extensions
	}
	if 'apps' in domains {
		p.apps = apps
	}
	return p
}

fn write_profile_dir(dir string, p WorkspaceProfile, pw_files map[string]string, jack_files map[string]string) ! {
	os.mkdir_all(dir) or { return error('cannot create ${dir}: ${err.msg()}') }
	pw_sub := os.join_path(dir, 'pipewire', 'pipewire.conf.d')
	jack_sub := os.join_path(dir, 'pipewire', 'jack.conf.d')
	if os.is_dir(pw_sub) {
		os.rmdir_all(pw_sub) or {}
	}
	if os.is_dir(jack_sub) {
		os.rmdir_all(jack_sub) or {}
	}
	os.mkdir_all(pw_sub) or { return error('cannot create ${pw_sub}: ${err.msg()}') }
	os.mkdir_all(jack_sub) or { return error('cannot create ${jack_sub}: ${err.msg()}') }
	if 'audio' in p.domains {
		for fname in p.audio.pipewire_dropins {
			if body := pw_files[fname] {
				write_file_atomic(os.join_path(pw_sub, fname), body)!
			}
		}
		for fname in p.audio.jack_dropins {
			if body := jack_files[fname] {
				write_file_atomic(os.join_path(jack_sub, fname), body)!
			}
		}
	}
	write_file_atomic(os.join_path(dir, 'profile.json'), json2.encode(p, escape_unicode: true) + '\n')!
}

fn check_profile_hardware(p WorkspaceProfile, snap LiveAudioSnapshot) (string, []string) {
	if 'audio' !in p.domains || (p.audio.default_sink.len == 0 && p.audio.default_source.len == 0) {
		return 'ok', []string{}
	}
	if !snap.pactl_available {
		return 'unknown', []string{}
	}
	mut missing := []string{}
	if p.audio.default_sink.len > 0 {
		mut found := false
		for s in snap.sinks {
			if s.name == p.audio.default_sink {
				found = true
				break
			}
		}
		if !found {
			missing << p.audio.default_sink
		}
	}
	if p.audio.default_source.len > 0 {
		mut found := false
		for s in snap.sources {
			if s.name == p.audio.default_source {
				found = true
				break
			}
		}
		if !found {
			missing << p.audio.default_source
		}
	}
	if missing.len > 0 {
		return 'degraded', missing
	}
	return 'ok', []string{}
}

fn evaluate_profile_apps(apps []ProfileApp, proc_names []string) ([]ProfileAppLive, int, int) {
	mut live_apps := []ProfileAppLive{}
	mut running_count := 0
	mut missing_count := 0
	for app in apps {
		installed, exec_cmd := app_exec_installed(app)
		running := proc_matches_app(proc_names, app)
		if running {
			running_count++
		} else {
			missing_count++
		}
		live_apps << ProfileAppLive{
			id:        app.id
			name:      app.name
			exec:      exec_cmd
			category:  app.category
			installed: installed
			running:   running
		}
	}
	return live_apps, running_count, missing_count
}

pub fn profile_list_result() CommandResult {
	profiles_dir := resolve_profiles_dir()
	base_dir := profile_baseline_dir()
	prev_dir := profile_previous_dir()
	has_baseline := os.is_file(os.join_path(base_dir, 'profile.json'))
	has_previous := os.is_file(os.join_path(prev_dir, 'profile.json'))
	active_id := read_active_profile_id()
	audio_snap := read_live_audio_snapshot()
	proc_names := profile_running_proc_names()
	mut items := []ProfileSummaryItem{}
	if has_baseline {
		if p := read_profile_from_dir(base_dir) {
			hw_status, hw_missing := check_profile_hardware(p, audio_snap)
			_, running_cnt, missing_cnt := evaluate_profile_apps(p.apps, proc_names)
			items << ProfileSummaryItem{
				id:               'baseline'
				name:             p.name
				description:      p.description
				created_at:       p.created_at
				updated_at:       p.updated_at
				is_baseline:      true
				is_active:        active_id == 'baseline'
				domains:          p.domains
				apps_count:       p.apps.len
				apps_running:     running_cnt
				apps_missing:     missing_cnt
				hardware_status:  hw_status
				hardware_missing: hw_missing
			}
		}
	}
	if os.is_dir(profiles_dir) {
		mut entries := os.ls(profiles_dir) or { []string{} }
		entries.sort()
		for e in entries {
			if !valid_profile_id(e) || e in profile_reserved_ids {
				continue
			}
			dir := os.join_path(profiles_dir, e)
			if !os.is_dir(dir) {
				continue
			}
			if p := read_profile_from_dir(dir) {
				hw_status, hw_missing := check_profile_hardware(p, audio_snap)
				_, running_cnt, missing_cnt := evaluate_profile_apps(p.apps, proc_names)
				items << ProfileSummaryItem{
					id:               p.id
					name:             p.name
					description:      p.description
					created_at:       p.created_at
					updated_at:       p.updated_at
					is_baseline:      false
					is_active:        active_id == p.id
					domains:          p.domains
					apps_count:       p.apps.len
					apps_running:     running_cnt
					apps_missing:     missing_cnt
					hardware_status:  hw_status
					hardware_missing: hw_missing
				}
			}
		}
	}
	mut lines := []string{}
	if items.len == 0 {
		lines << 'No profiles captured yet.'
	} else {
		for item in items {
			mark := if item.is_active { '*' } else { ' ' }
			tag := if item.is_baseline { ' [baseline]' } else { '' }
			lines << '${mark} ${item.id}${tag}: ${item.name} (domains: ${item.domains.join(',')}, apps: ${item.apps_running}/${item.apps_count} running, hw: ${item.hardware_status})'
		}
	}
	lines << '${items.len} profile(s), active: ${if active_id.len > 0 { active_id } else { 'none' }}'
	return ok_result('profile list', lines.join('\n'), {
		'active':       active_id
		'has_baseline': has_baseline.str()
		'has_previous': has_previous.str()
		'count':        '${items.len}'
		'profiles':     json2.encode(items, escape_unicode: true)
	})
}

pub fn profile_show_result(id string) CommandResult {
	cmd := 'profile show'
	if !valid_profile_id(id) {
		return fail_result(cmd, 'invalid profile id: ${id}.\nExample: horneroctl profile show music-prod')
	}
	dir := resolve_profile_dir_for_id(id)
	p := read_profile_from_dir(dir) or {
		return fail_result(cmd, 'profile not found: ${id}.\nRun: horneroctl profile list')
	}
	audio_snap := read_live_audio_snapshot()
	hw_status, hw_missing := check_profile_hardware(p, audio_snap)
	live_apps, _, _ := evaluate_profile_apps(p.apps, profile_running_proc_names())
	active_id := read_active_profile_id()
	detail := ProfileShowDetail{
		api_version:      p.api_version
		kind:             p.kind
		id:               p.id
		name:             p.name
		description:      p.description
		hostname:         p.hostname
		created_at:       p.created_at
		updated_at:       p.updated_at
		is_baseline:      id == 'baseline'
		is_active:        active_id == id
		domains:          p.domains
		experience:       p.experience
		audio:            p.audio
		power:            p.power
		extensions:       p.extensions
		apps:             p.apps
		apps_live:        live_apps
		hardware_status:  hw_status
		hardware_missing: hw_missing
	}
	mut lines := [
		'Profile: ${p.id} (${p.name})',
		'Domains: ${p.domains.join(', ')}',
		'Hardware: ${hw_status}${if hw_missing.len > 0 {
			' (missing: ' + hw_missing.join(', ') + ')'
		} else {
			''
		}}',
		'Experience: mode=${p.experience.mode}, theme=${p.experience.theme}, layout=${p.experience.layout_preset}',
		'Audio: mode=${p.audio.studio_audio_mode}, rate=${p.audio.clock_rate}, quantum=${p.audio.clock_quantum}, sink=${p.audio.default_sink}, dropins=${p.audio.pipewire_dropins.len + p.audio.jack_dropins.len}, links=${p.audio.links.len}',
		'Power: profile=${p.power.profile}, idle_inhibitor=${p.power.idle_inhibitor}',
		'Extensions (${p.extensions.enabled.len}): ${p.extensions.enabled.join(', ')}',
		'Apps (${live_apps.len}):',
	]
	for a in live_apps {
		lines << '  ${a.id} (${a.name}) [installed=${a.installed}, running=${a.running}]'
	}
	return ok_result(cmd, lines.join('\n'), {
		'id':               p.id
		'hardware_status':  hw_status
		'hardware_missing': json2.encode(hw_missing, escape_unicode: true)
		'profile':          json2.encode(detail, escape_unicode: true)
	})
}

pub fn profile_capture_result(opts ProfileCaptureOptions) CommandResult {
	cmd := 'profile capture'
	if !valid_profile_id(opts.id) {
		return fail_result(cmd, 'invalid profile id: ${opts.id} (lowercase [a-z0-9][a-z0-9_-]*, max 64 chars).\nExample: horneroctl profile capture music-prod --yes')
	}
	if opts.id in profile_reserved_ids {
		return fail_result(cmd, '"${opts.id}" is a reserved snapshot name managed automatically by horneroctl.\nExample: horneroctl profile capture music-prod --yes')
	}
	domains := normalize_profile_domains(opts.domains) or {
		return fail_result(cmd, err.msg())
	}
	if !opts.yes && !opts.dry_run {
		return fail_result(cmd, 'capturing profile "${opts.id}" requires --yes (preview with --dry-run).\nExample: horneroctl profile capture ${opts.id} --dry-run')
	}
	for raw in opts.apps {
		resolve_profile_app_spec(raw) or { return fail_result(cmd, err.msg()) }
	}
	base_dir := profile_baseline_dir()
	will_create_baseline := !os.is_file(os.join_path(base_dir, 'profile.json'))
	target_dir := resolve_profile_dir_for_id(opts.id)
	if opts.dry_run {
		return ok_result(cmd, 'Dry run: would capture profile "${opts.id}" at ${target_dir} (domains: ${domains.join(', ')})${if will_create_baseline {
			' after creating initial baseline snapshot'
		} else {
			''
		}}. Nothing was written.',
			{
				'dry_run':              'true'
				'id':                   opts.id
				'path':                 target_dir
				'domains':              domains.join(',')
				'will_create_baseline': will_create_baseline.str()
			})
	}
	live := capture_live_system_state()
	if will_create_baseline {
		base_apps := read_live_apps(live.proc_names, []string{}, false) or { []ProfileApp{} }
		base_prof := build_profile_from_live('baseline', 'Baseline', 'Automatic initial baseline snapshot',
			profile_all_domains.clone(), live, base_apps, '')
		write_profile_dir(base_dir, base_prof, live.pw_dropin_files, live.jack_dropin_files) or {
			return fail_result(cmd, 'cannot write baseline snapshot: ${err.msg()}')
		}
	}
	apps := if 'apps' in domains {
		read_live_apps(live.proc_names, opts.apps, opts.no_apps) or {
			return fail_result(cmd, err.msg())
		}
	} else {
		[]ProfileApp{}
	}
	mut existing_created := ''
	if prev := read_profile_from_dir(target_dir) {
		existing_created = prev.created_at
	}
	prof := build_profile_from_live(opts.id, opts.name, opts.description, domains, live,
		apps, existing_created)
	write_profile_dir(target_dir, prof, live.pw_dropin_files, live.jack_dropin_files) or {
		return fail_result(cmd, 'cannot write profile ${opts.id}: ${err.msg()}')
	}
	if opts.activate {
		write_active_profile_id(opts.id) or {
			return fail_result(cmd, 'profile saved, but failed to mark active: ${err.msg()}')
		}
	}
	return ok_result(cmd, 'Captured profile "${opts.id}" at ${target_dir} (domains: ${domains.join(', ')}, apps: ${apps.len})${if will_create_baseline {
		' (initial baseline snapshot created)'
	} else {
		''
	}}.', {
		'id':               opts.id
		'path':             target_dir
		'baseline_created': will_create_baseline.str()
		'active':           if opts.activate { opts.id } else { read_active_profile_id() }
		'profile':          json2.encode(prof, escape_unicode: true)
	})
}

fn read_profile_dropin_files(profile_dir string, is_jack bool, names []string) map[string]string {
	sub := if is_jack {
		os.join_path(profile_dir, 'pipewire', 'jack.conf.d')
	} else {
		os.join_path(profile_dir, 'pipewire', 'pipewire.conf.d')
	}
	return read_dropin_file_map(sub, names)
}

fn is_hornero_managed_dropin(path string) bool {
	body := os.read_file(path) or { return false }
	return body.contains(studio_routing_marker) || body.contains('# HorneroOS Studio')
}

fn load_applied_dropins_receipt() []string {
	raw := os.read_file(profile_managed_dropins_receipt()) or { return [] }
	decoded := json2.decode[[]string](raw) or { return [] }
	return decoded
}

fn save_applied_dropins_receipt(paths []string) {
	mut sorted := paths.clone()
	sorted.sort()
	write_file_atomic(profile_managed_dropins_receipt(), json2.encode(sorted, escape_unicode: true) +
		'\n') or {}
}

fn dropin_sync_needed(live_dir string, live_files map[string]string, target_names []string, target_files map[string]string, tracked_paths []string) bool {
	for fname in target_names {
		target_body := target_files[fname] or { continue }
		live_body := live_files[fname] or { return true }
		if live_body != target_body {
			return true
		}
	}
	for fname, _ in live_files {
		if fname !in target_names {
			full := os.join_path(live_dir, fname)
			if is_hornero_managed_dropin(full) || full in tracked_paths {
				return true
			}
		}
	}
	return false
}

fn compute_profile_diff(p WorkspaceProfile, profile_dir string, live LiveSystemState, domains []string) ([]ProfileDiffEntry, bool, []string, []ProfileMissingAppItem) {
	mut changes := []ProfileDiffEntry{}
	mut will_restart_pw := false
	tracked := load_applied_dropins_receipt()
	if 'experience' in domains && 'experience' in p.domains {
		if p.experience.mode.len > 0 && p.experience.mode != live.experience.mode {
			changes << ProfileDiffEntry{
				domain:  'experience'
				field:   'mode'
				current: live.experience.mode
				target:  p.experience.mode
			}
		}
		if p.experience.theme.len > 0 && p.experience.theme != live.experience.theme {
			changes << ProfileDiffEntry{
				domain:  'experience'
				field:   'theme'
				current: live.experience.theme
				target:  p.experience.theme
			}
		}
		if p.experience.layout_preset.len > 0
			&& p.experience.layout_preset != live.experience.layout_preset {
			changes << ProfileDiffEntry{
				domain:  'experience'
				field:   'layout_preset'
				current: live.experience.layout_preset
				target:  p.experience.layout_preset
			}
		}
	}
	if 'audio' in domains && 'audio' in p.domains {
		if p.audio.studio_audio_mode.len > 0
			&& p.audio.studio_audio_mode != live.audio.studio_audio_mode {
			changes << ProfileDiffEntry{
				domain:  'audio'
				field:   'studio_audio_mode'
				current: live.audio.studio_audio_mode
				target:  p.audio.studio_audio_mode
			}
		}
		if p.audio.clock_rate.len > 0 && p.audio.clock_rate != live.audio.clock_rate {
			changes << ProfileDiffEntry{
				domain:  'audio'
				field:   'clock_rate'
				current: live.audio.clock_rate
				target:  p.audio.clock_rate
			}
		}
		if p.audio.clock_quantum.len > 0 && p.audio.clock_quantum != live.audio.clock_quantum {
			changes << ProfileDiffEntry{
				domain:  'audio'
				field:   'clock_quantum'
				current: live.audio.clock_quantum
				target:  p.audio.clock_quantum
			}
		}
		if p.audio.clock_min_quantum.len > 0
			&& p.audio.clock_min_quantum != live.audio.clock_min_quantum {
			changes << ProfileDiffEntry{
				domain:  'audio'
				field:   'clock_min_quantum'
				current: live.audio.clock_min_quantum
				target:  p.audio.clock_min_quantum
			}
		}
		if p.audio.clock_max_quantum.len > 0
			&& p.audio.clock_max_quantum != live.audio.clock_max_quantum {
			changes << ProfileDiffEntry{
				domain:  'audio'
				field:   'clock_max_quantum'
				current: live.audio.clock_max_quantum
				target:  p.audio.clock_max_quantum
			}
		}
		if p.audio.default_sink.len > 0 && p.audio.default_sink != live.audio.default_sink {
			changes << ProfileDiffEntry{
				domain:  'audio'
				field:   'default_sink'
				current: live.audio.default_sink
				target:  p.audio.default_sink
			}
		}
		if p.audio.default_source.len > 0 && p.audio.default_source != live.audio.default_source {
			changes << ProfileDiffEntry{
				domain:  'audio'
				field:   'default_source'
				current: live.audio.default_source
				target:  p.audio.default_source
			}
		}
		pw_target := read_profile_dropin_files(profile_dir, false, p.audio.pipewire_dropins)
		jack_target := read_profile_dropin_files(profile_dir, true, p.audio.jack_dropins)
		pw_changed := dropin_sync_needed(studio_pipewire_dropin_dir(), live.pw_dropin_files,
			p.audio.pipewire_dropins, pw_target, tracked)
		jack_changed := dropin_sync_needed(studio_jack_dropin_dir(), live.jack_dropin_files,
			p.audio.jack_dropins, jack_target, tracked)
		if pw_changed {
			changes << ProfileDiffEntry{
				domain:  'audio'
				field:   'pipewire_dropins'
				current: live.audio.pipewire_dropins.join(',')
				target:  p.audio.pipewire_dropins.join(',')
			}
		}
		if jack_changed {
			changes << ProfileDiffEntry{
				domain:  'audio'
				field:   'jack_dropins'
				current: live.audio.jack_dropins.join(',')
				target:  p.audio.jack_dropins.join(',')
			}
		}
		will_restart_pw = pw_changed || jack_changed
		mut missing_links := []string{}
		for l in p.audio.links {
			if l !in live.audio.links {
				missing_links << l
			}
		}
		if missing_links.len > 0 {
			changes << ProfileDiffEntry{
				domain:  'audio'
				field:   'links'
				current: '${live.audio.links.len} link(s)'
				target:  '${missing_links.len} link(s) to connect'
			}
		}
	}
	if 'power' in domains && 'power' in p.domains {
		if p.power.profile.len > 0 && p.power.profile != live.power.profile {
			changes << ProfileDiffEntry{
				domain:  'power'
				field:   'profile'
				current: live.power.profile
				target:  p.power.profile
			}
		}
		if p.power.idle_inhibitor != live.power.idle_inhibitor {
			changes << ProfileDiffEntry{
				domain:  'power'
				field:   'idle_inhibitor'
				current: live.power.idle_inhibitor.str()
				target:  p.power.idle_inhibitor.str()
			}
		}
	}
	if 'extensions' in domains && 'extensions' in p.domains {
		mut cur_ext := live.extensions.enabled.clone()
		cur_ext.sort()
		mut tgt_ext := p.extensions.enabled.clone()
		tgt_ext.sort()
		if cur_ext != tgt_ext {
			changes << ProfileDiffEntry{
				domain:  'extensions'
				field:   'enabled'
				current: cur_ext.join(',')
				target:  tgt_ext.join(',')
			}
		}
	}
	mut missing_apps := []ProfileMissingAppItem{}
	if 'apps' in domains && 'apps' in p.domains {
		live_apps, _, _ := evaluate_profile_apps(p.apps, live.proc_names)
		for a in live_apps {
			if !a.running {
				missing_apps << ProfileMissingAppItem{
					id:        a.id
					name:      a.name
					exec:      a.exec
					category:  a.category
					installed: a.installed
				}
			}
		}
		if missing_apps.len > 0 {
			mut names := []string{}
			for m in missing_apps {
				names << m.id
			}
			changes << ProfileDiffEntry{
				domain:  'apps'
				field:   'missing_apps'
				current: 'not running'
				target:  names.join(',')
			}
		}
	}
	_, hw_missing := check_profile_hardware(p, live.audio_snapshot)
	return changes, will_restart_pw, hw_missing, missing_apps
}

pub fn profile_diff_result(id string) CommandResult {
	cmd := 'profile diff'
	if !valid_profile_id(id) {
		return fail_result(cmd, 'invalid profile id: ${id}.\nExample: horneroctl profile diff music-prod')
	}
	dir := resolve_profile_dir_for_id(id)
	p := read_profile_from_dir(dir) or {
		return fail_result(cmd, 'profile not found: ${id}.\nRun: horneroctl profile list')
	}
	live := capture_live_system_state()
	changes, will_restart_pw, hw_missing, missing_apps := compute_profile_diff(p, dir,
		live, p.domains)
	mut lines := ['Diff for profile "${id}" (${changes.len} change(s), will_restart_pipewire=${will_restart_pw}):']
	for c in changes {
		lines << '  [${c.domain}] ${c.field}: "${c.current}" -> "${c.target}"'
	}
	if hw_missing.len > 0 {
		lines << 'Missing hardware: ${hw_missing.join(', ')}'
	}
	return ok_result(cmd, lines.join('\n'), {
		'id':                    id
		'changes_count':         '${changes.len}'
		'changes':               json2.encode(changes, escape_unicode: true)
		'will_restart_pipewire': will_restart_pw.str()
		'hardware_missing':      json2.encode(hw_missing, escape_unicode: true)
		'missing_apps':          json2.encode(missing_apps, escape_unicode: true)
	})
}

fn sync_dropin_dir(live_dir string, target_names []string, target_files map[string]string, tracked_in []string) !(bool, []string, []string) {
	mut changed := false
	mut new_tracked := []string{}
	mut warnings := []string{}
	os.mkdir_all(live_dir) or { return error('cannot create ${live_dir}: ${err.msg()}') }
	for fname in target_names {
		body := target_files[fname] or { continue }
		dest := os.join_path(live_dir, fname)
		existing := os.read_file(dest) or { '' }
		if !os.is_file(dest) || existing != body {
			write_file_atomic(dest, body)!
			changed = true
		}
		if !is_hornero_managed_dropin(dest) && dest !in new_tracked {
			new_tracked << dest
		}
	}
	if entries := os.ls(live_dir) {
		for e in entries {
			if !e.ends_with('.conf') || e in target_names {
				continue
			}
			full := os.join_path(live_dir, e)
			if !os.is_file(full) || os.is_link(full) {
				continue
			}
			if is_hornero_managed_dropin(full) || full in tracked_in {
				os.rm(full) or {
					warnings << 'could not remove ${full}: ${err.msg()}'
					continue
				}
				changed = true
			} else {
				warnings << 'preserved unmanaged drop-in: ${full}'
			}
		}
	}
	return changed, new_tracked, warnings
}

fn build_detached_launch_cmd(exec_cmd []string) (string, []string) {
	sr := resolve_systemd_run_bin()
	if sr.len > 0 {
		mut args := ['--user', '--scope', '--no-block']
		args << exec_cmd
		return sr, args
	}
	setsid := find_on_path('setsid')
	if setsid.len > 0 {
		mut args := ['-f']
		args << exec_cmd
		return setsid, args
	}
	mut fallback_args := ['--user', '--scope', '--no-block']
	fallback_args << exec_cmd
	return 'systemd-run', fallback_args
}

fn launch_app_detached(app ProfileAppLive) (bool, string, string) {
	if !app.installed || app.exec.len == 0 {
		return false, '', 'application "${app.id}" is not installed'
	}
	prog, args := build_detached_launch_cmd(app.exec)
	if find_on_path(prog).len > 0 {
		rep := run_exec(ExecSpec{
			prog:        prog
			args:        args
			timeout_sec: 5
		})
		if !rep.ok {
			return false, rep.command_line, 'failed to launch ${app.id}: ${rep.output}'
		}
		return true, rep.command_line, ''
	}
	// Fallback: spawn detached child process directly when neither systemd-run nor setsid exists.
	bin := find_on_path(app.exec[0])
	if bin.len == 0 {
		return false, command_line(app.exec[0], app.exec[1..]), 'executable not found: ${app.exec[0]}'
	}
	mut proc := os.new_process(bin)
	proc.set_args(app.exec[1..])
	proc.run()
	return true, command_line(bin, app.exec[1..]), ''
}

fn apply_loaded_profile(p WorkspaceProfile, profile_dir string, domains []string, no_restart_pw bool, launch_apps bool, target_label string) CommandResult {
	cmd := if target_label == 'revert' { 'profile revert' } else { 'profile apply' }
	live := capture_live_system_state()
	// Auto-create baseline if missing, and auto-save current live state to `previous` before mutating.
	base_dir := profile_baseline_dir()
	if !os.is_file(os.join_path(base_dir, 'profile.json')) {
		base_apps := read_live_apps(live.proc_names, []string{}, false) or { []ProfileApp{} }
		base_prof := build_profile_from_live('baseline', 'Baseline', 'Automatic initial baseline snapshot',
			profile_all_domains.clone(), live, base_apps, '')
		write_profile_dir(base_dir, base_prof, live.pw_dropin_files, live.jack_dropin_files) or {
			return fail_result(cmd, 'cannot create baseline snapshot: ${err.msg()}')
		}
	}
	prev_apps := read_live_apps(live.proc_names, []string{}, false) or { []ProfileApp{} }
	prev_prof := build_profile_from_live('previous', 'Previous', 'Automatic pre-apply snapshot',
		profile_all_domains.clone(), live, prev_apps, '')
	write_profile_dir(profile_previous_dir(), prev_prof, live.pw_dropin_files, live.jack_dropin_files) or {
		return fail_result(cmd, 'cannot save previous state snapshot: ${err.msg()}')
	}

	mut warnings := []string{}
	mut pw_restarted := false

	// 1. Experience domain
	if 'experience' in domains && 'experience' in p.domains {
		if p.experience.mode.len > 0 && p.experience.mode != live.experience.mode {
			if shell_ipc_bypassed() {
				warnings << 'shell IPC bypassed; experience mode "${p.experience.mode}" not applied'
			} else {
				qs := resolve_qs_bin()
				if qs.len == 0 {
					warnings << 'qs not found; experience mode "${p.experience.mode}" not applied'
				} else {
					rep := run_exec(ExecSpec{
						prog:        qs
						args:        ['-c', 'hornero', 'ipc', 'call', 'experience', 'set',
							p.experience.mode]
						timeout_sec: 8
					})
					if !rep.ok {
						warnings << 'experience mode set failed: ${rep.output}'
					}
				}
			}
		}
		if p.experience.theme.len > 0 && p.experience.theme != live.experience.theme {
			t_res := theme_apply_native(p.experience.theme, '', false)
			if !t_res.ok {
				warnings << 'theme "${p.experience.theme}" not applied: ${t_res.message}'
			}
		}
		if p.experience.layout_preset.len > 0
			&& p.experience.layout_preset != live.experience.layout_preset {
			pr_res := preset_apply_report(PresetApplyOptions{
				name: p.experience.layout_preset
				yes:  true
			})
			if !pr_res.ok {
				warnings << 'layout preset "${p.experience.layout_preset}" not applied: ${pr_res.message}'
			}
		}
	}

	// 2. Audio domain
	if 'audio' in domains && 'audio' in p.domains {
		if p.audio.studio_audio_mode.len > 0
			&& p.audio.studio_audio_mode != live.audio.studio_audio_mode {
			m_res := studio_audio_mode_set_result(p.audio.studio_audio_mode, true)
			if !m_res.ok {
				warnings << 'studio audio mode "${p.audio.studio_audio_mode}" not updated: ${m_res.message}'
			}
		}
		pw_target := read_profile_dropin_files(profile_dir, false, p.audio.pipewire_dropins)
		jack_target := read_profile_dropin_files(profile_dir, true, p.audio.jack_dropins)
		tracked := load_applied_dropins_receipt()
		pw_changed, pw_tracked, pw_warns := sync_dropin_dir(studio_pipewire_dropin_dir(),
			p.audio.pipewire_dropins, pw_target, tracked) or {
			return fail_result(cmd, 'failed syncing PipeWire drop-ins: ${err.msg()}')
		}
		jack_changed, jack_tracked, jack_warns := sync_dropin_dir(studio_jack_dropin_dir(),
			p.audio.jack_dropins, jack_target, tracked) or {
			return fail_result(cmd, 'failed syncing JACK drop-ins: ${err.msg()}')
		}
		warnings << pw_warns
		warnings << jack_warns
		mut combined_tracked := pw_tracked.clone()
		combined_tracked << jack_tracked
		save_applied_dropins_receipt(combined_tracked)

		if (pw_changed || jack_changed) && !no_restart_pw {
			restarted, r_warn := restart_user_pipewire()
			pw_restarted = restarted
			if r_warn.len > 0 {
				warnings << r_warn
			}
		}
		// Apply PipeWire clock runtime settings (min/max before quantum).
		clock_pairs := [
			['clock.min-quantum', p.audio.clock_min_quantum, live.audio.clock_min_quantum],
			['clock.max-quantum', p.audio.clock_max_quantum, live.audio.clock_max_quantum],
			['clock.quantum', p.audio.clock_quantum, live.audio.clock_quantum],
			['clock.rate', p.audio.clock_rate, live.audio.clock_rate],
		]
		mut need_clock := false
		for pair in clock_pairs {
			if pair[1].len > 0 && pair[1] != pair[2] {
				need_clock = true
				break
			}
		}
		if need_clock {
			if resolve_pw_metadata_bin().len == 0 {
				warnings << 'pw-metadata not found; PipeWire runtime clock values not updated'
			} else {
				for pair in clock_pairs {
					if pair[1].len > 0 && pair[1] != pair[2] {
						if !set_pw_setting(pair[0], pair[1]) {
							warnings << 'could not set PipeWire runtime ${pair[0]}=${pair[1]}'
						}
					}
				}
			}
		}
		// Re-read audio snapshot if PipeWire restarted; otherwise reuse.
		post_audio := if pw_restarted { read_live_audio_snapshot() } else { live.audio_snapshot }
		pactl := resolve_pactl_bin()
		if p.audio.default_sink.len > 0 && p.audio.default_sink != post_audio.default_sink {
			mut sink_present := false
			for s in post_audio.sinks {
				if s.name == p.audio.default_sink {
					sink_present = true
					break
				}
			}
			if !post_audio.pactl_available {
				warnings << 'pactl unavailable; default sink "${p.audio.default_sink}" not set'
			} else if !sink_present {
				warnings << 'hardware sink missing: ${p.audio.default_sink}'
			} else if pactl.len > 0 {
				rep := run_exec(ExecSpec{
					prog:        pactl
					args:        ['set-default-sink', p.audio.default_sink]
					timeout_sec: 5
				})
				if !rep.ok {
					warnings << 'could not set default sink ${p.audio.default_sink}: ${rep.output}'
				}
			}
		}
		if p.audio.default_source.len > 0 && p.audio.default_source != post_audio.default_source {
			mut source_present := false
			for s in post_audio.sources {
				if s.name == p.audio.default_source {
					source_present = true
					break
				}
			}
			if !post_audio.pactl_available {
				warnings << 'pactl unavailable; default source "${p.audio.default_source}" not set'
			} else if !source_present {
				warnings << 'hardware source missing: ${p.audio.default_source}'
			} else if pactl.len > 0 {
				rep := run_exec(ExecSpec{
					prog:        pactl
					args:        ['set-default-source', p.audio.default_source]
					timeout_sec: 5
				})
				if !rep.ok {
					warnings << 'could not set default source ${p.audio.default_source}: ${rep.output}'
				}
			}
		}
		// Restore PipeWire links best-effort.
		if p.audio.links.len > 0 {
			pw_link := resolve_pw_link_bin()
			if pw_link.len == 0 {
				warnings << 'pw-link not found; audio graph links not restored'
			} else {
				cur_links := if pw_restarted { read_live_pw_links() } else { live.audio.links }
				for link in p.audio.links {
					if link in cur_links {
						continue
					}
					parts := link.split(' -> ')
					if parts.len != 2 {
						continue
					}
					rep := run_exec(ExecSpec{
						prog:        pw_link
						args:        [parts[0].trim_space(), parts[1].trim_space()]
						timeout_sec: 4
					})
					if !rep.ok {
						warnings << 'pw-link failed for "${link}": ${rep.output}'
					}
				}
			}
		}
		// Move active matching streams best-effort.
		if p.audio.stream_routes.len > 0 && post_audio.pactl_available && pactl.len > 0 {
			for st in post_audio.streams {
				for route in p.audio.stream_routes {
					if st.app == route.app && st.sink != route.sink {
						rep := run_exec(ExecSpec{
							prog:        pactl
							args:        ['move-sink-input', st.id, route.sink]
							timeout_sec: 4
						})
						if !rep.ok {
							warnings << 'could not move stream #${st.id} (${st.app}) to ${route.sink}: ${rep.output}'
						}
						break
					}
				}
			}
		}
	}

	// 3. Power domain
	if 'power' in domains && 'power' in p.domains {
		if p.power.profile.len > 0 && p.power.profile != live.power.profile {
			pp := resolve_powerprofilesctl_bin()
			if pp.len == 0 {
				warnings << 'powerprofilesctl not found; power profile "${p.power.profile}" not set'
			} else {
				rep := run_exec(ExecSpec{
					prog:        pp
					args:        ['set', p.power.profile]
					timeout_sec: 5
				})
				if !rep.ok {
					warnings << 'powerprofilesctl set ${p.power.profile} failed: ${rep.output}'
				}
			}
		}
		if p.power.idle_inhibitor != live.power.idle_inhibitor {
			if shell_ipc_bypassed() {
				warnings << 'shell IPC bypassed; idle inhibitor state not changed'
			} else {
				qs := resolve_qs_bin()
				if qs.len == 0 {
					warnings << 'qs not found; idle inhibitor state not changed'
				} else {
					action := if p.power.idle_inhibitor { 'enable' } else { 'disable' }
					rep := run_exec(ExecSpec{
						prog:        qs
						args:        ['-c', 'hornero', 'ipc', 'call', 'idleInhibitor', action]
						timeout_sec: 4
					})
					if !rep.ok {
						warnings << 'idleInhibitor ${action} failed: ${rep.output}'
					}
				}
			}
		}
	}

	// 4. Extensions domain (never removes payloads)
	if 'extensions' in domains && 'extensions' in p.domains {
		_, receipts := community_plugin_roots()
		mut installed_ids := []string{}
		if os.is_dir(receipts) {
			mut files := os.ls(receipts) or { []string{} }
			files.sort()
			for f in files {
				if !f.ends_with('.json') {
					continue
				}
				raw := os.read_file(os.join_path(receipts, f)) or { continue }
				rec := json2.decode[CommunityPluginReceipt](raw) or { continue }
				installed_ids << rec.id
				should_enable := rec.id in p.extensions.enabled
				if should_enable && !rec.enabled {
					r := community_plugin_enable_report(CommunityPluginOptions{
						value: rec.id
						yes:   true
					})
					if !r.ok {
						warnings << 'could not enable extension ${rec.id}: ${r.message}'
					}
				} else if !should_enable && rec.enabled {
					r := community_plugin_disable_report(CommunityPluginOptions{
						value: rec.id
						yes:   true
					})
					if !r.ok {
						warnings << 'could not disable extension ${rec.id}: ${r.message}'
					}
				}
			}
		}
		for want_id in p.extensions.enabled {
			if want_id !in installed_ids {
				warnings << 'extension not installed: ${want_id}'
			}
		}
	}

	// 5. Apps domain
	mut missing_apps := []ProfileMissingAppItem{}
	mut launched_apps := []string{}
	if 'apps' in domains && 'apps' in p.domains {
		live_apps, _, _ := evaluate_profile_apps(p.apps, live.proc_names)
		for a in live_apps {
			if !a.running {
				if launch_apps && a.installed {
					ok, _, l_warn := launch_app_detached(a)
					if ok {
						launched_apps << a.id
					} else {
						if l_warn.len > 0 {
							warnings << l_warn
						}
						missing_apps << ProfileMissingAppItem{
							id:        a.id
							name:      a.name
							exec:      a.exec
							category:  a.category
							installed: a.installed
						}
					}
				} else {
					missing_apps << ProfileMissingAppItem{
						id:        a.id
						name:      a.name
						exec:      a.exec
						category:  a.category
						installed: a.installed
					}
				}
			}
		}
	}

	write_active_profile_id(p.id) or {
		warnings << 'failed to update active.txt: ${err.msg()}'
	}

	mut msg := 'Applied profile "${p.id}" (previous state saved).'
	if pw_restarted {
		msg += ' PipeWire restarted.'
	}
	if launched_apps.len > 0 {
		msg += ' Launched: ${launched_apps.join(', ')}.'
	}
	if missing_apps.len > 0 {
		mut m_ids := []string{}
		for m in missing_apps {
			m_ids << m.id
		}
		msg += ' Not running: ${m_ids.join(', ')}.'
	}
	if warnings.len > 0 {
		msg += ' Warnings (${warnings.len}): ${warnings.join('; ')}'
	}
	return ok_result(cmd, msg, {
		'id':                 p.id
		'previous_saved':     'true'
		'pipewire_restarted': pw_restarted.str()
		'missing_apps':       json2.encode(missing_apps, escape_unicode: true)
		'launched_apps':      json2.encode(launched_apps, escape_unicode: true)
		'warnings':           json2.encode(warnings, escape_unicode: true)
	})
}

pub fn profile_apply_result(opts ProfileApplyOptions) CommandResult {
	cmd := 'profile apply'
	if !valid_profile_id(opts.id) {
		return fail_result(cmd, 'invalid profile id: ${opts.id}.\nExample: horneroctl profile apply music-prod --dry-run')
	}
	if !opts.yes && !opts.dry_run {
		return fail_result(cmd, 'applying profile "${opts.id}" requires --yes (preview with --dry-run).\nExample: horneroctl profile apply ${opts.id} --dry-run')
	}
	dir := resolve_profile_dir_for_id(opts.id)
	p := read_profile_from_dir(dir) or {
		return fail_result(cmd, 'profile not found: ${opts.id}.\nRun: horneroctl profile list')
	}
	domains := if opts.domains.len > 0 {
		normalize_profile_domains(opts.domains) or { return fail_result(cmd, err.msg()) }
	} else {
		p.domains.clone()
	}
	if opts.dry_run {
		live := capture_live_system_state()
		changes, will_restart_pw, hw_missing, missing_apps := compute_profile_diff(p,
			dir, live, domains)
		return ok_result(cmd, 'Dry run: would save previous state and apply "${opts.id}" (${changes.len} change(s), restart_pipewire=${will_restart_pw && !opts.no_restart_pipewire}). Nothing was changed.',
			{
				'dry_run':               'true'
				'id':                    opts.id
				'changes_count':         '${changes.len}'
				'changes':               json2.encode(changes, escape_unicode: true)
				'will_restart_pipewire': (will_restart_pw && !opts.no_restart_pipewire).str()
				'hardware_missing':      json2.encode(hw_missing, escape_unicode: true)
				'missing_apps':          json2.encode(missing_apps, escape_unicode: true)
			})
	}
	return apply_loaded_profile(p, dir, domains, opts.no_restart_pipewire, opts.launch_apps,
		'apply')
}

pub fn profile_revert_result(opts ProfileRevertOptions) CommandResult {
	cmd := 'profile revert'
	target := if opts.to.len > 0 { opts.to } else { 'previous' }
	if target !in ['previous', 'baseline'] {
		return fail_result(cmd, 'invalid --to target "${target}" (expected: previous or baseline).\nExample: horneroctl profile revert --to previous --dry-run')
	}
	if !opts.yes && !opts.dry_run {
		return fail_result(cmd, 'reverting to "${target}" requires --yes (preview with --dry-run).\nExample: horneroctl profile revert --to ${target} --dry-run')
	}
	dir := resolve_profile_dir_for_id(target)
	p := read_profile_from_dir(dir) or {
		return fail_result(cmd, 'no ${target} snapshot available to revert to.')
	}
	if opts.dry_run {
		live := capture_live_system_state()
		changes, will_restart_pw, hw_missing, missing_apps := compute_profile_diff(p,
			dir, live, p.domains)
		return ok_result(cmd, 'Dry run: would revert to "${target}" (${changes.len} change(s), restart_pipewire=${will_restart_pw && !opts.no_restart_pipewire}). Nothing was changed.',
			{
				'dry_run':               'true'
				'id':                    target
				'changes_count':         '${changes.len}'
				'changes':               json2.encode(changes, escape_unicode: true)
				'will_restart_pipewire': (will_restart_pw && !opts.no_restart_pipewire).str()
				'hardware_missing':      json2.encode(hw_missing, escape_unicode: true)
				'missing_apps':          json2.encode(missing_apps, escape_unicode: true)
			})
	}
	return apply_loaded_profile(p, dir, p.domains, opts.no_restart_pipewire, false, 'revert')
}

pub fn profile_delete_result(id string, dry_run bool, yes bool) CommandResult {
	cmd := 'profile delete'
	if !valid_profile_id(id) {
		return fail_result(cmd, 'invalid profile id: ${id}.\nExample: horneroctl profile delete music-prod --dry-run')
	}
	if id == 'baseline' || id == 'previous' {
		return fail_result(cmd, 'refusing to delete protected snapshot "${id}".')
	}
	if !yes && !dry_run {
		return fail_result(cmd, 'deleting profile "${id}" requires --yes (preview with --dry-run).\nExample: horneroctl profile delete ${id} --dry-run')
	}
	dir := resolve_profile_dir_for_id(id)
	if !os.is_file(os.join_path(dir, 'profile.json')) {
		return fail_result(cmd, 'profile not found: ${id}.\nRun: horneroctl profile list')
	}
	if dry_run {
		return ok_result(cmd, 'Dry run: would delete profile "${id}" at ${dir}. Nothing was removed.',
			{
				'dry_run': 'true'
				'id':      id
				'path':    dir
			})
	}
	os.rmdir_all(dir) or {
		return fail_result(cmd, 'cannot delete ${dir}: ${err.msg()}')
	}
	if read_active_profile_id() == id {
		os.rm(profile_active_file()) or {}
	}
	return ok_result(cmd, 'Deleted profile "${id}".', {
		'id':   id
		'path': dir
	})
}

pub fn profile_launch_apps_result(id string, app_filter string, dry_run bool, yes bool) CommandResult {
	cmd := 'profile launch-apps'
	if !valid_profile_id(id) {
		return fail_result(cmd, 'invalid profile id: ${id}.\nExample: horneroctl profile launch-apps music-prod --dry-run')
	}
	if !yes && !dry_run {
		return fail_result(cmd, 'launching companion apps for "${id}" requires --yes (preview with --dry-run).\nExample: horneroctl profile launch-apps ${id} --dry-run')
	}
	dir := resolve_profile_dir_for_id(id)
	p := read_profile_from_dir(dir) or {
		return fail_result(cmd, 'profile not found: ${id}.\nRun: horneroctl profile list')
	}
	live_apps, _, _ := evaluate_profile_apps(p.apps, profile_running_proc_names())
	mut targets := []ProfileAppLive{}
	if app_filter.len > 0 {
		for a in live_apps {
			if a.id == app_filter {
				targets << a
				break
			}
		}
		if targets.len == 0 {
			return fail_result(cmd, 'app "${app_filter}" is not in profile "${id}".')
		}
	} else {
		targets = live_apps.clone()
	}
	mut commands := []string{}
	mut to_launch := []ProfileAppLive{}
	mut skipped_apps := []string{}
	for a in targets {
		if a.running {
			skipped_apps << '${a.id} (already running)'
			continue
		}
		if !a.installed {
			skipped_apps << '${a.id} (not installed)'
			continue
		}
		prog, args := build_detached_launch_cmd(a.exec)
		commands << command_line(prog, args)
		to_launch << a
	}
	if dry_run {
		mut app_ids := []string{}
		for a in to_launch {
			app_ids << a.id
		}
		return ok_result(cmd, 'Dry run: would launch ${to_launch.len} app(s): ${if commands.len > 0 {
			commands.join('; ')
		} else {
			'(none)'
		}}.',
			{
				'dry_run':  'true'
				'id':       id
				'apps':     json2.encode(app_ids, escape_unicode: true)
				'commands': json2.encode(commands, escape_unicode: true)
				'skipped':  json2.encode(skipped_apps, escape_unicode: true)
			})
	}
	mut launched := []string{}
	mut exec_cmds := []string{}
	mut warnings := []string{}
	for a in to_launch {
		ok, cmd_line, warn := launch_app_detached(a)
		if cmd_line.len > 0 {
			exec_cmds << cmd_line
		}
		if ok {
			launched << a.id
		} else if warn.len > 0 {
			warnings << warn
		}
	}
	mut msg := 'Launched ${launched.len} app(s) for profile "${id}"'
	if launched.len > 0 {
		msg += ': ${launched.join(', ')}'
	}
	if skipped_apps.len > 0 {
		msg += '. Skipped: ${skipped_apps.join(', ')}'
	}
	if warnings.len > 0 {
		msg += '. Warnings: ${warnings.join('; ')}'
	}
	return ok_result(cmd, msg, {
		'id':       id
		'launched': json2.encode(launched, escape_unicode: true)
		'skipped':  json2.encode(skipped_apps, escape_unicode: true)
		'commands': json2.encode(exec_cmds, escape_unicode: true)
		'warnings': json2.encode(warnings, escape_unicode: true)
	})
}

pub fn profile_export_result(id string, file string, portable bool, dry_run bool, yes bool) CommandResult {
	cmd := 'profile export'
	if !valid_profile_id(id) {
		return fail_result(cmd, 'invalid profile id: ${id}.\nExample: horneroctl profile export music-prod ./music-prod.json --dry-run')
	}
	if file.len == 0 {
		return fail_result(cmd, 'missing output file path.\nExample: horneroctl profile export ${id} ./${id}.json --dry-run')
	}
	if !yes && !dry_run {
		return fail_result(cmd, 'exporting profile "${id}" to ${file} requires --yes (preview with --dry-run).\nExample: horneroctl profile export ${id} ${file} --dry-run')
	}
	dir := resolve_profile_dir_for_id(id)
	mut p := read_profile_from_dir(dir) or {
		return fail_result(cmd, 'profile not found: ${id}.\nRun: horneroctl profile list')
	}
	if portable {
		p.hostname = ''
	}
	pw_files := read_profile_dropin_files(dir, false, p.audio.pipewire_dropins)
	jack_files := read_profile_dropin_files(dir, true, p.audio.jack_dropins)
	if dry_run {
		return ok_result(cmd, 'Dry run: would export profile "${id}" (portable=${portable}, ${pw_files.len + jack_files.len} embedded drop-in(s)) to ${file}. Nothing was written.',
			{
				'dry_run':  'true'
				'id':       id
				'file':     file
				'portable': portable.str()
			})
	}
	bundle := WorkspaceProfileBundle{
		api_version:           profile_api_version
		kind:                  profile_bundle_kind
		portable:              portable
		profile:               p
		pipewire_dropin_files: pw_files
		jack_dropin_files:     jack_files
	}
	write_file_atomic(file, json2.encode(bundle, escape_unicode: true) + '\n') or {
		return fail_result(cmd, 'cannot write ${file}: ${err.msg()}')
	}
	return ok_result(cmd, 'Exported profile "${id}" to ${file} (portable=${portable}).', {
		'id':       id
		'file':     file
		'portable': portable.str()
	})
}

fn valid_dropin_filename(name string) bool {
	return name.len > 5 && name.ends_with('.conf') && !name.contains('/') && !name.contains('..')
		&& !name.contains('\x00')
}

pub fn profile_import_result(file string, new_id string, dry_run bool, yes bool) CommandResult {
	cmd := 'profile import'
	if file.len == 0 {
		return fail_result(cmd, 'missing bundle file path.\nExample: horneroctl profile import ./music-prod.json --dry-run')
	}
	if !os.is_file(file) {
		return fail_result(cmd, 'bundle file not found: ${file}')
	}
	raw := os.read_file(file) or {
		return fail_result(cmd, 'cannot read ${file}: ${err.msg()}')
	}
	bundle := json2.decode[WorkspaceProfileBundle](raw) or {
		return fail_result(cmd, 'invalid profile bundle JSON in ${file}: ${err.msg()}')
	}
	if bundle.api_version != profile_api_version || bundle.kind != profile_bundle_kind {
		return fail_result(cmd, 'unsupported bundle api_version/kind in ${file} (expected ${profile_api_version} / ${profile_bundle_kind})')
	}
	target_id := if new_id.len > 0 { new_id } else { bundle.profile.id }
	if !valid_profile_id(target_id) {
		return fail_result(cmd, 'invalid profile id "${target_id}".\nExample: horneroctl profile import ${file} --id my-profile --yes')
	}
	if target_id in profile_reserved_ids {
		return fail_result(cmd, '"${target_id}" is a reserved snapshot name; pass --id <new-id>.')
	}
	for fname, _ in bundle.pipewire_dropin_files {
		if !valid_dropin_filename(fname) {
			return fail_result(cmd, 'unsafe PipeWire drop-in filename in bundle: ${fname}')
		}
	}
	for fname, _ in bundle.jack_dropin_files {
		if !valid_dropin_filename(fname) {
			return fail_result(cmd, 'unsafe JACK drop-in filename in bundle: ${fname}')
		}
	}
	if !yes && !dry_run {
		return fail_result(cmd, 'importing profile "${target_id}" requires --yes (preview with --dry-run).\nExample: horneroctl profile import ${file} --dry-run')
	}
	target_dir := resolve_profile_dir_for_id(target_id)
	if dry_run {
		return ok_result(cmd, 'Dry run: would import profile "${target_id}" into ${target_dir}. Nothing was written.',
			{
				'dry_run': 'true'
				'id':      target_id
				'path':    target_dir
				'file':    file
			})
	}
	mut p := bundle.profile
	p.id = target_id
	if p.name.len == 0 {
		p.name = target_id
	}
	if p.domains.len == 0 {
		p.domains = profile_all_domains.clone()
	}
	p.updated_at = profile_iso_now()
	if p.created_at.len == 0 {
		p.created_at = p.updated_at
	}
	write_profile_dir(target_dir, p, bundle.pipewire_dropin_files, bundle.jack_dropin_files) or {
		return fail_result(cmd, 'cannot materialize imported profile "${target_id}": ${err.msg()}')
	}
	return ok_result(cmd, 'Imported profile "${target_id}" into ${target_dir}.', {
		'id':   target_id
		'path': target_dir
		'file': file
	})
}
