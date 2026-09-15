# VM smoke tests

Two levels share the KVM discipline (no CI wiring: runners have no KVM;
without `/dev/kvm` both scripts exit 0 with `*-SKIP`).

## CLI smoke (`smoke.sh`)

CLI-level guest validation of the pinned composition. Boots an Arch cloud
image under KVM, materializes the composition inside the guest, and runs
the same checks `scripts/compose.sh` runs on the host (plus a shell-syntax
pass over every shipped config script).

## Appearance matrix (`tests/vm/p2-screenshots.sh`)

Preview 2 graphical evidence: for each official theme
(`hornero-dark`, `hornero-light`, `pampa`) applies it through the real
control plane (`horneroctl appearance theme set --yes`) inside a live
Hyprland + Hornero Shell session and captures ten cells per theme
(`desktop`, `kitty`, `gtk3`, `gtk4`, `qt6`, `launcher`, `dashboard`,
`adwaita`, `lockscreen`, `hyprlock`) plus machine-readable state, all
offline behind the same firewall discipline as `smoke.sh`.

```bash
tests/vm/p2-screenshots.sh [--work DIR] [--ssh-port N] [--keep]
```

Hardening learned from review (each fails loudly instead of
mislabeling): zero-client verification after every close (kitty's
close-confirm survives `killactive`), per-theme fresh sessions (a
released hyprlock poisons the next shell lock), effective-lock asserts
from locker logs, and shell-IPCs verified after every lock/unlock.
The Qt cell captures CopyQ itself (the shipped Qt6 app) under the
theme's generated `qt6ct` palette, with `QT_QPA_PLATFORMTHEME=qt6ct` set
explicitly at launch because the harness test-session compositor does
not source the deployed `environment.conf` (the deployed pin is
asserted per theme in the state snapshot); the `adwaita`
cell captures `loupe` on the theme wallpaper (libadwaita follows the
color scheme by design, see config `docs/DECISIONS.md`). Contact
sheets are generated from the shots dir with ImageMagick `montage`.

## Graphical smoke (`scripts/graphical-smoke.sh`)

Graphical guest validation of the pinned composition. Runs
`scripts/compose.sh --yes`, then invokes the shell pin's graphical
scenario (HorneroOS/shell `tests/vm/scenarios/vm-smoke.sh`) with the
composed environment (`HX_CONFIG_PIN`, `HX_MATERIALIZE_BIN`,
`HX_HOREROCTL_BIN`, `HX_MANIFEST`), so the pinned shell plus the pinned
config are exercised together under Hyprland on virtio-vga.

```bash
scripts/graphical-smoke.sh [--manifest FILE] [--work DIR] [--ssh-port N] [--keep] SUBCOMMAND
# subcommands: start status exec screenshot smoke(stop by default) stop
```

The `smoke` subcommand merges a structured result object
`{status,checks,artifacts,duration}` into the harness `assertions.json`
(additive: existing keys are untouched) and also writes `result.json`
under the work dir. The shell pin must carry harness composition support
(`HX_CONFIG_PIN` in its `tests/vm/lib/env.sh`); otherwise the run fails
with a clear message instead of silently testing shell-local only.

## Scope

- IN: `horneroctl config materialize/paths/validate/show` in a pristine
  Arch guest, theme-manifest parse, `bash -n` over `bin/dots-*`,
  `lib/dots/*.sh`, `scripts/*.sh`.
- OUT: anything graphical. There is no GPU/seat in this VM, so the
  quickshell shell never starts here. QML syntax is covered by shell CI
  (`lint_qml.sh`); `dots-appearance doctor` runs in the guest for
  information only (missing scheme/pointer on a fresh root is expected).

## Run

```bash
tests/vm/smoke.sh [--image FILE] [--work DIR] [--ssh-port N] [--keep]
```

Defaults: image `~/.local/share/hornero/vm/Arch-cloudimg.qcow2`
(`$HX_VM_IMAGE` overrides), work `~/.local/share/hornero/vm/work`.
`--keep` leaves the guest running and prints the ssh command.

The base image is NOT in this repo (559 MB). Fetch it once:

```bash
mkdir -p ~/.local/share/hornero/vm
curl -L -o ~/.local/share/hornero/vm/Arch-cloudimg.qcow2 \
  https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2
# verify against the published .SHA256 before first use
```

## Why not CI

GitHub runners have no KVM, so this stays a manual pre-release gate:
without `/dev/kvm` the script exits 0 with `VM-SMOKE-SKIP`. Paste the
`VM-SMOKE-PASS: ALL GREEN` trailer into the release notes as evidence.

## Bring-up notes

The Arch cloud image needs three seed ingredients (see `smoke.sh`
header): `network-config` (DHCP, else first boot hangs on
network-online), all SSH bring-up in `bootcmd` (the final stage never
completes, so `runcmd` never runs), and `sshd` via `systemd-run`
(`sshd.service` is `After=network-online.target`). `instance-id` is
stamped per run because cloud-init caches user-data per instance.
