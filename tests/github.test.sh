#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2034 # pass/fail helpers never fail; stand-ins are single-quoted on purpose
# Intent (the captain): setup adds GitHub's host keys to known_hosts and gets
# the computer's SSH key onto their GitHub account (the person adds it on
# GitHub's page; the Mac gets no permission to manage keys), so a fresh
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
# gh: signed in with repo and workflow only (as runner-up leaves it); the account's keys are in $T/account. It must never be needed.
stub gh 'echo "gh $*" >> "$LOG"
case "$1 $2" in
  "auth status") exit 0 ;;
  "api --paginate") echo "HTTP 404: Not Found (needs read:public_key)" >&2; exit 1 ;;
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

# --- the key is added on GitHub's page, by the person
# open: the person adds the key on GitHub when the page opens (ADD=0: they do not).
stub open 'echo "open $*" >> "$LOG"; [ "${ADD-1}" = 0 ] || awk "{print \$1, \$2}" "$HOME/.ssh/id_ed25519.pub" >> "$T/account"'
stub pbcopy 'cat > "$T/clipboard"'
: > "$LOG"; : > "$T/account"; echo > "$T/tty"; stage; rc=$?
assert_eq "$rc" 0 "a Mac GitHub does not know: the person adds the key on GitHub and the stage passes"
assert_contains "$(cat "$LOG")" "open https://github.com/settings/ssh/new" "GitHub's new-key page is opened"
assert_eq "$(cat "$T/clipboard")" "$(cat "$HOME/.ssh/id_ed25519.pub")" "with the Mac's public key copied"
assert_contains "$(cat "$T/out")" "SSH to GitHub works" "and GitHub's greeting is checked"
assert_not_contains "$(cat "$LOG")" "gh " "gh is never used: the Mac gets no permission to manage keys"
assert_eq "$(grep -c 'github.com ' "$KH")" 2 "a rerun adds no host key twice"
: > "$LOG"; rm -f "$HR_TTY"; stage; rc=$?
assert_eq "$rc" 0 "key already known to GitHub: no question, the stage passes"
assert_eq "$(grep -c '^open \|^gh ' "$LOG")" 0 "and nothing is opened or added"
assert_contains "$(grep '^ssh ' "$LOG" | head -n 1)" "StrictHostKeyChecking=yes" "the check trusts only known_hosts"
# gh is not even needed: a broken sign-in changes nothing
stub gh 'echo "gh $*" >> "$LOG"; exit 1'
: > "$LOG"; stage; rc=$?
assert_eq "$rc" 0 "an invalid gh sign-in does not stop a Mac whose SSH already works"
assert_eq "$(grep -c '^gh ' "$LOG")" 0 "and gh is not called"

# --- the person does not add it, or there is no one to ask
: > "$T/account"; echo > "$T/tty"
ADD=0 stage && fail "pressing Return without adding the key stops the stage" || pass "pressing Return without adding the key stops the stage"
assert_contains "$(cat "$T/out")" "Permission denied" "and shows what GitHub said"
rm -f "$HR_TTY"; stage && fail "no terminal stops the stage" || pass "no terminal stops the stage"
assert_contains "$(cat "$T/out")" "no terminal to wait on" "and says why"
done_tests
