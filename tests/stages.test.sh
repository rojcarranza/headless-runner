#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2034 # pass/fail helpers never fail; stand-ins are single-quoted on purpose
# Intent (the review of PR #2): a clean Mac must get through the projects stage
# (the gate guard needs no-mistakes init first), and a rerun of the runner-up
# stage after a failed "machine add" must finish adding the machine.
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
export HOME="$T/home" HR_NAME=builder DEV_HOME="$T/home/Dev/github.com" HR_STATE="$T/state" LOG="$T/log"
mkdir -p "$HOME" "$T/bin"
stub() { printf '#!/bin/sh\n%s\n' "$2" > "$T/bin/$1"; chmod +x "$T/bin/$1"; }
stub uname '[ "$1" = -m ] && echo arm64 || echo Darwin'
export PATH="$T/bin:$PATH"

# --- projects: PraiseLineup's gate guard fails until no-mistakes init has run
for r in praiselineup praiselineup-backend dotfiles; do mkdir -p "$DEV_HOME/rojcarranza/$r/.git"; done
mkdir -p "$DEV_HOME/rojcarranza/praiselineup/ios/Tools" "$DEV_HOME/rojcarranza/praiselineup/scripts"
: > "$LOG"
stub no-mistakes 'echo "no-mistakes $*" >> "$LOG"'
stub sh 'echo "sh $*" >> "$LOG"
case "$1" in
  scripts/install-gate-guard.sh) grep -q "^no-mistakes init" "$LOG" || { echo "No no-mistakes remote here." >&2; exit 1; } ;;
  ios/Tools/nightly_ui_tests.sh) mkdir -p "$PL_NIGHTLY_HOME/latest"; echo "passed 0123abc" > "$PL_NIGHTLY_HOME/latest/result" ;;
esac'
bash "$ROOT/projects/praiselineup.sh" > "$T/out" 2>&1; rc=$?
assert_eq "$rc" 0 "a fresh PraiseLineup clone gets through the projects script"
assert_eq "$(grep -n 'no-mistakes init\|install-gate-guard' "$LOG" | cut -d: -f1 | tr '\n' ' ')" "1 2 " "init runs before the gate guard"
assert_contains "$(cat "$LOG")" "sh ios/Tools/nightly_ui_tests.sh --no-post" "the trial nightly is the real one, with nothing posted"
assert_contains "$(cat "$T/out")" "trial nightly passed" "and its latest/result is read"
stub sh 'case "$1" in ios/Tools/nightly_ui_tests.sh) exit 0 ;; esac'
bash "$ROOT/projects/praiselineup.sh" > "$T/out" 2>&1 && fail "a nightly that wrote no result fails the stage" || pass "a nightly that wrote no result fails the stage"

# --- runner-up: init done but machine add failed; a rerun adds the machine
mkdir -p "$DEV_HOME/rojcarranza/headless-runner/.git" "$DEV_HOME/rojcarranza/headless-runner/machine"
CFG="$HOME/Library/Application Support/runner-up/config.json"
stub gh 'exit 0'; stub launchctl 'exit 0'; stub sleep 'exit 0'
stub runner-up 'CFG="$HOME/Library/Application Support/runner-up/config.json"
case "$1" in
  init) mkdir -p "$(dirname "$CFG")"; echo "{\"machines\":[]}" > "$CFG" ;;
  machine) [ -z "${FAIL_ADD-}" ] || exit 1; jq --arg n "$3" ".machines += [{name: \$n}]" "$CFG" > "$CFG.new" && mv "$CFG.new" "$CFG" ;;
  status) echo "place $HR_NAME free" ;;
esac'
FAIL_ADD=1 bash "$ROOT/stages/runner-up.sh" > /dev/null 2>&1 && fail "a failed machine add stops the stage" || pass "a failed machine add stops the stage"
assert_eq "$(jq '.machines | length' "$CFG")" 0 "the setup file exists with no machine"
bash "$ROOT/stages/runner-up.sh" > /dev/null 2>&1
assert_eq "$(jq -r '.machines[0].name' "$CFG")" builder "a rerun adds the machine the file lacks"
bash "$ROOT/stages/runner-up.sh" > /dev/null 2>&1
assert_eq "$(jq '.machines | length' "$CFG")" 1 "and a second rerun adds nothing twice"
done_tests
