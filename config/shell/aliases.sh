# shellcheck shell=bash
# Shared aliases for interactive zsh and bash. Aliases do not apply in
# scripts, so scripts always get the standard commands. To bypass an alias
# at the prompt, use `command ls` or `\ls`.

_dotfiles_has() { command -v "$1" >/dev/null 2>&1; }

# Debian and Ubuntu install bat as batcat.
if ! _dotfiles_has bat && _dotfiles_has batcat; then
  alias bat='batcat'
fi

# File listings: eza when present, otherwise ls with colour.
if _dotfiles_has eza; then
  alias ls='eza --icons=auto --color=auto --group-directories-first'
  alias ll='eza -lah --icons=auto --color=auto --group-directories-first'
  alias la='eza -a --icons=auto --color=auto --group-directories-first'
  alias lt='eza --tree --level=2 --icons=auto'
else
  if command ls --color=auto -d . >/dev/null 2>&1; then
    alias ls='ls --color=auto'
  else
    alias ls='ls -G'
  fi
  alias ll='ls -lah'
  alias la='ls -A'
  if _dotfiles_has tree; then alias lt='tree -L 2'; else alias lt='find . -maxdepth 2'; fi
fi

# Print a file with highlighting and no pager.
if _dotfiles_has bat || _dotfiles_has batcat; then
  alias catp='bat --paging=never'
else
  alias catp='cat'
fi

alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'

# Kubernetes. `k` uses kubecolor when it is installed.
if _dotfiles_has kubectl; then
  alias ku='kubectl'
  if _dotfiles_has kubecolor; then alias k='kubecolor'; else alias k='kubectl'; fi
fi
_dotfiles_has kubectx && alias ktx='kubectx'
_dotfiles_has kubens && alias kn='kubens'

unset -f _dotfiles_has
