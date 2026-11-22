#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2034 # pass/fail helpers never fail; stand-ins are single-quoted on purpose
# Intent (the captain): the new user's name becomes the computer's name, the
# Mac reaches itself by key, and no password is written to any file.
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
export HOME="$T/home" HR_NAME=builder HR_PASSWORD="sentinel-password-9f3"
mkdir -p "$HOME/.ssh" "$T/repo/machines" "$T/repo/keys"
make_key "$T/own"; make_key "$T/pro"
cp "$T/pro.pub" "$T/repo/keys/first-mate.pub"
. "$ROOT/lib/common.sh"
. "$ROOT/lib/config.sh"
HR_ROOT="$T/repo" KEY_FILE="$T/own"
cp -r "$ROOT/machine" "$T/repo/machine"

ensure_machine_file > /dev/null
f="$T/repo/machines/builder.json"
assert_eq "$(jq -r .user "$f")" builder "machine file names the user"
assert_eq "$(jq -r .hostName "$f")" builder "host name is the user's short name"
assert_eq "$(jq -r '.sshKeys | length' "$f")" 2 "own key and the first mate's key are allowed in"
assert_eq "$(jq -r .keyOnlySsh "$f")" true "SSH takes keys only"
assert_eq "$(jq -r .autoLogin "$f")" true "auto sign-in is on"
assert_eq "$(jq -r .tailscale.enable "$f")" true "Tailscale is on"
before="$(cat "$f")"; ensure_machine_file > /dev/null
assert_eq "$(cat "$f")" "$before" "an existing machine file is kept"

assemble_config "$T/cfg"
for n in flake.nix machine.nix flake.lock settings.json headless.env; do [ -f "$T/cfg/$n" ] && pass "config has $n" || fail "config lacks $n"; done
assert_contains "$(cat "$T/cfg/headless.env")" "ADDRESS=127.0.0.1" "the Mac reaches itself"
assert_eq "$(grep -rl "$HR_PASSWORD" "$T/cfg" "$T/repo" 2> /dev/null | wc -l | tr -d ' ')" 0 "no file holds the password"
done_tests
