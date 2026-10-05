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
supported, and Niri is experimental. Server, Agents, and Studio remain planned
until their install, runtime, security, and acceptance work is complete.

Agents inherit Server and use a rootless Podman/systemd direction. The
catalogue explicitly forbids the host Docker socket and secrets in images.
Hermes is the first workload target, not the host architecture. Studio inherits
Desktop and records REAPER/yabridge as optional user-licensed integrations;
those packages and proprietary plugins are excluded from the core package set.

Niri exposes real event-driven compositor state and uses its native screencast
path through the GNOME portal backend, with GTK providing the fallback and file
chooser portal, over PipeWire. Labwc remains planned and is not offered as an
install choice. Package and feature maturity must stay tied to the integration
evidence, not just the presence of a package name.
