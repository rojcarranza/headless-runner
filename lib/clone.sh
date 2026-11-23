# shellcheck shell=bash
# clone.sh - the one way every script clones a project, so every computer
# keeps projects in the same place: ~/Dev/github.com/<owner>/<repo>.
# sourced after common.sh.

# clone_path OWNER/REPO: where the clone lives.
clone_path() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || die "not an owner/repo: $1"
  printf '%s/%s\n' "$DEV_HOME" "$1"
}

# clone_repo OWNER/REPO [REF]: clone into its place (or leave it, when it is
# already there) and check out REF when given. Prints the path.
clone_repo() {
  local repo="$1" ref="${2-}" dest
  dest="$(clone_path "$repo")"
  if [ ! -d "$dest/.git" ]; then
    mkdir -p "$(dirname "$dest")"
    git clone --quiet "https://github.com/$repo.git" "$dest" >&2
  fi
  if [ -n "$ref" ]; then
    git -C "$dest" -c advice.detachedHead=false checkout --quiet "$ref" 2> /dev/null \
      || { git -C "$dest" fetch --quiet origin >&2 && git -C "$dest" -c advice.detachedHead=false checkout --quiet "$ref" >&2; }
  fi
  printf '%s\n' "$dest"
}

# clone_latest OWNER/REPO: clone_repo, and a clone that is already there is
# brought up to date with GitHub when it is on its default branch (main) with
# no uncommitted changes: fetch, then fast-forward only, so a project's checks
# run GitHub's newest main. A clone on another branch or with uncommitted
# changes is left as it is, with a warning. A main with commits GitHub's main
# lacks, or a fetch that fails, stops the run. Prints the path.
# Every failure dies by name: a $(...) caller runs it without set -e.
clone_latest() {
  local repo="$1" dest main branch before after
  dest="$(clone_path "$repo")"
  if [ ! -d "$dest/.git" ]; then
    clone_repo "$repo"
    return
  fi
  main="$(git -C "$dest" symbolic-ref --quiet --short refs/remotes/origin/HEAD || echo origin/main)"
  main="${main#origin/}"
  branch="$(git -C "$dest" symbolic-ref --quiet --short HEAD || true)"
  if [ "$branch" != "$main" ]; then
    warn "$repo is on ${branch:-a detached commit}, not $main; left as it is, so its checks run that version"
  elif [ -n "$(git -C "$dest" status --porcelain --untracked-files=no)" ]; then
    warn "$repo has uncommitted changes; left as it is, so its checks run them"
  else
    # No sign-in prompt: the stage may run unattended, where a prompt would wait forever.
    GIT_TERMINAL_PROMPT=0 git -C "$dest" fetch --quiet origin >&2 \
      || die "could not fetch $repo from GitHub, so its checks would run an old version; check this Mac's GitHub sign-in, then run the stage again"
    git -C "$dest" merge-base --is-ancestor HEAD "origin/$main" \
      || die "$repo's $main has commits GitHub's $main lacks, so it cannot fast-forward; it is left as it is. Push or remove them, then run the stage again"
    before="$(git -C "$dest" rev-parse --short HEAD)"
    git -C "$dest" merge --ff-only --quiet "origin/$main" >&2 \
      || die "could not fast-forward $repo's $main to GitHub's; git said why above"
    after="$(git -C "$dest" rev-parse --short HEAD)"
    if [ "$before" = "$after" ]; then
      say "$repo is up to date with GitHub's $main ($after)" >&2
    else
      say "$repo brought up to date with GitHub's $main: $before to $after" >&2
    fi
  fi
  printf '%s\n' "$dest"
}
