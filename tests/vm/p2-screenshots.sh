#!/usr/bin/env bash
# p2-screenshots.sh - Preview 2 per-theme graphical evidence matrix.
#
# For each official theme (hornero-dark, hornero-light, pampa): apply it
# through the real control plane (`horneroctl appearance theme set --yes`)
# inside a live Hyprland + Hornero Shell session, launch representative
# applications per toolkit, and capture screenshots plus machine-readable
# state. No hand-editing of generated consumer files between themes: the
# Appearance System itself performs every transition.
#
# Reuses the shell pin's graphical harness (boot/provision/deploy/session/
# screenshot) and the composed environment (HX_*), the same pieces
# scripts/graphical-smoke.sh orchestrates — this script adds the P2 guest
# preparation (appearance deps, demo apps), the per-theme apply loop, and
# the toolkit screenshot matrix on top.
#
# Network boundary: package installs and pip fetches happen in PREP with
# network up. Before the per-theme loop the guest is walled off with the
# same firewall discipline as tests/vm/smoke.sh (v4 egress limited to the
# slirp host net so SSH stays up, v6 egress dropped); every apply and
# capture runs offline. Rules are flushed again at the end.
#
# Guest DNS: QEMU slirp's `dns=` relay drops packets in at least one real
# environment (proven: 1.1.1.1 via relay times out while plain NAT works),
# so after boot the guest DNS is pinned to a non-relayed public resolver
# (8.8.8.8) at runtime plus persistently, the same drop-in approach the
# shell harness provision.sh uses.
#
# Usage:
#   tests/vm/p2-screenshots.sh [--work DIR] [--ssh-port N] [--keep]
#
#   --work      scratch dir (compose outputs, harness cache, artifacts).
#               Default: ~/.local/share/hornero/vm/work-shots
#   --ssh-port  host forward for guest sshd. Default: 2222
#   --keep      leave the guest running and print how to reach it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="manifests/v0.1.0-draft.yaml"
WORK="$HOME/.local/share/hornero/vm/work-shots"
SSH_PORT=2222
KEEP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --work) WORK="$2"; shift 2 ;;
    --ssh-port) SSH_PORT="$2"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    -h | --help) sed -n '2,40p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "p2-screenshots: unknown argument: $1" >&2; exit 2 ;;
  esac
done

pass() { echo "P2SHOTS-PASS: $1"; }
fail() {
  # Forensic bundle: on any failure inside the theme loop the guest holds
  # the only copy of the shell/compositor logs. Fetch them best-effort so
  # a crashed shell (proven once: quickshell died on lock, Hyprland
  # showed its crashed-lockscreen screen) leaves evidence, not silence.
  if [[ -n ${SHOT_LOGS:-} && -n ${VM_SSH_USER:-} ]]; then
    mkdir -p "$SHOT_LOGS"
    vm_scp "${VM_SSH_USER}@127.0.0.1:/tmp/qs.log" "$SHOT_LOGS/fail-qs.log" >/dev/null 2>&1 || true
    vm_scp "${VM_SSH_USER}@127.0.0.1:/tmp/hypr.log" "$SHOT_LOGS/fail-hypr.log" >/dev/null 2>&1 || true
  fi
  echo "P2SHOTS-FAIL: $1" >&2; exit 1
}

if [[ ! -e /dev/kvm ]] || ! command -v qemu-system-x86_64 >/dev/null; then
  echo "P2SHOTS-SKIP: no KVM (needs /dev/kvm + qemu-system-x86_64)"
  exit 0
fi
for tool in qemu-img ssh scp python3 git; do
  command -v "$tool" >/dev/null || fail "missing host tool: $tool"
done

mkdir -p "$WORK"
COMPOSE_WORK="$WORK/compose"
COMPOSE_DEST="$WORK/root"
SHOTS_DIR="$WORK/p2shots"
SHOT_IMG="$SHOTS_DIR/screenshots"
SHOT_LOGS="$SHOTS_DIR/logs"
mkdir -p "$SHOT_IMG" "$SHOT_LOGS"

# --- 1. host-side composition (pins + binary + materialized root) -------------
"$ROOT/scripts/compose.sh" --manifest "$MANIFEST" \
  --work "$COMPOSE_WORK" --dest "$COMPOSE_DEST" --yes \
  >/dev/null || fail "host compose.sh --yes"
CTL="$ROOT/cli/build/horneroctl"
[[ -x $CTL ]] || fail "horneroctl binary missing after compose"
pass "host composition built"

# --- 2. shell harness environment ----------------------------------------------
# Same exports scripts/graphical-smoke.sh builds: the harness reads VM_*
# knobs from the environment and the HX_* composition pointers.
SHELL_HARNESS="$COMPOSE_WORK/shell/tests/vm"
[[ -x $SHELL_HARNESS/scenarios/vm-smoke.sh ]] \
  || fail "shell harness not found at $SHELL_HARNESS"
grep -q "HX_CONFIG_PIN" "$SHELL_HARNESS/lib/env.sh" \
  || fail "shell pin predates composition support (tests/vm/lib/env.sh lacks HX_CONFIG_PIN)"
read -r _SHELL_REPO _SHELL_SHA CONFIG_REPO CONFIG_SHA < <(python3 - "$ROOT/$MANIFEST" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
for name in ("shell", "config"):
    comp = doc["components"][name]
    assert comp.get("status") == "pinned", f"{name} is not pinned"
    print(comp["repo"], comp["sha"], end=" " if name == "shell" else "\n")
PY
)
export VM_CACHE_DIR="$WORK/vm/cache"
export VM_ARTIFACTS_DIR="$WORK/vm/artifacts"
export VM_SHARED_DIR="$WORK/vm/shared"
export VM_SSH_DIR="$WORK/vm/ssh"
export VM_SSH_PORT="$SSH_PORT"
HX_MANIFEST="$(basename "$MANIFEST" .yaml)"
export HX_MANIFEST
export HX_CONFIG_PIN="$CONFIG_REPO $CONFIG_SHA"
export HX_MATERIALIZE_BIN="$COMPOSE_WORK/config/scripts/materialize.sh"
export HX_HOREROCTL_BIN="$CTL"
# shellcheck source=/dev/null
source "$SHELL_HARNESS/lib/env.sh"
pass "harness environment ready (shell=${_SHELL_SHA:0:8} config=${CONFIG_SHA:0:8})"

# --- 3. boot + provision + deploy + session ------------------------------------
bash "$SHELL_HARNESS/lib/boot.sh" || fail "guest boot"
bash "$SHELL_HARNESS/lib/wait-ssh.sh" 300 || fail "guest SSH"
pass "guest booted (ssh localhost:$SSH_PORT)"

# Guest DNS onto the NAT path (see header: slirp `dns=` relay is broken
# in at least one real environment). Runtime plus persistent drop-in, same
# approach as the shell harness provision.sh; VM_GUEST_DNS stays
# overridable for networks where another resolver is needed.
P2_DNS="${P2_GUEST_DNS:-8.8.8.8}"
if ! vm_ssh 'getent hosts archlinux.org >/dev/null 2>&1'; then
  dns_ok=0
  for _ in $(seq 1 6); do
    # shellcheck disable=SC2016
    vm_ssh "sudo resolvectl dns eth0 $P2_DNS && \
      netfile=\$(networkctl status eth0 --no-pager 2>/dev/null | awk -F': ' '/Network File:/{ print \$2 }' | xargs -r basename) && \
      if [ -n \"\$netfile\" ]; then \
        sudo mkdir -p /etc/systemd/network/\"\${netfile}.d\" && \
        printf '[Network]\nDNS=$P2_DNS\n\n[DHCPv4]\nUseDNS=no\n' | \
        sudo tee /etc/systemd/network/\"\${netfile}.d\"/10-p2-dns-override.conf > /dev/null; \
      fi && \
      sudo networkctl reload" >/dev/null 2>&1 || true
    sleep 5
    # shellcheck disable=SC2016
    if vm_ssh 'getent hosts archlinux.org >/dev/null 2>&1'; then dns_ok=1; break; fi
    sleep 5
  done
  [[ $dns_ok -eq 1 ]] || fail "guest DNS still broken after pinning $P2_DNS"
fi
pass "guest DNS resolves ($P2_DNS)"

bash "$SHELL_HARNESS/lib/provision.sh" || fail "guest provision"
pass "guest provisioned (hyprland, kitty, qt6, grim, quickshell)"

bash "$SHELL_HARNESS/lib/deploy-shell.sh" || fail "guest deploy (shell + config + factory + wallpapers)"
pass "guest deployed (shell, composed config, factory defaults, wallpapers)"

# --- 4. P2 overlay preparation (network PREP phase) -----------------------------
# Appearance deps (hard requirements of dots_apply_theme: wal,
# materialyoucolor, ImageMagick for pywal's wal backend) plus the demo apps
# the matrix captures (gtk3/gtk4 widget factories, hyprlock). Runs after
# deploy so the composition owns HOME first; pip --user lands in the real
# session HOME (/home/hornero) where the matrix applies themes.
# shellcheck disable=SC2016
vm_ssh 'sudo pacman -S --noconfirm --needed python-pip gtk3 gtk4 gtk4-demos zenity loupe hyprlock imagemagick qt6ct copyq' \
  || fail "guest P2 packages"
# shellcheck disable=SC2016
vm_ssh 'python3 -m pip install --user -q --break-system-packages pywal materialyoucolor' \
  || fail "guest pip install (pywal + materialyoucolor)"
# shellcheck disable=SC2016
vm_ssh 'export PATH=$HOME/.local/bin:$PATH
  command -v wal >/dev/null && python3 -c "import materialyoucolor" \
  && command -v magick >/dev/null || command -v convert >/dev/null' \
  || fail "guest P2 apply deps (wal + materialyoucolor + imagemagick)"
pass "guest P2 preparation complete"

bash "$SHELL_HARNESS/lib/start-session.sh" || fail "guest session (Hyprland + shell)"
pass "guest session up (Hyprland + shell)"

# --- 5. offline boundary (same discipline as tests/vm/smoke.sh) -----------------
# v4 egress limited to the slirp host net (SSH stays up), v6 egress dropped.
# Idempotent (-F first). Every apply and capture below runs offline.
# shellcheck disable=SC2016
vm_ssh 'sudo iptables -F; sudo ip6tables -F;
  sudo iptables -A OUTPUT -o lo -j ACCEPT; sudo iptables -A OUTPUT -d 10.0.2.0/24 -j ACCEPT; sudo iptables -A OUTPUT -j DROP;
  sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT; sudo iptables -A INPUT -s 10.0.2.0/24 -j ACCEPT; sudo iptables -A INPUT -i lo -j ACCEPT; sudo iptables -A INPUT -j DROP;
  sudo ip6tables -A OUTPUT -o lo -j ACCEPT; sudo ip6tables -A OUTPUT -j DROP;
  sudo ip6tables -A INPUT -i lo -j ACCEPT; sudo ip6tables -A INPUT -j DROP;
  sudo resolvectl flush-caches' || fail "guest offline boundary (rule install)"
vm_ssh true || fail "guest SSH died behind the firewall"
vm_ssh 'sudo resolvectl statistics | grep -qiE "Current Cache Size:\s+0(\s|$)"' \
  || fail "guest resolver cache not empty (DNS probe would be dishonest)"
leak=""
if vm_ssh 'getent hosts archlinux.org >/dev/null 2>&1'; then leak="dns"; fi
if [[ -z $leak ]] && vm_ssh 'python3 -c "import urllib.request; urllib.request.urlopen(\"https://archlinux.org\", timeout=8)" >/dev/null 2>&1'; then leak="https"; fi
[[ -z $leak ]] || fail "guest still reaches the internet via $leak"
pass "guest is offline (firewall: no DNS, no HTTPS egress; host SSH alive)"

# --- 6. per-theme matrix ---------------------------------------------------------
# Session environment for compositor commands (hyprctl, grim, app launch).
# shellcheck disable=SC2016
HENV="$(vm_hypr_env)"
# Session apply environment: real session HOME (factory-installed), helper
# bins on PATH like a real user session.
GENV='export PATH=$HOME/.local/bin:$PATH'

shot() {
  # shot <theme> <name>: capture the desktop into the matrix. Primary path
  # is grim (exact compositor pixels); grim is known to hang on virtio-vga
  # when no new frame arrives, so retry, then fall back to the QEMU
  # framebuffer screendump (harness helper, independent of the guest
  # compositor). The path used is recorded in the assertions report.
  local theme="$1" name="$2"
  local out="$SHOT_IMG/$theme/$name.png" via="grim" ok=0
  mkdir -p "$SHOT_IMG/$theme"
  # Wake + unlock + damage nudge: with no physical input the session
  # DPMS-blanks the output (300s) and shell-locks it (180s) while applies
  # run; on virtio-vga grim then waits forever (proven: `dpms on`
  # unwedges it) and captures would show the lock screen instead of the
  # intended content. Unlock is verified (not just requested) so a
  # still-locked capture fails loudly instead of silently mislabelling.
  # Parking the cursor at a fixed spot additionally forces a fresh frame
  # and keeps its position deterministic across captures.
  local locked
  # shellcheck disable=SC2016
  locked="$(vm_ssh "$HENV
export LC_ALL=C.UTF-8
QS_BIN=\$(command -v qs || command -v quickshell)
\$QS_BIN ipc call lock isLocked 2>/dev/null")" || fail "guest lock state ($theme/$name)"
  if [[ $locked == "true" ]]; then
    # shellcheck disable=SC2016
    vm_ssh "$HENV
export LC_ALL=C.UTF-8
QS_BIN=\$(command -v qs || command -v quickshell)
\$QS_BIN ipc call lock unlock" >/dev/null || fail "guest unlock ($theme/$name)"
    sleep 2
    # shellcheck disable=SC2016
    locked="$(vm_ssh "$HENV
export LC_ALL=C.UTF-8
QS_BIN=\$(command -v qs || command -v quickshell)
\$QS_BIN ipc call lock isLocked 2>/dev/null")" || fail "guest lock re-state ($theme/$name)"
    [[ $locked != "true" ]] || fail "guest still locked ($theme/$name)"
  fi
  # shellcheck disable=SC2016
  vm_ssh "$HENV
hyprctl dispatch dpms on >/dev/null 2>&1 || true
hyprctl dispatch movecursor 640 360 >/dev/null 2>&1 || true" >/dev/null 2>&1 || true
  sleep 2
  for _ in 1 2 3; do
    # shellcheck disable=SC2016
    if vm_ssh "$HENV
timeout 25 grim /tmp/p2shot.png" 2>/dev/null; then ok=1; break; fi
    sleep 2
  done
  if [[ $ok -eq 1 ]]; then
    vm_scp "${VM_SSH_USER}@127.0.0.1:/tmp/p2shot.png" "$out" >/dev/null \
      || fail "guest shot fetch ($theme/$name)"
  else
    SHOT_VIA="qemu-screendump" bash "$SHELL_HARNESS/lib/qemu-screenshot.sh" "$out" \
      >/dev/null || fail "guest shot fallback ($theme/$name)"
    via="qemu-screendump"
  fi
  python3 "$SHELL_HARNESS/lib/check_screenshot.py" "$out" >/dev/null 2>&1 \
    || fail "guest shot blank ($theme/$name)"
  echo "$theme/$name $via" >>"$SHOT_LOGS/shots.tsv"
  echo "P2SHOTS-SHOT: $theme/$name.png (via $via)"
}

close_apps() {
  # Close every demo window, then VERIFY zero clients. killactive alone
  # cannot close kitty: it only summons kitty's close-confirm dialog, which
  # then survives into later captures and leaks across themes (proven: the
  # light/pampa desktop cells showed dark's orphaned dialog). So SIGTERM
  # each demo binary first (no confirm prompt on SIGTERM), killactive as
  # fallback, and fail loudly on any leaked client instead of silently
  # mislabelling the next capture. The -f patterns use the [x] trick: a
  # bare `pkill -f foo` also matches the invoking ssh shell (its cmdline
  # contains the pattern), suiciding the shell mid-chain so later targets
  # survive and the leak assert fires intermittently.
  # shellcheck disable=SC2016
  vm_ssh 'pkill -x kitty; pkill -f [z]enity; pkill -f [g]tk3-widget-factory; pkill -f [g]tk4-widget-factory; pkill -x qml6; pkill -x loupe; pkill -x qt6ct; pkill -x copyq' >/dev/null 2>&1 || true
  sleep 1
  # shellcheck disable=SC2016
  vm_ssh "$HENV
hyprctl dispatch killactive >/dev/null 2>&1 || true" >/dev/null 2>&1 || true
  sleep 1
  local nclients
  # shellcheck disable=SC2016
  nclients="$(vm_ssh "$HENV
hyprctl clients -j 2>/dev/null | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))'")" \
    || fail "guest client count ($*)"
  [[ $nclients -eq 0 ]] || fail "guest windows leaked after close ($*): $nclients clients remain"
}

launch() {
  # launch <command...>: run a demo app inside the session. The `--`
  # separator is mandatory: without it hyprctl parses the app's own
  # dash-flags (kitty --title, zenity --forms) as its own and prints usage.
  # shellcheck disable=SC2016
  vm_ssh "$HENV
hyprctl dispatch exec -- $*" >/dev/null || fail "guest launch: $*"
  sleep 4
}

# Demo app commands (verified by probing a live session; override for
# toolkit renames). Shell drawers toggle over quickshell IPC
# (`drawers state <name>` -> true/false, `drawers toggle <name>` flips).
# Qt vehicle is the qt6ct configurator window, not a QML demo: the config
# repo's documented Qt story (docs/QT_DECISION.md) is Qt6 Widgets apps via
# the qt6ct platform theme (the shipped Qt app is CopyQ); QtQuick Controls
# do not consume qt6ct and render stock Fusion, so a QML window would be
# dishonest evidence. The qt6ct window shows the deployed style, fonts,
# and icon theme directly.
GTK3_BIN="${P2_GTK3_BIN:-zenity --forms --title=Hornero-P2-GTK3 --text=GTK3-widget-evidence --add-entry=Normal-entry --add-entry=Second-entry}"
GTK4_BIN="${P2_GTK4_BIN:-gtk4-widget-factory}"
QT_BIN="${P2_QT_BIN:-qt6ct}"

drawer_set() {
  # drawer_set <name> <true|false>: deterministic drawer visibility over
  # quickshell IPC (state-checked toggle; LC_ALL silences the Qt C-locale
  # warning that would otherwise pollute captures of command output).
  local name="$1" want="$2" cur
  cur="$(vm_ssh "$HENV
export LC_ALL=C.UTF-8
QS_BIN=\$(command -v qs || command -v quickshell)
\$QS_BIN ipc call drawers state $name 2>/dev/null")" || fail "guest drawer state ($name)"
  if [[ $cur != "$want" ]]; then
    vm_ssh "$HENV
export LC_ALL=C.UTF-8
QS_BIN=\$(command -v qs || command -v quickshell)
\$QS_BIN ipc call drawers toggle $name" >/dev/null || fail "guest drawer toggle ($name)"
    sleep 2
    cur="$(vm_ssh "$HENV
export LC_ALL=C.UTF-8
QS_BIN=\$(command -v qs || command -v quickshell)
\$QS_BIN ipc call drawers state $name 2>/dev/null")" || fail "guest drawer re-state ($name)"
    [[ $cur == "$want" ]] || fail "guest drawer $name did not reach $want (got $cur)"
  fi
}

# Close any overlay drawer left open (probes, previous runs): the matrix
# starts each theme from a known-clean desktop. Bar/OSD are never touched.
for _d in launcher dashboard session utilities; do drawer_set "$_d" false; done
pass "guest drawers closed (clean desktop baseline)"

# Terminal demo content (palette + ANSI readability), staged once.
# shellcheck disable=SC2016
vm_ssh 'cat > /tmp/p2-term-demo.sh <<'"'"'DEMO'"'"'
ls --color=always /usr/bin | head -20
echo
for i in 0 1 2 3 4 5 6 7; do printf "\033[3%sm FG%s \033[9%sm BG%s \033[0m" "$i" "$i" "$i" "$i"; done
echo
echo "boldilu" | sed "s/.*/\x1b[1m&\x1b[0m/;s/ilu/\x1b[3milu\x1b[0m/"
exec bash
DEMO
chmod +x /tmp/p2-term-demo.sh' || fail "guest term demo write"

for spec in \
  "hornero-dark:Hornero-Dark:hornero-dark/hornero-dark-01.png:dark" \
  "hornero-light:Hornero-Light:hornero-light/hornero-light-01.png:light" \
  "pampa:Hornero-Pampa:pampa/pampa-01.png:dark"; do
  id="${spec%%:*}"; rest="${spec#*:}"
  gtk="${rest%%:*}"; rest="${rest#*:}"
  wall="${rest%%:*}"; mode="${rest##*:}"

  # 6a0. fresh session per theme. Proven necessity, not paranoia: a
  # SIGTERM-released hyprlock poisons the NEXT shell lock in the same
  # session (quickshell dies with a Wayland invalid-object error and
  # Hyprland shows its crashed-lockscreen fallback — reproduced live).
  # Restarting gives every theme a pristine compositor+shell pair, so
  # each theme's evidence stands alone and no locker state bleeds
  # across themes. (The interop bug itself belongs to the shell repo;
  # this sequencing only avoids the test-artifact trigger.)
  bash "$SHELL_HARNESS/lib/start-session.sh" || fail "guest session restart ($id)"
  for _d in launcher dashboard session utilities; do drawer_set "$_d" false; done

  # 6a. apply through the real control plane (validate/resolve/apply/verify).
  # NOTE: $HOME below is guest-side (escaped); unescaped $HOME would expand
  # on the host and run the wrong binary.
  if ! bout="$(vm_ssh "$GENV; \$HOME/horneroctl appearance theme set $id --yes" 2>&1)"; then
    fail "guest theme set $id: $bout"
  fi
  getout="$(vm_ssh "$GENV; \$HOME/horneroctl appearance theme get" 2>&1)" \
    || fail "guest theme get $id: $getout"
  echo "$getout" | grep -q "current theme: $id (" \
    || fail "guest theme get $id (no id match): $getout"
  # mode lives in scheme/state.json (dots-color-scheme writer, absent in
  # minimal guests): assert it when reported, note when the GTK match
  # governs (same contract as tests/vm/smoke.sh).
  if ! echo "$getout" | grep -q "(mode=$mode,"; then
    echo "note: guest backend reports no mode for $id (want $mode; GTK match governs)"
  fi
  pass "guest theme $id applied via horneroctl (offline)"

  # 6b. machine-readable consumer state snapshot.
  # shellcheck disable=SC2016
  vm_ssh "$GENV; {
    echo '--- theme get'; \$HOME/horneroctl appearance theme get
    echo '--- gtk3 settings'; grep -H '^gtk-theme-name\|^gtk-application-prefer-dark' \$HOME/.config/gtk-3.0/settings.ini 2>/dev/null || echo '(no gtk3 settings)'
    echo '--- gtk4 settings'; grep -H '^gtk-theme-name\|^gtk-application-prefer-dark' \$HOME/.config/gtk-4.0/settings.ini 2>/dev/null || echo '(no gtk4 settings)'
    echo '--- wallpaper pointer'; cat \$HOME/.local/state/hornero/wallpaper/path 2>/dev/null || echo '(no wallpaper pointer)'
    echo '--- kitty'; ls -la \$HOME/.config/kitty/kitty.conf 2>/dev/null || echo '(no kitty conf)'
    echo '--- M3 scheme'; ls -la \$HOME/.cache/hornero/smart-colors/scheme.json 2>/dev/null || echo '(no M3 scheme)'
    echo '--- qt6ct'; cat \$HOME/.config/qt6ct/qt6ct.conf 2>/dev/null | head -6 || cat /etc/xdg/qt6ct/qt6ct.conf 2>/dev/null | head -6 || echo '(no qt6ct conf)'
    echo '--- hyprland borders'; $HENV hyprctl getoption general:col.active_border 2>/dev/null || echo '(no hypr border option)'
  }" >"$SHOT_LOGS/$id-state.txt" 2>&1 || fail "guest state snapshot ($id)"
  # NOTE: snapshot lines carry grep -H filename prefixes, so the theme
  # assertion must not anchor at line start.
  grep -q "gtk-theme-name=$gtk\$" "$SHOT_LOGS/$id-state.txt" \
    || fail "guest GTK mapping $id ($gtk)"
  grep -q "$wall\$" "$SHOT_LOGS/$id-state.txt" \
    || fail "guest wallpaper pointer $id ($wall)"

  # 6c. desktop with the applied theme (wallpaper + shell bar).
  # Belt-and-braces: the previous theme's loop must have left zero
  # clients (close_apps verifies), but re-verify before the first cell
  # so a leak can never hide in a desktop baseline again.
  close_apps "pre-desktop $id"
  shot "$id" desktop

  # 6d. kitty with palette/ANSI readability content (demo file written
  # once before the loop; -e with inline quoting does not survive SSH).
  launch "kitty --title p2-term -e bash /tmp/p2-term-demo.sh"
  shot "$id" kitty
  close_apps

  # 6e. GTK3 + GTK4 widget factories.
  launch "$GTK3_BIN"
  shot "$id" gtk3
  close_apps
  launch "$GTK4_BIN"
  shot "$id" gtk4
  close_apps

  # 6f. Qt6 platform-theme evidence: the qt6ct window (style + fonts +
  # icon theme the deployed qt6ct.conf prescribes for Qt6 Widgets apps).
  launch "$QT_BIN"
  shot "$id" qt6
  close_apps qt6

  # 6g. shell launcher + dashboard (deterministic IPC visibility).
  drawer_set launcher true
  shot "$id" launcher
  drawer_set launcher false
  drawer_set dashboard true
  shot "$id" dashboard
  drawer_set dashboard false

  # 6g2. libadwaita witness: loupe (GTK4/libadwaita) showing the theme's
  # own wallpaper, so the recolor path renders Hornero content.
  # shellcheck disable=SC2016
  launch "loupe \$HOME/.local/share/hornero/wallpapers/$id/$id-01.png"
  shot "$id" adwaita
  close_apps

  # 6h0. shell lock screen (deterministic IPC lock; shot() would unlock,
  # so the lock/unlock pair is inline with post-state verification).
  # shellcheck disable=SC2016
  vm_ssh "$HENV
export LC_ALL=C.UTF-8
QS_BIN=\$(command -v qs || command -v quickshell)
\$QS_BIN ipc call lock lock" >/dev/null || fail "guest shell lock ($id)"
  sleep 2
  # Verify the shell still owns the lock: if the lockscreen client died
  # (Hyprland falls back to its crashed-lockscreen screen), the IPC
  # endpoint goes with it and the capture below would mislabel the
  # fallback as the shell lock screen.
  # shellcheck disable=SC2016
  locked="$(vm_ssh "$HENV
export LC_ALL=C.UTF-8
QS_BIN=\$(command -v qs || command -v quickshell)
\$QS_BIN ipc call lock isLocked 2>/dev/null")" || fail "guest lock state post-lock ($id: shell IPC gone)"
  [[ $locked == "true" ]] || fail "guest lock not held post-lock ($id: got $locked)"
  # shellcheck disable=SC2016
  vm_ssh "$HENV
hyprctl dispatch dpms on >/dev/null 2>&1 || true" >/dev/null 2>&1 || true
  sleep 1
  mkdir -p "$SHOT_IMG/$id"
  # shellcheck disable=SC2016
  vm_ssh "$HENV
timeout 25 grim /tmp/p2shot.png" 2>/dev/null || fail "guest grim ($id/lockscreen)"
  vm_scp "${VM_SSH_USER}@127.0.0.1:/tmp/p2shot.png" "$SHOT_IMG/$id/lockscreen.png" >/dev/null \
    || fail "guest shot fetch ($id/lockscreen)"
  python3 "$SHELL_HARNESS/lib/check_screenshot.py" "$SHOT_IMG/$id/lockscreen.png" >/dev/null 2>&1 \
    || fail "guest shot blank ($id/lockscreen)"
  echo "$id/lockscreen grim" >>"$SHOT_LOGS/shots.tsv"
  echo "P2SHOTS-SHOT: $id/lockscreen.png (via grim)"

  # 6h0b. release the shell lock before the hyprlock cell: a session can
  # hold only one locker, and hyprlock is yeeted ("Is another lockscreen
  # running?") while the shell lock holds it — proven by the hyprlock
  # logs of the previous matrix run.
  # shellcheck disable=SC2016
  vm_ssh "$HENV
export LC_ALL=C.UTF-8
QS_BIN=\$(command -v qs || command -v quickshell)
\$QS_BIN ipc call lock unlock" >/dev/null || fail "guest shell unlock ($id)"
  sleep 1
  # shellcheck disable=SC2016
  locked="$(vm_ssh "$HENV
export LC_ALL=C.UTF-8
QS_BIN=\$(command -v qs || command -v quickshell)
\$QS_BIN ipc call lock isLocked 2>/dev/null")" || fail "guest lock re-state ($id/unlock)"
  [[ $locked != "true" ]] || fail "guest still locked after unlock ($id)"

  # 6h. hyprlock (lock screen over the applied theme). The lock must be
  # proven EFFECTIVE, not just started: a yeeted or dead hyprlock leaves
  # the plain desktop in frame and the cell would silently mislabel it
  # (seen in review: pgrep passed on a process that never locked). So
  # the log must show "Locking session" with no "yeeten" after the shot.
  # shellcheck disable=SC2016
  vm_ssh "$HENV
(hyprlock >/tmp/p2-hyprlock.log 2>&1 &) ; sleep 4" || fail "guest hyprlock start ($id)"
  # shellcheck disable=SC2016
  vm_ssh 'pgrep -x hyprlock >/dev/null' \
    || fail "guest hyprlock not running ($id)"
  shot "$id" hyprlock
  vm_scp "${VM_SSH_USER}@127.0.0.1:/tmp/p2-hyprlock.log" "$SHOT_LOGS/$id-hyprlock.log" >/dev/null \
    || fail "guest hyprlock log fetch ($id)"
  grep -q "Locking session" "$SHOT_LOGS/$id-hyprlock.log" \
    || fail "guest hyprlock never locked ($id, see $id-hyprlock.log)"
  grep -q "yeeten" "$SHOT_LOGS/$id-hyprlock.log" \
    && fail "guest hyprlock was yeeted by another locker ($id, see $id-hyprlock.log)"
  # shellcheck disable=SC2016
  vm_ssh 'pkill -x hyprlock' >/dev/null 2>&1 || true
  sleep 1
done
pass "guest trio matrix captured (3 themes x desktop/kitty/gtk3/gtk4/qt6/launcher/dashboard/adwaita/lockscreen/hyprlock)"

# --- 7. restore egress, report, stop --------------------------------------------
vm_ssh 'sudo iptables -F 2>/dev/null; sudo ip6tables -F 2>/dev/null; sudo ip route add default via 10.0.2.2 2>/dev/null || true'
THEMES_JSON="$(python3 - "$SHOT_IMG" <<'PY'
import json, sys
from pathlib import Path
img = Path(sys.argv[1])
shots = ["desktop", "kitty", "gtk3", "gtk4", "qt6", "launcher", "dashboard", "adwaita", "lockscreen", "hyprlock"]
out = {}
for theme in ("hornero-dark", "hornero-light", "pampa"):
    got = {s: (img / theme / f"{s}.png").is_file() for s in shots}
    out[theme] = {"shots": got, "complete": all(got.values())}
print(json.dumps(out))
PY
)"
echo "$THEMES_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); assert all(v['complete'] for v in d.values()), d; print('matrix complete:', sorted(d))" \
  || fail "screenshot matrix incomplete: $THEMES_JSON"
python3 - "$SHOT_LOGS" "$THEMES_JSON" <<'PY' || fail "assertions report"
import json, sys
from pathlib import Path
logs, themes = Path(sys.argv[1]), json.loads(sys.argv[2])
via = {}
tsv = logs / "shots.tsv"
if tsv.is_file():
    for line in tsv.read_text().splitlines():
        parts = line.split()
        if len(parts) == 2:
            via[parts[0]] = parts[1]
(logs / "assertions.json").write_text(json.dumps({
    "scenario": "p2-screenshots",
    "result": "PASS",
    "offline": True,
    "capture_via": via,
    "themes": themes,
}, indent=2) + "\n")
PY
pass "assertions report written ($SHOT_LOGS/assertions.json)"

if [[ $KEEP -eq 1 ]]; then
  echo "P2SHOTS-PASS: guest left running; ssh -i $VM_SSH_KEY -p $VM_SSH_PORT ${VM_SSH_USER}@127.0.0.1"
else
  vm_ssh 'sudo -n poweroff' >/dev/null 2>&1 || true
  sleep 5
  if vm_running; then
    kill "$(cat "$VM_PID_FILE")" 2>/dev/null || true
  fi
  pass "guest stopped"
fi
echo "P2SHOTS-PASS: ALL GREEN (shots dir: $SHOTS_DIR)"
