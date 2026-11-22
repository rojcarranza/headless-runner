#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2034 # pass/fail helpers never fail; stand-ins are single-quoted on purpose
# Intent (the captain): verify.sh reads every setting back, reports one line
# per check, changes nothing, and also reports the case where another user is
# at the screen. Stand-ins print what macOS prints; HEALTHY=0 breaks one.
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
export HOME="$T/home" HR_NAME=builder DEV_HOME="$T/home/Dev/github.com" HR_SETTINGS="$T/settings.json"
export HR_STATE="$T/state"
mkdir -p "$HOME" "$DEV_HOME/rojcarranza/headless-runner/.git" "$T/bin"
jq -n '{keyOnlySsh:true,autoLogin:true,user:"builder"}' > "$HR_SETTINGS"
echo 'export DEV_HOME="'"$DEV_HOME"'"' > "$HOME/.zprofile"

stub() { printf '#!/bin/sh\n%s\n' "$2" > "$T/bin/$1"; chmod +x "$T/bin/$1"; }
stub uname '[ "$1" = -m ] && echo arm64 || echo Darwin'
stub id 'case "$1" in -Gn) echo "staff admin everyone" ;; -u) echo 501 ;; *) echo builder ;; esac'
stub sysadminctl 'echo "2026-11-22 sysadminctl[1:2] Secure token is ENABLED for user builder" >&2'
stub nc 'exit 0'
stub defaults 'echo builder'
stub fdesetup 'if [ "${FILEVAULT-off}" = on ]; then echo "FileVault is On."; else echo "FileVault is Off."; fi'
stub pmset 'printf " SleepDisabled\t\t1\n"'
stub tailscale 'echo "{\"BackendState\": \"Running\"}"'
stub xcodebuild 'case "$1" in -version) printf "Xcode 27.1\nBuild version 27A100\n" ;; esac'
stub xcrun 'case "$*" in "simctl list runtimes available") echo "iOS 27.1 (27.1 - 27A5000) - com.apple.CoreSimulator.SimRuntime.iOS-27-1" ;; "simctl list devices available") printf "== Devices ==\n-- iOS 27.1 --\n    iPhone 18 Pro (AAAAAAAA-0000-0000-0000-000000000001) (Shutdown)\n    iPad Pro 11-inch (M5) (AAAAAAAA-0000-0000-0000-000000000002) (Shutdown)\n" ;; esac'
stub docker 'exit 0'
stub git 'exit 0'; stub gh 'exit 0'; stub python3 'exit 0'; stub no-mistakes 'exit 0'
stub launchctl 'exit 0'
stub runner-up 'echo "place builder  online"'
stub pgrep 'echo 123'
stub stat 'echo "${CONSOLE-builder}"'
stub osascript 'exit 0'
export PATH="$T/bin:$PATH"
ln -sf "$(command -v jq)" "$T/bin/jq" 2> /dev/null || true

out="$("$ROOT/verify.sh" 2>&1)"; rc=$?
assert_eq "$rc" 0 "a healthy Mac passes"
assert_contains "$out" "all checks passed" "the summary says so"
assert_contains "$out" "ok    FileVault is off" "each check is one line"
assert_contains "$out" "switched-user check skipped" "at the screen: the switched-user check says it is skipped"

out="$(FILEVAULT=on "$ROOT/verify.sh" 2>&1)"; rc=$?
assert_eq "$rc" 1 "FileVault on fails the run"
assert_contains "$out" "FAIL  FileVault is off" "and names the line"

out="$(CONSOLE=guest "$ROOT/verify.sh" 2>&1)"; rc=$?
assert_eq "$rc" 0 "another user at the screen still passes"
assert_contains "$out" "ok    another user (guest) is at the screen" "and the switched-user check runs"
assert_contains "$out" "ok    work still runs here" "runner-up and the simulator answer in this session"
done_tests
