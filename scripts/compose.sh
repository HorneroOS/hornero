#!/usr/bin/env bash
# compose.sh - build the pinned composition and validate it end to end.
#
# Reads the shell/config pins from a composition manifest, fetches both
# repos at exactly those SHAs, builds horneroctl from this repository,
# materializes the config pin into a destination root via
# `horneroctl config materialize`, then validates the result with
# `horneroctl config paths/show/validate` against that root.
#
# Hermetic: nothing is written outside --work/--dest (plus the local
# cli/build/ binary output). Idempotent: re-runs skip fetches and rebuilds
# that are already at the pinned state.
#
# Usage:
#   scripts/compose.sh [--manifest FILE] [--work DIR] [--dest DIR] [--yes]
#
#   --manifest  composition manifest (default: manifests/v0.1.0-draft.yaml)
#   --work      scratch dir for pin checkouts (default: <mktemp>)
#   --dest      materialization root (default: <work>/root)
#   --yes       actually materialize (default is preview: --dry-run + report)
#
# Toolchain: needs python3 with PyYAML and a V toolchain for horneroctl
# (the CI pin in cli/.v-version; make.vsh honours $V/$VBIN).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="manifests/v0.1.0-draft.yaml"
WORK=""
DEST=""
YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) MANIFEST="$2"; shift 2 ;;
    --work) WORK="$2"; shift 2 ;;
    --dest) DEST="$2"; shift 2 ;;
    --yes) YES=1; shift ;;
    -h | --help)
      sed -n '2,20p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      echo "compose: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z $WORK ]]; then
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
else
  mkdir -p "$WORK"
fi
if [[ -z $DEST ]]; then
  DEST="$WORK/root"
fi

pass() { echo "COMPOSE-PASS: $1"; }
fail() { echo "COMPOSE-FAIL: $1" >&2; exit 1; }

# --- 1. read pins -------------------------------------------------------------
read -r SHELL_REPO SHELL_SHA CONFIG_REPO CONFIG_SHA < <(python3 - "$ROOT/$MANIFEST" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
for name in ("shell", "config"):
    comp = doc["components"][name]
    assert comp.get("status") == "pinned", f"{name} is not pinned"
    print(comp["repo"], comp["sha"], end=" " if name == "shell" else "\n")
PY
)
[[ $SHELL_SHA =~ ^[0-9a-f]{40}$ ]] || fail "bad shell pin: $SHELL_SHA"
[[ $CONFIG_SHA =~ ^[0-9a-f]{40}$ ]] || fail "bad config pin: $CONFIG_SHA"
pass "pins shell=${SHELL_SHA:0:8} config=${CONFIG_SHA:0:8}"

# --- 2. fetch pins at exact SHAs (idempotent) ---------------------------------
fetch_pin() {
  local name="$1" repo="$2" sha="$3"
  local dir="$WORK/$name"
  if [[ -d $dir/.git ]] && [[ $(git -C "$dir" rev-parse HEAD) == "$sha" ]]; then
    pass "$name checkout already at ${sha:0:8}"
    return
  fi
  rm -rf "$dir"
  git init -q "$dir"
  git -C "$dir" remote add origin "$repo"
  git -C "$dir" fetch -q --depth 1 origin "$sha"
  git -C "$dir" checkout -q "$sha"
  [[ $(git -C "$dir" rev-parse HEAD) == "$sha" ]] || fail "$name checkout mismatch"
  pass "$name checkout at ${sha:0:8}"
}
fetch_pin shell "$SHELL_REPO" "$SHELL_SHA"
fetch_pin config "$CONFIG_REPO" "$CONFIG_SHA"

# --- 3. shell pin provenance (conformance marker) ------------------------------
grep -q "hornero" "$WORK/shell/utils/Paths.qml" \
  || fail "shell pin lacks path-contract resolution (utils/Paths.qml)"
pass "shell pin carries path-contract resolution"

# --- 4. build horneroctl -------------------------------------------------------
# Release provenance is baked into the binary via -d defines (see
# cli/make.vsh build-cli): the pins below become `horneroctl version`.
HX_MANIFEST="$(python3 -c "import yaml; print(yaml.safe_load(open('$ROOT/$MANIFEST'))['name'])")"
HX_RELEASE_FILE="$ROOT/releases/$(basename "$MANIFEST" .yaml).yaml"
HX_RELEASE="$(python3 -c "import yaml,sys; print(yaml.safe_load(open(sys.argv[1])).get('version', 'unknown'))" "$HX_RELEASE_FILE" 2>/dev/null || echo unknown)"
export HX_SHELL_SHA="$SHELL_SHA" HX_CONFIG_SHA="$CONFIG_SHA"
export HX_MANIFEST HX_RELEASE
HORNERectl="$ROOT/cli/build/horneroctl"
if [[ $YES -eq 1 || ! -x $HORNERectl ]]; then
  # A stale cli/build/ dir without sources shadows vlib's `build` module;
  # it is regenerable output, so drop it before invoking make.vsh.
  # Always rebuild for --yes: the binary embeds this run's pins.
  if [[ -d $ROOT/cli/build ]]; then
    rm -rf "$ROOT/cli/build"
  fi
  (cd "$ROOT/cli" && ./make.vsh build-cli) || fail "horneroctl build"
  pass "horneroctl built (shell=${SHELL_SHA:0:8} config=${CONFIG_SHA:0:8})"
else
  pass "horneroctl binary already built"
fi

# --- 5. materialize the config pin into DEST -----------------------------------
MATERIALIZE="$WORK/config/scripts/materialize.sh"
[[ -x $MATERIALIZE ]] || fail "materialize.sh missing in config pin"
if [[ $YES -eq 1 ]]; then
  HORNERO_MATERIALIZE_BIN="$MATERIALIZE" "$HORNERectl" config materialize \
    --dest "$DEST" --yes || fail "horneroctl config materialize"
  pass "materialized config pin into $DEST"
else
  HORNERO_MATERIALIZE_BIN="$MATERIALIZE" "$HORNERectl" config materialize \
    --dest "$DEST" --dry-run || fail "horneroctl config materialize --dry-run"
  pass "materialize dry-run previews $DEST"
  echo "COMPOSE-PASS: dry-run only (re-run with --yes to materialize)"
  exit 0
fi

# --- 6. validate the materialized root -----------------------------------------
export HOME="$DEST"
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME
"$HORNERectl" config paths >/dev/null || fail "config paths against $DEST"
pass "config paths resolves against materialized root"
"$HORNERectl" config validate || fail "config validate against $DEST"
pass "config validate accepts materialized root (missing shell.json = defaults)"
"$HORNERectl" version --json | python3 -c "
import json, sys
data = json.load(sys.stdin)['data']
assert data['shell_sha'] == '$SHELL_SHA', data
assert data['config_sha'] == '$CONFIG_SHA', data
assert data['manifest'] == '$HX_MANIFEST', data
" || fail "version provenance does not match pins"
pass "version reports shell=${SHELL_SHA:0:8} config=${CONFIG_SHA:0:8} manifest=$HX_MANIFEST"
# shell.json is user-created (the shell writes it on settings change; no
# repo ships a factory default yet). Seed an empty object so `config show`
# exercises the parse path against this root without faking user content.
mkdir -p "$DEST/.config/hornero"
printf '{}\n' >"$DEST/.config/hornero/shell.json"
"$HORNERectl" config show >/dev/null || fail "config show against $DEST"
pass "config show parses the materialized root"

echo "COMPOSE-PASS: shell=${SHELL_SHA:0:8} config=${CONFIG_SHA:0:8} root=$DEST"
