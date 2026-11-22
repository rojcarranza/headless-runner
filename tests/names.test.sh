#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2034 # pass/fail helpers never fail; stand-ins are single-quoted on purpose
# Intent (the captain): the same scripts serve any Mac, so no script may name
# one computer. The name comes from the user running them.
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hits="$(cd "$ROOT" && grep -rniE 'thirdmate|secondmate|firstmate|macbook' setup.sh verify.sh stages projects lib machine scripts launchd .github || true)"
assert_eq "$hits" "" "no script, flake or workflow names a computer"
done_tests
