#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2034 # pass/fail helpers never fail; stand-ins are single-quoted on purpose
# Intent (the captain): every computer keeps projects at
# ~/Dev/github.com/<owner>/<repo>, so clones always go there.
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
done_tests
