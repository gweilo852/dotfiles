# shellcheck shell=bash
# Portable tmux helpers for zsh and bash. Sourced by both rc files.
# A helper is defined only when no command, alias or function of the same
# name exists already, so local definitions always win. Nothing here runs
# tmux at shell start-up.
#
#   tm [name]                         attach to (or create) a session
#   tmux-workspace [-d] SESSION [WINDOW ...]
#                                     create missing session and windows
#   tmux-send [-y] SESSION:WINDOW TEXT  type TEXT + Enter into a window,
#                                     after checking the target
# See docs/tmux.md.

_dotfiles_free() { ! type "$1" >/dev/null 2>&1; }

# All helpers call tmux through this, so tests can use an isolated server
# (DOTFILES_TMUX_SOCKET=name works like tmux -L name).
_dt_tmux() {
  if [ -n "${DOTFILES_TMUX_SOCKET:-}" ]; then
    command tmux -L "$DOTFILES_TMUX_SOCKET" "$@"
  else
    command tmux "$@"
  fi
}

# Session names cannot contain "." or ":"; keep letters, digits, - and _.
_dt_session_name() { printf '%s' "$1" | tr -c 'A-Za-z0-9_-' '-'; }

_dt_attach() { # session
  if [ -n "${TMUX:-}" ]; then
    _dt_tmux switch-client -t "=$1"
  else
    _dt_tmux attach-session -t "=$1"
  fi
}

if _dotfiles_free tm; then
  # tm            session named after the current directory
  # tm CLOUD-1234 session for a story
  tm() {
    local name
    name=$(_dt_session_name "${1:-$(basename "$PWD")}")
    _dt_tmux has-session -t "=$name" 2>/dev/null ||
      _dt_tmux new-session -d -s "$name" -c "$PWD" || return
    _dt_attach "$name"
  }
fi

if _dotfiles_free tmux-workspace; then
  # tmux-workspace ghost-tower infra claude codex
  # Creates what is missing, in the current directory. Never closes,
  # renames or restarts anything that exists. -d: do not attach.
  tmux-workspace() {
    local detach=0 session w
    if [ "${1:-}" = -d ]; then detach=1; shift; fi
    if [ $# -lt 1 ]; then
      echo "usage: tmux-workspace [-d] SESSION [WINDOW ...]" >&2
      return 2
    fi
    session=$(_dt_session_name "$1")
    shift
    if ! _dt_tmux has-session -t "=$session" 2>/dev/null; then
      if [ $# -gt 0 ]; then
        _dt_tmux new-session -d -s "$session" -n "$1" -c "$PWD" || return
        echo "created session $session with window $1"
        shift
      else
        _dt_tmux new-session -d -s "$session" -c "$PWD" || return
        echo "created session $session"
      fi
    fi
    for w in "$@"; do
      if _dt_tmux list-windows -t "=$session" -F '#{window_name}' | grep -qxF -- "$w"; then
        echo "window $w exists"
      else
        _dt_tmux new-window -d -t "=$session:" -n "$w" -c "$PWD" || return
        echo "added window $w"
      fi
    done
    [ "$detach" = 1 ] || _dt_attach "$session"
  }
fi

if _dotfiles_free tmux-send; then
  # tmux-send ghost-tower:claude "run the tests"
  # The window is matched by exact name or index, and must match exactly
  # one window. The target and text are shown, and you confirm, unless -y.
  # The text is sent literally (no key names), then Enter.
  tmux-send() {
    local yes=0 target session window matches count index name cmd reply
    if [ "${1:-}" = -y ]; then yes=1; shift; fi
    if [ $# -lt 2 ]; then
      echo "usage: tmux-send [-y] SESSION:WINDOW TEXT..." >&2
      return 2
    fi
    target=$1
    shift
    case "$target" in
      ?*:?*) ;;
      *) echo "tmux-send: target must be SESSION:WINDOW, got '$target'" >&2; return 2 ;;
    esac
    session=${target%%:*}
    window=${target#*:}
    if ! _dt_tmux has-session -t "=$session" 2>/dev/null; then
      echo "tmux-send: no session named '$session'. Sessions:" >&2
      _dt_tmux list-sessions -F '  #{session_name}' >&2 2>/dev/null
      return 1
    fi
    # "index name" lines; a tab separator is not safe, because tmux may
    # escape control characters in its output.
    matches=$(_dt_tmux list-windows -t "=$session" -F '#{window_index} #{window_name}' |
      awk -v w="$window" '{ n = substr($0, length($1) + 2) } $1 == w || n == w')
    count=$(printf '%s\n' "$matches" | grep -c .)
    if [ "$count" -ne 1 ]; then
      echo "tmux-send: '$window' matches $count windows in '$session'. Windows:" >&2
      _dt_tmux list-windows -t "=$session" -F '  #{window_index}: #{window_name}' >&2
      return 1
    fi
    index=${matches%% *}
    name=${matches#* }
    cmd=$(_dt_tmux display-message -p -t "=$session:$index" '#{pane_current_command}')
    printf 'target: %s:%s (window %s, running %s)\ntext:   %s\n' "$session" "$name" "$index" "$cmd" "$*"
    if [ "$yes" != 1 ]; then
      if [ ! -t 0 ]; then
        echo "tmux-send: not interactive; add -y to send without a prompt" >&2
        return 1
      fi
      printf 'send? [y/N] '
      read -r reply
      case "$reply" in [Yy] | [Yy][Ee][Ss]) ;; *) echo "cancelled"; return 1 ;; esac
    fi
    # A short pause before Enter, so TUI agents (Claude Code, Codex) treat
    # the text as typed input and not as a pasted block.
    _dt_tmux send-keys -t "=$session:$index" -l -- "$*" &&
      sleep 0.3 &&
      _dt_tmux send-keys -t "=$session:$index" Enter
  }
fi

unset -f _dotfiles_free
