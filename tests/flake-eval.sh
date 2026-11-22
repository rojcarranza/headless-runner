#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2034 # pass/fail helpers never fail; stand-ins are single-quoted on purpose
# Intent: the machine flake must evaluate for an Apple silicon Mac, with a
# config folder built the way setup.sh builds it (the person's own settings).
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
dir="$T/cfg"
export HR_NAME=buildbox
. "$ROOT/lib/common.sh"
. "$ROOT/lib/config.sh"
make_key "$T/key"
KEY_FILE="$T/key" HR_ROOT="$T/repo"
mkdir -p "$T/repo/machines" "$T/repo/keys"
cp -r "$ROOT/machine" "$T/repo/machine"
ensure_machine_file
assemble_config "$dir"
drv="$(nix eval --raw "path:$dir#darwinConfigurations.machine.system.drvPath")"
case "$drv" in /nix/store/*-darwin-system-*.drv) pass "machine flake evaluates for aarch64-darwin" ;; *) fail "unexpected result: $drv" ;; esac
done_tests
