#!/usr/bin/env bash
# PraiseLineup: clone it, its backend and the dotfiles in the standard place,
# link the review gate, make the gate simulator and try the checks.
# shellcheck source=lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=lib/clone.sh
. "$HR_ROOT/lib/clone.sh"

PL="$(clone_repo rojcarranza/praiselineup)"
clone_repo rojcarranza/praiselineup-backend > /dev/null
DOT="$(clone_repo rojcarranza/dotfiles)"

# The review step reads the gate folder from the dotfiles, so every computer
# shares one copy.
mkdir -p "$HOME/.no-mistakes"
if [ -d "$DOT/home/no-mistakes/review-gate" ]; then
  ln -sfn "$DOT/home/no-mistakes/review-gate" "$HOME/.no-mistakes/review-gate"
else
  warn "the dotfiles have no home/no-mistakes/review-gate; the review step will not find it"
fi

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd "$PL"
sh scripts/install-gate-guard.sh
sh ios/Tools/make_gate_simulator.sh
sh ios/Tools/gate_unit_tests.sh

# Trial nightly into a scratch results folder, so the real one is untouched.
if [ -f ios/Tools/nightly.sh ]; then
  scratch="$(mktemp -d)"
  PL_NIGHTLY_HOME="$scratch" sh ios/Tools/nightly.sh
  grep -q '^passed ' "$scratch"/* \
    || die "the trial nightly did not write 'passed <commit>' in $scratch"
  say "trial nightly passed"
else
  warn "PraiseLineup has no ios/Tools/nightly.sh here; the trial nightly was not run"
fi
