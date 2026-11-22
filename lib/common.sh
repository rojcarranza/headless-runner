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
