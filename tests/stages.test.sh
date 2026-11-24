#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2034 # pass/fail helpers never fail; stand-ins are single-quoted on purpose
# Intent (the review of PR #2): a clean Mac must get through the projects stage
# (the gate guard needs no-mistakes init first), and a rerun of the runner-up
# stage after a failed "machine add" must finish adding the machine. Intent (a
# filed defect: a rerun of the projects stage tried an old clone's scripts): a
# rerun brings each clone on a clean main up to date with GitHub first. Intent
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
# Real repositories stand in for GitHub, through git's own URL rewriting.
# PraiseLineup's holds the scripts the stage runs, each logging its version.
export GIT_CONFIG_GLOBAL="$T/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" "url.file://$T/remote/.insteadOf" "https://github.com/"
# publish REPO VERSION: GitHub's main of rojcarranza/REPO moves on to VERSION.
publish() {
  local w="$T/work/$1" s
  [ -d "$w" ] || git init -q -b main "$w"
  if [ "$1" = praiselineup ]; then
    mkdir -p "$w/scripts" "$w/ios/Tools"
    for s in scripts/install-gate-guard.sh ios/Tools/make_gate_simulator.sh ios/Tools/gate_unit_tests.sh ios/Tools/nightly_ui_tests.sh; do
      printf '#!/bin/sh\necho "%s: %s $*" >> "$LOG"\n' "$2" "$s" > "$w/$s"
    done
    echo 'grep -q "^no-mistakes init" "$LOG" || { echo "No no-mistakes remote here." >&2; exit 1; }' >> "$w/scripts/install-gate-guard.sh"
    echo '[ -n "${NO_RESULT-}" ] || { mkdir -p "$PL_NIGHTLY_HOME/latest"; echo "passed 0123abc" > "$PL_NIGHTLY_HOME/latest/result"; }' >> "$w/ios/Tools/nightly_ui_tests.sh"
  else
    echo "$2" > "$w/VERSION"
  fi
  git -C "$w" add -A
  git -C "$w" -c user.name=t -c user.email=t@example.com commit -q -m "$2"
  [ -d "$T/remote/rojcarranza/$1.git" ] || git init -q --bare -b main "$T/remote/rojcarranza/$1.git"
  git -C "$w" push -q "$T/remote/rojcarranza/$1.git" main
}
for r in praiselineup praiselineup-backend dotfiles; do publish "$r" v1; done
: > "$LOG"
stub no-mistakes 'echo "no-mistakes $*" >> "$LOG"'
bash "$ROOT/projects/praiselineup.sh" > "$T/out" 2>&1; rc=$?
assert_eq "$rc" 0 "a fresh PraiseLineup clone gets through the projects script"
assert_eq "$(grep -n 'no-mistakes init\|install-gate-guard' "$LOG" | cut -d: -f1 | tr '\n' ' ')" "1 2 " "init runs before the gate guard"
assert_contains "$(cat "$LOG")" "v1: ios/Tools/nightly_ui_tests.sh --no-post" "the trial nightly is the real one, with nothing posted"
assert_contains "$(cat "$T/out")" "trial nightly passed" "and its latest/result is read"
NO_RESULT=1 bash "$ROOT/projects/praiselineup.sh" > "$T/out" 2>&1 && fail "a nightly that wrote no result fails the stage" || pass "a nightly that wrote no result fails the stage"

# --- projects, run again after GitHub's main moved on
for r in praiselineup praiselineup-backend dotfiles; do publish "$r" v2; done
: > "$LOG"
bash "$ROOT/stages/projects.sh" > "$T/out" 2>&1; rc=$?
assert_eq "$rc" 0 "a rerun of the projects stage passes"
assert_contains "$(cat "$LOG")" "v2: ios/Tools/gate_unit_tests.sh" "the rerun's gate unit tests are GitHub's newest"
assert_contains "$(cat "$LOG")" "v2: ios/Tools/nightly_ui_tests.sh --no-post" "and so is its trial nightly"
assert_not_contains "$(cat "$LOG")" "v1: " "no script of the old clone runs"
for r in praiselineup praiselineup-backend dotfiles; do
  assert_eq "$(git -C "$DEV_HOME/rojcarranza/$r" rev-parse HEAD)" "$(git -C "$T/work/$r" rev-parse HEAD)" "the $r clone is at GitHub's main"
done

# --- runner-up: init done but machine add failed; a rerun adds the machine
mkdir -p "$DEV_HOME/rojcarranza/headless-runner/.git" "$DEV_HOME/rojcarranza/headless-runner/machine"
CFG="$HOME/Library/Application Support/runner-up/config.json"
stub gh 'echo "gh $*" >> "$LOG"'; stub gh-axi 'echo "gh-axi $*" >> "$LOG"; [ -z "${SIGNED_OUT-}" ]'; stub launchctl 'exit 0'; stub sleep 'exit 0'
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
# Intent (the captain): sign-in checks go through gh-axi; gh auth login and setup-git are the named exception.
: > "$LOG"; bash "$ROOT/stages/runner-up.sh" > /dev/null 2>&1
assert_contains "$(cat "$LOG")" "gh-axi api /user" "the stage checks the GitHub sign-in with gh-axi"
assert_not_contains "$(cat "$LOG")" "gh auth status" "and never with gh auth status"
assert_not_contains "$(cat "$LOG")" "gh auth login" "a signed-in Mac is not asked to sign in again"
assert_contains "$(cat "$LOG")" "gh auth setup-git" "git's credential helper is still set up through gh"
: > "$LOG"; SIGNED_OUT=1 bash "$ROOT/stages/runner-up.sh" > /dev/null 2>&1
assert_contains "$(cat "$LOG")" "gh auth login --hostname github.com" "a signed-out Mac is sent through gh auth login"
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
