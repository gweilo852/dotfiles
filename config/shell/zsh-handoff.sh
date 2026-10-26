# shellcheck shell=sh disable=SC3043
# SC3043: `local` is not POSIX, but dash, bash, busybox ash and zsh have it.
# Interactive zsh handoff: one decision, shared by config/bash/bashrc
# (sourced), config/tmux/shell.sh (run by tmux), doctor.sh and the tests.
# POSIX sh; works in bash 3.2, dash and busybox ash. Nothing runs here.
#
# Machine-local settings, never in the repository:
#   ${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/local.conf
#     DOTFILES_INTERACTIVE_ZSH=1     interactive bash and new tmux windows
#                                    start zsh (opt-in; default off)
#     DOTFILES_ZSH=/opt/bin/zsh      zsh to use (default: zsh on PATH)
# The file is read, not executed. Only NAME=value lines count, and the last
# one wins. An environment variable of the same name wins over the file.
# DOTFILES_NO_ZSH=1 in the environment turns the handoff off for one shell.

# Returns 0 and sets _dotfiles_zsh to an absolute zsh path when the handoff
# applies to this machine. Otherwise returns 1 and sets _dotfiles_zsh_why.
_dotfiles_zsh_handoff_target() {
  local conf line on zsh dir IFS
  _dotfiles_zsh='' _dotfiles_zsh_why=''
  on=${DOTFILES_INTERACTIVE_ZSH-} zsh=${DOTFILES_ZSH-}
  conf="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/local.conf"
  if [ -r "$conf" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line=${line#export }
      case $line in
        DOTFILES_INTERACTIVE_ZSH=*) [ -n "${DOTFILES_INTERACTIVE_ZSH+x}" ] || on=${line#*=} ;;
        DOTFILES_ZSH=*) [ -n "${DOTFILES_ZSH+x}" ] || zsh=${line#*=} ;;
      esac
    done <"$conf"
  fi
  # Drop a trailing comment and one level of quotes.
  on=${on%%[[:space:]]*} on=${on#[\"\']} on=${on%[\"\']}
  zsh=${zsh%%[[:space:]]#*} zsh=${zsh#[\"\']} zsh=${zsh%[\"\']}

  case $on in
    1 | [Yy] | [Yy][Ee][Ss] | [Tt][Rr][Uu][Ee] | [Oo][Nn]) ;;
    *) _dotfiles_zsh_why="off (DOTFILES_INTERACTIVE_ZSH is not set to 1)"; return 1 ;;
  esac
  if [ -n "${DOTFILES_NO_ZSH-}" ]; then
    _dotfiles_zsh_why="off for this shell (DOTFILES_NO_ZSH is set)"
    return 1
  fi
  if [ -f "${DOTFILES_SYSROOT-}/etc/unraid-version" ]; then
    _dotfiles_zsh_why="off (Unraid always uses bash)"
    return 1
  fi
  if [ -z "$zsh" ]; then
    # command -v would need a subshell in bash; walk PATH instead.
    IFS=:
    for dir in $PATH; do
      case $dir in /*) ;; *) continue ;; esac
      if [ -f "$dir/zsh" ] && [ -x "$dir/zsh" ]; then zsh=$dir/zsh; break; fi
    done
    if [ -z "$zsh" ]; then
      _dotfiles_zsh_why="inactive (zsh not found on PATH)"
      return 1
    fi
  fi
  case $zsh in
    /*) ;;
    *) _dotfiles_zsh_why="inactive (DOTFILES_ZSH must be an absolute path: $zsh)"; return 1 ;;
  esac
  if [ ! -f "$zsh" ] || [ ! -x "$zsh" ]; then
    _dotfiles_zsh_why="inactive ($zsh is not an executable file)"
    return 1
  fi
  _dotfiles_zsh=$zsh
}
