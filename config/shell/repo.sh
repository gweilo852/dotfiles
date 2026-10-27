# shellcheck shell=bash
# Repository navigation for zsh and bash: `repo`. Sourced by both rc files,
# after config/shell/tmux.sh and config/shell/local-conf.sh. Defined only
# when no command, alias or function named `repo` exists. Nothing runs at
# shell start-up. See docs/repositories.md.
#
# Layout (root: DOTFILES_PROJECTS in local.conf, default ~/projects):
#   <root>/personal/<org>/<repo>/   <root>/work/<org>/<repo>/   <root>/scratch/<repo>/
#   <root>/<scope>/<org>/.worktrees/<repo>/<context>/   (worktrees)
#
#   repo                     choose with fzf (on a terminal), else list
#   repo list [--worktrees]  list repositories (worktrees only on request)
#   repo NAME                cd to a repository: repo, org/repo or scope/org/repo
#   repo root                print the root of the current repository
#   repo worktrees [NAME]    git worktree list
#   repo tmux [-d] [NAME] [CONTEXT]
#                            attach to (or create) the repository's tmux
#                            session; CONTEXT opens or selects a window

_dr_root() {
  local r="$HOME/projects"
  # shellcheck disable=SC2154 # set by _dotfiles_conf_get (local-conf.sh)
  if _dotfiles_conf_get DOTFILES_PROJECTS 2>/dev/null; then r=$_dotfiles_conf; fi
  case $r in "~"/*) r="$HOME/${r#\~/}" ;; esac
  # Physical path, so it compares with paths from git (/tmp -> /private/tmp).
  (cd "$r" 2>/dev/null && pwd -P) || printf '%s' "${r%/}"
}

# Prints "ID<TAB>PATH" lines, sorted. IDs: scope/org/repo and scratch/repo;
# with --worktrees also scope/org/repo@context for worktrees.
_dr_list() {
  local root wt=0 f rel id
  root=$(_dr_root)
  [ "${1:-}" = --worktrees ] && wt=1
  [ -d "$root" ] || return 0
  {
    find "$root" -mindepth 2 -maxdepth 4 -name .worktrees -prune -o -name .git -print 2>/dev/null
    [ "$wt" = 1 ] && find "$root" -mindepth 6 -maxdepth 6 -path '*/.worktrees/*/*/.git' -print 2>/dev/null
  } | while IFS= read -r f; do
    rel=${f#"$root"/}
    rel=${rel%/.git}
    case $rel in
      personal/*/*/.worktrees/*/* | work/*/*/.worktrees/*/*) continue ;;
      personal/*/.worktrees/*/* | work/*/.worktrees/*/*)
        # scope/org/.worktrees/repo/context -> scope/org/repo@context
        id=$(printf '%s' "$rel" | sed 's|^\([^/]*/[^/]*\)/\.worktrees/\([^/]*\)/\([^/]*\)$|\1/\2@\3|')
        ;;
      personal/*/*/* | work/*/*/* | scratch/*/*) continue ;;
      personal/*/* | work/*/* | scratch/*) id=$rel ;;
      *) continue ;;
    esac
    printf '%s\t%s\n' "$id" "${f%/.git}"
  done | LC_ALL=C sort
}

# Prints the lines of _dr_list that NAME selects: an exact ID, or an ID
# that ends with /NAME (whole path components).
_dr_match() {
  local name=$1 all exact
  all=$(_dr_list)
  exact=$(printf '%s\n' "$all" | awk -F'\t' -v n="$name" '$1 == n')
  if [ -n "$exact" ]; then
    printf '%s\n' "$exact"
  else
    printf '%s\n' "$all" | awk -F'\t' -v n="$name" 'length($1) > length(n) && substr($1, length($1) - length(n)) == "/" n'
  fi
}

# Resolves NAME to one path. Prints it, or explains and returns 1 (no
# match) or 2 (several matches: never a guess).
_dr_resolve() {
  local m n
  m=$(_dr_match "$1")
  n=$(printf '%s' "$m" | grep -c .)
  if [ "$n" = 1 ]; then
    printf '%s\n' "${m#*	}"
  elif [ "$n" = 0 ]; then
    echo "repo: no repository named '$1' under $(_dr_root)" >&2
    m=$(_dr_list | awk -F'\t' -v n="$1" 'index($1, n)' | cut -f1)
    [ -z "$m" ] || printf 'similar:\n%s\n' "$m" | sed '2,$s/^/  /' >&2
    return 1
  else
    echo "repo: '$1' is ambiguous; use one of:" >&2
    printf '%s\n' "$m" | cut -f1 | sed 's/^/  /' >&2
    return 2
  fi
}

# The ID of a repository path, from its main worktree. Outside the layout:
# other/<directory name>.
_dr_id_of() {
  local p=$1 root rel
  root=$(_dr_root)
  case $p in
    "$root"/*) rel=${p#"$root"/} ;;
    *) printf 'other/%s' "${p##*/}"; return ;;
  esac
  case $rel in
    personal/*/*/* | work/*/*/* | scratch/*/*) printf 'other/%s' "${p##*/}" ;;
    *) printf '%s' "$rel" ;;
  esac
}

# The main worktree of the repository here, also from a linked worktree.
# (--git-common-dir works with git 2.30; --path-format needs 2.31.)
_dr_toplevel() {
  local common
  common=$(command git rev-parse --git-common-dir 2>/dev/null) || return 1
  common=$(cd "$common" 2>/dev/null && pwd -P) || return 1
  case $common in
    */.git) printf '%s\n' "${common%/.git}" ;;
    *) command git rev-parse --show-toplevel ;;
  esac
}

# Session name: the ID, with the characters tmux does not allow in a name
# (. and :) replaced by _. (No variable is named "path": zsh ties it to PATH.)
_dr_session_name() { printf '%s' "$1" | tr '.:' '__'; }

# Attach to (or create) the session of repository PATH, ID; a CONTEXT opens
# or selects a window of that name. Never renames, closes or restarts.
_dr_tmux() {
  local detach=$1 rpath=$2 id=$3 ctx=$4 name other dir hash index
  command -v tmux >/dev/null 2>&1 || { echo "repo: tmux is not installed" >&2; return 1; }
  name=$(_dr_session_name "$id")
  if _dt_tmux has-session -t "=$name" 2>/dev/null; then
    other=$(_dt_tmux show-options -qv -t "=$name:" @dotfiles_repo 2>/dev/null)
    if [ "$other" != "$rpath" ]; then
      # The name belongs to another session (another path, or a session
      # made by hand). Use a name with a hash of the path instead.
      hash=$(printf '%s' "$rpath" | cksum | awk '{ printf "%06x", $1 % 16777216 }')
      name="$name-$hash"
      if _dt_tmux has-session -t "=$name" 2>/dev/null &&
        [ "$(_dt_tmux show-options -qv -t "=$name:" @dotfiles_repo 2>/dev/null)" != "$rpath" ]; then
        echo "repo: tmux sessions '$(_dr_session_name "$id")' and '$name' belong to other paths; not touched" >&2
        return 1
      fi
    fi
  fi
  if ! _dt_tmux has-session -t "=$name" 2>/dev/null; then
    _dt_tmux new-session -d -s "$name" -c "$rpath" || return
    _dt_tmux set-option -t "=$name:" @dotfiles_repo "$rpath"
    echo "created tmux session $name"
  fi
  if [ -n "$ctx" ]; then
    # Exact window name; the first match if there are several.
    index=$(_dt_tmux list-windows -t "=$name" -F '#{window_index} #{window_name}' |
      awk -v w="$ctx" 'substr($0, length($1) + 2) == w { print $1; exit }')
    if [ -n "$index" ]; then
      _dt_tmux select-window -t "=$name:$index"
    else
      dir=$rpath
      # A worktree for this context, if one exists (Story Status makes them).
      case $id in
        */*/*) [ -d "${rpath%/*}/.worktrees/${rpath##*/}/$ctx" ] && dir="${rpath%/*}/.worktrees/${rpath##*/}/$ctx" ;;
      esac
      _dt_tmux new-window -t "=$name:" -n "$ctx" -c "$dir" || return
      echo "added window $ctx in $dir"
    fi
  fi
  [ "$detach" = 1 ] || _dt_attach "$name"
}

if ! type repo >/dev/null 2>&1; then
  repo() {
    local p sel detach=0 name="" ctx=""
    case "${1:-}" in
      "")
        if command -v fzf >/dev/null 2>&1 && [ -t 0 ] && [ -t 1 ]; then
          sel=$(_dr_list | fzf --delimiter='	' --with-nth=1 --prompt='repo> ') || return 1
          cd "${sel#*	}" || return
        else
          _dr_list | awk -F'\t' '{ printf "%-40s %s\n", $1, $2 }'
        fi
        ;;
      list)
        _dr_list "${2:-}" | awk -F'\t' '{ printf "%-40s %s\n", $1, $2 }'
        ;;
      root)
        command git rev-parse --show-toplevel 2>/dev/null || { echo "repo: not inside a git repository" >&2; return 1; }
        ;;
      worktrees)
        if [ -n "${2:-}" ]; then p=$(_dr_resolve "$2") || return; else p=.; fi
        command git -C "$p" worktree list
        ;;
      tmux)
        shift
        if [ "${1:-}" = -d ]; then detach=1; shift; fi
        name=${1:-} ctx=${2:-}
        if [ -n "$name" ]; then
          p=$(_dr_resolve "$name") || return
        else
          p=$(_dr_toplevel) || { echo "repo tmux: not inside a git repository; give a name" >&2; return 1; }
          # In a linked worktree <repo>/../.worktrees/<repo>/<context>,
          # the context defaults to the worktree's name.
          if [ -z "$ctx" ]; then
            sel=$(cd "$(command git rev-parse --show-toplevel)" && pwd -P)
            case $sel in "${p%/*}/.worktrees/${p##*/}/"*) ctx=${sel##*/} ;; esac
          fi
        fi
        _dr_tmux "$detach" "$p" "$(_dr_id_of "$p")" "$ctx"
        ;;
      -h | --help | help)
        echo "usage: repo [list [--worktrees] | NAME | root | worktrees [NAME] | tmux [-d] [NAME] [CONTEXT]]"
        ;;
      *)
        p=$(_dr_resolve "$1") || return
        cd "$p" || return
        ;;
    esac
  }
fi
