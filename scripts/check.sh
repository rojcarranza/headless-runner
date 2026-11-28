#!/usr/bin/env bash
# check.sh - this repository's gate: shell syntax and lint, the script tests,
# the secret scan, the code file size limit, and the machine flake evaluating
# for an Apple silicon Mac. It runs on any computer with bash, zsh, shellcheck,
# jq, python3 and Nix (the flake step is skipped, and says so, when Nix is
# missing). The no-mistakes gate runs it.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
files=(setup.sh verify.sh stages/*.sh projects/*.sh lib/*.sh scripts/*.sh tests/*.sh)

echo "== bash -n"
for f in "${files[@]}"; do bash -n "$f"; done
echo "== shellcheck"
shellcheck -x "${files[@]}"
echo "== secret scan"
./scripts/scan-secrets.sh
echo "== size check"
./scripts/size-check.py
echo "== script tests"
./tests/run.sh
echo "== machine flake, aarch64-darwin"
if command -v nix > /dev/null; then
  ./tests/flake-eval.sh
else
  echo "nix is not installed; flake evaluation skipped" >&2
fi
echo "check: all passed"
