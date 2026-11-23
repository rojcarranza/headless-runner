#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2034 # pass/fail helpers never fail; stand-ins are single-quoted on purpose
# Intent (the captain): one command, ./setup.sh, runs every stage in order,
# stops where something fails, and picks up there when run again.
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
export HOME="$T/home" HR_NAME=builder HR_PASSWORD="sentinel-password-9f3" LOG="$T/log" LOGPW="$T/logpw"
mkdir -p "$HOME" "$T/bin"
# A Mac's answer to uname, so the Apple silicon check passes on this computer.
printf '#!/bin/sh\n[ "$1" = -m ] && echo arm64 || echo Darwin\n' > "$T/bin/uname"; chmod +x "$T/bin/uname"
export PATH="$T/bin:$PATH"

# The repository's scripts with each stage replaced by one that records itself.
mkdir -p "$T/r"; (cd "$ROOT" && tar -cf - setup.sh pins.env lib stages) | tar -xf - -C "$T/r"
for s in account machine claude-code xcode runner-up projects restart; do
  printf '#!/bin/sh\necho %s >> "$LOG"\n[ -z "${HR_PASSWORD-}" ] || echo %s >> "$LOGPW"\n[ "${STUB_FAIL-}" = %s ] && exit 1\nexit 0\n' "$s" "$s" "$s" > "$T/r/stages/$s.sh"
done
run() { : > "$LOG"; : > "$LOGPW"; "$T/r/setup.sh" "$@" 2>&1; }

out="$(run)"; assert_eq "$(tr '\n' ' ' < "$LOG")" "account machine claude-code xcode runner-up projects restart " "stages run in order"
assert_not_contains "$out" "$HR_PASSWORD" "the password is never printed"
assert_eq "$(tr '\n' ' ' < "$LOGPW")" "account machine xcode restart " "only the stages that use the password receive it"
run > /dev/null; assert_eq "$(tr '\n' ' ' < "$LOG")" "restart " "a second run skips every finished stage"

rm -rf "$HOME/.headless-runner"
STUB_FAIL=xcode run > /dev/null && fail "a failing stage stops the run" || pass "a failing stage stops the run"
assert_eq "$(tr '\n' ' ' < "$LOG")" "account machine claude-code xcode " "nothing runs after the failure"
run > /dev/null; assert_eq "$(tr '\n' ' ' < "$LOG")" "xcode runner-up projects restart " "a rerun resumes at the failed stage"

rm -rf "$HOME/.headless-runner"
run --no-restart > /dev/null; assert_eq "$(tr '\n' ' ' < "$LOG")" "account machine claude-code xcode runner-up projects " "--no-restart leaves the restart out"
run xcode > /dev/null; assert_eq "$(tr '\n' ' ' < "$LOG")" "xcode " "naming a stage runs only it, again"
run nonsense > /dev/null && fail "an unknown stage is refused" || pass "an unknown stage is refused"

# Intent (the captain): a Mac set up before the claude-code stage existed gets
# it with one more run after a git pull. Its other stages are done, so only the
# new one runs.
rm -rf "$HOME/.headless-runner"; mkdir -p "$HOME/.headless-runner/done"
for s in account machine xcode runner-up projects restart; do : > "$HOME/.headless-runner/done/$s"; done
run > /dev/null; assert_eq "$(tr '\n' ' ' < "$LOG")" "claude-code " "a Mac set up before the claude-code stage gets only that stage on its next run"
done_tests
