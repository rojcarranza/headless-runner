#!/usr/bin/env bash
# scan-secrets.sh - fail when a tracked or new file holds a password, token or
# private key. This repository stores none: sign-ins stay the person's steps.
#   ./scripts/scan-secrets.sh [DIR]     scan DIR (default: the repository)
set -euo pipefail
root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
patterns=(
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
  'gh[pousr]_[A-Za-z0-9]{30,}'
  'github_pat_[A-Za-z0-9_]{30,}'
  'tskey-[A-Za-z0-9-]{20,}'
  'sk-[A-Za-z0-9]{32,}'
  'AKIA[0-9A-Z]{16}'
  '(password|passwd|secret|token)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"'$]{6,}["'"'"']'
)
found=0
for p in "${patterns[@]}"; do
  if grep -rEin --exclude-dir=.git --exclude-dir=node_modules --exclude=scan-secrets.sh --exclude='*.test.sh' -e "$p" "$root"; then
    found=1
  fi
done
[ "$found" = 0 ] || { echo "scan-secrets: a secret-looking value is in the files above" >&2; exit 1; }
echo "scan-secrets: clean"
