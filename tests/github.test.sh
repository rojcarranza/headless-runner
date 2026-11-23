#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2034 # pass/fail helpers never fail; stand-ins are single-quoted on purpose
# Intent (the captain): setup adds GitHub's host keys to known_hosts and gets
# the computer's SSH key onto their GitHub account, with their yes, so a fresh
# worker can clone projects with SSH addresses.
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
export T HOME="$T/home" HR_NAME=builder HR_STATE="$T/state" LOG="$T/log" HR_TTY="$T/tty"
mkdir -p "$HOME/.ssh" "$T/bin" "$T/hk"
stub() { printf '#!/bin/sh\n%s\n' "$2" > "$T/bin/$1"; chmod +x "$T/bin/$1"; }
stub uname '[ "$1" = -m ] && echo arm64 || echo Darwin'
export PATH="$T/bin:$PATH"
make_key "$HOME/.ssh/id_ed25519"
# Host keys in the shape of GitHub's /meta answer: real keys, one per type.
make_key "$T/hk/a"; make_key "$T/hk/b"
k1="$(awk '{print $1, $2}' "$T/hk/a.pub")"; k2="$(awk '{print $1, $2}' "$T/hk/b.pub")"
jq -n --arg a "$k1" --arg b "$k2" '{ssh_keys: [$a, $b]}' > "$T/meta.json"
export HR_GITHUB_META="$T/meta.json"
stub curl '[ -z "${CURL_FAIL-}" ] || exit 6; cat "${2:?}"'
# gh: signed in; the account's keys are in $T/account; add and refresh are logged.
stub gh 'echo "gh $*" >> "$LOG"
case "$1 $2" in
  "auth status") exit 0 ;;
  "api --paginate") cat "$T/account" ;;
  "ssh-key add") awk "{print \$1, \$2}" "$3" >> "$T/account" ;;
esac'
# ssh: GitHub greets only when the account holds the key and known_hosts has a host key.
stub ssh 'echo "ssh $*" >> "$LOG"
grep -qxF "$(awk "{print \$1, \$2}" "$HOME/.ssh/id_ed25519.pub")" "$T/account" && grep -q "^github.com " "$HOME/.ssh/known_hosts" \
  && { echo "Hi octo! You'"'"'ve successfully authenticated, but GitHub does not provide shell access."; exit 1; }
echo "git@github.com: Permission denied (publickey)." >&2; exit 255'
: > "$LOG"
set +e
stage() { bash "$ROOT/stages/github.sh" > "$T/out" 2>&1; }
KH="$HOME/.ssh/known_hosts"

# --- host keys
printf 'example.org ssh-ed25519 AAAAother' > "$KH"; : > "$T/account"; : > "$T/tty"
CURL_FAIL=1 stage && fail "GitHub's keys unreachable stops the stage" || pass "GitHub's keys unreachable stops the stage"
assert_eq "$(cat "$KH")" "example.org ssh-ed25519 AAAAother" "and known_hosts is untouched"
echo n > "$T/tty"; stage
assert_eq "$(head -n 1 "$KH")" "example.org ssh-ed25519 AAAAother" "another host's line stays, even one without a final newline"
assert_eq "$(grep -c '^github.com ' "$KH")" 2 "both of GitHub's host keys are added"
assert_eq "$(grep '^github.com ' "$KH" | sed 's/^github.com //' | sort)" "$(printf '%s\n%s\n' "$k1" "$k2" | sort)" "they are exactly the keys GitHub lists"
assert_eq "$(ssh-keygen -F github.com -f "$KH" | grep -c '^# Host')" 2 "ssh-keygen finds them"
printf '{"ssh_keys":[]}' > "$T/empty.json"; HR_GITHUB_META="$T/empty.json" stage && fail "an answer without keys stops the stage" || pass "an answer without keys stops the stage"

# --- the yes
: > "$LOG"; echo n > "$T/tty"; stage
assert_eq "$(grep -c 'ssh-key add' "$LOG")" 0 "answering no adds nothing"
assert_contains "$(cat "$T/out")" "not adding the key" "and says what that means"
: > "$LOG"; rm -f "$HR_TTY"; stage && fail "no terminal means no yes" || pass "no terminal means no yes"
assert_eq "$(grep -c 'ssh-key add' "$LOG")" 0 "and nothing is added silently"
: > "$LOG"; echo y > "$T/tty"; stage; rc=$?
assert_eq "$rc" 0 "yes: the stage passes"
assert_eq "$(grep -c '^gh ssh-key add' "$LOG")" 1 "the key is added once"
assert_contains "$(cat "$LOG")" "gh ssh-key add $HOME/.ssh/id_ed25519.pub --title builder --type authentication" "with the Mac's public key and the computer's name as title"
assert_contains "$(cat "$LOG")" "gh auth refresh --hostname github.com --scopes admin:public_key" "after asking GitHub for permission to add keys"
assert_contains "$(cat "$T/out")" "SSH to GitHub works" "and GitHub's greeting is checked"
assert_eq "$(grep -c 'github.com ' "$KH")" 2 "a rerun adds no host key twice"
: > "$LOG"; rm -f "$HR_TTY"; stage; rc=$?
assert_eq "$rc" 0 "key already on the account: no question, the stage passes"
assert_eq "$(grep -c 'ssh-key add\|auth refresh' "$LOG")" 0 "and nothing is added again"
assert_contains "$(grep '^ssh ' "$LOG" | head -n 1)" "StrictHostKeyChecking=yes" "the check trusts only known_hosts"

# --- GitHub refusing the key
: > "$T/account"; echo y > "$T/tty"; stub gh 'case "$1 $2" in "auth status") exit 0 ;; "api --paginate") cat "$T/account" ;; esac'
stage && fail "a key GitHub does not accept stops the stage" || pass "a key GitHub does not accept stops the stage"
assert_contains "$(cat "$T/out")" "Permission denied" "and shows what GitHub said"
done_tests
