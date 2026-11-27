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

# headless's own verify.sh reads back everything its settings declare: FileVault,
# auto sign-in, key-only SSH (it tries a password sign-in and expects it refused),
# sleep and Tailscale. It signs in over SSH by key, so a sudo ticket from this
# terminal cannot make its "sudo asks for the password" line fail falsely.
HEADLESS_VERIFY="$(clone_path kunchenguid/headless)/skills/headless/scripts/mac/verify.sh"
headless_checks() {
  local out n
  [ -f "$HEADLESS_VERIFY" ] || { bad "headless's verify.sh is at $HEADLESS_VERIFY (run bash setup.sh machine)"; return; }
  out="$(/bin/bash "$HEADLESS_VERIFY" "$HR_CONFIG" 2>&1)" || true
  [ -z "$out" ] || printf '%s\n' "$out"
  n="$(grep -c '^FAIL' <<< "$out")"
  if [ "$n" = 0 ] && ! grep -q '^ok' <<< "$out"; then bad "headless's verify.sh printed no result"; else fails=$((fails + n)); fi
}
# Called directly (not inside bash -c, whose own arguments would match pgrep -f).
work_runs_here() {
  pgrep -u "$(id -u)" -f 'runner-up serve' > /dev/null && xcrun simctl list devices available > /dev/null
}
xcode_is_new_enough() {
  version_ge "$(xcodebuild -version | awk '/^Xcode/ { print $2; exit }')" "$XCODE_MIN"
}
# runner-up status prints "place ID on MACHINE (host, N cores, M MB) STATE" for
# each place, and also "waiting ..." lines for queued jobs. Only this Mac's place
# lines count, and none of them may be resting.
runner_up_place_ok() {
  local lines
  lines="$(runner-up status 2> /dev/null | grep -E "^[[:space:]]*place .* on ${HR_NAME} \(")"
  [ -n "$lines" ] && ! grep -qi resting <<< "$lines"
}
# A non-interactive SSH command, by key against the host key headless pinned,
# the way headless's own scripts sign in here: its zsh reads only ~/.zshenv,
# so claude answers by name only through the claude-code stage's PATH line.
claude_over_ssh() {
  ssh -o "UserKnownHostsFile=\"$HR_CONFIG/known_hosts\"" -o StrictHostKeyChecking=yes \
    -o IdentitiesOnly=yes -i "$HOME/.ssh/id_ed25519" -o BatchMode=yes -o ConnectTimeout=15 \
    "$HR_NAME@127.0.0.1" claude --version
}

# Tailscale SSH answers port 22 itself and, in check mode, asks the person for a
# browser approval every 12 hours; macOS's own sshd takes the first mate's key.
tailscale_ssh_off() {
  local prefs
  prefs="$(tailscale debug prefs 2> /dev/null)" || return 1
  grep -q '"RunSSH"' <<< "$prefs" && ! grep -Eq '"RunSSH":[[:space:]]*true' <<< "$prefs"
}
# This Mac's own key lets it into itself only; another computer needs its own line.
other_key_authorized() {
  local line own
  own="$(key_id "$(head -n 1 "$HOME/.ssh/id_ed25519.pub")")"
  while IFS= read -r line; do
    case "$line" in '' | '#'*) continue ;; esac
    [ "$(key_id "$line")" = "$own" ] || return 0
  done < "$HOME/.ssh/authorized_keys"
  return 1
}

[ "$(uname -s)" = Darwin ] || { bad "this is a Mac"; exit 1; }
check "admin user $HR_NAME" bash -c "id -Gn | tr ' ' '\n' | grep -qx admin"
check "secure token for $HR_NAME" bash -c "sysadminctl -secureTokenStatus '$HR_NAME' 2>&1 | grep -qi ENABLED"
check "Remote Login is on" nc -z 127.0.0.1 22
headless_checks
check "Tailscale SSH is off (RunSSH false; sshd on port 22 takes keys)" tailscale_ssh_off
check "SSH authorizes a key other than this Mac's own" other_key_authorized
# headless checks sleep and disksleep only; the lid-closed setting is this repository's.
check "awake with the lid closed (pmset disablesleep)" bash -c "pmset -g | grep -Eq 'SleepDisabled[[:space:]]+1'"
check "Xcode $XCODE_MIN or later selected" xcode_is_new_enough
check "Xcode license accepted" xcodebuild -checkFirstLaunchStatus
check "iOS 27 runtime installed" bash -c "xcrun simctl list runtimes available | grep -q 'iOS 27'"
check "iPhone 18 Pro simulator" bash -c "xcrun simctl list devices available | grep -q '^ *iPhone 18 Pro ('"
check "iPad Pro 11-inch (M5) simulator" bash -c "xcrun simctl list devices available | grep -q '^ *iPad Pro 11-inch (M5) ('"
check "Rancher Desktop is installed" test -d "${HR_RANCHER_APP:-/Applications/Rancher Desktop.app}"
for t in git gh gh-axi python3 no-mistakes; do check "$t is present" command -v "$t"; done
check "Claude Code is installed at ~/.local/bin/claude" "$HOME/.local/bin/claude" --version
check "claude runs by name in a non-interactive SSH command" claude_over_ssh
check "DEV_HOME is set to $DEV_HOME in ~/.zprofile" grep -qxF "export DEV_HOME=\"$DEV_HOME\"" "$HOME/.zprofile"
# Every clone sits at ~/Dev/github.com/<owner>/<repo>.
check "this repository is at $DEV_HOME/rojcarranza/headless-runner" test -d "$DEV_HOME/rojcarranza/headless-runner/.git"
check "runner-up login agent is loaded" launchctl print "gui/$(id -u)/com.github.runner-up"
# runner-up status reads the setup and the coordinator's saved state, so the
# running coordinator process is checked beside it.
check "runner-up coordinator is running" pgrep -u "$(id -u)" -f 'runner-up serve'
check "runner-up has a place on $HR_NAME and it is not resting" runner_up_place_ok
check "GitHub sign-in works (runner-up needs it)" github_signed_in
check "GitHub accepts this Mac's SSH key (clones with SSH addresses work)" github_greets

# With another user at the screen, this user's session must keep working.
console="$(stat -f%Su /dev/console 2> /dev/null)"
if [ -n "$console" ] && [ "$console" != "$HR_NAME" ] && [ "$console" != root ]; then
  ok "another user ($console) is at the screen"
  check "work still runs here: runner-up and the simulator service answer" work_runs_here
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
