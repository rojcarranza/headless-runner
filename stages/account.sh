#!/usr/bin/env bash
# Stage account: the new user is ready for the rest. You made the admin user in
# System Settings, which gives it a secure token; this checks that, turns
# Remote Login on, makes the user's own SSH key and the projects folder.
# shellcheck source=lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_apple_silicon_mac
need_password

id -Gn | tr ' ' '\n' | grep -qx admin \
  || die "$HR_NAME is not an administrator. In System Settings, Users & Groups, make it one (or add a new administrator) and sign in as it"

# The password must be right before anything depends on it.
printf '%s\n' "$HR_PASSWORD" | sudo -S -p '' -v 2> /dev/null || die "that password does not unlock sudo for $HR_NAME"

# A user made in System Settings has a secure token; FileVault and software
# updates need it, and headless needs it to turn FileVault off.
sysadminctl -secureTokenStatus "$HR_NAME" 2>&1 | grep -qi 'ENABLED' \
  || die "$HR_NAME has no secure token. Make a fresh administrator in System Settings, Users & Groups (not one made with a script), and run setup.sh as it"

# Command line tools hold git, which every later stage needs.
if ! xcode-select -p > /dev/null 2>&1; then
  xcode-select --install || true
  die "the command line tools are installing; finish the window that opened, then run bash setup.sh again"
fi

# Remote Login: headless reaches this Mac over SSH to itself.
if ! nc -z 127.0.0.1 22 2> /dev/null; then
  as_root systemsetup -setremotelogin on \
    || die "could not turn on Remote Login; turn it on in System Settings, General, Sharing, Remote Login, then run bash setup.sh again"
  sleep 2
  nc -z 127.0.0.1 22 || die "Remote Login is still off"
fi
say "Remote Login is on"

# This user's own SSH key: the Mac reaches itself with it (headless, runner-up).
mkdir -p "$HOME/.ssh"
chmod 0700 "$HOME/.ssh"
[ -f "$HOME/.ssh/id_ed25519" ] || ssh-keygen -q -t ed25519 -N '' -C "$HR_NAME@headless-runner" -f "$HOME/.ssh/id_ed25519"

# Public keys of the computers that will add this one in Infinitary. keyOnlySsh
# turns password sign-in off, so Infinitary can only come in by such a key.
if ! ls "$HR_ROOT"/keys/*.pub > /dev/null 2>&1; then
  [ -t 0 ] || die "keys/ holds no public key; add the first mate's computer key as keys/<name>.pub"
  say "Paste the public key of the computer that will add this one in Infinitary."
  say "On that computer run: cat ~/.ssh/id_ed25519.pub"
  printf 'public key: ' >&2
  IFS= read -r pub
  [[ "$pub" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+)\ [A-Za-z0-9+/=]+ ]] || die "that is not a public SSH key line"
  printf '%s\n' "$pub" > "$HR_ROOT/keys/first-mate.pub"
fi

# One projects folder, the same path as on every other computer.
mkdir -p "$DEV_HOME"
profile_line="export DEV_HOME=\"$DEV_HOME\""
for f in "$HOME/.zprofile" "$HOME/.zshrc"; do
  grep -qxF "$profile_line" "$f" 2> /dev/null || printf '%s\n' "$profile_line" >> "$f"
done
say "projects live in $DEV_HOME/<owner>/<repo>"
