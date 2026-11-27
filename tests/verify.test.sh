#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2034 # pass/fail helpers never fail; stand-ins are single-quoted on purpose
# Intent (the captain): verify.sh reads every setting back, reports one line
# per check, changes nothing, and also reports the case where another user is
# at the screen. Stand-ins print what macOS prints; FILEVAULT, LID, RESTING and PLACE_MACHINE break one
# check each, and CONSOLE sets which user is at the screen. Intent (the
# captain): verify.sh also checks claude --version in a non-interactive SSH command.
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
export HOME="$T/home" HR_NAME=builder DEV_HOME="$T/home/Dev/github.com"
export HR_STATE="$T/state"
mkdir -p "$HOME" "$DEV_HOME/rojcarranza/headless-runner/.git" "$T/bin"
echo 'export DEV_HOME="'"$DEV_HOME"'"' > "$HOME/.zprofile"

stub() { printf '#!/bin/sh\n%s\n' "$2" > "$T/bin/$1"; chmod +x "$T/bin/$1"; }
stub uname '[ "$1" = -m ] && echo arm64 || echo Darwin'
stub id 'case "$1" in -Gn) echo "staff admin everyone" ;; -u) echo 501 ;; *) echo builder ;; esac'
stub sysadminctl 'echo "2026-11-22 sysadminctl[1:2] Secure token is ENABLED for user builder" >&2'
stub nc 'exit 0'
stub pmset 'printf " SleepDisabled\t\t${LID-1}\n"'
stub xcodebuild 'case "$1" in -version) printf "Xcode 27.1\nBuild version 27A100\n" ;; esac'
stub xcrun 'case "$*" in "simctl list runtimes available") echo "iOS 27.1 (27.1 - 27A5000) - com.apple.CoreSimulator.SimRuntime.iOS-27-1" ;; "simctl list devices available") printf "== Devices ==\n-- iOS 27.1 --\n    iPhone 18 Pro (AAAAAAAA-0000-0000-0000-000000000001) (Shutdown)\n    iPad Pro 11-inch (M5) (AAAAAAAA-0000-0000-0000-000000000002) (Shutdown)\n" ;; esac'
stub git 'exit 0'; stub gh 'exit 0'
# gh-axi api /user reads gh's token from the login keychain, which macOS opens
# only to the signed-in session (launchd's jobs); anywhere else, as over SSH,
# it says what the real one says there. $T/signed-out: no sign-in anywhere.
stub gh-axi '[ -n "${IN_SIGNED_IN_SESSION-}" ] && [ ! -e "'"$T"'/signed-out" ] && { echo "login: octo"; exit 0; }
echo "error: \"gh: Requires authentication (HTTP 401)\""; echo "code: UNKNOWN"; exit 1'
stub python3 'exit 0'; stub no-mistakes 'exit 0'
stand_in_launchctl "$T/bin"
# runner-up's real status lines; RESTING=1 rests the place and a job waits on the pool.
stub runner-up 'echo "place host-1 on ${PLACE_MACHINE-builder} (host, 4 cores, 8192 MB) $([ "${RESTING-}" = 1 ] && echo "resting (agent unreachable since 2026-11-22T10:00:00Z)" || echo free)"
echo "waiting rojcarranza/builder-app builder job-1 since 2026-11-22T10:00:00Z"'
stub pgrep 'echo 123'
stub stat 'echo "${CONSOLE-builder}"'
stub osascript 'exit 0'
# headless's own verify.sh "DIR", as the pinned clone holds it; FILEVAULT=on breaks one line.
HV="$DEV_HOME/kunchenguid/headless/skills/headless/scripts/mac/verify.sh"
mkdir -p "$(dirname "$HV")" "$T/rancher" "$HOME/Library/LaunchAgents"
printf '#!/bin/sh\necho "ok    read with $1"\necho "ok    password sign-in refused (key only)"\nif [ "${FILEVAULT-off}" = on ]; then echo "FAIL  FileVault off (needed for automatic sign-in) (found true, want false)"; else echo "ok    FileVault off (needed for automatic sign-in)"; fi\n' > "$HV"
export HR_RANCHER_APP="$T/rancher"
# Claude Code as the claude-code stage leaves it, and SSH commands run as sshd runs them.
install_claude_native "$HOME" 2.1.330
printf '%s\n' 'export PATH="$HOME/.local/bin:$PATH"' > "$HOME/.zshenv"
stand_in_ssh "$T/bin"
# GitHub answers git@github.com with its greeting (and exit 1) while the key is on the account (GH_KEY=none: refused).
mv "$T/bin/ssh" "$T/bin/ssh-host"
printf '#!/bin/sh\ncase "$*" in\n  *git@github.com*) [ "${GH_KEY-ok}" = ok ] && { echo "Hi octo! You'"'"'ve successfully authenticated, but GitHub does not provide shell access."; exit 1; }; echo "Permission denied (publickey)." >&2; exit 255 ;;\nesac\nexec "$(dirname "$0")/ssh-host" "$@"\n' > "$T/bin/ssh"; chmod +x "$T/bin/ssh"
# Tailscale's prefs as tailscale debug prefs prints them; SSH=on turns Tailscale SSH on.
stub tailscale 'printf "{\n\t\"ControlURL\": \"https://controlplane.tailscale.com\",\n\t\"RunSSH\": %s,\n\t\"WantRunning\": true\n}\n" "$([ "${SSH-off}" = on ] && echo true || echo false)"'
# sshd's keys as nix-darwin leaves them: the user's own file holds the Mac's own
# key (headless's first sign-in), the file nix-darwin serves holds sshKeys: the
# own key and the first mate computer's.
mkdir -p "$HOME/.ssh"; make_key "$HOME/.ssh/id_ed25519"; make_key "$T/mate"
cat "$HOME/.ssh/id_ed25519.pub" > "$HOME/.ssh/authorized_keys"
export NIX_AUTHORIZED_KEYS="$T/nix_authorized_keys"
cat "$HOME/.ssh/id_ed25519.pub" "$T/mate.pub" > "$NIX_AUTHORIZED_KEYS"
export PATH="$T/bin:$PATH"

out="$("$ROOT/verify.sh" 2>&1)"; rc=$?
assert_eq "$rc" 0 "a healthy Mac passes"
assert_contains "$out" "all checks passed" "the summary says so"
assert_contains "$out" "ok    FileVault off" "each check is one line, headless's own lines among them"
assert_contains "$out" "switched-user check skipped" "at the screen: the switched-user check says it is skipped"

assert_contains "$out" "ok    Tailscale SSH is off" "Tailscale SSH off passes"
assert_contains "$out" "ok    SSH authorizes a key other than" "a second key passes"

out="$(SSH=on "$ROOT/verify.sh" 2>&1)"; rc=$?
assert_eq "$rc" 1 "Tailscale SSH on fails the run"
assert_contains "$out" "FAIL  Tailscale SSH is off" "and names the line"

cat "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_ed25519.pub" > "$NIX_AUTHORIZED_KEYS"
out="$("$ROOT/verify.sh" 2>&1)"; rc=$?
assert_eq "$rc" 1 "only the own key authorized fails the run"
assert_contains "$out" "FAIL  SSH authorizes a key other than" "and names the line"
rm "$NIX_AUTHORIZED_KEYS"
out="$("$ROOT/verify.sh" 2>&1)"; rc=$?
assert_eq "$rc" 1 "a missing nix-darwin key file leaves only the own key and fails the run"
cat "$HOME/.ssh/id_ed25519.pub" "$T/mate.pub" > "$NIX_AUTHORIZED_KEYS"

out="$(FILEVAULT=on "$ROOT/verify.sh" 2>&1)"; rc=$?
assert_eq "$rc" 1 "FileVault on fails the run"
assert_contains "$out" "FAIL  FileVault off" "and names the line"

out="$(CONSOLE=guest "$ROOT/verify.sh" 2>&1)"; rc=$?
assert_eq "$rc" 0 "another user at the screen still passes"
assert_contains "$out" "ok    another user (guest) is at the screen" "and the switched-user check runs"
assert_contains "$out" "ok    work still runs here" "runner-up and the simulator answer in this session"
assert_contains "$(CONSOLE=builder "$ROOT/verify.sh" 2>&1)" "ok    read with $HR_STATE/config/builder" "headless's verify.sh is run on this computer's config folder, which checks password refusal"

out="$(RESTING=1 "$ROOT/verify.sh" 2>&1)"; rc=$?
assert_eq "$rc" 1 "a resting runner-up place fails the run, whatever waits on its pool"
assert_contains "$out" "FAIL  runner-up has a place on builder and it is not resting" "and names the line"
out="$(PLACE_MACHINE=other "$ROOT/verify.sh" 2>&1)"; rc=$?
assert_eq "$rc" 1 "no runner-up place for this computer fails the run, a waiting line named for it does not pass it"

out="$(LID=0 "$ROOT/verify.sh" 2>&1)"; rc=$?
assert_eq "$rc" 1 "a Mac that sleeps when the lid closes fails the run"
assert_contains "$out" "FAIL  awake with the lid closed" "and names the line"

# claude found only by its full path is what stopped Infinitary from finding it.
mv "$HOME/.zshenv" "$T/zshenv"
out="$("$ROOT/verify.sh" 2>&1)"; rc=$?
assert_eq "$rc" 1 "claude that SSH commands cannot run by name fails the run"
assert_contains "$out" "FAIL  claude runs by name in a non-interactive SSH command" "and names the line"
mv "$T/zshenv" "$HOME/.zshenv"
mv "$HOME/.local" "$T/local"
assert_contains "$("$ROOT/verify.sh" 2>&1)" "FAIL  Claude Code is installed at ~/.local/bin/claude" "no Claude Code fails its line"
mv "$T/local" "$HOME/.local"

# The switched-user check must fail when the coordinator is not running.
stub pgrep 'exit 1'
out="$(CONSOLE=guest "$ROOT/verify.sh" 2>&1)"
assert_contains "$out" "FAIL  work still runs here" "with another user at the screen, a stopped runner-up fails the work-still-runs line"
stub pgrep 'echo 123'

# After a restart the login agent must go: its file is deleted before the agent
# is stopped, because stopping the agent ends the script.
PLIST="$HOME/Library/LaunchAgents/com.headless-runner.verify.plist"
mv "$T/bin/launchctl" "$T/bin/launchctl-launchd"
stub launchctl "[ \"\$1 \$2\" = 'bootout gui/501/com.headless-runner.verify' ] && { [ -e '$PLIST' ] && echo file-still-there > '$T/order' || echo file-gone > '$T/order'; }
exec \"\$(dirname \"\$0\")/launchctl-launchd\" \"\$@\""
: > "$PLIST"
"$ROOT/verify.sh" --after-restart > /dev/null 2>&1
assert_eq "$(cat "$T/order" 2> /dev/null)" "file-gone" "the login agent's file is deleted before the agent is stopped"
out="$(GH_KEY=none "$ROOT/verify.sh" 2>&1)"; rc=$?
assert_eq "$rc" 1 "a GitHub that refuses this Mac's SSH key fails the run"
assert_contains "$out" "FAIL  GitHub accepts this Mac's SSH key" "and names the line"
assert_contains "$("$ROOT/verify.sh" 2>&1)" "ok    GitHub accepts this Mac's SSH key" "a healthy Mac's SSH greeting passes its line"
# The sign-in check asks gh-axi, never gh auth status (a gh that fails on auth must not matter).
# Intent (the captain's error): verify.sh run over SSH, where gh cannot read its
# keychain, failed this line although runner-up's session is signed in.
stub gh '[ "$1" = auth ] && exit 1; exit 0'
out="$("$ROOT/verify.sh" 2>&1)"; rc=$?
assert_eq "$rc" 0 "run where gh cannot read its keychain (as over SSH), a signed-in Mac passes"
assert_contains "$out" "ok    GitHub sign-in works" "the sign-in line answers for the signed-in session"
touch "$T/signed-out"
out="$("$ROOT/verify.sh" 2>&1)"; rc=$?
assert_eq "$rc" 1 "a Mac with no GitHub sign-in fails the run"
assert_contains "$out" "FAIL  GitHub sign-in works" "and names the line"
rm "$T/signed-out"
done_tests
