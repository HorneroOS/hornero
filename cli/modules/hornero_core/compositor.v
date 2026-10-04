module hornero_core

import os

// active_compositor identifies the session from compositor-owned environment.
// Prefer Niri when nested sessions inherit a parent's Hyprland signature.
// Unknown compositors remain unknown until an adapter is implemented.
pub fn active_compositor() string {
	if os.getenv('NIRI_SOCKET').len > 0 {
		return 'niri'
	}
	if os.getenv('HYPRLAND_INSTANCE_SIGNATURE').len > 0 {
		return 'hyprland'
	}
	return 'unknown'
}
