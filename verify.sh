#!/usr/bin/env bash
# verify.sh - read every setting back and report one line per check. It
# changes nothing and needs no password. Exit status 1 when any line fails.
#
#   ./verify.sh                run the checks
#   ./verify.sh --after-restart   same, then show the result as a notification
#                                 and remove the one-time login agent
# shellcheck source=lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# shellcheck source=lib/clone.sh
. "$HR_ROOT/lib/clone.sh"
set +e

mode="${1-}"
fails=0
ok() { echo "ok    $1"; }
bad() { echo "FAIL  $1"; fails=$((fails + 1)); }
check() { # check DESCRIPTION COMMAND...
  local d="$1"; shift
  if "$@" > /dev/null 2>&1; then ok "$d"; else bad "$d"; fi
}

# headless's own read-back of what its settings declare: FileVault, auto
# sign-in, key-only SSH, sleep, Tailscale. Its lines pass through here.
HEADLESS_VERIFY="$(clone_path kunchenguid/headless)/skills/headless/scripts/mac/remote/verify.sh"
headless_checks() {
  local out line
  [ -f "$HEADLESS_VERIFY" ] || { bad "headless's verify.sh is at $HEADLESS_VERIFY (run bash setup.sh machine)"; return; }
  out="$(/bin/bash "$HEADLESS_VERIFY" 2>&1)" || true
  [ -n "$out" ] || { bad "headless's verify.sh printed nothing"; return; }
  while IFS= read -r line; do
    case "$line" in
      ok* ) echo "$line" ;;
      FAIL* ) echo "$line"; fails=$((fails + 1)) ;;
      * ) echo "$line" ;;
    esac
  done <<< "$out"
}

[ "$(uname -s)" = Darwin ] || { bad "this is a Mac"; exit 1; }
check "admin user $HR_NAME" bash -c "id -Gn | tr ' ' '\n' | grep -qx admin"
check "secure token for $HR_NAME" bash -c "sysadminctl -secureTokenStatus '$HR_NAME' 2>&1 | grep -qi ENABLED"
check "Remote Login is on" nc -z 127.0.0.1 22
headless_checks
check "Xcode $XCODE_MIN or later selected" bash -c "v=\$(xcodebuild -version | awk '/^Xcode/ { print \$2; exit }'); [ \"\$(printf '%s\n%s\n' '$XCODE_MIN' \"\$v\" | sort -V | head -n 1)\" = '$XCODE_MIN' ]"
check "Xcode license accepted" xcodebuild -checkFirstLaunchStatus
check "iOS 27 runtime installed" bash -c "xcrun simctl list runtimes available | grep -q 'iOS 27'"
check "iPhone 18 Pro simulator" bash -c "xcrun simctl list devices available | grep -q '^ *iPhone 18 Pro ('"
check "iPad Pro 11-inch (M5) simulator" bash -c "xcrun simctl list devices available | grep -q '^ *iPad Pro 11-inch (M5) ('"
check "Rancher Desktop is installed" test -d "${HR_RANCHER_APP:-/Applications/Rancher Desktop.app}"
for t in git gh python3 no-mistakes; do check "$t is present" command -v "$t"; done
check "DEV_HOME is set to $DEV_HOME in ~/.zprofile" grep -qxF "export DEV_HOME=\"$DEV_HOME\"" "$HOME/.zprofile"
# Every clone sits at ~/Dev/github.com/<owner>/<repo>.
check "this repository is at $DEV_HOME/rojcarranza/headless-runner" test -d "$DEV_HOME/rojcarranza/headless-runner/.git"
check "runner-up login agent is loaded" launchctl print "gui/$(id -u)/com.github.runner-up"
# runner-up status reads the setup and the coordinator's saved state; the place
# is up when the coordinator process runs and the place is not resting.
check "runner-up coordinator is running" pgrep -u "$(id -u)" -f 'runner-up serve'
check "runner-up place $HR_NAME is not resting" bash -c "runner-up status | grep -i '$HR_NAME' | grep -viq resting"
check "GitHub sign-in works (runner-up needs it)" gh auth status

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
  # Delete the file first: stopping the agent ends this script.
  rm -f "$HOME/Library/LaunchAgents/com.headless-runner.verify.plist"
  launchctl bootout "gui/$(id -u)/com.headless-runner.verify" 2> /dev/null
fi
[ "$fails" = 0 ]
