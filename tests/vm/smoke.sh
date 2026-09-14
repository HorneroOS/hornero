#!/usr/bin/env bash
# smoke.sh - CLI-level guest validation of the pinned composition in a VM.
#
# Boots an Arch cloud image with KVM, copies in the horneroctl binary built
# from this repository plus the pinned config checkout, materializes the
# composition inside the guest, and validates it there (config
# paths/validate/show, theme manifest parse, shell syntax of shipped
# scripts). Idempotent work dir; safe to re-run (reuses overlay and seed
# key, re-materializes from scratch).
#
# NOT wired into CI: GitHub runners have no KVM. Run before cutting a
# Development Preview and paste the VM-SMOKE-PASS trailer into the release
# notes. Graphical quickshell smoke (Hyprland seat, GPU) is out of scope:
# see tests/vm/README.md.
#
# Bring-up notes (Arch cloud image under qemu, learned the hard way):
# - The seed MUST contain network-config (DHCP), or first boot hangs on
#   network-online forever.
# - cloud-init's final stage never completes here, so runcmd never runs:
#   all bring-up lives in bootcmd (user, keys, ssh-keygen -A, sshd).
# - sshd.service is After=network-online.target, which never resolves, so
#   sshd is started via `systemd-run` (no ordering deps).
# - cloud-init caches user-data per instance-id: bump the instance-id on
#   every seed change (this script stamps it).
# - pgrep/pkill -f must never contain the literal image filename: the
#   caller's own cmdline self-matches and the kill suicides. Patterns
#   below are written with a bracket guard (gues[t]...).
#
# Usage:
#   tests/vm/smoke.sh [--image FILE] [--work DIR] [--ssh-port N] [--keep]
#
#   --image     base cloud image (qcow2). Default: $HX_VM_IMAGE or
#               ~/.local/share/hornero/vm/Arch-cloudimg.qcow2
#   --work      scratch dir (overlay, seed, compose output).
#               Default: ~/.local/share/hornero/vm/work
#   --ssh-port  host forward for guest sshd. Default: 2222
#   --keep      leave the guest running and print how to reach it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE="${HX_VM_IMAGE:-$HOME/.local/share/hornero/vm/Arch-cloudimg.qcow2}"
WORK="$HOME/.local/share/hornero/vm/work"
SSH_PORT=2222
KEEP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image) IMAGE="$2"; shift 2 ;;
    --work) WORK="$2"; shift 2 ;;
    --ssh-port) SSH_PORT="$2"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    -h | --help) sed -n '2,32p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "smoke: unknown argument: $1" >&2; exit 2 ;;
  esac
done

pass() { echo "VM-SMOKE-PASS: $1"; }
fail() { echo "VM-SMOKE-FAIL: $1" >&2; exit 1; }

# --- 0. prerequisites (SKIP, not fail, without KVM) ---------------------------
if [[ ! -e /dev/kvm ]] || ! command -v qemu-system-x86_64 >/dev/null; then
  echo "VM-SMOKE-SKIP: no KVM (needs /dev/kvm + qemu-system-x86_64)"
  exit 0
fi
for tool in qemu-img genisoimage ssh scp python3; do
  command -v "$tool" >/dev/null || fail "missing host tool: $tool"
done
[[ -f $IMAGE ]] || fail "base image not found: $IMAGE (set --image)"
pass "host has KVM, qemu, and base image"

mkdir -p "$WORK"
OVERLAY="$WORK/guest.qcow2"
SEED_ISO="$WORK/seed.iso"
SEED_DIR="$WORK/seed"
KEY="$WORK/hx-key"
SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=$WORK/known-hosts -o ConnectTimeout=8 -i $KEY -p $SSH_PORT arch@127.0.0.1"

# --- 1. host-side composition (pins + binary + materialized root) -------------
"$ROOT/scripts/compose.sh" --work "$WORK/compose" --dest "$WORK/root" --yes \
  >/dev/null || fail "host compose.sh --yes"
CTL="$ROOT/cli/build/horneroctl"
[[ -x $CTL ]] || fail "horneroctl binary missing after compose"
pass "host composition built ($("$CTL" version 2>/dev/null || echo built))"

# --- 2. overlay + seed (idempotent; instance-id always fresh) ------------------
# Bracket guard: this pattern must not literally contain the image name.
PAT='gues[t].qcow2'
if [[ ! -f $OVERLAY ]]; then
  qemu-img create -q -f qcow2 -F qcow2 -b "$IMAGE" "$OVERLAY"
fi
pass "guest overlay ready"
[[ -f $KEY ]] || ssh-keygen -q -t ed25519 -N "" -f "$KEY"
mkdir -p "$SEED_DIR"
PUBKEY="$(cat "$KEY.pub")"
python3 - "$PUBKEY" >"$SEED_DIR/user-data" <<'EOF'
import sys
key = sys.argv[1]
print(f"""#cloud-config
users:
  - name: arch
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - {key}
ssh_pwauth: false
bootcmd:
  - ssh-keygen -A
  - "useradd -m -s /bin/bash -G wheel arch 2>/dev/null || true"
  - "echo 'arch ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/99-hx-arch && chmod 440 /etc/sudoers.d/99-hx-arch"
  - "install -d -m 700 -o arch -g arch /home/arch/.ssh"
  - "echo '{key}' > /home/arch/.ssh/authorized_keys"
  - "chmod 600 /home/arch/.ssh/authorized_keys && chown arch:arch /home/arch/.ssh/authorized_keys"
  - systemctl enable sshd.service
  - systemd-run --unit=hx-sshd --collect /usr/bin/sshd -D -e
  - echo HX-SSHD-RUNNING > /dev/ttyS0
""")
EOF
cat >"$SEED_DIR/network-config" <<'EOF'
version: 1
config:
  - type: physical
    name: eth0
    subnets:
      - type: dhcp
EOF
printf 'instance-id: hx-%s\nlocal-hostname: hx-guest\n' "$(date +%s)" >"$SEED_DIR/meta-data"
genisoimage -output "$SEED_ISO" -volid cidata -joliet -rock \
  "$SEED_DIR/user-data" "$SEED_DIR/meta-data" "$SEED_DIR/network-config" \
  >/dev/null 2>&1
pass "seed ISO built (fresh instance-id)"

# --- 3. boot -------------------------------------------------------------------
if ! pgrep -f "$PAT" >/dev/null; then
  # shellcheck disable=SC2086
  setsid -f qemu-system-x86_64 -enable-kvm -m 4096 -smp 4 \
    -drive file="$OVERLAY",if=virtio -drive file="$SEED_ISO",media=cdrom \
    -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:"$SSH_PORT"-:22 \
    -display none -serial file:"$WORK/boot.log" -serial none -monitor none \
    </dev/null >>"$WORK/qemu.log" 2>&1
fi
pass "guest booting"
ready=0
for _ in $(seq 1 30); do
  if $SSH true 2>/dev/null; then ready=1; break; fi
  sleep 10
done
[[ $ready -eq 1 ]] || fail "guest SSH never came up (see $WORK/boot.log)"
pass "guest SSH reachable"
# cloud-init regenerates guest host keys on every fresh-instance boot, so a
# stale known-hosts entry is expected (host-only VM, not an attack):
# refresh it once SSH is up to keep later diagnostics banner-free.
ssh-keygen -R "[127.0.0.1]:$SSH_PORT" -f "$WORK/known-hosts" >/dev/null 2>&1 || true
ssh-keyscan -p "$SSH_PORT" -t ed25519 127.0.0.1 >>"$WORK/known-hosts" 2>/dev/null \
  || fail "guest host-key refresh"

# --- 4. guest validation --------------------------------------------------------
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile="$WORK/known-hosts" \
  -i "$KEY" -P "$SSH_PORT" "$CTL" arch@127.0.0.1:/home/arch/horneroctl >/dev/null
# tar, not scp -r: the pin checkout carries a .git dir whose object files
# scp cannot reliably transfer (same --exclude=.git approach as the shell
# harness deploy-shell.sh; the guest never needs the pin history).
tar cf - --exclude=.git -C "$WORK/compose" config \
  | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile="$WORK/known-hosts" \
    -i "$KEY" -p "$SSH_PORT" arch@127.0.0.1 \
    'rm -rf ~/hx-config && mkdir -p ~/hx-config && tar xf - -C ~/hx-config --strip-components=1' \
  || fail "payload transfer (config pin)"
pass "payload transferred (horneroctl + config pin)"
# Guest DNS under QEMU slirp is frequently LAN-only/broken. Same cure as
# the shell harness (provision.sh): pin VM_GUEST_DNS at runtime AND
# persistently (a .d/ override on the network file that actually manages
# eth0 — a standalone file would be silently ignored), applied with
# `networkctl reload` (a full restart drops the DHCP lease under slirp).
if ! $SSH 'getent hosts archlinux.org >/dev/null 2>&1'; then
  GUEST_DNS="${VM_GUEST_DNS:-1.1.1.1}"
  dns_ok=0
  for _ in $(seq 1 6); do
    $SSH "sudo resolvectl dns eth0 $GUEST_DNS && \
      sudo rm -f /etc/systemd/network/10-harness-dns.network && \
      netfile=\$(networkctl status eth0 --no-pager 2>/dev/null | awk -F': ' '/Network File:/{ print \$2 }' | xargs -r basename) && \
      if [ -n \"\$netfile\" ]; then \
        sudo mkdir -p /etc/systemd/network/\"\${netfile}.d\" && \
        printf '[Network]\nDNS=$GUEST_DNS\n\n[DHCPv4]\nUseDNS=no\n' | \
        sudo tee /etc/systemd/network/\"\${netfile}.d\"/10-harness-dns-override.conf > /dev/null; \
      else \
        sudo mkdir -p /etc/systemd/network && \
        printf '[Match]\nName=eth0\n\n[Network]\nDHCP=yes\nDNS=$GUEST_DNS\n\n[DHCPv4]\nUseDNS=no\n' | \
        sudo tee /etc/systemd/network/05-harness-dns.network > /dev/null; \
      fi && \
      sudo networkctl reload" >/dev/null 2>&1 || true
    sleep 5
    if $SSH 'getent hosts archlinux.org >/dev/null 2>&1'; then dns_ok=1; break; fi
    sleep 5
  done
  [[ $dns_ok -eq 1 ]] || fail "guest DNS still broken after pinning $GUEST_DNS"
fi
pass "guest DNS resolves"
# Guest appearance pre-requisites (network PREP phase, before the offline
# boundary): pywal (`wal`) and materialyoucolor are hard requirements of
# dots_apply_theme, and the wallpaper PNGs are rendered on the host
# (rsvg-convert) and shipped in, mirroring deploy-shell.sh. pip installs
# with HOME pointed at the materialized root so the user site lands where
# the apply runs.
# A previous failed run may have left the guest offline (route-drop
# boundary): restore egress for prep (idempotent), the boundary section
# drops it again before the matrix.
$SSH 'sudo ip route add default via 10.0.2.2 2>/dev/null || true'
$SSH 'command -v pip3 >/dev/null 2>&1 || sudo pacman -Sy --noconfirm --needed python-pip' \
  || fail "guest python-pip install"
# pywal's default `wal` backend shells out to ImageMagick (proven: bare
# `wal -i` fails in a minimal guest with "Imagemagick wasn't found").
$SSH 'command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1 || sudo pacman -S --noconfirm --needed imagemagick' \
  || fail "guest imagemagick install"
# Arch Python is PEP 668 externally-managed: --break-system-packages is the
# documented override. Scoped to the test guest (prep phase); the install
# lands in the materialized root's user site (HOME=hx-root), never system-wide.
$SSH 'export HOME=$HOME/hx-root; python3 -m pip install --user -q --break-system-packages pywal materialyoucolor' \
  || fail "guest pip install (pywal + materialyoucolor)"
$SSH 'export HOME=$HOME/hx-root; unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME
  export PATH=$HOME/.local/bin:$PATH
  command -v wal >/dev/null && python3 -c "import materialyoucolor"' \
  || fail "guest apply deps (wal + materialyoucolor)"
pass "guest apply deps installed (wal + materialyoucolor)"
WALLS_DIR="$(mktemp -d)"
"$WORK/compose/config/scripts/render-brand-assets.sh" --wallpapers "$WALLS_DIR" \
  >/dev/null || fail "host wallpaper render"
tar cf - -C "$WALLS_DIR" . | $SSH '
  export HOME=$HOME/hx-root; unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME
  mkdir -p "$HOME/.local/share/hornero/wallpapers"
  tar xf - -C "$HOME/.local/share/hornero/wallpapers"' || fail "guest wallpaper ship"
rm -rf "$WALLS_DIR"
pass "wallpaper PNGs rendered on host and shipped to guest"
$SSH 'HORNERO_MATERIALIZE_BIN=$HOME/hx-config/scripts/materialize.sh ./horneroctl config materialize --dest $HOME/hx-root --yes >/dev/null' \
  || fail "guest materialize"
pass "guest materialized composition"
$SSH 'export HOME=$HOME/hx-root; unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME
  ./horneroctl config paths >/dev/null && ./horneroctl config validate' \
  || fail "guest config validate"
pass "guest config validate: valid"
$SSH 'export HOME=$HOME/hx-root; unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME
  mkdir -p $HOME/.config/hornero; printf "{}\n" > $HOME/.config/hornero/shell.json
  ./horneroctl config show >/dev/null' || fail "guest config show"
pass "guest config show parses"
EXPECTED_THEMES="$(python3 -c "import json; print(len(json.load(open('$WORK/compose/config/profiles/themes/wallpapers.manifest.json'))['themes']))")"
GUEST_THEMES="$($SSH 'python3 -c "import json; print(len(json.load(open(\"hx-root/.local/share/hornero/themes/wallpapers.manifest.json\"))[\"themes\"]))"')" \
  || fail "guest manifest entries"
[[ $GUEST_THEMES == "$EXPECTED_THEMES" ]] || fail "guest manifest entries ($GUEST_THEMES != $EXPECTED_THEMES)"
pass "guest theme manifest: $GUEST_THEMES entries (matches config pin)"
$SSH 'for f in hx-config/bin/dots-* hx-config/lib/dots/*.sh hx-config/scripts/*.sh; do bash -n "$f" || exit 1; done' \
  || fail "guest shell syntax"
pass "guest shell syntax of shipped scripts"
# --- 4b. offline boundary ------------------------------------------------------
# All network prep is done. Drop the default route: packets for the slirp
# host (10.0.2.2, SSH) still flow over the connected route, but nothing
# leaves the guest. Every appearance assertion below runs offline.
# Route drops must cover both families: QEMU slirp can egress IPv6 even
# with the v4 default gone. resolved caches are flushed so the DNS probe
# cannot pass on prep-phase answers.
$SSH 'sudo ip route del default 2>/dev/null; sudo ip -6 route del default 2>/dev/null; sudo resolvectl flush-caches 2>/dev/null; true' \
  || fail "guest offline boundary"
$SSH true || fail "guest SSH died with the default route (boundary broke SSH)"
leak=""
if $SSH 'getent hosts archlinux.org >/dev/null 2>&1'; then leak="dns"; fi
if [[ -z $leak ]] && $SSH 'python3 -c "import urllib.request; urllib.request.urlopen(\"https://archlinux.org\", timeout=8)" >/dev/null 2>&1'; then leak="https"; fi
if [[ -n $leak ]]; then
  fail "guest still reaches the internet via $leak (offline boundary broken)"
fi
pass "guest is offline (no DNS, no HTTPS egress; host SSH alive)"
# --- 4c. official trio matrix --------------------------------------------------
# Each official theme goes through the real control plane
# (`horneroctl appearance theme set --yes`: validate -> resolve -> apply via
# dots-appearance -> verify mode+GTK), then `theme get` must read the id
# back and the consumer files must agree. No hand-editing between themes.
GENV='export HOME=$HOME/hx-root; unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME; export PATH=$HOME/.local/bin:$PATH'
for spec in \
  "hornero-dark:Hornero-Dark:hornero-dark/hornero-dark-01.png:dark" \
  "hornero-light:Hornero-Light:hornero-light/hornero-light-01.png:light" \
  "pampa:Hornero-Pampa:pampa/pampa-01.png:dark"; do
  id="${spec%%:*}"; rest="${spec#*:}"
  gtk="${rest%%:*}"; rest="${rest#*:}"
  wall="${rest%%:*}"; mode="${rest##*:}"
  if ! bout="$($SSH "$GENV; ./horneroctl appearance theme set $id --yes" 2>&1)"; then
    fail "guest theme set $id: $bout"
  fi
  $SSH "$GENV; ./horneroctl appearance theme get" | grep -q "current theme: $id (mode=$mode," \
    || fail "guest theme get $id"
  $SSH "$GENV; grep -q \"^gtk-theme-name=$gtk\$\" \$HOME/.config/gtk-3.0/settings.ini" \
    || fail "guest GTK mapping $id ($gtk)"
  $SSH "$GENV; grep -q \"$wall\$\" \$HOME/.local/state/hornero/wallpaper/path" \
    || fail "guest wallpaper pointer $id ($wall)"
  $SSH "$GENV; test -f \$HOME/.config/kitty/kitty.conf" \
    || fail "guest kitty palette $id"
  $SSH "$GENV; test -f \$HOME/.cache/hornero/smart-colors/scheme.json" \
    || fail "guest M3 scheme $id"
  pass "guest official theme $id (set+get+GTK+wallpaper+kitty+M3)"
done
pass "guest trio matrix: hornero-dark hornero-light pampa applied via horneroctl (offline)"
$SSH 'sudo ip route add default via 10.0.2.2' || true

# --- 5. done --------------------------------------------------------------------
if [[ $KEEP -eq 1 ]]; then
  echo "VM-SMOKE-PASS: guest left running; ssh -i $KEY -p $SSH_PORT arch@127.0.0.1"
else
  $SSH 'sudo -n poweroff' >/dev/null 2>&1 || true
  sleep 5
  PIDS="$(pgrep -f "$PAT" || true)"
  [[ -n $PIDS ]] && kill $PIDS 2>/dev/null || true
  pass "guest shut down"
fi
echo "VM-SMOKE-PASS: ALL GREEN (work dir: $WORK)"
