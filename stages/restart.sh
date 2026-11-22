#!/usr/bin/env bash
# Stage restart: restart once so the Mac proves it signs itself back in. A
# login agent then runs verify.sh as soon as the user is back, and shows the
# result in a notification and in ~/Library/Logs/headless-runner-verify.log.
# shellcheck source=lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_apple_silicon_mac
need_password
PLIST="$HOME/Library/LaunchAgents/com.headless-runner.verify.plist"
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
sed -e "s|@ROOT@|$HR_ROOT|g" -e "s|@HOME@|$HOME|g" "$HR_ROOT/launchd/com.headless-runner.verify.plist.tmpl" > "$PLIST"
stage_mark restart
say "restarting in 10 seconds; the Mac signs back in by itself and checks everything"
as_root /bin/sh -c '(sleep 10; /sbin/shutdown -r now) > /dev/null 2>&1 &'
