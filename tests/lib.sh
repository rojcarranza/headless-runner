# shellcheck shell=bash disable=SC2034
# Test helpers: a scratch folder per test file and tiny assertions.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FAILED=0
pass() { echo "  ok   $1"; }
fail() { echo "  FAIL $1" >&2; FAILED=1; }
assert_eq() { if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (got '$1', want '$2')"; fi; }
assert_contains() { if grep -qF -- "$2" <<< "$1"; then pass "$3"; else fail "$3 (no '$2' in: $1)"; fi; }
assert_not_contains() { if grep -qF -- "$2" <<< "$1"; then fail "$3 ('$2' found)"; else pass "$3"; fi; }
done_tests() { exit "$FAILED"; }
# make_key PATH: a real ed25519 key pair for fixtures; never reused elsewhere.
make_key() { ssh-keygen -q -t ed25519 -N '' -C fixture -f "$1"; }
# install_claude_native HOME VERSION: what Anthropic's native installer leaves,
# as a real install shows: the build in ~/.local/share/claude/versions, linked
# from ~/.local/bin/claude, printing what claude --version prints.
install_claude_native() {
  mkdir -p "$1/.local/share/claude/versions" "$1/.local/bin"
  printf '#!/bin/sh\necho "%s (Claude Code)"\n' "$2" > "$1/.local/share/claude/versions/$2"
  chmod +x "$1/.local/share/claude/versions/$2"
  ln -sfn "$1/.local/share/claude/versions/$2" "$1/.local/bin/claude"
}
# stand_in_ssh BIN: ssh as this Mac's sshd answers a command. The user's zsh
# (a real one) runs it non-interactively with sshd's short PATH, so it reads
# ~/.zshenv and no other profile. Fails the test when this computer has no zsh.
stand_in_ssh() {
  local zsh
  zsh="$(command -v zsh)" || { fail "zsh is needed: SSH commands on a Mac run in it"; return 1; }
  cat > "$1/ssh" << EOF
#!/bin/sh
while [ \$# -gt 0 ]; do case "\$1" in -o | -i) shift 2 ;; -*) shift ;; *) break ;; esac; done
shift
exec env -i HOME="\$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin "$zsh" -c "\$*"
EOF
  chmod +x "$1/ssh"
}
