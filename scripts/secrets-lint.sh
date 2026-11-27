#!/usr/bin/env bash
# secrets-lint.sh - gitleaks-style grep gate for committed secrets.
#
# Scans the repository for high-signal token/key patterns (AWS keys,
# GitHub/Slack/Stripe tokens, PEM private keys, credential assignments).
# Patterns are deliberately tight: prose words like "password" or
# "secret" alone never match, so the gate passes on a clean tree.
#
# Usage:
#   scripts/secrets-lint.sh [--root DIR]
#
# Exit 0 when no findings, 1 otherwise. The lint script itself is
# excluded from the scan so its own pattern strings are not flagged.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      ROOT="${2:-}"
      shift 2
      ;;
    *)
      echo "usage: secrets-lint.sh [--root DIR]" >&2
      exit 2
      ;;
  esac
done

PATTERN='AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36,}|gho_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{20,}|xox[bpas]-[A-Za-z0-9-]{10,}|sk-live-[A-Za-z0-9]{16,}|BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY|aws_secret_access_key|api[_-]?key[[:space:]]*[:=][[:space:]]*.[^[:space:]]+|(password|passwd|secret)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']+["'"'"']'

HITS="$(grep -rInE --exclude-dir=.git --exclude-dir=__pycache__ \
  --exclude='*.pyc' --exclude='secrets-lint.sh' \
  --exclude='secrets-allowlist.txt' \
  -e "$PATTERN" "$ROOT" || true)"

# Scoped suppressions (scripts/secrets-allowlist.txt):
# path-prefix|fixed-string|reason. Hits are relativized to the scanned root,
# then a hit survives only when no entry matches both its file and its line.
ALLOWLIST="$(dirname "${BASH_SOURCE[0]}")/secrets-allowlist.txt"
if [[ -n "$HITS" && -f "$ALLOWLIST" ]]; then
  HITS="$(printf '%s\n' "$HITS" | sed "s|^${ROOT}/||")"
  while IFS='|' read -r prefix fixed _reason; do
    [[ "$prefix" =~ ^[[:space:]]*# || -z "$prefix" ]] && continue
    HITS="$(printf '%s\n' "$HITS" \
      | awk -v p="$prefix" -v f="$fixed" 'index($0, p) == 1 && index($0, f) > 0 { next } { print }')"
  done < "$ALLOWLIST"
  HITS="$(printf '%s\n' "$HITS" | grep -v '^$' || true)"
fi

if [[ -n "$HITS" ]]; then
  echo "SECRETS-FAIL: possible credentials found:"
  echo "$HITS"
  echo "Remove the secrets from history, use placeholders, and re-run:"
  echo "  scripts/secrets-lint.sh"
  exit 1
fi
echo "SECRETS-PASS: no token/key patterns found"
