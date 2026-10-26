#!/bin/sh
# Shell for new tmux windows. tmux.conf runs this (run-shell) each time the
# configuration loads, also on reload (prefix r).
#   handoff on  (DOTFILES_INTERACTIVE_ZSH=1): default-shell is that zsh
#   handoff off (default, and always on Unraid): the tmux default, which is
#                $SHELL of the tmux server or the account's login shell
# See config/shell/zsh-handoff.sh for the settings. Windows that exist keep
# their shell. A setting in ~/.tmux.conf.local loads later and wins.
#   sh shell.sh --print   show the choice and change nothing
here=$(dirname "$0")
# shellcheck source=config/shell/zsh-handoff.sh
. "$here/../shell/zsh-handoff.sh"

if [ "${1:-}" = --print ]; then
  if _dotfiles_zsh_handoff_target; then echo "$_dotfiles_zsh"; else echo "default ($_dotfiles_zsh_why)"; fi
  exit 0
fi

# Talk only to the server that runs this script ($TMUX names its socket).
# Without $TMUX, do nothing: never fall back to the default server.
[ -n "${TMUX:-}" ] || exit 0
t() { tmux -S "${TMUX%%,*}" "$@"; }

# The server's own choice, kept from the first load. `set -gu` would give
# /bin/sh, not the $SHELL or login shell that tmux found at start.
default=$(t show-options -gqv @dotfiles_default_shell)
if [ -z "$default" ]; then
  default=$(t show-options -gv default-shell)
  t set-option -g @dotfiles_default_shell "$default"
fi
if _dotfiles_zsh_handoff_target; then
  t set-option -g default-shell "$_dotfiles_zsh"
else
  t set-option -g default-shell "$default"
fi
