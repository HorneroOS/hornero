#!/usr/bin/env bash
# Host acceptance for the HorneroOS agentic surface (hornero#391, Wave 4).
# Builds horneroctl (or reuses $HORNEROS_HORNEROCTL_BIN), runs every check
# against an isolated temp HOME/XDG, and exits non-zero on the first failed
# assertion. Never touches the real HOME. No QEMU/ISO required.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

fail() { echo "FAIL: $*" >&2; exit 1; }
step() { echo "== $*"; }

TMP_ROOT="$(mktemp -d)"
cleanup() { rm -rf "${TMP_ROOT}"; }
trap cleanup EXIT

export HOME="${TMP_ROOT}/home"
export XDG_CONFIG_HOME="${TMP_ROOT}/xdg-config"
export XDG_STATE_HOME="${TMP_ROOT}/xdg-state"
export XDG_DATA_HOME="${TMP_ROOT}/xdg-data"
export XDG_CACHE_HOME="${TMP_ROOT}/xdg-cache"
export CODEX_HOME="${TMP_ROOT}/codex"
mkdir -p "${HOME}" "${XDG_CONFIG_HOME}" "${XDG_STATE_HOME}" "${XDG_DATA_HOME}" "${XDG_CACHE_HOME}" "${CODEX_HOME}"

# --- Binary ---------------------------------------------------------------
if [ -n "${HORNEROS_HORNEROCTL_BIN:-}" ]; then
  BIN="${HORNEROS_HORNEROCTL_BIN}"
  [ -x "${BIN}" ] || fail "HORNEROS_HORNEROCTL_BIN=${BIN} is not executable"
  step "reusing horneroctl at ${BIN}"
else
  BIN_DIR="${TMP_ROOT}/bin"
  mkdir -p "${BIN_DIR}"
  step "building horneroctl into temp dir"
  if [ -n "${HORNERO_VBIN:-}" ]; then VCMD="${HORNERO_VBIN}"; elif command -v v >/dev/null 2>&1; then VCMD="$(command -v v)"; else fail "v toolchain not found (set HORNERO_VBIN or HORNEROS_HORNEROCTL_BIN)"; fi
  # Build directly into the temp dir; no repo build artifacts are left.
  (cd "${REPO_ROOT}/cli" && VJOBS="${VJOBS:-1}" VMODULES="${REPO_ROOT}/cli/modules" "${VCMD}" -o "${BIN_DIR}/horneroctl" cmd/horneroctl >/dev/null) \
    || fail "v build failed"
  BIN="${BIN_DIR}/horneroctl"
  [ -x "${BIN}" ] || fail "built horneroctl missing at ${BIN}"
fi
echo "horneroctl: ${BIN}"

run() { "${BIN}" "$@"; }
must_contain() { # haystack needle label
  case "$1" in *"$2"*) : ;; *) fail "$3: expected output to contain [$2], got: $1" ;; esac
}

# --- 1. agent list ----------------------------------------------------------
step "agent list"
OUT="$(run agent list)" || fail "agent list exited non-zero"
echo "${OUT}"
must_contain "${OUT}" "codex" "agent list"
must_contain "${OUT}" "Registered agents:" "agent list"

# --- 2. agent default set/show round-trip (migration: write, read back) -----
step "agent default round-trip"
OUT="$(run agent default show)" || fail "agent default show (empty) failed"
must_contain "${OUT}" "No default agent recorded" "default show empty"
OUT="$(run agent default set codex --dry-run)" || fail "agent default set --dry-run failed"
must_contain "${OUT}" "nothing written" "default dry-run"
[ ! -e "${XDG_CONFIG_HOME}/hornero/agent-default.json" ] \
  || fail "default set --dry-run wrote agent-default.json"
OUT="$(run agent default set codex --yes)" || fail "agent default set --yes failed"
[ -f "${XDG_CONFIG_HOME}/hornero/agent-default.json" ] \
  || fail "default set --yes did not write agent-default.json"
grep -q '"default": "codex"' "${XDG_CONFIG_HOME}/hornero/agent-default.json" \
  || fail "agent-default.json does not record codex"
OUT="$(run agent default show)" || fail "agent default show (after set) failed"
must_contain "${OUT}" "Default agent: codex" "default show round-trip"

# --- 3. agent config: dry-run / apply / idempotent / drift / rollback -------
step "agent config apply lifecycle"
REGISTRY="${XDG_CONFIG_HOME}/hornero/agent-config.json"
mkdir -p "$(dirname "${REGISTRY}")"
cat > "${REGISTRY}" <<'EOF'
{"schemaVersion":1,"entries":[{"id":"acc-skill","kind":"skill","name":"Acceptance Skill","targets":["codex"],"skillId":"acc-skill","content":"# Acceptance Skill\n\nhello acceptance\n"}]}
EOF
SKILL_FILE="${CODEX_HOME}/skills/acc-skill/SKILL.md"
STATE_DIR="${XDG_STATE_HOME}/hornero/agent-config"

OUT="$(run agent config status)" || fail "agent config status (pre-apply) failed"
must_contain "${OUT}" "missing" "config status pre-apply"

OUT="$(run agent config apply --dry-run)" || fail "agent config apply --dry-run failed"
must_contain "${OUT}" "would-apply" "config apply dry-run"
[ ! -e "${SKILL_FILE}" ] || fail "config apply --dry-run wrote ${SKILL_FILE}"
[ ! -e "${STATE_DIR}" ] || fail "config apply --dry-run wrote state dir ${STATE_DIR}"

OUT="$(run agent config apply --yes)" || fail "agent config apply --yes failed"
must_contain "${OUT}" "applied" "config apply yes"
[ -f "${SKILL_FILE}" ] || fail "config apply --yes did not write ${SKILL_FILE}"
grep -q "hello acceptance" "${SKILL_FILE}" || fail "applied skill lacks registry content"
ls "${STATE_DIR}/receipts/"*.json >/dev/null 2>&1 \
  || fail "config apply --yes wrote no ownership receipt"

SNAP_BEFORE="$(sha256sum "${SKILL_FILE}" "${STATE_DIR}/receipts/"*.json | awk '{print $1}'; stat -c%Y "${SKILL_FILE}" "${STATE_DIR}/receipts/"*.json)"
OUT="$(run agent config apply --yes)" || fail "second agent config apply failed"
must_contain "${OUT}" "unchanged" "config apply idempotent"
must_contain "${OUT}" "0 changed" "config apply idempotent counts"
SNAP_AFTER="$(sha256sum "${SKILL_FILE}" "${STATE_DIR}/receipts/"*.json | awk '{print $1}'; stat -c%Y "${SKILL_FILE}" "${STATE_DIR}/receipts/"*.json)"
[ "${SNAP_BEFORE}" = "${SNAP_AFTER}" ] \
  || fail "second apply changed skill/receipt bytes or mtimes (not idempotent)"

echo "hand edit by acceptance" >> "${SKILL_FILE}"
OUT="$(run agent config status)" || fail "agent config status (after edit) failed"
must_contain "${OUT}" "drifted" "config status drift"

# Manual backup-restore rollback (the documented recovery procedure; there
# is no product restore command): a pre-existing unmanaged skill is backed
# up on apply, and the original content is restored from the newest backup.
step "agent config backup / manual rollback procedure"
cat > "${REGISTRY}" <<'EOF'
{"schemaVersion":1,"entries":[{"id":"acc-skill2","kind":"skill","name":"Second Skill","targets":["codex"],"skillId":"acc-skill2","content":"managed body\n"}]}
EOF
SKILL2_DIR="${CODEX_HOME}/skills/acc-skill2"
SKILL2_FILE="${SKILL2_DIR}/SKILL.md"
mkdir -p "${SKILL2_DIR}"
printf 'ORIGINAL UNMANAGED CONTENT\n' > "${SKILL2_FILE}"
OUT="$(run agent config apply --yes)" || fail "agent config apply (unmanaged) failed"
must_contain "${OUT}" "backed up unmanaged" "config apply backup"
grep -q "managed body" "${SKILL2_FILE}" || fail "managed content not written over unmanaged file"
NEWEST_BACKUP="$(ls -t "${STATE_DIR}/backups/"*.bak 2>/dev/null | head -n 1)"
[ -n "${NEWEST_BACKUP}" ] || fail "no backup created under ${STATE_DIR}/backups"
grep -q "ORIGINAL UNMANAGED CONTENT" "${NEWEST_BACKUP}" \
  || fail "newest backup does not hold the original unmanaged content"
# Rollback = restore the skill file from the newest backup.
cp "${NEWEST_BACKUP}" "${SKILL2_FILE}" || fail "rollback copy from backup failed"
grep -q "ORIGINAL UNMANAGED CONTENT" "${SKILL2_FILE}" \
  || fail "rollback did not restore the original unmanaged content"
echo "rollback restored ${SKILL2_FILE} from ${NEWEST_BACKUP}"

# --- 4. assistant shell-proposal: never executes, protected classification --
step "assistant shell-proposal"
MARKER="${TMP_ROOT}/marker-should-not-exist"
OUT="$(run assistant shell-proposal --command "touch ${MARKER}")" \
  || fail "assistant shell-proposal (touch) failed"
must_contain "${OUT}" "nothing executed" "shell-proposal marker"
[ ! -e "${MARKER}" ] || fail "shell-proposal executed the command (marker exists)"
OUT="$(run assistant shell-proposal --command "/usr/bin/sudo rm -rf /")" \
  || fail "assistant shell-proposal (protected) failed"
must_contain "${OUT}" "protected" "shell-proposal protected classification"

# --- 5. assistant delegate: unknown fails, codex states no ABAC inheritance -
step "assistant delegate"
if OUT="$(run assistant delegate nope --workspace "${TMP_ROOT}" "do a thing" 2>&1)"; then
  fail "assistant delegate with unknown agent unexpectedly succeeded"
fi
must_contain "${OUT}" "Unknown agent id" "delegate unknown agent"
WS_BEFORE="$(find "${TMP_ROOT}" -type f | sort)"
OUT="$(run assistant delegate codex --workspace "${TMP_ROOT}" "review the parser")" \
  || fail "assistant delegate codex failed"
must_contain "${OUT}" "does NOT inherit Hornero ABAC" "delegate ABAC truth"
WS_AFTER="$(find "${TMP_ROOT}" -type f | sort)"
[ "${WS_BEFORE}" = "${WS_AFTER}" ] \
  || fail "delegate launched something or wrote into the workspace (proposal must be inert)"

# --- 6. plugin install-local dry-run writes nothing -------------------------
step "plugin install-local --dry-run"
PLUGIN_SRC="${TMP_ROOT}/plugsrc"
mkdir -p "${PLUGIN_SRC}"
printf '%s' '{"schemaVersion":1,"id":"example-clock","name":"Example Clock","version":"1.0.0","capabilities":{"processCommands":[],"networkHosts":[],"settings":{}}}' \
  > "${PLUGIN_SRC}/manifest.json"
printf 'import QtQuick\nItem {}\n' > "${PLUGIN_SRC}/Main.qml"
OUT="$(run plugin install-local "${PLUGIN_SRC}" --dry-run)" \
  || fail "plugin install-local --dry-run failed"
must_contain "${OUT}" "not loaded or sandboxed" "plugin dry-run inert note"
[ ! -e "${XDG_DATA_HOME}/hornero/plugins/example-clock" ] \
  || fail "plugin install-local --dry-run installed a payload"
[ ! -e "${XDG_STATE_HOME}/hornero/plugins/receipts/example-clock.json" ] \
  || fail "plugin install-local --dry-run wrote a receipt"

# --- 7. Resource measurement --------------------------------------------------
step "resource measurement"
BIN_SIZE="$(stat -c%s "${BIN}" 2>/dev/null || stat -f%z "${BIN}")"
echo "binary size: ${BIN_SIZE} bytes (${BIN})"
measure() { # label command...
  local label="$1"; shift
  if [ -x /usr/bin/time ]; then
    local tf="${TMP_ROOT}/time.txt"
    /usr/bin/time -v "$@" >/dev/null 2>"${tf}" || fail "measured command failed: ${label}"
    local elapsed rss
    elapsed="$(grep 'Elapsed (wall clock)' "${tf}" | awk '{print $NF}')"
    rss="$(grep 'Maximum resident set size' "${tf}" | awk '{print $NF}')"
    echo "measure ${label}: elapsed=${elapsed} max-rss=${rss} KB (/usr/bin/time -v)"
  else
    local start end
    start="$(date +%s%N)"
    "$@" >/dev/null || fail "measured command failed: ${label}"
    end="$(date +%s%N)"
    echo "measure ${label}: elapsed_ms=$(( (end - start) / 1000000 )) max-rss=unavailable (/usr/bin/time not present)"
  fi
}
measure "agent list" "${BIN}" agent list
measure "assistant shell-proposal" "${BIN}" assistant shell-proposal --command "ls -la"

echo "PASS: agentic acceptance (all assertions held; temp dir ${TMP_ROOT} removed on exit)"
