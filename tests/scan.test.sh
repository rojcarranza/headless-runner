#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2034 # pass/fail helpers never fail; stand-ins are single-quoted on purpose
# Intent (the captain): scripts never hold a secret, password or token. The
# scan must pass the repository and catch a planted token.
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
if "$ROOT/scripts/scan-secrets.sh" > /dev/null 2>&1; then pass "the repository holds no secret"; else fail "the repository holds a secret-looking value"; fi
mkdir -p "$T/planted"
printf 'TOKEN="%s"\n' "ghp_$(printf 'a%.0s' $(seq 1 36))" > "$T/planted/env"
if "$ROOT/scripts/scan-secrets.sh" "$T/planted" > /dev/null 2>&1; then fail "a planted GitHub token is missed"; else pass "a planted GitHub token is caught"; fi
mkdir -p "$T/planted2"
printf 'password = "hunter2hunter2"\n' > "$T/planted2/x"
if "$ROOT/scripts/scan-secrets.sh" "$T/planted2" > /dev/null 2>&1; then fail "a planted password is missed"; else pass "a planted password is caught"; fi
mkdir -p "$T/planted3"
printf 'DB_PASSWORD = "hunter2hunter2"\n' > "$T/planted3/x"
if "$ROOT/scripts/scan-secrets.sh" "$T/planted3" > /dev/null 2>&1; then fail "an upper-case password name is missed"; else pass "an upper-case password name is caught"; fi
done_tests
