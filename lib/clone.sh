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
