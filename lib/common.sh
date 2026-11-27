# shellcheck shell=bash
# shellcheck disable=SC2034 # the scripts that source this use its variables
# common.sh - shared by setup.sh, the stages and verify.sh; sourced, not run.
# Holds no secret: the account password only ever lives in HR_PASSWORD, in
# the memory of one setup.sh run.
set -euo pipefail

HR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=pins.env
. "$HR_ROOT/pins.env"

# The computer's name is the short name of the user running the scripts.
# Tools from the machine's Nix system and Homebrew, once the machine stage has run.
export PATH="/run/current-system/sw/bin:/opt/homebrew/bin:$PATH"

HR_NAME="${HR_NAME:-$(id -un)}"
# Projects live in one place on every computer: ~/Dev/github.com/<owner>/<repo>.
DEV_HOME="${DEV_HOME:-$HOME/Dev/github.com}"
HR_STATE="${HR_STATE:-$HOME/.headless-runner}"
HR_CONFIG="$HR_STATE/config/$HR_NAME"

say() { printf 'headless-runner: %s\n' "$*"; }
warn() { printf 'headless-runner: warning: %s\n' "$*" >&2; }
die() { printf 'headless-runner: %s\n' "$*" >&2; exit 1; }

# need_password: the account password is asked once by setup.sh. A stage run
# on its own asks here, hidden, and keeps it only in memory. It is a plain
# shell variable, never exported: setup.sh hands it only to the stages that use it.
need_password() {
  # Never let it reach child processes: only with_password and sudo's input do.
  export -n HR_PASSWORD
  [ -z "${HR_PASSWORD-}" ] || return 0
  [ -t 0 ] || die "no password: run bash setup.sh from Terminal so it can ask for it"
  printf 'Password for %s (kept in memory for this run only): ' "$HR_NAME" >&2
  IFS= read -rs HR_PASSWORD
  printf '\n' >&2
  [ -n "$HR_PASSWORD" ] || die "empty password"
}

# as_root COMMAND...: run COMMAND with sudo, the password piped to sudo -S
# on standard input, never on a command line.
as_root() {
  need_password
  printf '%s\n' "$HR_PASSWORD" | sudo -S -p '' "$@"
}

# open_page URL: open a sign-in page for the person at the screen.
open_page() {
  say "opening $1"
  if command -v open > /dev/null 2>&1; then open "$1" || true; else say "open it in a browser: $1"; fi
}

# A stage marks itself done once it has checked its own result.
stage_done() { [ -f "$HR_STATE/done/$1" ]; }
stage_mark() { mkdir -p "$HR_STATE/done"; : > "$HR_STATE/done/$1"; }
stage_clear() { rm -f "$HR_STATE/done/$1"; }

# version_ge A B: true when version A is B or later.
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n 1)" = "$2" ]; }

require_apple_silicon_mac() {
  [ "$(uname -s)" = Darwin ] || die "this runs on a Mac; this computer is $(uname -s)"
  [ "$(uname -m)" = arm64 ] || die "this needs an Apple silicon Mac; this one is $(uname -m)"
}

# github_greets [KEY]: GitHub greets this Mac's SSH key by name, checked
# against known_hosts. ssh -T exits 1 even when GitHub greets you, so its words
# are read, not its status. What it said stays in GITHUB_SAID.
github_greets() {
  GITHUB_SAID="$(ssh -T -o StrictHostKeyChecking=yes -o BatchMode=yes -o IdentitiesOnly=yes \
    -o ConnectTimeout=15 -i "${1:-$HOME/.ssh/id_ed25519}" git@github.com 2>&1 || true)"
  grep -q 'successfully authenticated' <<< "$GITHUB_SAID"
}

# github_signed_in: gh-axi api /user answers in this user's signed-in session,
# where runner-up runs as a login agent and uses gh's sign-in. gh keeps its
# token in the login keychain, which macOS does not open to an SSH session:
# there gh-axi answers "Requires authentication (HTTP 401)" while runner-up is
# signed in. So the call runs as a one-shot login agent in that session, with
# this shell's PATH (launchd's own lacks the Nix profile where gh-axi lives),
# and hands back its exit status in a file. No signed-in session, no answer:
# runner-up cannot run then either.
github_signed_in() {
  local dir label rc="" deadline
  dir="$(mktemp -d)" || return 1
  label="com.headless-runner.github-check.$$"
  {
    printf 'export PATH=%q\n' "$PATH"
    printf 'gh-axi api /user > /dev/null 2>&1\n'
    # Written whole, then renamed, so the waiting shell never reads half a status.
    printf 'echo $? > %q && mv %q %q\n' "$dir/status.new" "$dir/status.new" "$dir/status"
  } > "$dir/check.sh"
  cat > "$dir/check.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$(xml_text "$dir/check.sh")</string>
  </array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
PLIST
  if launchctl bootstrap "gui/$(id -u)" "$dir/check.plist" 2> /dev/null; then
    # launchd starts the job after bootstrap returns; a slow network gets a minute.
    deadline=$((SECONDS + 60))
    while [ ! -f "$dir/status" ] && [ "$SECONDS" -lt "$deadline" ]; do sleep 0.2; done
    launchctl bootout "gui/$(id -u)/$label" 2> /dev/null
    rc="$(cat "$dir/status" 2> /dev/null)"
  fi
  rm -rf "$dir"
  [ "$rc" = 0 ]
}

# xml_text TEXT: TEXT with &, < and > escaped, for a plist <string>. sed, not
# ${var//}: bash 5.2 reads & in a substitution's replacement as the match.
xml_text() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# key_id LINE: a public key's type and key material, the part that identifies
# it; the comment at the end of an authorized_keys line is free text.
key_id() { printf '%s\n' "$1" | awk '{ print $1, $2 }'; }

# is_own_key LINE: true when LINE is this user's own public key. The first
# mate's key must be another computer's: this Mac's own key only lets the Mac
# into itself, so a key-only sshd would turn every other computer away.
is_own_key() {
  local own="${KEY_FILE:-$HOME/.ssh/id_ed25519}.pub"
  [ -f "$own" ] || return 1
  [ "$(key_id "$1")" = "$(key_id "$(head -n 1 "$own")")" ]
}

# has_other_key DIR: true when a *.pub file in DIR holds a key that is not this
# user's own.
has_other_key() {
  local k
  for k in "$1"/*.pub; do
    [ -f "$k" ] || continue
    is_own_key "$(head -n 1 "$k")" || return 0
  done
  return 1
}
