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
SSH="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 -i $KEY -p $SSH_PORT arch@127.0.0.1"

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

# --- 4. guest validation --------------------------------------------------------
scp -o StrictHostKeyChecking=no -i "$KEY" -P "$SSH_PORT" "$CTL" \
  arch@127.0.0.1:/home/arch/horneroctl >/dev/null
scp -qr -o StrictHostKeyChecking=no -i "$KEY" -P "$SSH_PORT" \
  "$WORK/compose/config" arch@127.0.0.1:/home/arch/hx-config >/dev/null
pass "payload transferred (horneroctl + config pin)"
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
$SSH 'python3 -c "import json; d=json.load(open(\"hx-root/.local/share/hornero/themes/wallpapers.manifest.json\")); assert len(d[\"themes\"]) == 12; print(len(d[\"themes\"]))"' \
  | grep -q 12 || fail "guest manifest entries"
pass "guest theme manifest: 12 entries"
$SSH 'for f in hx-config/bin/dots-* hx-config/lib/dots/*.sh hx-config/scripts/*.sh; do bash -n "$f" || exit 1; done' \
  || fail "guest shell syntax"
pass "guest shell syntax of shipped scripts"

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
