# shellcheck shell=sh disable=SC3043,SC2154
# SC3043: `local` is not POSIX, but dash, bash, busybox ash and zsh have it.
# SC2154: _dotfiles_conf is set by _dotfiles_conf_get (local-conf.sh).
# Interactive zsh handoff: one decision, shared by config/bash/bashrc
# (sourced), config/tmux/shell.sh (run by tmux), doctor.sh and the tests.
# POSIX sh; works in bash 3.2, dash and busybox ash. Nothing runs here.
#
# Machine-local settings, never in the repository:
#   ${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/local.conf
#     DOTFILES_INTERACTIVE_ZSH=1     interactive bash and new tmux windows
#                                    start zsh (opt-in; default off)
#     DOTFILES_ZSH=/opt/bin/zsh      zsh to use (default: zsh on PATH)
# Read with _dotfiles_conf_get (config/shell/local-conf.sh, which the
# caller sources first): the environment wins over the file.
# DOTFILES_NO_ZSH=1 in the environment turns the handoff off for one shell.

# Returns 0 and sets _dotfiles_zsh to an absolute zsh path when the handoff
# applies to this machine. Otherwise returns 1 and sets _dotfiles_zsh_why.
_dotfiles_zsh_handoff_target() {
  local on="" zsh="" dir IFS
  _dotfiles_zsh='' _dotfiles_zsh_why=''
  if _dotfiles_conf_get DOTFILES_INTERACTIVE_ZSH; then on=$_dotfiles_conf; fi
  if _dotfiles_conf_get DOTFILES_ZSH; then zsh=$_dotfiles_conf; fi

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
