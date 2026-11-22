# shellcheck shell=bash
# config.sh - builds headless's config folder for this computer from the
# repository's machine/ flake and machines/<name>.json. sourced after common.sh.

KEY_FILE="${KEY_FILE:-$HOME/.ssh/id_ed25519}"

# ensure_machine_file: machines/<name>.json, made once. It holds the user,
# the host name, the public keys allowed in by SSH and the sign-in choice -
# no secret. The keys are this user's own key (the Mac reaches itself with it
# for runner-up) and every public key in keys/.
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
