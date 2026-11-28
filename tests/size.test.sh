#!/usr/bin/env bash
# Intent (the captain): a 1,000-line limit per code file. A file over it that is
# listed in .baseline-long-files may shrink but never grow.
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
check="$ROOT/scripts/size-check.py"
# shell_file PATH N: a valid shell script of exactly N lines (N >= 2).
shell_file() { { echo '#!/usr/bin/env bash'; seq 2 "$2" | sed 's/^/echo /'; } > "$1"; }

p="$T/project"
git init -q "$p"
mkdir -p "$p/lib"
shell_file "$p/lib/ok.sh" 1000
out="$("$check" "$p")"
assert_eq "$?" 0 "a 1,000-line code file passes"

shell_file "$p/lib/long.sh" 1001
out="$("$check" "$p")"
assert_eq "$?" 1 "a new 1,001-line code file fails"
assert_contains "$out" "fail: lib/long.sh has 1001 lines and is not on the list" "the failure names the file and its lines"

printf '# long files\nlib/long.sh\t1050\n' > "$p/.baseline-long-files"
shell_file "$p/lib/long.sh" 1050
out="$("$check" "$p")"
assert_eq "$?" 0 "a listed file at its listed size passes"

shell_file "$p/lib/long.sh" 1051
out="$("$check" "$p")"
assert_eq "$?" 1 "a listed file grown by one line fails"
assert_contains "$out" "fail: lib/long.sh grew from 1050 to 1051 lines" "the failure says how far it grew"

shell_file "$p/lib/long.sh" 1049
out="$("$check" "$p")"
assert_eq "$?" 0 "a listed file that shrank passes"
assert_contains "$out" "note: lib/long.sh shrank from 1050 to 1049 lines; update the list" "a shrunk file asks for the list to follow"

shell_file "$p/lib/long.sh" 900
out="$("$check" "$p")"
assert_eq "$?" 0 "a listed file now under the limit passes"
assert_contains "$out" "note: lib/long.sh is under the limit or gone; remove it from the list" "a file under the limit asks to leave the list"

d="$T/documents"
git init -q "$d"
mkdir -p "$d/machine"
seq 1 2000 | sed 's/^/line /' > "$d/README.md"
seq 1 2000 | sed 's/^/"node": /' > "$d/machine/flake.lock"
out="$("$check" "$d")"
assert_eq "$?" 0 "long documents and lock files pass"
assert_contains "$out" "size: 0 files over 1000 lines, 0 problems" "documents and lock files are not code files"
done_tests
