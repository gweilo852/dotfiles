# Plugins and prompt. Each loads once, even if this file is sourced again,
# and a missing tool is skipped without an error.

_dotfiles_source_first() {
  local f
  for f in "$@"; do
    [[ -r $f ]] && { source $f; return 0; }
  done
  return 1
}

# Where packages put zsh plugins: Homebrew, Debian/Fedora, Arch, manual.
typeset -ga _dotfiles_plugin_dirs=(
  ${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/share}
  /usr/share /usr/share/zsh/plugins /usr/local/share
  $HOME/.local/share/zsh/plugins
)

# fzf: Ctrl+R history, Ctrl+T files, Alt+C directories.
# fzf 0.48+ prints its own shell integration; older versions ship files.
# Key bindings need a terminal; without one (zsh -i -c ...) they are skipped.
if (( $+commands[fzf] )) && [[ -t 0 ]] && (( ! $+widgets[fzf-history-widget] )); then
  if _dotfiles_init=$(fzf --zsh 2>/dev/null); then
    eval "$_dotfiles_init"
  else
    _dotfiles_source_first /usr/share/doc/fzf/examples/key-bindings.zsh \
      /usr/share/fzf/key-bindings.zsh /usr/share/fzf/shell/key-bindings.zsh
    _dotfiles_source_first /usr/share/doc/fzf/examples/completion.zsh \
      /usr/share/fzf/completion.zsh
  fi
  unset _dotfiles_init
fi

# zoxide: z <part of a path>, zi for an interactive list.
if (( $+commands[zoxide] )) && (( ! $+functions[__zoxide_z] )); then
  eval "$(zoxide init zsh)"
fi

# Autosuggestions: grey text from history; Right arrow accepts it.
if (( ! $+functions[_zsh_autosuggest_start] )); then
  : ${ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE:='fg=#6e738d'}
  : ${ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE:=40}
  _dotfiles_source_first ${^_dotfiles_plugin_dirs}/zsh-autosuggestions/zsh-autosuggestions.zsh
fi

# Prompt. Without starship, use a plain two-line prompt.
if (( $+commands[starship] )); then
  (( $+functions[prompt_starship_precmd] || $+functions[starship_precmd] )) || eval "$(starship init zsh)"
else
  PROMPT=$'\n%F{blue}%~%f\n%(?.%F{green}.%F{red})❯%f '
fi

# Syntax highlighting must load last, after every other widget exists.
if (( ! $+functions[_zsh_highlight] )); then
  if _dotfiles_source_first ${^_dotfiles_plugin_dirs}/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh; then
    ZSH_HIGHLIGHT_STYLES[comment]='fg=#6e738d'
  fi
fi
