#!/usr/bin/env bash
# shellcheck disable=SC2015 # pass/fail helpers never fail
# Intent (HER-11, the captain): the first mate's key must be another
# computer's. This Mac's own key lets only this Mac in, which sent the setup to
# Tailscale SSH and its 12-hour browser approval.
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
export HOME="$T/home"
mkdir -p "$HOME/.ssh" "$T/keys"
make_key "$HOME/.ssh/id_ed25519"; make_key "$T/mate"
. "$ROOT/lib/common.sh"

is_own_key "$(cat "$HOME/.ssh/id_ed25519.pub")" && pass "this Mac's own key is recognised" || fail "own key not recognised"
# The same key with another comment is still the own key.
is_own_key "$(cut -d' ' -f1-2 "$HOME/.ssh/id_ed25519.pub") pasted-elsewhere" && pass "a different comment does not hide the own key" || fail "comment hid the own key"
is_own_key "$(cat "$T/mate.pub")" && fail "another computer's key taken for the own key" || pass "another computer's key is accepted"

cp "$HOME/.ssh/id_ed25519.pub" "$T/keys/first-mate.pub"
has_other_key "$T/keys" && fail "keys/ with only the own key passes" || pass "keys/ holding only the own key is refused"
cp "$T/mate.pub" "$T/keys/mac.pub"
has_other_key "$T/keys" && pass "keys/ with another computer's key passes" || fail "other key not found"
rm -rf "$T/keys"; mkdir "$T/keys"
has_other_key "$T/keys" && fail "empty keys/ passes" || pass "empty keys/ is refused"
done_tests
