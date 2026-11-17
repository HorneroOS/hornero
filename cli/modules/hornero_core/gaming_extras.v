module hornero_core

import os

// Gaming doctor probes beyond binary presence, plus the Steam launch-option
// helper. Everything here is read-only: no probe starts a daemon, writes a
// file, edits Steam configuration or claims game compatibility, measured
// performance or hardware qualification.

// Proton and many Windows games need a large memory-map limit; Steam Deck
// ships 2147483642 and the Arch default is 1048576. 262144 is the floor
// commonly documented for modern Proton titles.
pub const gaming_min_map_count = 262144

pub fn map_count_check(value int) DoctorCheck {
	name := 'vm-max-map-count'
	if value <= 0 {
		return DoctorCheck{
			name:   name
			ok:     true
			warn:   true
			detail: 'could not read /proc/sys/vm/max_map_count'
		}
	}
	if value < gaming_min_map_count {
		return DoctorCheck{
			name:   name
			ok:     false
			detail: 'vm.max_map_count is ${value}, below ${gaming_min_map_count}; some Proton games crash at start. Raise it with a sysctl drop-in (doctor does not change it)'
		}
	}
	return DoctorCheck{
		name:   name
		ok:     true
		detail: 'vm.max_map_count is ${value} (floor for Proton titles is ${gaming_min_map_count})'
	}
}

// nvidia_wayland_check: NVIDIA needs DRM kernel mode setting for a Wayland
// compositor. It is reported only when the proprietary module is loaded.
pub fn nvidia_modeset_check(nvidia_loaded bool, modeset string) DoctorCheck {
	name := 'nvidia-drm-modeset'
	if !nvidia_loaded {
		return DoctorCheck{
			name:   name
			ok:     true
			detail: 'not applicable: the NVIDIA kernel module is not loaded'
		}
	}
	if modeset.trim_space() == 'Y' {
		return DoctorCheck{
			name:   name
			ok:     true
			detail: 'nvidia_drm modeset=Y (required for a Wayland session on NVIDIA)'
		}
	}
	return DoctorCheck{
		name:   name
		ok:     false
		detail: 'nvidia_drm modeset is not Y (read "${modeset.trim_space()}"); set nvidia-drm.modeset=1 on the kernel command line, a Wayland session needs it'
	}
}

pub fn lib32_driver_check(nvidia_loaded bool, present bool) DoctorCheck {
	name := 'lib32-gpu-driver'
	if !nvidia_loaded {
		return DoctorCheck{
			name:   name
			ok:     true
			detail: 'not checked: the NVIDIA kernel module is not loaded (Mesa 32-bit stacks are covered by vulkan-32bit-loader)'
		}
	}
	if present {
		return DoctorCheck{
			name:   name
			ok:     true
			detail: '32-bit NVIDIA GL/Vulkan userspace present (Steam and 32-bit games need it)'
		}
	}
	return DoctorCheck{
		name:   name
		ok:     false
		detail: '32-bit NVIDIA userspace (lib32-nvidia-utils) not found; Steam and 32-bit games fail to start without it'
	}
}

// proton_builds lists Proton-style compatibility tools under the given
// roots. Roots are scanned one level deep; nothing is executed.
pub fn proton_builds(steamapps_common_dirs []string, compat_dirs []string) []string {
	mut found := []string{}
	for d in steamapps_common_dirs {
		for e in os.ls(d) or { []string{} } {
			if e.starts_with('Proton') && os.is_dir(os.join_path(d, e)) && e !in found {
				found << e
			}
		}
	}
	for d in compat_dirs {
		for e in os.ls(d) or { []string{} } {
			if os.is_dir(os.join_path(d, e)) && e !in found {
				found << e
			}
		}
	}
	found.sort()
	return found
}

pub fn proton_check(steam_installed bool, builds []string) DoctorCheck {
	name := 'proton'
	if !steam_installed {
		return DoctorCheck{
			name:   name
			ok:     true
			warn:   true
			detail: 'not checked: Steam is not installed (Proton comes with Steam)'
		}
	}
	if builds.len == 0 {
		return DoctorCheck{
			name:   name
			ok:     true
			warn:   true
			detail: 'no Proton build found yet; Steam downloads one on first use of a Windows game (Settings > Compatibility). Presence of a build is not a compatibility claim for any game'
		}
	}
	return DoctorCheck{
		name:   name
		ok:     true
		detail: '${builds.len} Proton build(s): ${builds.join(', ')} (installed, not a per-game compatibility claim)'
	}
}

// optional_bin_check reports a helper that is useful but not required:
// absent is a warning, never a failure.
pub fn optional_bin_check(name string, prog string, why string) DoctorCheck {
	found := find_on_path(prog)
	if found.len > 0 {
		return DoctorCheck{
			name:   name
			ok:     true
			detail: found
		}
	}
	return DoctorCheck{
		name:   name
		ok:     true
		warn:   true
		detail: 'optional, not installed (${why})'
	}
}

fn first_existing(paths []string) string {
	for p in paths {
		if os.exists(p) {
			return p
		}
	}
	return ''
}

pub fn gaming_probe_checks(sel GamingSelection) []DoctorCheck {
	mut checks := []DoctorCheck{}
	mut map_count := 0
	if raw := os.read_file('/proc/sys/vm/max_map_count') {
		map_count = raw.trim_space().int()
	}
	checks << map_count_check(map_count)
	nvidia := os.is_dir('/sys/module/nvidia')
	modeset := os.read_file('/sys/module/nvidia_drm/parameters/modeset') or { '' }
	checks << nvidia_modeset_check(nvidia, modeset)
	checks << lib32_driver_check(nvidia, first_existing(['/usr/lib32/libGLX_nvidia.so.0']).len > 0)
	home := os.home_dir()
	steam_root := os.join_path(home, '.local', 'share', 'Steam')
	checks << proton_check(find_on_path('steam').len > 0, proton_builds([
		os.join_path(steam_root, 'steamapps', 'common'),
	], [
		os.join_path(steam_root, 'compatibilitytools.d'),
		os.join_path(home, '.steam', 'root', 'compatibilitytools.d'),
		'/usr/share/steam/compatibilitytools.d',
	]))
	// GameMode client libraries: `gamemoderun` preloads them into the game.
	// 32-bit games need the lib32 build.
	lib64 := first_existing(['/usr/lib/libgamemodeauto.so.0', '/usr/lib64/libgamemodeauto.so.0'])
	lib32 := first_existing(['/usr/lib32/libgamemodeauto.so.0'])
	checks << DoctorCheck{
		name:   'gamemode-libs'
		ok:     lib64.len > 0 || find_on_path('gamemoderun').len == 0
		warn:   lib64.len == 0 && find_on_path('gamemoderun').len == 0
		detail: if find_on_path('gamemoderun').len == 0 {
			'gamemode is not installed'
		} else if lib64.len > 0 && lib32.len > 0 {
			'64-bit and 32-bit GameMode client libraries present; the daemon starts on demand and is not started by doctor'
		} else if lib64.len > 0 {
			'64-bit GameMode client library present, 32-bit missing (lib32-gamemode); 32-bit games will not be optimised'
		} else {
			'gamemoderun is installed but libgamemodeauto is missing'
		}
	}
	return checks
}

// ---- Steam launch options ------------------------------------------------

pub struct LaunchOptionsRequest {
pub:
	gamemode   bool
	mangohud   bool
	gamescope  bool
	width      int
	height     int
	refresh    int
	fullscreen bool
}

// steam_launch_options composes one Steam "Launch Options" string from the
// tools that are actually installed. `available` maps a tool id to its
// presence. Missing tools are omitted and reported in `notes`; the string is
// printed, never written to Steam's configuration.
pub fn steam_launch_options(req LaunchOptionsRequest, available map[string]bool) (string, []string) {
	mut notes := []string{}
	mut inner := []string{}
	if req.gamemode {
		if available['gamemode'] {
			inner << 'gamemoderun'
		} else {
			notes << 'gamemoderun is not installed; omitted'
		}
	}
	if req.mangohud {
		if available['mangohud'] {
			inner << 'mangohud'
		} else {
			notes << 'mangohud is not installed; omitted'
		}
	}
	inner << '%command%'
	mut outer := []string{}
	if req.gamescope {
		if available['gamescope'] {
			outer << 'gamescope'
			if req.width > 0 && req.height > 0 {
				outer << '-W ${req.width} -H ${req.height}'
			}
			if req.refresh > 0 {
				outer << '-r ${req.refresh}'
			}
			if req.fullscreen {
				outer << '-f'
			}
			outer << '--'
		} else {
			notes << 'gamescope is not installed; omitted'
		}
	}
	return outer.join(' ') + if outer.len > 0 { ' ' } else { '' } + inner.join(' '), notes
}

pub fn gaming_launch_options_result(req LaunchOptionsRequest) CommandResult {
	avail := {
		'gamemode':  find_on_path('gamemoderun').len > 0
		'mangohud':  find_on_path('mangohud').len > 0
		'gamescope': find_on_path('gamescope').len > 0
	}
	opts, notes := steam_launch_options(req, avail)
	mut msg := 'Steam launch options (paste into the game Properties > Launch Options):\n  ${opts}\n'
	for n in notes {
		msg += 'note: ${n}\n'
	}
	msg += 'Printed only: horneroctl does not edit Steam configuration. These are launch composition templates; whether they help a given game or driver is not claimed, measure it with MangoHud frametimes.'
	return ok_result('gaming launch-options', msg, {
		'options':    opts
		'gamemode':   '${avail['gamemode']}'
		'mangohud':   '${avail['mangohud']}'
		'gamescope':  '${avail['gamescope']}'
		'written_to': 'nowhere (print only)'
	})
}
