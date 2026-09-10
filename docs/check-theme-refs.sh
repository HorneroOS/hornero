#!/usr/bin/env bash
# check-theme-refs.sh - verify theme/wallpaper split-readiness of HorneroOS/config.
#
# Validates JSON syntax plus referential integrity between
# profiles/themes/<id>/theme.json packs and profiles/themes/wallpapers.manifest.json:
# required keys, id == directory name, manifest/theme default parity, unique ids,
# sane wallpaper extensions, and absence of absolute paths or template markers.
#
# Wallpaper binaries are intentionally NOT vendored in config (~46 MB upstream),
# so binary existence is a warning only, unless --wallpapers-root is given.
#
# Usage:
#   docs/check-theme-refs.sh [--config-root DIR] [--wallpapers-root DIR] [--strict]
#
# Exit 0 when all hard checks pass, 1 otherwise. Warnings never fail,
# except under --strict where missing wallpaper binaries also fail.
set -euo pipefail

CONFIG_ROOT=""
WALLPAPERS_ROOT=""
STRICT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config-root)
      CONFIG_ROOT="${2:-}"
      shift 2
      ;;
    --wallpapers-root)
      WALLPAPERS_ROOT="${2:-}"
      shift 2
      ;;
    --strict)
      STRICT=1
      shift
      ;;
    -h|--help)
      sed -n '1,20p' "$0"
      exit 0
      ;;
    *)
      echo "CHECK-FAIL: unknown argument: $1" >&2
      echo "Usage: $0 [--config-root DIR] [--wallpapers-root DIR] [--strict]" >&2
      exit 1
      ;;
  esac
done

if [[ -z $CONFIG_ROOT ]]; then
  CONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd || true)"
  # When run from the hornero composition repo there is no local profiles/
  # tree; require an explicit config checkout in that case.
  if [[ ! -d "$CONFIG_ROOT/profiles/themes" ]]; then
    echo "CHECK-FAIL: no profiles/themes under $CONFIG_ROOT" >&2
    echo "Hint: pass --config-root /path/to/HorneroOS-config checkout." >&2
    exit 1
  fi
fi

THEMES_DIR="$CONFIG_ROOT/profiles/themes"
MANIFEST="$THEMES_DIR/wallpapers.manifest.json"
FAIL=0

pass() { echo "CHECK-PASS: $1"; }
fail() { echo "CHECK-FAIL: $1" >&2; FAIL=1; }

[[ -f "$MANIFEST" ]] || { fail "missing manifest: $MANIFEST"; exit 1; }

if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$MANIFEST"; then
  fail "manifest is not valid JSON: $MANIFEST"
  exit 1
fi
pass "manifest is valid JSON"

export THEMES_DIR MANIFEST WALLPAPERS_ROOT STRICT
if ! python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

themes_dir = Path(os.environ["THEMES_DIR"])
manifest_path = Path(os.environ["MANIFEST"])
walls_root = os.environ.get("WALLPAPERS_ROOT") or ""
strict = os.environ.get("STRICT") == "1"
errors: list[str] = []
warnings: list[str] = []

REQUIRED = ("schemaVersion", "id", "name", "defaultWallpaper", "wallpaperDir")
ALLOWED_EXTS = (".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp")

packs: dict[str, dict] = {}
for child in sorted(themes_dir.iterdir()):
    if not child.is_dir():
        continue
    path = child / "theme.json"
    if not path.is_file():
        errors.append(f"{child.name}: missing theme.json")
        continue
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        errors.append(f"{child.name}/theme.json: invalid JSON ({exc})")
        continue
    for key in REQUIRED:
        if key not in data:
            errors.append(f"{child.name}/theme.json: missing key {key}")
    if data.get("id") != child.name:
        errors.append(
            f"{child.name}/theme.json: id {data.get('id')!r} "
            "does not match directory name"
        )
    blob = path.read_text(encoding="utf-8")
    if "/home/" in blob or "{{" in blob:
        errors.append(
            f"{child.name}/theme.json: absolute path or template marker found"
        )
    default = str(data.get("defaultWallpaper") or "")
    if default and not default.lower().endswith(ALLOWED_EXTS):
        errors.append(
            f"{child.name}/theme.json: unexpected wallpaper extension {default!r}"
        )
    if child.name in packs:
        errors.append(f"duplicate theme directory: {child.name}")
    packs[child.name] = data

try:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"CHECK-FAIL: manifest parse error: {exc}", file=sys.stderr)
    sys.exit(1)

entries = manifest.get("themes")
if not isinstance(entries, list) or not entries:
    print("CHECK-FAIL: manifest has no non-empty 'themes' array", file=sys.stderr)
    sys.exit(1)

seen: set[str] = set()
for entry in entries:
    theme_id = entry.get("id")
    if not theme_id:
        errors.append("manifest entry without id")
        continue
    if theme_id in seen:
        errors.append(f"manifest duplicate id: {theme_id}")
    seen.add(theme_id)
    if theme_id not in packs:
        errors.append(f"manifest id has no theme pack: {theme_id}")
        continue
    pack = packs[theme_id]
    for key in ("defaultWallpaper", "wallpaperDir"):
        if entry.get(key) != pack.get(key):
            errors.append(
                f"{theme_id}: manifest {key} {entry.get(key)!r} != "
                f"theme.json {pack.get(key)!r}"
            )

for theme_id in sorted(packs):
    if theme_id not in seen:
        errors.append(f"theme pack missing from manifest: {theme_id}")

# Binary existence is advisory: config vendors recipes only.
if walls_root:
    root = Path(walls_root)
    for theme_id, pack in sorted(packs.items()):
        candidate = root / str(pack.get("wallpaperDir") or theme_id) / str(
            pack.get("defaultWallpaper") or ""
        )
        if not candidate.is_file():
            msg = f"dangling default wallpaper: {theme_id} -> {candidate}"
            if strict:
                errors.append(msg)
            else:
                warnings.append(msg)
else:
    warnings.append(
        "wallpaper binaries not checked (recipes only; "
        "pass --wallpapers-root to verify defaults exist)"
    )

for message in warnings:
    print(f"CHECK-WARN: {message}", file=sys.stderr)
for message in errors:
    print(f"CHECK-FAIL: {message}", file=sys.stderr)
if errors:
    sys.exit(1)
print(f"CHECK-PASS: {len(packs)} theme packs agree with manifest")
PY
then
  fail "theme/manifest integrity"
else
  pass "theme/manifest integrity"
fi

if [[ $FAIL -ne 0 ]]; then
  echo "check-theme-refs: FAIL" >&2
  exit 1
fi
echo "check-theme-refs: ALL GREEN (warnings, if any, are listed above)"
