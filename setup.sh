#!/usr/bin/env bash
# setup.sh - one command that turns this Mac into a work computer for
# Infinitary tasks and iOS CI. Run it in Terminal as the admin user you made
# in System Settings. It skips stages that are done and picks up where it
# stopped when you run it again.
#
#   bash setup.sh            run every stage that is not done yet
#   bash setup.sh STAGE         run one stage again (account, machine,
#                            claude-code, xcode, runner-up, github, projects,
#                            restart)
#   bash setup.sh --no-restart  everything except the final restart
#   bash setup.sh --list        show the stages and which are done
#
# The password is asked once, hidden, and lives only in this run's memory.
# shellcheck source=lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

STAGES=(account machine claude-code xcode runner-up github projects restart)
# Only these stages use the password; the others (claude-code, runner-up,
# github, projects) never see it: runner-up and projects run PraiseLineup's scripts
# and the nightly.
PASSWORD_STAGES=" account machine xcode restart "

usage() { sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

run_stage() {
  local s="$1"
  say "== stage: $s"
  if [[ "$PASSWORD_STAGES" == *" $s "* ]]; then
    HR_PASSWORD="$HR_PASSWORD" bash "$HR_ROOT/stages/$s.sh"
  else
    env -u HR_PASSWORD bash "$HR_ROOT/stages/$s.sh"
  fi
  # The restart stage ends the run; the others mark themselves done here.
  [ "$s" = restart ] || stage_mark "$s"
}

want="" restart=1
for a in "$@"; do
  case "$a" in
    -h | --help) usage; exit 0 ;;
    --list)
      for s in "${STAGES[@]}"; do
        if stage_done "$s"; then echo "done   $s"; else echo "todo   $s"; fi
      done
      exit 0 ;;
    --no-restart) restart=0 ;;
    *) want="$a" ;;
  esac
done

require_apple_silicon_mac
if [ -n "$want" ]; then
  printf '%s\n' "${STAGES[@]}" | grep -qx "$want" || die "unknown stage '$want'; stages are: ${STAGES[*]}"
  stage_clear "$want"
fi
need_password

for s in "${STAGES[@]}"; do
  [ -z "$want" ] || [ "$s" = "$want" ] || continue
  if [ "$s" = restart ] && [ "$restart" = 0 ]; then say "skipping the restart"; continue; fi
  if stage_done "$s"; then say "stage $s is done; skipping"; continue; fi
  run_stage "$s"
done
say "finished"
