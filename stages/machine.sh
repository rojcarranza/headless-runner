#!/usr/bin/env bash
# Stage machine: headless puts the Mac in its work-computer state (never
# asleep, signs itself in, SSH by key only, Tailscale, the CI tools) by
# running headless's own scripts against this Mac over SSH to itself.
# shellcheck source=lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=lib/clone.sh
. "$HR_ROOT/lib/clone.sh"
# shellcheck source=lib/config.sh
. "$HR_ROOT/lib/config.sh"
require_apple_silicon_mac
need_password
[ ! -d /Applications/Tailscale.app ] \
  || die "the Tailscale app is installed. headless runs Tailscale as a background service instead and refuses to run beside the app: remove the app, then run bash setup.sh again"

ensure_machine_file
# headless's scripts come from the same commit the flake locks for its nix-darwin
# module, so one pin (machine/flake.nix and flake.lock) moves both.
HEADLESS_REF="$(jq -r '.nodes.headless.locked.rev' "$HR_ROOT/machine/flake.lock")"
[[ "$HEADLESS_REF" =~ ^[0-9a-f]{40}$ ]] || die "machine/flake.lock holds no headless commit"
H="$(clone_repo kunchenguid/headless "$HEADLESS_REF")"
S="$H/skills/headless/scripts/mac"

# Homebrew holds Rancher Desktop and mas. The installer needs sudo once.
if [ ! -x /opt/homebrew/bin/brew ]; then
  say "installing Homebrew"
  printf '%s\n' "$HR_PASSWORD" | sudo -S -p '' -v
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

assemble_config "$HR_CONFIG"
# HR_PASSWORD reaches headless through its "cmd:" secret store, by environment,
# for the headless scripts only.
with_password() { HR_PASSWORD="$HR_PASSWORD" "$@"; }
with_password "$S/connect.sh" "$HR_CONFIG"
with_password "$S/admin.sh" "$HR_CONFIG"
with_password "$S/apply.sh" "$HR_CONFIG"

ensure_rancher_profile
start_rancher_desktop

# Tailscale: headless prints a sign-in link; the page is yours to approve.
out="$(with_password "$S/tailscale.sh" "$HR_CONFIG" 2>&1 | tee /dev/stderr)"
link="$(printf '%s\n' "$out" | grep -Eo 'https://[^ ]+' | head -n 1 || true)"
[ -z "$link" ] || open_page "$link"
with_password "$S/tailscale.sh" "$HR_CONFIG" --wait
say "Tailscale is connected. In the Tailscale admin page, turn off key expiry for $HR_NAME so it never drops off the tailnet"
