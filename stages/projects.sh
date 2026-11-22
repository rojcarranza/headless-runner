#!/usr/bin/env bash
# Stage projects: one script per app under projects/, each run in turn.
# shellcheck source=lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_apple_silicon_mac
for p in "$HR_ROOT"/projects/*.sh; do
  [ -f "$p" ] || continue
  say "project: $(basename "$p" .sh)"
  bash "$p"
done
