# HorneroOS edition catalogue

`catalogue.yaml` is the single product source for edition package layers,
compositor choices, and maturity. Resolve an edition without installing it:

```sh
python3 scripts/resolve-edition.py desktop --json
python3 scripts/resolve-edition.py desktop --compositor niri --json
python3 scripts/resolve-edition.py server --json
```

The resolver produces a deterministic Arch package list. A package list is not
an image or proof of a working system. Desktop is in Preview, Hyprland is
supported, and Niri is experimental. Desktop and Studio are in Preview:
Studio installs from the signed v0.2.0-preview22 ISO, is not Supported,
and its hardware evidence is still pending. Server and Agents remain
planned until their install, runtime, security, and acceptance work is
complete.

Agents inherit Server and use a rootless Podman/systemd direction. The
catalogue explicitly forbids the host Docker socket and secrets in images.
Hermes is the first workload target, not the host architecture. Studio inherits
Desktop and records REAPER/yabridge as optional user-licensed integrations;
those packages and proprietary plugins are excluded from the core package set.

Every Studio package and optional integration carries `studioProvenance`
metadata: Arch source and package link, license identifiers and class,
install method, optional/opt-in state, and support maturity. The resolver
validates that metadata and exposes it as `packageProvenance` /
`optionalIntegrations` in its JSON output, so installer, CLI, and Shell
consumers never duplicate a package list. Provenance is auditable metadata,
not a support claim and never a software license grant. REAPER stays
proprietary and opt-in; yabridge is only a Wine compatibility layer for
Windows plugins the user obtained legally. AUR entries, if ever added, must
stay optional with manual install: no consumer executes AUR build recipes.

Studio workloads are composable. `studioApplications` maps stable
application IDs to packages, `studioSpecializations` defines the ten
user-facing specializations (Audio & Music Production through Custom
Selection), and `studioPlatformPackages` is the shared pro-audio platform
every selection builds on. Resolve a selection plan without installing
anything:

```sh
python3 scripts/resolve-edition.py studio \
  --specialization audio-music-production --application reaper
```

The plan is deterministic and versioned (`schemaVersion`): selected IDs,
the deduplicated package closure, and provenance for every package.
Proprietary applications in a specialization are reported under
`proprietaryOptInRequired` and only enter the package list when selected
explicitly by application ID. Experimental applications are flagged, and
reference-only entries (for example Penpot, which has no Arch package) fail
with an actionable error instead of falling back to a full workstation.

Gaming extends Desktop and is planned: it has no installable image yet.
Its package layer carries the cross-vendor Mesa/Vulkan baseline, 32-bit
compat, GameMode and MangoHud; compositor choice and graphics experience
match Desktop. Steam is not in the gaming package set: it only enters
when explicitly selected by application ID (see below).
`gamingApplications` and `gamingSpecializations` mirror Studio's
composable model with six profiles: Desktop Gaming (the only default),
Handheld, Streaming, Multi-Launcher, VR (experimental), and Advanced
Compatibility. Steam is proprietary and opt-in: only an explicit
`--application steam` selects it. AUR entries stay manual and optional,
reference-only entries (Heroic, SteamVR) fail actionably, and every package
carries `gamingProvenance`. Resolve a plan without installing anything:

```sh
python3 scripts/resolve-edition.py gaming --specialization desktop-gaming
python3 scripts/resolve-edition.py gaming --application steam
```

Gaming plans record hardware intent only. No consumer derives a GPU vendor
driver from a PCI ID, and provenance is never a hardware-compatibility or
performance claim.

Post-install, `horneroctl gaming selection show|set` records the same
selection intent in `~/.config/hornero/gaming-selection.json` (validating
IDs fail-closed; recording installs nothing), and
`horneroctl gaming doctor [--json]` reports capability and readiness
only. The Control Center Gaming pane and the QA gaming gate consume
that single state source.

The shared base carries the filesystem, encryption, and GRUB tools needed by
the Calamares installation path across editions. Desktop also owns SDDM and the
Hornero greeter packages so the selected desktop composition can boot to its
configured login screen.

The desktop package set includes the providers used by its factory defaults:
Exo's `exo-open` launcher, Material Symbols and Papirus icons, Qt6ct, and the
Rubik and Caskaydia Cove font families.

Niri exposes real event-driven compositor state and uses its native screencast
path through the GNOME portal backend, with GTK providing the fallback and file
chooser portal, over PipeWire. Labwc remains planned and is not offered as an
install choice. Package and feature maturity must stay tied to the integration
evidence, not just the presence of a package name.

The Calamares image builder generates a small `hornero-profile-*` package for
each installable composition. Its `/usr/lib/hornero/system-profile.json` file
records the resolved profile and catalogue revision for post-install
introspection; it does not define or duplicate package composition.

## Studio audio and performance modes

`studioAudioModes` defines Balanced (the only default), Low Latency, and
Advanced modes. Low Latency and Advanced require explicit opt-in, may be
calibrated per interface in Advanced, and always restore the exact previous
rate/quantum/device state on disable, error, logout, or reboot. Quantum is a
scheduling period, never physical round-trip latency, and no consumer may
present it as such. `studioPerformanceMode` is a temporary, opt-in mode that
reuses power-profiles-daemon and restores the previous power profile on
timeout, cancellation, error, or reboot. Neither contract ever forces an RT
kernel, IRQ tuning, CPU governor, GPU tuning, I/O scheduler, or
privilege-policy change.
