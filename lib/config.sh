# shellcheck shell=bash
# config.sh - builds headless's config folder for this computer from the
# repository's machine/ flake and machines/<name>.json. sourced after common.sh.

KEY_FILE="${KEY_FILE:-$HOME/.ssh/id_ed25519}"

# ensure_machine_file: machines/<name>.json, made once. It holds the user,
# the host name, the public keys allowed in by SSH and the sign-in choice -
# no secret. The keys are this user's own key (headless's scripts reach this Mac
# at 127.0.0.1 with it) and every public key in keys/.
ensure_machine_file() {
  local file="$HR_ROOT/machines/$HR_NAME.json" keys="" k
  [ ! -f "$file" ] || return 0
  [ -f "$KEY_FILE.pub" ] || die "no $KEY_FILE.pub; run the account stage first"
  for k in "$KEY_FILE.pub" "$HR_ROOT"/keys/*.pub; do
    [ -f "$k" ] || continue
    keys="$keys${keys:+, }$(jq -Rn --arg k "$(cut -d' ' -f1-3 < "$k" | head -n 1)" '$k')"
  done
  # shellcheck disable=SC2086 # keys is a list of JSON strings
  jq -n --arg user "$HR_NAME" --argjson keys "[$keys]" '{
    user: $user, hostName: $user, sshKeys: $keys, keyOnlySsh: true, autoLogin: true,
    tailscale: { enable: true },
    extras: { neverSleep: true, startAfterPowerLoss: true, wakeOnLan: true,
              powerNapOff: true, spotlightOff: true, siriOff: true } }' > "$file"
  say "wrote machines/$HR_NAME.json (public keys only)"
}

# assemble_config DIR: flake, settings and how to reach this Mac. headless.env
# only names where the password comes from: HR_PASSWORD in this run's memory.
assemble_config() {
  local dir="$1"
  mkdir -p "$dir"
  cp "$HR_ROOT/machine/flake.nix" "$HR_ROOT/machine/machine.nix" "$dir/"
  cp "$HR_ROOT/machine/flake.lock" "$dir/"
  cp "$HR_ROOT/machines/$HR_NAME.json" "$dir/settings.json"
  cat > "$dir/headless.env" <<ENV
# How headless reaches this Mac: itself, by SSH. No secret is stored here.
ADDRESS=127.0.0.1
LOGIN=$HR_NAME
SSH_KEY=$KEY_FILE
PASSWORD_REF=cmd:printf '%s' "\$HR_PASSWORD"
TAILSCALE_KEY_REF=
TAILSCALE_LOGIN_SERVER=
ENV
}

# Rancher Desktop shows a first-run window, and starts no Docker until a person
# closes it, when it has no settings file and no deployment profile. A defaults
# profile skips that window, so the nightly's local server can start Docker with
# nobody at the screen. Settings: the Docker engine (moby), no Kubernetes.
# "version" is the settings version the profile is written at (10); Rancher
# Desktop migrates an older profile to its own current version on first open.
ensure_rancher_profile() {
  local profile="$HOME/Library/Preferences/io.rancherdesktop.profile.defaults.plist"
  [ ! -e "$profile" ] || return 0
  mkdir -p "$(dirname "$profile")"
  cat > "$profile" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>version</key><integer>10</integer>
  <key>containerEngine</key>
  <dict><key>name</key><string>moby</string></dict>
  <key>kubernetes</key>
  <dict><key>enabled</key><false/></dict>
</dict>
</plist>
PLIST
  say "wrote Rancher Desktop's defaults profile (no first-run window)"
}

# start_rancher_desktop: Rancher Desktop makes its docker command (~/.rd/bin/docker)
# only the first time it starts, and PraiseLineup's local server stops without it.
# Opened in view, once, while a person is at the screen: macOS asks them to click
# Open the first time an app installed by Homebrew starts. Waits up to 5 minutes
# for Docker to answer.
start_rancher_desktop() {
  local docker="$HOME/.rd/bin/docker" tries=0
  [ -x "$docker" ] && "$docker" info > /dev/null 2>&1 && return 0
  say "opening Rancher Desktop once; if macOS asks, click Open in its window"
  open -a "Rancher Desktop" || die "could not open Rancher Desktop; open it from Applications, then run bash setup.sh machine again"
  until [ -x "$docker" ] && "$docker" info > /dev/null 2>&1; do
    tries=$((tries + 1))
    [ "$tries" -lt 60 ] || die "Docker did not answer from Rancher Desktop; finish its window, then run bash setup.sh machine again"
    sleep 5
  done
  say "Docker answers"
}
