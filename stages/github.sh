#!/usr/bin/env bash
# Stage github: this Mac can clone projects with SSH addresses
# (git@github.com:owner/repo.git), which is how Infinitary clones them. Three
# steps: GitHub's published host keys go in ~/.ssh/known_hosts (so no one has
# to trust a host by hand), and if GitHub does not already greet this Mac's key
# by name, you add the key on GitHub's own page (the Mac is given no permission
# to manage your account) and ssh -T checks that GitHub then greets it.
# shellcheck source=lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_apple_silicon_mac

# 1. Host keys, from GitHub's own API over TLS (the same keys GitHub publishes
# in its documentation), each once, on a line of its own.
mkdir -p "$HOME/.ssh"
chmod 0700 "$HOME/.ssh"
meta="$(curl -fsSL "${HR_GITHUB_META:-https://api.github.com/meta}")" \
  || die "could not read GitHub's host keys; check the internet connection, then run bash setup.sh github again"
host_keys="$(jq -r '.ssh_keys[]?' <<< "$meta")"
[ -n "$host_keys" ] || die "GitHub's answer holds no SSH host keys; run bash setup.sh github again later"
known="$HOME/.ssh/known_hosts"
touch "$known"
chmod 0600 "$known"
[ ! -s "$known" ] || [ -z "$(tail -c 1 "$known")" ] || printf '\n' >> "$known"
added=0
while IFS= read -r key; do
  grep -qxF "github.com $key" "$known" || { printf 'github.com %s\n' "$key" >> "$known"; added=$((added + 1)); }
done <<< "$host_keys"
say "GitHub's host keys are in ~/.ssh/known_hosts ($added added)"

# 2. Already greeted by name (the key is on the account): nothing to ask.
pub="$HOME/.ssh/id_ed25519.pub"
[ -f "$pub" ] || die "no SSH key at $pub; run bash setup.sh account first"
if github_greets "${pub%.pub}"; then
  say "${GITHUB_SAID%%!*}! this Mac's SSH key is already on your GitHub account"
  exit 0
fi

# 3. Not greeted: you add the key on GitHub's own page. This Mac never gets
# permission to manage your account's keys; your click on GitHub is the yes.
say "GitHub does not know this Mac's SSH key yet. Add it on GitHub's page:"
say "  1. the key is copied (or shown below); paste it into the Key box"
say "  2. type the title $HR_NAME and keep the type Authentication Key"
say "  3. press Add SSH key, then come back here and press Return"
if command -v pbcopy > /dev/null 2>&1; then pbcopy < "$pub" || true; fi
cat "$pub" >&2
open_page "https://github.com/settings/ssh/new"
printf 'Press Return once GitHub shows the key added: ' >&2
# Asked on the terminal, never on a pipe: no terminal means no way to wait.
IFS= read -r _ < "${HR_TTY:-/dev/tty}" 2> /dev/null || { printf '\n' >&2; die "no terminal to wait on; run bash setup.sh github in Terminal"; }

# 4. GitHub must now greet you by name.
github_greets "${pub%.pub}" \
  || die "GitHub did not accept this Mac's SSH key (it said: $GITHUB_SAID); add the key on GitHub's page, then run bash setup.sh github again"
say "${GITHUB_SAID%%!*}! SSH to GitHub works"
