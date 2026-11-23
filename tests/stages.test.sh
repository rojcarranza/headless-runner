#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2034 # pass/fail helpers never fail; stand-ins are single-quoted on purpose
# Intent (the review of PR #2): a clean Mac must get through the projects stage
# (the gate guard needs no-mistakes init first), and a rerun of the runner-up
# stage after a failed "machine add" must finish adding the machine. Intent
# (the captain): the claude-code stage installs Claude Code, and claude then
# answers by name in a non-interactive SSH command.
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
  status) echo "place host-1 on $HR_NAME (host, 4 cores, 8192 MB) free" ;;
esac'
FAIL_ADD=1 bash "$ROOT/stages/runner-up.sh" > /dev/null 2>&1 && fail "a failed machine add stops the stage" || pass "a failed machine add stops the stage"
assert_eq "$(jq '.machines | length' "$CFG")" 0 "the setup file exists with no machine"
bash "$ROOT/stages/runner-up.sh" > /dev/null 2>&1
assert_eq "$(jq -r '.machines[0].name' "$CFG")" builder "a rerun adds the machine the file lacks"
bash "$ROOT/stages/runner-up.sh" > /dev/null 2>&1
assert_eq "$(jq '.machines | length' "$CFG")" 1 "and a second rerun adds nothing twice"
# --- the password stays out of child processes, even when it arrives exported
out="$(HR_PASSWORD=sentinel-9f3 bash -c '. "$1/lib/common.sh"; need_password; bash -c "echo \"[\${HR_PASSWORD-}]\""' _ "$ROOT")"
assert_eq "$out" "[]" "need_password stops the password reaching child processes"

# --- Rancher Desktop's defaults profile: parses, names the engine, never overwritten
. "$ROOT/lib/common.sh"; . "$ROOT/lib/config.sh"
ensure_rancher_profile > /dev/null
P="$HOME/Library/Preferences/io.rancherdesktop.profile.defaults.plist"
assert_eq "$(python3 -I -c 'import plistlib,sys; d=plistlib.load(open(sys.argv[1],"rb")); print(d["version"], d["containerEngine"]["name"], d["kubernetes"]["enabled"])' "$P")" "10 moby False" "the profile parses and sets version, engine and no Kubernetes"
echo marker > "$P"; ensure_rancher_profile > /dev/null
assert_eq "$(cat "$P")" marker "an existing profile is left alone"
# --- Rancher Desktop is opened once, in view, and Docker is awaited
stub sleep 'exit 0'
stub open 'echo "open $*" >> "$LOG"; mkdir -p "$HOME/.rd/bin"; printf "#!/bin/sh\\nexit 0\\n" > "$HOME/.rd/bin/docker"; chmod +x "$HOME/.rd/bin/docker"'
: > "$LOG"; rm -rf "$HOME/.rd"
start_rancher_desktop > /dev/null 2>&1
assert_eq "$(cat "$LOG")" "open -a Rancher Desktop" "a clean Mac: Rancher Desktop is opened once and Docker then answers"
: > "$LOG"; start_rancher_desktop > /dev/null 2>&1
assert_eq "$(cat "$LOG")" "" "when Docker already answers, nothing is opened"
stub open 'exit 0'; rm -rf "$HOME/.rd"
(start_rancher_desktop) > /dev/null 2>&1 && fail "Docker never answering stops the stage" || pass "Docker never answering stops the stage"

# --- claude-code (the captain): a Mac set up by these scripts gets Claude Code,
# and claude answers by name in a non-interactive SSH command
V=2.1.330 # the version Anthropic's installer installed when this test was written
{ echo 'echo "Setting up Claude Code..."'; declare -f install_claude_native
  printf 'install_claude_native "$HOME" %s\necho "Installation complete!"\n' "$V"; } > "$T/install.sh"
# An installer that put claude where Infinitary does not look.
printf 'mkdir -p "$HOME/.claude/local"; printf "#!/bin/sh\\necho %s\\n" > "$HOME/.claude/local/claude"; chmod +x "$HOME/.claude/local/claude"\n' "$V" > "$T/install-elsewhere.sh"
stub curl 'echo "curl $*" >> "$LOG"
[ -z "${CURL_FAIL-}" ] || { echo "curl: (6) Could not resolve host: claude.ai" >&2; exit 6; }
[ "$*" = "-fsSL https://claude.ai/install.sh" ] && cat "${INSTALLER:-'"$T"'/install.sh}"'
stand_in_ssh "$T/bin"
HR_ZSH="$(command -v zsh)"; export HR_ZSH
set +e # common.sh, sourced above, turned set -e on; every result here is asserted
cc() { bash "$ROOT/stages/claude-code.sh" > "$T/out" 2>&1; }
line='export PATH="$HOME/.local/bin:$PATH"'

: > "$LOG"; rm -rf "$HOME/.local" "$HOME/.zshenv"
cc; rc=$?
assert_eq "$rc" 0 "a Mac without Claude Code gets through the claude-code stage"
assert_eq "$(cat "$LOG")" "curl -fsSL https://claude.ai/install.sh" "Anthropic's native installer is fetched once"
assert_eq "$("$HOME/.local/bin/claude" --version)" "$V (Claude Code)" "claude is at ~/.local/bin/claude, where Infinitary looks"
assert_eq "$(ssh builder@127.0.0.1 claude --version 2>&1)" "$V (Claude Code)" "a non-interactive ssh claude --version answers by name"
assert_contains "$(cat "$T/out")" "Claude Code $V runs by name in SSH commands" "the stage says which version it checked"

cp "$HOME/.zshenv" "$T/zshenv"; : > "$LOG"
cc; rc=$?
assert_eq "$rc" 0 "a second run passes"
assert_eq "$(cat "$LOG")" "" "and installs nothing again"
cmp -s "$HOME/.zshenv" "$T/zshenv" && pass "and leaves ~/.zshenv as it was" || fail "a second run changed ~/.zshenv"

printf 'export EDITOR=nvim' > "$HOME/.zshenv"
cc
assert_eq "$(head -n 1 "$HOME/.zshenv")" "export EDITOR=nvim" "a ~/.zshenv's own lines stay, the last one whole"
assert_eq "$(grep -cxF "$line" "$HOME/.zshenv")" 1 "and the PATH line is added once"

printf '%s\n' "$line" > "$HOME/.zshenv"; cp "$HOME/.zshenv" "$T/zshenv"
cc
cmp -s "$HOME/.zshenv" "$T/zshenv" && pass "a ~/.zshenv that has the installer's line already (set by hand) is left alone" || fail "a hand-set ~/.zshenv was changed"

printf 'export PATH=/usr/bin:/bin\n' >> "$HOME/.zshenv"
cc && fail "a ~/.zshenv that drops ~/.local/bin again fails the stage" || pass "a ~/.zshenv that drops ~/.local/bin again fails the stage"
assert_contains "$(cat "$T/out")" "claude does not run by name in a non-interactive shell" "and says so"

rm -rf "$HOME/.local" "$HOME/.zshenv"
CURL_FAIL=1 cc && fail "an installer that cannot be fetched stops the stage" || pass "an installer that cannot be fetched stops the stage"
assert_contains "$(cat "$T/out")" "Claude Code did not install" "and says so"
INSTALLER="$T/install-elsewhere.sh" cc && fail "claude installed outside ~/.local/bin stops the stage" || pass "claude installed outside ~/.local/bin stops the stage"
assert_contains "$(cat "$T/out")" "where Infinitary looks for it" "and says why"
done_tests
