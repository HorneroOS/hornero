#!/usr/bin/env bash
# graphical-smoke.sh - graphical guest validation of the pinned composition.
#
# Runs scripts/compose.sh --yes, then invokes the shell-pin's graphical
# scenario (HorneroOS/shell tests/vm) with the composed environment, so the
# pinned shell plus the pinned config are exercised together under Hyprland
# on virtio-vga (Hyprland DRM/gles2, seatd, qs, grim with QEMU framebuffer
# fallback). CLI-only guest checks stay in tests/vm/smoke.sh.
#
# Agent-composable subcommands (each delegates to a shell harness script):
#   start       boot the VM and wait for SSH (lib/boot.sh + lib/wait-ssh.sh)
#   status      report VM/SSH/Hyprland/shell state, one key=value per line
#   exec CMD..  run a command inside the guest over SSH
#   screenshot  capture the desktop (grim, QEMU framebuffer fallback)
#   smoke       full chain: compose --yes, shell-pin scenario, result JSON
#   stop        shut the guest down and release the VM
#
# The smoke subcommand merges a structured result object
# {status,checks,artifacts,duration} into the harness assertions.json
# (additive: existing keys are untouched) and also writes result.json.
#
# Usage:
#   scripts/graphical-smoke.sh [--manifest FILE] [--work DIR]
#       [--shell-harness DIR] [--ssh-port N] [--keep] [--dry-run] [SUBCOMMAND]
#
#   --manifest       composition manifest (default: manifests/v0.1.0-draft.yaml)
#   --work           scratch dir (default: ~/.local/share/hornero/graphical-smoke/work)
#   --shell-harness  shell tests/vm dir (default: the composed shell pin's)
#   --ssh-port       host forward for guest sshd (default: 2222)
#   --keep           smoke leaves the guest running (default: stop afterwards)
#   --dry-run        print the plan without touching compose or any VM
#
# NOT wired into CI: GitHub runners have no KVM. Without /dev/kvm the
# smoke/start subcommands exit 0 with GRAPHICAL-SMOKE-SKIP (same discipline
# as tests/vm/smoke.sh). Paste the result.json trailer into release notes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="manifests/v0.1.0-draft.yaml"
WORK="$HOME/.local/share/hornero/graphical-smoke/work"
SHELL_HARNESS=""
SSH_PORT=2222
KEEP=0
DRY_RUN=0
CMD="smoke"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) MANIFEST="$2"; shift 2 ;;
    --work) WORK="$2"; shift 2 ;;
    --shell-harness) SHELL_HARNESS="$2"; shift 2 ;;
    --ssh-port) SSH_PORT="$2"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    start | status | exec | screenshot | smoke | stop) CMD="$1"; shift; break ;;
    -h | --help) sed -n '2,40p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "graphical-smoke: unknown argument: $1" >&2; exit 2 ;;
  esac
done

pass() { echo "GRAPHICAL-SMOKE-PASS: $1"; }
fail() { echo "GRAPHICAL-SMOKE-FAIL: $1" >&2; exit 1; }

if [[ $DRY_RUN -eq 1 ]]; then
  echo "dry-run: would run scripts/compose.sh --manifest $MANIFEST --yes into $WORK"
  echo "dry-run: would export the composed env (HX_CONFIG_PIN/HX_MATERIALIZE_BIN/HX_HOREROCTL_BIN/HX_MANIFEST)"
  echo "dry-run: subcommand '$CMD' would delegate to the shell harness (${SHELL_HARNESS:-<composed shell pin>}/tests/vm)"
  exit 0
fi

mkdir -p "$WORK"
COMPOSE_WORK="$WORK/compose"
COMPOSE_DEST="$WORK/root"
RESULT="$WORK/result.json"

# --- composed environment for the shell harness ------------------------------
# Resolved lazily (needs compose outputs), exported by hx_composed_env.
hx_composed_env() {
  # Same one-line pin format as scripts/compose.sh (shell pair, config pair).
  read -r _SHELL_REPO _SHELL_SHA CONFIG_REPO CONFIG_SHA < <(python3 - "$ROOT/$MANIFEST" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
for name in ("shell", "config"):
    comp = doc["components"][name]
    assert comp.get("status") == "pinned", f"{name} is not pinned"
    print(comp["repo"], comp["sha"], end=" " if name == "shell" else "\n")
PY
)
  [[ $CONFIG_SHA =~ ^[0-9a-f]{40}$ ]] || fail "bad config pin: $CONFIG_SHA"
  # VM_* stay overridable through the environment (harness convention);
  # HX_* are forced: they define the composition under test.
  VM_CACHE_DIR="${VM_CACHE_DIR:-$WORK/vm/cache}"
  VM_ARTIFACTS_DIR="${VM_ARTIFACTS_DIR:-$WORK/vm/artifacts}"
  VM_SHARED_DIR="${VM_SHARED_DIR:-$WORK/vm/shared}"
  VM_SSH_DIR="${VM_SSH_DIR:-$WORK/vm/ssh}"
  VM_SSH_PORT="${VM_SSH_PORT:-$SSH_PORT}"
  export VM_CACHE_DIR VM_ARTIFACTS_DIR VM_SHARED_DIR VM_SSH_DIR VM_SSH_PORT
  HX_MANIFEST="$(basename "$MANIFEST" .yaml)"
  export HX_MANIFEST
  export HX_CONFIG_PIN="$CONFIG_REPO $CONFIG_SHA"
  export HX_MATERIALIZE_BIN="$COMPOSE_WORK/config/scripts/materialize.sh"
  export HX_HOREROCTL_BIN="$ROOT/cli/build/horneroctl"
}

# --- shell harness resolution -------------------------------------------------
hx_harness() {
  if [[ -z $SHELL_HARNESS ]]; then
    SHELL_HARNESS="$COMPOSE_WORK/shell/tests/vm"
  fi
  [[ -x $SHELL_HARNESS/scenarios/vm-smoke.sh ]] \
    || fail "shell harness not found at $SHELL_HARNESS (run the smoke subcommand first)"
  grep -q "HX_CONFIG_PIN" "$SHELL_HARNESS/lib/env.sh" \
    || fail "shell pin predates composition support (tests/vm/lib/env.sh lacks HX_CONFIG_PIN)"
  # shellcheck source=/dev/null
  source "$SHELL_HARNESS/lib/env.sh"
}

needs_kvm() {
  if [[ ! -e /dev/kvm ]] || ! command -v qemu-system-x86_64 >/dev/null; then
    echo "GRAPHICAL-SMOKE-SKIP: no KVM (needs /dev/kvm + qemu-system-x86_64)"
    exit 0
  fi
}

case "$CMD" in
  start)
    needs_kvm
    hx_composed_env
    hx_harness
    bash "$SHELL_HARNESS/lib/boot.sh"
    bash "$SHELL_HARNESS/lib/wait-ssh.sh" 300 || fail "ssh not reachable"
    pass "guest booted (ssh localhost:$SSH_PORT)"
    ;;
  status)
    hx_composed_env 2>/dev/null || true
    # A bare status works before any compose: fall back to harness defaults.
    export VM_CACHE_DIR="${VM_CACHE_DIR:-$WORK/vm/cache}"
    export VM_SSH_DIR="${VM_SSH_DIR:-$WORK/vm/ssh}"
    export VM_SSH_PORT="${VM_SSH_PORT:-$SSH_PORT}"
    export VM_ARTIFACTS_DIR="${VM_ARTIFACTS_DIR:-$WORK/vm/artifacts}"
    if [[ -n ${SHELL_HARNESS:-} || -d $COMPOSE_WORK/shell/tests/vm ]]; then
      hx_harness
    else
      echo "vm_running=false"
      echo "ssh_reachable=false"
      echo "note=no-harness-yet"
      exit 0
    fi
    vm_running && echo "vm_running=true" || echo "vm_running=false"
    vm_ssh_ready && echo "ssh_reachable=true" || echo "ssh_reachable=false"
    vm_session_ready && echo "hyprland_running=true" || echo "hyprland_running=false"
    vm_shell_ready && echo "shell_running=true" || echo "shell_running=false"
    ;;
  exec)
    needs_kvm
    hx_composed_env
    hx_harness
    [[ $# -gt 0 ]] || fail "exec needs a command"
    vm_ssh "$@"
    ;;
  screenshot)
    needs_kvm
    hx_composed_env
    hx_harness
    OUT="${1:-$VM_ARTIFACTS_DIR/screenshots/graphical-smoke.png}"
    if bash "$SHELL_HARNESS/lib/screenshot.sh" "$OUT" 2>/dev/null; then
      pass "screenshot $OUT"
    else
      bash "$SHELL_HARNESS/lib/qemu-screenshot.sh" "$OUT" || fail "screenshot"
      pass "screenshot $OUT (qemu framebuffer fallback)"
    fi
    ;;
  stop)
    hx_composed_env 2>/dev/null || true
    export VM_CACHE_DIR="${VM_CACHE_DIR:-$WORK/vm/cache}"
    export VM_SSH_DIR="${VM_SSH_DIR:-$WORK/vm/ssh}"
    export VM_SSH_PORT="${VM_SSH_PORT:-$SSH_PORT}"
    if [[ -d ${SHELL_HARNESS:-$COMPOSE_WORK/shell/tests/vm} ]]; then
      SHELL_HARNESS="${SHELL_HARNESS:-$COMPOSE_WORK/shell/tests/vm}"
      # shellcheck source=/dev/null
      source "$SHELL_HARNESS/lib/env.sh"
      if vm_ssh_ready; then
        vm_ssh 'sudo -n poweroff' >/dev/null 2>&1 || true
        sleep 5
      fi
      if vm_running; then
        kill "$(cat "$VM_PID_FILE")" 2>/dev/null || true
      fi
    fi
    pass "guest stopped"
    ;;
  smoke)
    needs_kvm
    for tool in qemu-img ssh scp python3 git; do
      command -v "$tool" >/dev/null || fail "missing host tool: $tool"
    done
    SMOKE_START=$SECONDS
    "$ROOT/scripts/compose.sh" --manifest "$MANIFEST" \
      --work "$COMPOSE_WORK" --dest "$COMPOSE_DEST" --yes \
      || fail "compose.sh --yes"
    [[ -x $ROOT/cli/build/horneroctl ]] || fail "horneroctl missing after compose"
    pass "host composition built"
    hx_composed_env
    hx_harness
    SCENARIO_RC=0
    bash "$SHELL_HARNESS/scenarios/vm-smoke.sh" || SCENARIO_RC=$?
    DURATION=$((SECONDS - SMOKE_START))
    ASSERTIONS="$VM_ARTIFACTS_DIR/assertions.json"
    if [[ $SCENARIO_RC -eq 0 && -f $ASSERTIONS ]]; then
      STATUS="PASS"
    else
      STATUS="FAIL"
    fi
    SCREENSHOT="$VM_ARTIFACTS_DIR/screenshots/desktop-final.png"
    RECORDING="$VM_ARTIFACTS_DIR/recordings/desktop-recording.mp4"
    python3 - "$ASSERTIONS" "$RESULT" "$STATUS" "$DURATION" \
      "$SCREENSHOT" "$RECORDING" <<'PY'
import json, os, sys
assertions_path, result_path, status, duration, shot, rec = (
    sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]),
    sys.argv[5], sys.argv[6],
)
try:
    report = json.load(open(assertions_path))
except (OSError, ValueError):
    report = {"result": "FAIL", "assertions": {}}
checks = dict(report.get("assertions", {}))
checks["scenario_pass"] = (status == "PASS")
checks["composition_validated"] = (
    report.get("composition", {}).get("config_sha") not in (None, "none", "unknown")
)
artifacts = {"assertions": assertions_path}
if os.path.isfile(shot) and os.path.getsize(shot) > 0:
    artifacts["screenshot"] = shot
    checks["screenshot_present"] = True
else:
    checks["screenshot_present"] = False
if os.path.isfile(rec) and os.path.getsize(rec) > 0:
    artifacts["recording"] = rec
result = {
    "status": status,
    "checks": checks,
    "artifacts": artifacts,
    "duration": duration,
}
json.dump(result, open(result_path, "w"), indent=2, sort_keys=True)
report["graphical_smoke"] = result
json.dump(report, open(assertions_path, "w"), indent=2, sort_keys=True)
print(f"result: status={status} duration={duration}s checks={len(checks)}")
PY
    if [[ $KEEP -eq 0 ]]; then
      if vm_ssh_ready; then
        vm_ssh 'sudo -n poweroff' >/dev/null 2>&1 || true
        sleep 5
      fi
      if vm_running; then
        kill "$(cat "$VM_PID_FILE")" 2>/dev/null || true
      fi
    else
      echo "GRAPHICAL-SMOKE-PASS: guest left running"
    fi
    [[ $STATUS == "PASS" ]] || fail "graphical scenario failed (see $ASSERTIONS)"
    pass "ALL GREEN in ${DURATION}s (result: $RESULT)"
    ;;
esac
