#!/usr/bin/env bash
# verify.sh - read every setting back and report one line per check. It
# changes nothing and needs no password. Exit status 1 when any line fails.
#
#   ./verify.sh                run the checks
#   ./verify.sh --after-restart   same, then show the result as a notification
#                                 and remove the one-time login agent
#   ./verify.sh --ci           same checks, for the manual GitHub Actions run
# shellcheck source=lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
set +e

mode="${1-}"
fails=0
ok() { echo "ok    $1"; }
bad() { echo "FAIL  $1"; fails=$((fails + 1)); }
check() { # check DESCRIPTION COMMAND...
  local d="$1"; shift
  if "$@" > /dev/null 2>&1; then ok "$d"; else bad "$d"; fi
}

has_setting() { jq -e "$1" "${HR_SETTINGS:-/etc/headless/settings.json}" > /dev/null 2>&1; }

[ "$(uname -s)" = Darwin ] || { bad "this is a Mac"; exit 1; }
check "admin user $HR_NAME" bash -c "id -Gn | tr ' ' '\n' | grep -qx admin"
check "secure token for $HR_NAME" bash -c "sysadminctl -secureTokenStatus '$HR_NAME' 2>&1 | grep -qi ENABLED"
check "Remote Login is on" nc -z 127.0.0.1 22
check "SSH takes keys only" has_setting '.keyOnlySsh == true'
check "auto sign-in is set for $HR_NAME" bash -c "[ \"\$(defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null)\" = '$HR_NAME' ]"
check "FileVault is off" bash -c "fdesetup status | grep -q 'FileVault is Off'"
check "awake with the lid closed (pmset disablesleep)" bash -c "pmset -g | grep -Eq 'SleepDisabled[[:space:]]+1'"
check "Tailscale is up" bash -c "tailscale status --json | jq -e '.BackendState == \"Running\"'"
check "Xcode $XCODE_MIN or later selected" bash -c "v=\$(xcodebuild -version | awk '/^Xcode/ { print \$2; exit }'); [ \"\$(printf '%s\n%s\n' '$XCODE_MIN' \"\$v\" | sort -V | head -n 1)\" = '$XCODE_MIN' ]"
check "Xcode license accepted" xcodebuild -checkFirstLaunchStatus
check "iOS 27 runtime installed" bash -c "xcrun simctl list runtimes available | grep -q 'iOS 27'"
check "iPhone 18 Pro simulator" bash -c "xcrun simctl list devices available | grep -q '^ *iPhone 18 Pro ('"
check "iPad Pro 11-inch (M5) simulator" bash -c "xcrun simctl list devices available | grep -q '^ *iPad Pro 11-inch (M5) ('"
check "Docker answers" docker info
for t in git gh python3 no-mistakes; do check "$t is present" command -v "$t"; done
check "DEV_HOME is $DEV_HOME" bash -c "[ \"\${DEV_HOME-}\" = '$DEV_HOME' ] || grep -qxF 'export DEV_HOME=\"$DEV_HOME\"' ~/.zprofile"
# Every clone sits at ~/Dev/github.com/<owner>/<repo>.
check "this repository is at $DEV_HOME/rojcarranza/headless-runner" test -d "$DEV_HOME/rojcarranza/headless-runner/.git"
check "runner-up login agent is loaded" launchctl print "gui/$(id -u)/com.github.runner-up"
check "runner-up shows $HR_NAME online" bash -c "runner-up status | grep -qi '$HR_NAME'"

# With another user at the screen, this user's session must keep working.
console="$(stat -f%Su /dev/console 2> /dev/null)"
if [ -n "$console" ] && [ "$console" != "$HR_NAME" ] && [ "$console" != root ]; then
  ok "another user ($console) is at the screen"
  check "work still runs here: runner-up and the simulator service answer" bash -c "pgrep -u '$(id -u)' -f 'runner-up serve' && xcrun simctl list devices available"
else
  echo "note  switched-user check skipped: $HR_NAME is at the screen. Switch User to another account and run ./verify.sh over SSH to run it"
fi

if [ "$fails" = 0 ]; then echo "all checks passed"; else echo "$fails check(s) failed"; fi

if [ "$mode" = --after-restart ]; then
  msg="all checks passed"
  [ "$fails" = 0 ] || msg="$fails check(s) failed: see ~/Library/Logs/headless-runner-verify.log"
  osascript -e "display notification \"$msg\" with title \"headless-runner\"" 2> /dev/null
  launchctl bootout "gui/$(id -u)/com.headless-runner.verify" 2> /dev/null
  rm -f "$HOME/Library/LaunchAgents/com.headless-runner.verify.plist"
fi
[ "$fails" = 0 ]
