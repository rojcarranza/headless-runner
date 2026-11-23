#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2034 # pass/fail helpers never fail; stand-ins are single-quoted on purpose
# Intent (the captain): every computer keeps projects at
# ~/Dev/github.com/<owner>/<repo>, so clones always go there. Intent (a filed
# defect: a rerun of the projects stage tried an old clone's scripts): a clone
# already there on a clean main is brought up to date with GitHub, fast-forward
# only; any other clone is left as it is.
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
export HOME="$T/home" DEV_HOME="$T/home/Dev/github.com"
mkdir -p "$HOME"
. "$ROOT/lib/common.sh"
. "$ROOT/lib/clone.sh"

# A real repository stands in for GitHub through git's own URL rewriting.
mkdir -p "$T/work" "$T/remote/acme"
git -C "$T/work" init -q -b main
git -C "$T/work" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m first
git -C "$T/work" tag v1
git -C "$T/work" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m second
git clone -q --bare "$T/work" "$T/remote/acme/app.git"
export GIT_CONFIG_GLOBAL="$T/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" "url.file://$T/remote/.insteadOf" "https://github.com/"

assert_eq "$(clone_path acme/app)" "$DEV_HOME/acme/app" "path is DEV_HOME/owner/repo"
dest="$(clone_repo acme/app v1)"
assert_eq "$dest" "$DEV_HOME/acme/app" "clone lands in DEV_HOME/owner/repo"
assert_eq "$(git -C "$dest" log -1 --format=%s)" first "a ref is checked out"
assert_eq "$(clone_repo acme/app)" "$DEV_HOME/acme/app" "a second clone is a no-op that prints the same path"
(clone_path "not a repo") > /dev/null 2>&1 && fail "a bad name is refused" || pass "a bad name is refused"

# --- clone_latest: GitHub's main moves on while the clone waits
set +e # common.sh, sourced above, turned set -e on; every result here is asserted
# publish CHANGE: GitHub's main gets one more commit, a real change to a file.
publish() {
  echo "$1" >> "$T/work/app.txt"
  git -C "$T/work" add app.txt
  git -C "$T/work" -c user.name=t -c user.email=t@example.com commit -q -m "$1"
  git -C "$T/work" push -q "$T/remote/acme/app.git" main
}
latest() { (clone_latest acme/app) > "$T/path" 2> "$T/err"; }
at() { git -C "$dest" log -1 --format=%s; }
publish third

latest; rc=$?
assert_eq "$rc $(at)" "0 first" "a clone on a detached commit is left as it is"
assert_contains "$(cat "$T/err")" "acme/app is on a detached commit, not main; left as it is" "and the run says so"
assert_eq "$(cat "$T/path")" "$dest" "and its path is printed"

git -C "$dest" switch -q main
latest; rc=$?
assert_eq "$rc $(at)" "0 third" "a clean main behind GitHub's is fast-forwarded to it"
assert_contains "$(cat "$T/err")" "acme/app brought up to date with GitHub's main" "and the run says so"
assert_eq "$(cat "$T/path")" "$dest" "and its path is printed"

git -C "$dest" switch -q -c try
publish fourth
latest; rc=$?
assert_eq "$rc $(git -C "$dest" branch --show-current) $(at)" "0 try third" "a clone on another branch is left there"
assert_contains "$(cat "$T/err")" "acme/app is on try, not main; left as it is" "and the run says so"

git -C "$dest" switch -q main
echo mine >> "$dest/app.txt"
latest; rc=$?
assert_eq "$rc $(at) $(tail -n 1 "$dest/app.txt")" "0 third mine" "a main with uncommitted changes is left as it is, changes kept"
assert_contains "$(cat "$T/err")" "acme/app has uncommitted changes; left as it is" "and the run says so"

git -C "$dest" -c user.name=t -c user.email=t@example.com commit -q -am mine
latest; rc=$?
assert_eq "$rc $(at)" "1 mine" "a main with a commit GitHub's main lacks stops the run and is left as it is"
assert_contains "$(cat "$T/err")" "acme/app's main has commits GitHub's main lacks" "and the run says why"

git -C "$dest" reset -q --hard HEAD~1
mv "$T/remote/acme/app.git" "$T/remote/acme/gone.git"
latest; rc=$?
mv "$T/remote/acme/gone.git" "$T/remote/acme/app.git"
assert_eq "$rc $(at)" "1 third" "GitHub out of reach stops the run, the clone untouched"
assert_contains "$(cat "$T/err")" "could not fetch acme/app from GitHub" "and the run says why"
done_tests
