#!/usr/bin/env bash
# Stage github: this Mac can clone projects with SSH addresses
# (git@github.com:owner/repo.git), which is how Infinitary clones them. Three
# steps: GitHub's published host keys go in ~/.ssh/known_hosts (so no one has
# to trust a host by hand), and if GitHub does not already greet this Mac's key
# by name, the key goes on your GitHub account once you say yes. ssh -T checks.
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

# 3. This Mac's key on your GitHub account, with your yes.
gh auth status > /dev/null 2>&1 || die "GitHub is not signed in; run bash setup.sh runner-up first"
say "This Mac's SSH key is not on your GitHub account yet. Adding it lets this Mac"
say "read and write every repository your account can, as you do with your own key."
printf 'Add it to your GitHub account now, titled "%s"? [y/N] ' "$HR_NAME" >&2
answer=""
# Asked on the terminal, never on a pipe: no terminal means no yes.
IFS= read -r answer < "${HR_TTY:-/dev/tty}" 2> /dev/null || { printf '\n' >&2; die "no terminal to ask on; run bash setup.sh github in Terminal"; }
case "$answer" in
  y | Y | yes | Yes) ;;
  *) die "not adding the key; the Mac cannot clone with SSH addresses until it is on your GitHub account. Run bash setup.sh github again when you want it" ;;
esac
gh auth refresh --hostname github.com --scopes admin:public_key \
  || die "GitHub did not grant permission to add keys; run bash setup.sh github again"
gh ssh-key add "$pub" --title "$HR_NAME" --type authentication \
  || die "GitHub did not accept the key; run bash setup.sh github again"
say "added this Mac's SSH key to your GitHub account as $HR_NAME"

# 4. GitHub must now greet you by name.
github_greets "${pub%.pub}" \
  || die "GitHub did not accept this Mac's SSH key (it said: $GITHUB_SAID); run bash setup.sh github again"
say "${GITHUB_SAID%%!*}! SSH to GitHub works"
