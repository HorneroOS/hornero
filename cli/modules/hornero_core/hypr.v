module hornero_core

import os
import x.json2

// Hyprland desktop controls ported from the dots-* reference scripts:
// - `dots-hypr-animations` profiles (default|cozy|cyberpunk|nature|minimal|
//   vaporwave) applied live via `hyprctl keyword bezier/animation` from the
//   hyprland.conf.d profile confs, with the active profile persisted under
//   XDG state (dots/hypr-animations/current).
// - `dots-hypr-layout` profiles (scrolling|dwindle|master) applied via
//   `hyprctl keyword general:layout` (+ the scrolling tunables), persisted
//   under XDG state (dots/hypr-layout/current).
// - `dots-hypr-monitors` arrangements (internal-only, external-only,
//   extend-*, mirror, disable-external) applied via `hyprctl keyword
//   monitor`, with the internal/external split read from
//   `hyprctl monitors -j` (eDP* first, else first/second entry).
// - `dots-next-workspace` next/prev cycling via i3-msg (the legacy script
//   is i3-msg based: ordered `set $WS` names from the config, focused
//   workspace from get_workspaces, with wrap-around).
// - `dots-hyprland-plugins` ScrollOverview status via `hyprpm list`
//   (read-only) plus the idempotent install/enable/reload bootstrap
//   via `hyprpm update/add/enable/reload`.
//
// Reads (list/current/status) never fail on a missing compositor: they
// report persisted state, defaults, or backend presence. Mutations need
// --yes; --dry-run only previews.

// resolve_hyprctl_bin locates hyprctl. Override with HORNERO_HYPRCTL_BIN.
pub fn resolve_hyprctl_bin() string {
	env := os.getenv('HORNERO_HYPRCTL_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('hyprctl')
}

// resolve_hyprpm_bin locates hyprpm. Override with HORNERO_HYPRPM_BIN.
pub fn resolve_hyprpm_bin() string {
	env := os.getenv('HORNERO_HYPRPM_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('hyprpm')
}

// resolve_i3_msg_bin locates i3-msg. Override with HORNERO_I3_MSG_BIN.
pub fn resolve_i3_msg_bin() string {
	env := os.getenv('HORNERO_I3_MSG_BIN')
	if env.len > 0 {
		return env
	}
	return find_on_path('i3-msg')
}

// hypr_conf_dir is $XDG_CONFIG_HOME/hypr/hyprland.conf.d (else
// $HOME/.config/...), home of the animations[-<profile>].conf files.
fn hypr_conf_dir() string {
	mut base := os.getenv('XDG_CONFIG_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.config')
	}
	return os.join_path(base, 'hypr', 'hyprland.conf.d')
}

// hypr_state_base is $XDG_STATE_HOME (else $HOME/.local/state).
fn hypr_state_base() string {
	mut base := os.getenv('XDG_STATE_HOME')
	if base.len == 0 {
		base = os.join_path(os.home_dir(), '.local', 'state')
	}
	return base
}

// resolve_hypr_animations_state_file locates the persisted animation
// profile pointer. Override with HORNERO_HYPR_ANIMATIONS_STATE_FILE.
pub fn resolve_hypr_animations_state_file() string {
	env := os.getenv('HORNERO_HYPR_ANIMATIONS_STATE_FILE')
	if env.len > 0 {
		return env
	}
	return os.join_path(hypr_state_base(), 'dots', 'hypr-animations', 'current')
}

// resolve_hypr_layout_state_file locates the persisted layout pointer.
// Override with HORNERO_HYPR_LAYOUT_STATE_FILE.
pub fn resolve_hypr_layout_state_file() string {
	env := os.getenv('HORNERO_HYPR_LAYOUT_STATE_FILE')
	if env.len > 0 {
		return env
	}
	return os.join_path(hypr_state_base(), 'dots', 'hypr-layout', 'current')
}

fn hyprctl_or_fail(leaf string, dry_run bool) !string {
	bin := resolve_hyprctl_bin()
	if bin.len == 0 {
		if dry_run {
			return 'hyprctl'
		}
		return error('hyprctl not found. This command requires Hyprland.\nExample: horneroctl hypr ${leaf} --dry-run')
	}
	return bin
}

// read_state_token reads the first whitespace-delimited token of a state
// file, or '' when the file is missing/unreadable.
fn read_state_token(path string) string {
	raw := os.read_file(path) or { return '' }
	for tok in raw.split(' ') {
		t := tok.trim_space()
		if t.len > 0 {
			return t
		}
	}
	for tok in raw.split('\n') {
		t := tok.trim_space()
		if t.len > 0 {
			return t
		}
	}
	return ''
}

fn write_state_token(path string, value string) ! {
	dir := os.dir(path)
	os.mkdir_all(dir) or { return error('cannot create state dir ${dir}: ${err}') }
	os.write_file(path, value + '\n') or { return error('cannot write state file ${path}: ${err}') }
}

// hypr_animation_profiles lists the valid animation profiles in cycle order.
pub fn hypr_animation_profiles() []string {
	return ['default', 'cozy', 'cyberpunk', 'nature', 'minimal', 'vaporwave']
}

pub fn is_valid_animation_profile(candidate string) bool {
	return candidate in hypr_animation_profiles()
}

// animation_conf_path maps a profile to its conf file: the default profile
// lives in animations.conf, every other profile in animations-<p>.conf.
fn animation_conf_path(profile string) string {
	if profile == 'default' {
		return os.join_path(hypr_conf_dir(), 'animations.conf')
	}
	return os.join_path(hypr_conf_dir(), 'animations-${profile}.conf')
}

// animation_current_profile reports the persisted profile (default when
// the state file is missing or holds an unknown value). Read-only.
pub fn animation_current_profile() string {
	cur := read_state_token(resolve_hypr_animations_state_file())
	if is_valid_animation_profile(cur) {
		return cur
	}
	return 'default'
}

// animation_list_report implements `hypr animations list` (read-only).
pub fn animation_list_report() CommandResult {
	profiles := hypr_animation_profiles()
	return ok_result('hypr animations list', profiles.join('\n'), {
		'profiles': profiles.join(',')
		'count':    profiles.len.str()
	})
}

// animation_current_report implements `hypr animations current` (read-only).
pub fn animation_current_report() CommandResult {
	cur := animation_current_profile()
	return ok_result('hypr animations current', cur, {
		'profile': cur
	})
}

// animation_next_profile cycles one step forward from the persisted profile.
pub fn animation_next_profile() string {
	profiles := hypr_animation_profiles()
	cur := animation_current_profile()
	for i, p in profiles {
		if p == cur {
			return profiles[(i + 1) % profiles.len]
		}
	}
	return profiles[0]
}

// parse_animation_conf extracts the `bezier = ...` and `animation = ...`
// values from a profile conf (beziers first, mirroring the legacy script
// which defines beziers before the animations referencing them).
fn parse_animation_conf(path string) !([]string, []string) {
	raw := os.read_file(path) or { return error('profile config not found: ${path}') }
	mut beziers := []string{}
	mut anims := []string{}
	for line in raw.split_into_lines() {
		t := line.trim_space()
		if t.starts_with('bezier = ') {
			beziers << t.all_after('bezier = ').trim_space()
		} else if t.starts_with('animation = ') {
			anims << t.all_after('animation = ').trim_space()
		}
	}
	return beziers, anims
}

pub struct AnimationApplyOptions {
pub:
	profile   string
	dry_run   bool
	yes       bool
	ephemeral bool // do not persist the selection to disk
}

// animation_apply_report implements `hypr animations set|next|restore`:
// validate, apply the profile conf live via hyprctl keywords, persist the
// selection (unless ephemeral). Mutating: needs --yes; --dry-run previews.
pub fn animation_apply_report(opts AnimationApplyOptions) CommandResult {
	if !is_valid_animation_profile(opts.profile) {
		return fail_result('hypr animations set', 'unsupported profile: ${opts.profile}.\nAvailable: ${hypr_animation_profiles().join(' ')}.\nRun: horneroctl hypr animations --help')
	}
	if !opts.yes && !opts.dry_run {
		return fail_result('hypr animations set', 'refusing to apply animations without --yes (preview with --dry-run).\nExample: horneroctl hypr animations set ${opts.profile} --dry-run')
	}
	conf := animation_conf_path(opts.profile)
	beziers, anims := parse_animation_conf(conf) or {
		return fail_result('hypr animations set', '[ERROR] ${err.msg()}')
	}
	bin := hyprctl_or_fail('animations set', opts.dry_run) or {
		return fail_result('hypr animations set', err.msg())
	}
	mut previews := []string{}
	for b in beziers {
		previews << command_line(bin, ['keyword', 'bezier', b])
	}
	for a in anims {
		previews << command_line(bin, ['keyword', 'animation', a])
	}
	if opts.dry_run {
		mut lines := ['would apply profile ${opts.profile} from ${conf}:']
		for p in previews {
			lines << 'would run: ${p}'
		}
		return ok_result('hypr animations set', lines.join('\n'), {
			'profile':      opts.profile
			'command_line': previews.join('; ')
			'dry_run':      'true'
		})
	}
	for b in beziers {
		rep := run_exec(ExecSpec{
			prog: bin
			args: ['keyword', 'bezier', b]
		})
		if !rep.ok {
			return fail_result('hypr animations set', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
		}
	}
	for a in anims {
		rep := run_exec(ExecSpec{
			prog: bin
			args: ['keyword', 'animation', a]
		})
		if !rep.ok {
			return fail_result('hypr animations set', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
		}
	}
	if !opts.ephemeral {
		write_state_token(resolve_hypr_animations_state_file(), opts.profile) or {
			return fail_result('hypr animations set', err.msg())
		}
	}
	return ok_result('hypr animations set', 'applied profile ${opts.profile}', {
		'profile':      opts.profile
		'command_line': previews.join('; ')
	})
}

// hypr_layouts lists the valid layout profiles.
pub fn hypr_layouts() []string {
	return ['scrolling', 'dwindle', 'master']
}

pub fn is_valid_hypr_layout(candidate string) bool {
	return candidate in hypr_layouts()
}

// layout_persisted loads the persisted layout (default when the state file
// is missing or holds an unknown value).
fn layout_persisted() string {
	cur := read_state_token(resolve_hypr_layout_state_file())
	if is_valid_hypr_layout(cur) {
		return cur
	}
	return 'scrolling'
}

// layout_live queries the running compositor via
// `hyprctl getoption general:layout` (JSON first, plain `str:` fallback),
// or '' when hyprctl is absent or the value is unparseable.
fn layout_live() string {
	bin := resolve_hyprctl_bin()
	if bin.len == 0 {
		return ''
	}
	rep := run_exec(ExecSpec{
		prog: bin
		args: ['getoption', 'general:layout', '-j']
	})
	if rep.ok {
		parsed := json2_decode_map(rep.output)
		if parsed.len > 0 {
			s := json2_str(parsed, 'str')
			if s.len > 0 {
				return s
			}
		}
	}
	rep2 := run_exec(ExecSpec{
		prog: bin
		args: ['getoption', 'general:layout']
	})
	if rep2.ok {
		for line in rep2.output.split_into_lines() {
			t := line.trim_space()
			if t.starts_with('str:') {
				v := t.all_after('str:').trim_space()
				if v.len > 0 {
					return v
				}
			}
		}
	}
	return ''
}

// layout_restore_value is the persisted pointer `hypr layout restore`
// re-applies (mirroring the legacy script; live state is ignored).
pub fn layout_restore_value() string {
	return layout_persisted()
}

// layout_current_value prefers the live compositor value, then the
// persisted pointer, then the default. Read-only, never fails.
pub fn layout_current_value() string {
	live := layout_live()
	if is_valid_hypr_layout(live) {
		return live
	}
	return layout_persisted()
}

// layout_current_report implements `hypr layout current` (read-only).
pub fn layout_current_report() CommandResult {
	cur := layout_current_value()
	return ok_result('hypr layout current', cur, {
		'layout': cur
	})
}

// layout_toggle_value flips scrolling to dwindle, anything else to scrolling.
pub fn layout_toggle_value(active string) string {
	if active == 'scrolling' {
		return 'dwindle'
	}
	return 'scrolling'
}

// layout_keywords renders the hyprctl keyword invocations applying a layout:
// scrolling sets the full scrolling profile, dwindle/master set one keyword.
fn layout_keywords(bin string, layout string) [][]string {
	if layout == 'scrolling' {
		return [
			[bin, 'keyword', 'general:layout', 'scrolling'],
			[bin, 'keyword', 'scrolling:fullscreen_on_one_column', 'true'],
			[bin, 'keyword', 'scrolling:column_width', '0.62'],
			[bin, 'keyword', 'scrolling:focus_fit_method', '1'],
			[bin, 'keyword', 'scrolling:follow_focus', 'true'],
			[bin, 'keyword', 'scrolling:follow_min_visible', '0.45'],
			[bin, 'keyword', 'scrolling:explicit_column_widths', '0.333, 0.5, 0.618, 0.75, 1.0'],
			[bin, 'keyword', 'scrolling:direction', 'right'],
		]
	}
	return [[bin, 'keyword', 'general:layout', layout]]
}

pub struct LayoutApplyOptions {
pub:
	layout    string
	dry_run   bool
	yes       bool
	ephemeral bool // do not persist the selection to disk
}

// layout_apply_report implements `hypr layout set|toggle|restore`.
// Mutating: needs --yes; --dry-run previews.
pub fn layout_apply_report(opts LayoutApplyOptions) CommandResult {
	if !is_valid_hypr_layout(opts.layout) {
		return fail_result('hypr layout set', 'invalid layout: ${opts.layout}.\nValid values: scrolling, dwindle, master.\nRun: horneroctl hypr layout --help')
	}
	if !opts.yes && !opts.dry_run {
		return fail_result('hypr layout set', 'refusing to switch layout without --yes (preview with --dry-run).\nExample: horneroctl hypr layout set ${opts.layout} --dry-run')
	}
	bin := hyprctl_or_fail('layout set', opts.dry_run) or {
		return fail_result('hypr layout set', err.msg())
	}
	steps := layout_keywords(bin, opts.layout)
	mut previews := []string{}
	for s in steps {
		previews << command_line(s[0], s[1..])
	}
	if opts.dry_run {
		mut lines := ['would apply layout ${opts.layout}:']
		for p in previews {
			lines << 'would run: ${p}'
		}
		return ok_result('hypr layout set', lines.join('\n'), {
			'layout':       opts.layout
			'command_line': previews.join('; ')
			'dry_run':      'true'
		})
	}
	for s in steps {
		rep := run_exec(ExecSpec{
			prog: s[0]
			args: s[1..]
		})
		if !rep.ok {
			return fail_result('hypr layout set', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
		}
	}
	if !opts.ephemeral {
		write_state_token(resolve_hypr_layout_state_file(), opts.layout) or {
			return fail_result('hypr layout set', err.msg())
		}
	}
	return ok_result('hypr layout set', 'applied layout ${opts.layout}', {
		'layout':       opts.layout
		'command_line': previews.join('; ')
	})
}

// layout_status_report implements `hypr layout status` (read-only): live
// value, persisted pointer, and backend presence. It never fails.
pub fn layout_status_report() CommandResult {
	cur := layout_current_value()
	saved := layout_persisted()
	bin := resolve_hyprctl_bin()
	mut lines := []string{}
	mut data := map[string]string{}
	lines << 'layout: ${cur}'
	lines << 'persisted: ${saved}'
	lines << 'hyprctl: ${describe_bin(bin)}'
	data['layout'] = cur
	data['persisted'] = saved
	data['hyprctl'] = describe_bin(bin)
	return ok_result('hypr layout status', lines.join('\n'), data)
}

// hypr_monitor_modes lists the valid monitor arrangement modes.
pub fn hypr_monitor_modes() []string {
	return ['internal-only', 'external-only', 'extend-right', 'extend-left', 'extend-above',
		'extend-below', 'mirror', 'disable-external']
}

pub fn is_valid_monitor_mode(candidate string) bool {
	return candidate in hypr_monitor_modes()
}

struct MonitorInfo {
	name     string
	width    int
	height   int
	refresh  string
	scale    string
	is_inner bool // eDP* naming convention
}

// monitors_live queries `hyprctl monitors -j`, or [] when hyprctl is absent
// or the output is unparseable.
fn monitors_live() []MonitorInfo {
	bin := resolve_hyprctl_bin()
	if bin.len == 0 {
		return []
	}
	rep := run_exec(ExecSpec{
		prog: bin
		args: ['monitors', '-j']
	})
	if !rep.ok {
		return []
	}
	return parse_monitors_json(rep.output)
}

// split_monitors picks internal (first eDP*, else first entry) and external
// (first non-eDP, else second entry) names plus per-name geometry.
fn split_monitors(mons []MonitorInfo) (string, string, map[string]MonitorInfo) {
	mut by_name := map[string]MonitorInfo{}
	for m in mons {
		by_name[m.name] = m
	}
	mut internal := ''
	mut external := ''
	for m in mons {
		if internal.len == 0 && m.is_inner {
			internal = m.name
		}
		if external.len == 0 && !m.is_inner {
			external = m.name
		}
	}
	if internal.len == 0 && mons.len > 0 {
		internal = mons[0].name
	}
	if external.len == 0 && mons.len > 1 {
		for m in mons {
			if m.name != internal {
				external = m.name
				break
			}
		}
	}
	return internal, external, by_name
}

// monitor_needs_external reports whether a mode requires a second display.
fn monitor_needs_external(mode string) bool {
	return mode in ['external-only', 'extend-right', 'extend-left', 'extend-above', 'extend-below',
		'mirror']
}

// monitor_keywords renders the `monitor ...` keyword specs for a mode,
// mirroring the legacy script (preferred/auto placements, mirror,
// disable). Callers pass the resolved split: empty names select the
// eDP-1/HDMI-A-1 + 1920x1080 dry-run placeholders, so live callers must
// validate reachability before calling.
fn monitor_keywords(mode string, internal string, external string, mons []MonitorInfo, by_name map[string]MonitorInfo) []string {
	iname := if internal.len > 0 { internal } else { 'eDP-1' }
	ename := if external.len > 0 { external } else { 'HDMI-A-1' }
	iw := if iname in by_name { by_name[iname].width } else { 1920 }
	ih := if iname in by_name { by_name[iname].height } else { 1080 }
	ew := if ename in by_name { by_name[ename].width } else { 1920 }
	eh := if ename in by_name { by_name[ename].height } else { 1080 }
	match mode {
		'internal-only' {
			if external.len == 0 && mons.len > 0 {
				return ['${iname},preferred,auto,1']
			}
			return ['${ename},disable', '${iname},preferred,auto,1']
		}
		'external-only' {
			if external.len == 0 && mons.len > 0 {
				return ['${iname},preferred,auto,1']
			}
			return ['${iname},disable', '${ename},preferred,auto,1']
		}
		'extend-right' {
			return ['${iname},preferred,0x0,1', '${ename},preferred,${iw}x0,1']
		}
		'extend-left' {
			return ['${ename},preferred,0x0,1', '${iname},preferred,${ew}x0,1']
		}
		'extend-above' {
			return ['${ename},preferred,0x0,1', '${iname},preferred,0x${eh},1']
		}
		'extend-below' {
			return ['${iname},preferred,0x0,1', '${ename},preferred,0x${ih},1']
		}
		'mirror' {
			return ['${iname},preferred,0x0,1,mirror,${ename}']
		}
		'disable-external' {
			mut out := []string{}
			mut any := false
			for m in mons {
				if !m.is_inner {
					out << '${m.name},disable'
					any = true
				}
			}
			if !any {
				out << '${ename},disable'
			}
			return out
		}
		else {
			return []
		}
	}
}

// monitors_list_report implements `hypr monitors list` (read-only): one
// `name - WxH@refresh (Scale: s)` line per monitor from hyprctl.
pub fn monitors_list_report() CommandResult {
	mons := monitors_live()
	if mons.len == 0 {
		if resolve_hyprctl_bin().len == 0 {
			return fail_result('hypr monitors list', 'hyprctl not found. This command requires Hyprland.\nExample: horneroctl hypr monitors list --dry-run')
		}
		return fail_result('hypr monitors list', 'could not read monitor list (is Hyprland running?).')
	}
	mut lines := []string{}
	for m in mons {
		lines << '${m.name} - ${m.width}x${m.height}@${m.refresh} (Scale: ${m.scale})'
	}
	return ok_result('hypr monitors list', lines.join('\n'), {
		'count':    mons.len.str()
		'monitors': mons.map(it.name).join(',')
	})
}

// monitors_status_report implements `hypr monitors status` (read-only):
// internal/external split plus backend presence. It never fails.
pub fn monitors_status_report() CommandResult {
	bin := resolve_hyprctl_bin()
	mons := monitors_live()
	internal, external, _ := split_monitors(mons)
	mut lines := []string{}
	mut data := map[string]string{}
	lines << 'hyprctl: ${describe_bin(bin)}'
	data['hyprctl'] = describe_bin(bin)
	if mons.len == 0 {
		lines << 'monitors: unknown (is Hyprland running?)'
		data['monitors'] = 'unknown'
	} else {
		lines << 'monitors: ${mons.len}'
		data['monitors'] = mons.len.str()
	}
	if internal.len > 0 {
		lines << 'internal: ${internal}'
		data['internal'] = internal
	} else {
		lines << 'internal: unknown'
		data['internal'] = 'unknown'
	}
	if external.len > 0 {
		lines << 'external: ${external}'
		data['external'] = external
	} else {
		lines << 'external: none detected'
		data['external'] = 'none'
	}
	return ok_result('hypr monitors status', lines.join('\n'), data)
}

pub struct MonitorsSetOptions {
pub:
	mode    string
	dry_run bool
	yes     bool
}

// monitors_set_report implements `hypr monitors set <mode>`.
// Mutating: needs --yes; --dry-run previews.
pub fn monitors_set_report(opts MonitorsSetOptions) CommandResult {
	if !is_valid_monitor_mode(opts.mode) {
		return fail_result('hypr monitors set', 'unknown monitor mode: ${opts.mode}.\nValid values: ${hypr_monitor_modes().join(' ')}.\nRun: horneroctl hypr monitors --help')
	}
	if !opts.yes && !opts.dry_run {
		return fail_result('hypr monitors set', 'refusing to reconfigure monitors without --yes (preview with --dry-run).\nExample: horneroctl hypr monitors set ${opts.mode} --dry-run')
	}
	bin := hyprctl_or_fail('monitors set', opts.dry_run) or {
		return fail_result('hypr monitors set', err.msg())
	}
	mons := monitors_live()
	if mons.len == 0 && !opts.dry_run {
		return fail_result('hypr monitors set', 'could not read monitor list (is Hyprland running?).')
	}
	internal, external, by_name := split_monitors(mons)
	if mons.len > 0 && external.len == 0 {
		if monitor_needs_external(opts.mode) {
			only := if internal.len > 0 { internal } else { 'the internal display' }
			return fail_result('hypr monitors set', 'only one monitor detected (${only}): ${opts.mode} needs an external display.')
		}
		if opts.mode == 'disable-external' {
			return ok_result('hypr monitors set', 'no external monitors to disable', {
				'mode': opts.mode
			})
		}
	}
	specs := monitor_keywords(opts.mode, internal, external, mons, by_name)
	mut previews := []string{}
	for s in specs {
		previews << command_line(bin, ['keyword', 'monitor', s])
	}
	if opts.dry_run {
		mut lines := ['would apply monitor mode ${opts.mode}:']
		for p in previews {
			lines << 'would run: ${p}'
		}
		return ok_result('hypr monitors set', lines.join('\n'), {
			'mode':         opts.mode
			'command_line': previews.join('; ')
			'dry_run':      'true'
		})
	}
	for s in specs {
		rep := run_exec(ExecSpec{
			prog: bin
			args: ['keyword', 'monitor', s]
		})
		if !rep.ok {
			return fail_result('hypr monitors set', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
		}
	}
	return ok_result('hypr monitors set', 'applied monitor mode ${opts.mode}', {
		'mode':         opts.mode
		'command_line': previews.join('; ')
	})
}

// json2 helpers for the hyprctl/i3-msg JSON outputs (x.json2, never std json).

fn json2_decode_map(raw string) map[string]json2.Any {
	parsed := json2.decode[json2.Any](raw) or { return {} }
	if parsed is map[string]json2.Any {
		return parsed
	}
	return {}
}

fn json2_str(m map[string]json2.Any, key string) string {
	v := m[key] or { return '' }
	if v is string {
		return v
	}
	return ''
}

fn json2_f64(m map[string]json2.Any, key string) f64 {
	v := m[key] or { return 0 }
	if v is f64 {
		return v
	}
	if v is int {
		return f64(v)
	}
	if v is i64 {
		return f64(v)
	}
	return 0
}

fn json2_bool(m map[string]json2.Any, key string) bool {
	v := m[key] or { return false }
	if v is bool {
		return v
	}
	return false
}

fn json2_num_str(m map[string]json2.Any, key string) string {
	f := json2_f64(m, key)
	if f == f64(int(f)) {
		return int(f).str()
	}
	return f.str()
}

// parse_monitors_json parses `hyprctl monitors -j` into MonitorInfo entries,
// skipping entries without a name.
fn parse_monitors_json(raw string) []MonitorInfo {
	parsed := json2.decode[json2.Any](raw) or { return [] }
	if parsed is []json2.Any {
		mut out := []MonitorInfo{}
		for item in parsed {
			if item is map[string]json2.Any {
				name := json2_str(item, 'name')
				if name.len == 0 {
					continue
				}
				out << MonitorInfo{
					name:     name
					width:    int(json2_f64(item, 'width'))
					height:   int(json2_f64(item, 'height'))
					refresh:  json2_num_str(item, 'refreshRate')
					scale:    json2_num_str(item, 'scale')
					is_inner: name.starts_with('eDP')
				}
			}
		}
		return out
	}
	return []
}

struct I3Workspace {
	name    string
	focused bool
}

// parse_i3_workspaces parses `i3-msg -t get_workspaces` JSON.
fn parse_i3_workspaces(raw string) []I3Workspace {
	parsed := json2.decode[json2.Any](raw) or { return [] }
	if parsed is []json2.Any {
		mut out := []I3Workspace{}
		for item in parsed {
			if item is map[string]json2.Any {
				name := json2_str(item, 'name')
				if name.len == 0 {
					continue
				}
				out << I3Workspace{
					name:    name
					focused: json2_bool(item, 'focused')
				}
			}
		}
		return out
	}
	return []
}

// parse_i3_config_names extracts the ordered workspace names from
// `i3-msg -t get_config` (`set $WS <name>` lines, mirroring the legacy
// script's grep/cut pipeline; surrounding quotes are stripped).
fn parse_i3_config_names(raw string) []string {
	mut out := []string{}
	for line in raw.split_into_lines() {
		t := line.trim_space()
		if !t.contains('set \$WS') {
			continue
		}
		mut fields := []string{}
		for f in t.split(' ') {
			if f.len > 0 {
				fields << f
			}
		}
		if fields.len >= 3 && fields[0] == 'set' && fields[1].starts_with('\$WS') {
			name := fields[2..].join(' ').trim('"').trim("'").trim_space()
			if name.len > 0 {
				out << name
			}
		}
	}
	return out
}

// workspace_target picks the next/prev workspace name with wrap-around,
// defaulting to the first entry when the focused one is not listed.
fn workspace_target(names []string, focused string, prev bool) string {
	mut idx := 0
	for i, n in names {
		if n == focused {
			idx = i
			break
		}
	}
	if prev {
		return names[(idx - 1 + names.len) % names.len]
	}
	return names[(idx + 1) % names.len]
}

pub struct WorkspaceCycleOptions {
pub:
	direction string // next | prev
	dry_run   bool
	yes       bool
}

// workspace_cycle_report implements `hypr workspace next|prev`: resolve the
// ordered names plus the focused workspace live via i3-msg, then switch
// with wrap-around. Mutating: needs --yes; --dry-run previews (with a
// placeholder when no backend is reachable).
pub fn workspace_cycle_report(opts WorkspaceCycleOptions) CommandResult {
	if opts.direction !in ['next', 'prev'] {
		return fail_result('hypr workspace', 'unknown workspace direction: ${opts.direction}.\nRun: horneroctl hypr workspace --help')
	}
	if !opts.yes && !opts.dry_run {
		return fail_result('hypr workspace', 'refusing to switch workspace without --yes (preview with --dry-run).\nExample: horneroctl hypr workspace ${opts.direction} --dry-run')
	}
	bin := resolve_i3_msg_bin()
	prog := if bin.len > 0 { bin } else { 'i3-msg' }
	mut target := ''
	if bin.len > 0 {
		cfg := run_exec(ExecSpec{
			prog: bin
			args: ['-t', 'get_config']
		})
		ws := run_exec(ExecSpec{
			prog: bin
			args: ['-t', 'get_workspaces']
		})
		if cfg.ok && ws.ok {
			names := parse_i3_config_names(cfg.output)
			spaces := parse_i3_workspaces(ws.output)
			mut focused := ''
			for s in spaces {
				if s.focused {
					focused = s.name
					break
				}
			}
			if names.len > 0 {
				target = workspace_target(names, focused, opts.direction == 'prev')
			}
		}
	}
	if target.len == 0 {
		if !opts.dry_run {
			if bin.len == 0 {
				return fail_result('hypr workspace', 'i3-msg not found. This command requires a running i3 session. Set HORNERO_I3_MSG_BIN.\nExample: horneroctl hypr workspace ${opts.direction} --dry-run')
			}
			return fail_result('hypr workspace', 'could not resolve workspaces (is i3 running?).')
		}
		target = opts.direction
	}
	line := command_line(prog, ['workspace', target])
	if opts.dry_run {
		return ok_result('hypr workspace', 'would run: ${line}', {
			'direction':    opts.direction
			'target':       target
			'command_line': line
			'dry_run':      'true'
		})
	}
	rep := run_exec(ExecSpec{
		prog: prog
		args: ['workspace', target]
	})
	if rep.ok {
		return ok_result('hypr workspace', rep.output, {
			'direction':    opts.direction
			'target':       target
			'command_line': rep.command_line
		})
	}
	return fail_result('hypr workspace', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
}

// ScrollOverview plugin identity (dots-hyprland-plugins): status match
// strings plus the install coordinates used by `plugins install`.
const scrolloverview_repo_match = 'hyprland-scroll-overview'

const scrolloverview_enable_match = 'scrolloverview'

// hyprpm_list_output runs `hyprpm list`: the raw output plus whether the
// backend was actually reached (absent binary or failing exec → false).
fn hyprpm_list_output() (string, bool) {
	bin := resolve_hyprpm_bin()
	if bin.len == 0 {
		return '', false
	}
	rep := run_exec(ExecSpec{
		prog: bin
		args: ['list']
	})
	if !rep.ok {
		return '', false
	}
	return rep.output, true
}

// plugins_status_report implements `hypr plugins status` (read-only):
// hyprpm presence plus ScrollOverview installed/enabled. It never fails.
pub fn plugins_status_report() CommandResult {
	bin := resolve_hyprpm_bin()
	list, reachable := hyprpm_list_output()
	installed := list.contains(scrolloverview_repo_match)
	enabled := list.contains(scrolloverview_enable_match)
	mut lines := []string{}
	mut data := map[string]string{}
	lines << 'hyprpm: ${describe_bin(bin)}'
	data['hyprpm'] = describe_bin(bin)
	if !reachable {
		lines << 'ScrollOverview: unknown (hyprpm not reachable)'
		data['installed'] = 'unknown'
		data['enabled'] = 'unknown'
	} else if installed && enabled {
		lines << 'ScrollOverview: installed and enabled'
		data['installed'] = 'true'
		data['enabled'] = 'true'
	} else {
		lines << 'ScrollOverview: not installed or not enabled'
		data['installed'] = installed.str()
		data['enabled'] = enabled.str()
	}
	lines << 'install: owned by dots-hyprland-plugins (hyprpm/AUR-helper flow, not ported)'
	return ok_result('hypr plugins status', lines.join('\n'), data)
}

// plugins_list_report implements `hypr plugins list` (read-only): the raw
// `hyprpm list` output plus installed/enabled flags.
pub fn plugins_list_report() CommandResult {
	if resolve_hyprpm_bin().len == 0 {
		return fail_result('hypr plugins list', 'hyprpm not found. This command requires Hyprland. Set HORNERO_HYPRPM_BIN.\nExample: horneroctl hypr plugins status')
	}
	list, reachable := hyprpm_list_output()
	if !reachable {
		return fail_result('hypr plugins list', 'could not read plugin list (is Hyprland running?).')
	}
	installed := list.contains(scrolloverview_repo_match)
	enabled := list.contains(scrolloverview_enable_match)
	body := if list.trim_space().len > 0 { list.trim_space() } else { 'no plugins listed' }
	return ok_result('hypr plugins list', body, {
		'installed': installed.str()
		'enabled':   enabled.str()
	})
}

// ScrollOverview install identity: the repository `hyprpm add` installs
// and the handle `hyprpm enable` enables (dots-hyprland-plugins).
const scrolloverview_repo_url = 'https://github.com/yayuuu/hyprland-scroll-overview.git'

fn hyprpm_or_fail(leaf string, dry_run bool) !string {
	bin := resolve_hyprpm_bin()
	if bin.len == 0 {
		if dry_run {
			return 'hyprpm'
		}
		return error('hyprpm not found. This command requires Hyprland (hyprpm ships with it; on Arch: sudo pacman -S hyprland, or yay -S hyprland-git). Set HORNERO_HYPRPM_BIN.\nExample: horneroctl hypr ${leaf} --dry-run')
	}
	return bin
}

pub struct PluginsInstallOptions {
pub:
	force     bool // rebuild hyprpm headers (update -f)
	no_update bool // skip the header update (fast autostart path)
	dry_run   bool
	yes       bool
}

// plugins_install_report implements `hypr plugins install`: ensure the
// hyprpm headers, add/enable the ScrollOverview repository when needed,
// and reload it into the running session — mirroring the idempotent
// `dots-hyprland-plugins` bootstrap (safe no-op when everything is in
// place). Mutating: needs --yes; --dry-run only previews.
pub fn plugins_install_report(opts PluginsInstallOptions) CommandResult {
	if !opts.yes && !opts.dry_run {
		return fail_result('hypr plugins install', 'refusing to install plugins without --yes (preview with --dry-run).\nExample: horneroctl hypr plugins install --dry-run')
	}
	bin := hyprpm_or_fail('plugins install', opts.dry_run) or {
		return fail_result('hypr plugins install', err.msg())
	}
	mut plan := [][]string{}
	if !opts.no_update {
		if opts.force {
			plan << [bin, 'update', '-f']
		} else {
			plan << [bin, 'update']
		}
	}
	plan << [bin, 'list']
	plan << [bin, 'add', scrolloverview_repo_url]
	plan << [bin, 'enable', scrolloverview_enable_match]
	plan << [bin, 'reload', '-n']
	if opts.dry_run {
		mut lines := ['would bootstrap ScrollOverview via hyprpm:']
		mut previews := []string{}
		for s in plan {
			p := command_line(s[0], s[1..])
			previews << p
			lines << 'would run: ${p}'
		}
		lines << 'add/enable/reload run only when the plugin list needs them.'
		return ok_result('hypr plugins install', lines.join('\n'), {
			'command_line': previews.join('; ')
			'dry_run':      'true'
		})
	}
	if !opts.no_update {
		rep := if opts.force {
			run_exec(ExecSpec{
				prog: bin
				args: ['update', '-f']
			})
		} else {
			run_exec(ExecSpec{
				prog: bin
				args: ['update']
			})
		}
		if !rep.ok {
			return fail_result('hypr plugins install', 'backend failed (exit ${rep.exit_code}):\n${rep.output}')
		}
	}
	mut need_reload := false
	list, reachable := hyprpm_list_output()
	if !reachable {
		return fail_result('hypr plugins install', 'could not read plugin list (is Hyprland running?).')
	}
	if !list.contains(scrolloverview_repo_match) {
		add := run_exec(ExecSpec{
			prog: bin
			args: ['add', scrolloverview_repo_url]
		})
		if !add.ok {
			return fail_result('hypr plugins install', 'backend failed (exit ${add.exit_code}):\n${add.output}')
		}
		need_reload = true
	}
	current, _ := hyprpm_list_output()
	if !current.contains(scrolloverview_enable_match) {
		en := run_exec(ExecSpec{
			prog: bin
			args: ['enable', scrolloverview_enable_match]
		})
		if !en.ok {
			return fail_result('hypr plugins install', 'backend failed (exit ${en.exit_code}):\n${en.output}')
		}
		need_reload = true
	} else if opts.force {
		run_exec(ExecSpec{
			prog: bin
			args: ['enable', scrolloverview_enable_match]
		})
		need_reload = true
	}
	// The autostart --no-update path still reloads: a new Hyprland
	// process needs it to load enabled plugins into the session.
	if need_reload || opts.force || opts.no_update {
		re := run_exec(ExecSpec{
			prog: bin
			args: ['reload', '-n']
		})
		if !re.ok {
			return fail_result('hypr plugins install', 'hyprpm reload failed (not in a Hyprland session? run with status to verify)')
		}
	}
	return ok_result('hypr plugins install', 'ScrollOverview plugins installed and enabled',
		{
			'installed': 'true'
			'enabled':   'true'
		})
}
