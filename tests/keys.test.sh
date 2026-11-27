#!/usr/bin/env bash
# shellcheck disable=SC2015 # pass/fail helpers never fail
# Intent (the captain): the first mate's key must be another computer's; this
# Mac's own key lets only this Mac in.
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
has_other_key "$T"/keys/*.pub && fail "keys/ with only the own key passes" || pass "keys/ holding only the own key is refused"
cp "$T/mate.pub" "$T/keys/mac.pub"
has_other_key "$T"/keys/*.pub && pass "keys/ with another computer's key passes" || fail "other key not found"
rm -rf "$T/keys"; mkdir "$T/keys"
has_other_key "$T"/keys/*.pub && fail "empty keys/ passes" || pass "empty keys/ is refused"
# nix-darwin's file lists the own key twice, as the Mac's file does today.
printf '# keys\n\n%s\n%s\n' "$(cat "$HOME/.ssh/id_ed25519.pub")" "$(cat "$HOME/.ssh/id_ed25519.pub")" > "$T/served"
has_other_key "$T/served" "$T/absent" && fail "a file of only the own key (twice, with comments) passes" || pass "a file of only the own key, listed twice, is refused; a missing file is skipped"
cat "$T/mate.pub" >> "$T/served"
has_other_key "$T/absent" "$T/served" && pass "another computer's key on a later line is found" || fail "later line not found"
done_tests
