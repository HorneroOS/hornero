#!/bin/sh
# Fake hornero-chromatic for horneroctl tests: serves the golden JSON
# documents next to this script (contract: RFC 0002 / CHROMATIC-CONTRACT §5).
#   FAKE_EXIT=N     exit N with a stderr line (3 = source unreadable, 4 = gates)
#   FAKE_LOG=FILE   append one line per invocation (argv) to FILE
#   FAKE_ENGINE=0   (unused: tests point HORNERO_CHROMATIC_BIN at a missing path)
set -eu
here=$(dirname "$0")
[ -n "${FAKE_LOG:-}" ] && printf '%s\n' "$*" >>"$FAKE_LOG"
if [ -n "${FAKE_EXIT:-}" ]; then
  echo "fake-helper: forced exit ${FAKE_EXIT}" >&2
  exit "$FAKE_EXIT"
fi
verb=${1:-}
[ $# -gt 0 ] && shift
variant=balanced
source=
while [ $# -gt 0 ]; do
  case "$1" in
    --variant) variant=$2; shift ;;
    --source) source=$2; shift ;;
  esac
  shift
done
case "$verb" in
  generate)
    if [ -n "$source" ] && [ ! -r "$source" ]; then
      echo "fake-helper: cannot read $source" >&2
      exit 3
    fi
    case "$variant" in
      vibrant|expressive|faithful) f=generate-vibrant.json ;;
      neon) f=generate-neon.json ;;
      *) f=generate-balanced.json ;;
    esac
    cat "$here/$f" ;;
  analyze)
    if [ -n "$source" ] && [ ! -r "$source" ]; then
      echo "fake-helper: cannot read $source" >&2
      exit 3
    fi
    cat "$here/analyze.json" ;;
  variants) cat "$here/variants.json" ;;
  version) cat "$here/version.json" ;;
  *) echo "fake-helper: unknown verb $verb" >&2; exit 2 ;;
esac
