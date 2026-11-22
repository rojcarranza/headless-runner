# shellcheck shell=bash disable=SC2034
# Test helpers: a scratch folder per test file and tiny assertions.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FAILED=0
pass() { echo "  ok   $1"; }
fail() { echo "  FAIL $1" >&2; FAILED=1; }
assert_eq() { if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (got '$1', want '$2')"; fi; }
assert_contains() { if grep -qF -- "$2" <<< "$1"; then pass "$3"; else fail "$3 (no '$2' in: $1)"; fi; }
assert_not_contains() { if grep -qF -- "$2" <<< "$1"; then fail "$3 ('$2' found)"; else pass "$3"; fi; }
done_tests() { exit "$FAILED"; }
# make_key PATH: a real ed25519 key pair for fixtures; never reused elsewhere.
make_key() { ssh-keygen -q -t ed25519 -N '' -C fixture -f "$1"; }
