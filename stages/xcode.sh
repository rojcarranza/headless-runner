#!/usr/bin/env bash
# Stage xcode: Xcode from the App Store, its license, first launch, the iOS
# platform and the simulators the checks use. Device Hub is part of Xcode.
# shellcheck source=lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_apple_silicon_mac
need_password
command -v mas > /dev/null || die "mas is missing; run bash setup.sh machine first"

if [ ! -d /Applications/Xcode.app ]; then
  open -a "App Store" || true
  say "Sign in to the App Store with your Apple ID (the window that opened). Xcode downloads when you have."
  tries=0
  until mas install "$XCODE_APP_ID"; do
    tries=$((tries + 1))
    [ "$tries" -lt 90 ] || die "Xcode did not install; sign in to the App Store and run bash setup.sh xcode again"
    sleep 20
  done
fi

as_root xcode-select -s /Applications/Xcode.app/Contents/Developer
have="$(xcodebuild -version | awk '/^Xcode/ { print $2; exit }')"
version_ge "$have" "$XCODE_MIN" || die "Xcode $have is older than $XCODE_MIN, which PraiseLineup needs; update it in the App Store"
as_root xcodebuild -license accept
as_root xcodebuild -runFirstLaunch
xcodebuild -downloadPlatform iOS

# The simulators the checks name. Xcode may already have made them.
runtime="$(xcrun simctl list runtimes available | awk '/iOS 27/ { print $NF; exit }')"
[ -n "$runtime" ] || die "no iOS 27 runtime after the download; run bash setup.sh xcode again"
make_sim() { # make_sim NAME: create the simulator when no such device exists
  xcrun simctl list devices available | grep -q "^ *$1 (" && return 0
  local type
  type="$(xcrun simctl list devicetypes | awk -v n="$1" 'index($0, n " (") == 1 { gsub(/[()]/, "", $NF); print $NF; exit }')"
  [ -n "$type" ] || die "this Xcode has no device type named $1"
  xcrun simctl create "$1" "$type" "$runtime" > /dev/null
  say "made the $1 simulator"
}
make_sim "iPhone 18 Pro"
make_sim "iPad Pro 11-inch (M5)"
say "Xcode $have is ready"
