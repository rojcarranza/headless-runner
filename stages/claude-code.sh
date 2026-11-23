#!/usr/bin/env bash
# Stage claude-code: Claude Code, which Infinitary runs its work with on this
# Mac and does not bring. Anthropic's native installer puts it at
# ~/.local/bin/claude, and that build keeps itself up to date, so no version
# is pinned (pins.env). A non-interactive SSH command reads no profile but
# ~/.zshenv, so ~/.local/bin goes on PATH there, or claude is not found by
# name. Signing it in to Claude stays yours, through Infinitary's setup card.
# shellcheck source=lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_apple_silicon_mac

CLAUDE="$HOME/.local/bin/claude"
if [ ! -x "$CLAUDE" ]; then
  say "installing Claude Code with Anthropic's native installer"
  curl -fsSL https://claude.ai/install.sh | bash \
    || die "Claude Code did not install; check the internet connection, then run bash setup.sh claude-code again"
fi
"$CLAUDE" --version > /dev/null 2>&1 \
  || die "Claude Code does not answer at $CLAUDE, where Infinitary looks for it; remove it if it is there, then run bash setup.sh claude-code again"

# The installer's own PATH line, once, on a line of its own.
# shellcheck disable=SC2016 # written as is; zsh expands it
line='export PATH="$HOME/.local/bin:$PATH"'
zshenv="$HOME/.zshenv"
if ! grep -qxF "$line" "$zshenv" 2> /dev/null; then
  [ ! -s "$zshenv" ] || [ -z "$(tail -c 1 "$zshenv")" ] || printf '\n' >> "$zshenv"
  printf '# Claude Code, for every zsh: SSH commands read only this file\n%s\n' "$line" >> "$zshenv"
  say "put ~/.local/bin on PATH in ~/.zshenv"
fi

# The shell an SSH command gets here: zsh -c, with sshd's short PATH (the
# tests name their own zsh in HR_ZSH).
version="$(env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin "${HR_ZSH:-/bin/zsh}" -c 'claude --version' 2> /dev/null)" \
  || die "claude does not run by name in a non-interactive shell; check ~/.zshenv, then run bash setup.sh claude-code again"
say "Claude Code ${version%% *} runs by name in SSH commands; sign it in to Claude through Infinitary's setup card"
