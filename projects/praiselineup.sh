#!/usr/bin/env bash
# PraiseLineup: clone it, its backend and the dotfiles in the standard place,
# link the review gate, make the gate simulator and try the checks.
# A clone already there is brought up to date with GitHub first (a clean main,
# fast-forward only), so a rerun tries the checks and scripts of GitHub's main.
# shellcheck source=lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=lib/clone.sh
. "$HR_ROOT/lib/clone.sh"

PL="$(clone_latest rojcarranza/praiselineup)"
clone_latest rojcarranza/praiselineup-backend > /dev/null
DOT="$(clone_latest rojcarranza/dotfiles)"

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
# The gate guard needs the no-mistakes remote, which a fresh clone lacks. init
# makes it (and repairs it when it is there), so it runs first, every time.
no-mistakes init
sh scripts/install-gate-guard.sh
sh ios/Tools/make_gate_simulator.sh
sh ios/Tools/gate_unit_tests.sh

# Trial nightly: the real one, into a scratch results folder so the real one is
# untouched, and --no-post so no issue or notification is written. A full run
# takes up to six hours; it writes latest/result only when every stage ran.
scratch="$(mktemp -d)"
PL_NIGHTLY_HOME="$scratch" sh ios/Tools/nightly_ui_tests.sh --no-post
grep -q '^passed ' "$scratch/latest/result" \
  || die "the trial nightly did not write 'passed <commit>' in $scratch/latest/result"
rm -rf "$scratch"
say "trial nightly passed"
