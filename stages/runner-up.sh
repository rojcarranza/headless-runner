#!/usr/bin/env bash
# Stage runner-up: GitHub Actions jobs for this repository run on this Mac.
# runner-up runs as a login agent of this user, in the signed-in session, so
# it keeps running while someone else uses the Mac through Switch User.
# shellcheck source=lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=lib/clone.sh
. "$HR_ROOT/lib/clone.sh"
require_apple_silicon_mac
command -v runner-up > /dev/null || die "runner-up is missing; run bash setup.sh machine first"

command -v gh-axi > /dev/null || die "gh-axi is missing; run bash setup.sh machine first"
# gh-axi has no sign-in commands: gh auth login and gh auth setup-git are the
# only plain gh calls here, because gh-axi relies on gh's sign-in.
if ! gh-axi api /user > /dev/null 2>&1; then
  say "Sign in to GitHub: gh opens a page and shows a one-time code to type there."
  gh auth login --hostname github.com --git-protocol https --web --scopes repo,workflow
fi

# This repository becomes a normal clone in the standard place, so later
# updates are a git pull.
gh auth setup-git
HOME_CLONE="$(clone_repo rojcarranza/headless-runner)"
# What this run made (public settings and keys) goes along, so the clone is whole.
if [ "$HOME_CLONE" != "$HR_ROOT" ]; then
  mkdir -p "$HOME_CLONE/machines" "$HOME_CLONE/keys"
  cp -n "$HR_ROOT"/machines/*.json "$HOME_CLONE/machines/" 2> /dev/null || true
  cp -n "$HR_ROOT"/keys/*.pub "$HOME_CLONE/keys/" 2> /dev/null || true
fi
say "this repository is also at $HOME_CLONE; use it from now on"

CFG="$HOME/Library/Application Support/runner-up/config.json"
[ -f "$CFG" ] || runner-up init --repo rojcarranza/headless-runner --pool "$HR_NAME"
# A rerun after init but before machine add (or a failed add) finishes the job:
# the machine is looked up by name, not assumed from the file.
if ! jq -e --arg n "$HR_NAME" '.machines[]? | select(.name == $n)' "$CFG" > /dev/null 2>&1; then
  # No --ssh: the machine is this one. A host place runs one job at a time,
  # as this user, in this user's session.
  runner-up machine add "$HR_NAME" --provider host --pool "$HR_NAME"
fi
runner-up check-config

PLIST="$HOME/Library/LaunchAgents/com.github.runner-up.plist"
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
sed -e "s|@RUNNER_UP@|$(command -v runner-up)|g" -e "s|@HOME@|$HOME|g" \
  "$HR_ROOT/launchd/com.github.runner-up.plist.tmpl" > "$PLIST"
launchctl bootout "gui/$(id -u)" "$PLIST" 2> /dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
sleep 5
runner-up status
