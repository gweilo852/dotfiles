# Native zsh completion. compinit runs once per shell.

typeset -g _dotfiles_zcache=${XDG_CACHE_HOME:-$HOME/.cache}/zsh
[[ -d $_dotfiles_zcache/completions ]] || mkdir -p $_dotfiles_zcache/completions
fpath=(
  $_dotfiles_zcache/completions
  ${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/share/zsh/site-functions}
  $fpath
)

# Cache completion scripts that CLIs generate, so a new shell does not run
# `kubectl completion zsh` (about 100 ms) every time. A cached file is
# rebuilt when the binary is newer. To rebuild all: refresh-completions
_dotfiles_cache_completion() { # name, generator command...
  local name=$1 bin=${commands[$1]} out=$_dotfiles_zcache/completions/_$1
  shift
  [[ -n $bin ]] || return 0
  if [[ ! -s $out || $bin -nt $out ]]; then
    "$@" >| $out.tmp 2>/dev/null && mv -f $out.tmp $out || rm -f $out.tmp
  fi
}
_dotfiles_cache_completion kubectl kubectl completion zsh
_dotfiles_cache_completion helm helm completion zsh

refresh-completions() {
  rm -f $_dotfiles_zcache/completions/_* $_dotfiles_zcache/zcompdump-*
  exec zsh
}

# Full security check (compaudit) at most once a day; otherwise trust the
# cached dump. -i skips insecure directories instead of prompting.
autoload -Uz compinit
() {
  setopt local_options extended_glob
  local dump=$_dotfiles_zcache/zcompdump-$ZSH_VERSION
  if [[ -n $dump(#qN.mh-24) ]]; then
    compinit -C -d $dump
  else
    compinit -i -d $dump
  fi
}

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{8}-- %d --%f'
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path $_dotfiles_zcache/compcache

# Completion for tools whose scripts need compinit first.
(( $+commands[kubecolor] )) && compdef kubecolor=kubectl
for _f in $HOME/google-cloud-sdk/completion.zsh.inc \
  ${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/share/google-cloud-sdk/completion.zsh.inc}; do
  [[ -r $_f ]] && { source $_f; break; }
done
unset _f
