# shellcheck shell=bash
# Shared environment for interactive zsh and bash. Sourced by both rc files.
# Each value is a default: a value set earlier, or in a local file, wins.

export EDITOR="${EDITOR:-vim}"
export PAGER="${PAGER:-less}"
export LESS="${LESS:--FRX}"

# bat and delta use the terminal's own 16 colours, so they follow the
# low-glare Catppuccin Macchiato palette in WezTerm.
export BAT_THEME="${BAT_THEME:-ansi}"

# Muted Catppuccin Macchiato colours for fzf. The background follows the
# terminal. Only colour names that old fzf versions accept are used.
export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:---height=40% --layout=reverse --border=rounded --info=inline \
--color=fg:#b8c0d9,hl:#ed8796,fg+:#cad3f5,bg+:#363a4f,hl+:#ed8796 \
--color=info:#c6a0f6,prompt:#c6a0f6,pointer:#f4dbd6,marker:#b7bdf8,spinner:#f4dbd6,header:#8aadf4,border:#494d64}"

if command -v fd >/dev/null 2>&1; then
  export FZF_DEFAULT_COMMAND="${FZF_DEFAULT_COMMAND:-fd --type f --hidden --exclude .git}"
  export FZF_CTRL_T_COMMAND="${FZF_CTRL_T_COMMAND:-$FZF_DEFAULT_COMMAND}"
fi

# Ctrl+T previews files with bat (or batcat on Debian). Alt+C previews
# directories with eza. Both fall back to plain tools.
export FZF_CTRL_T_OPTS="${FZF_CTRL_T_OPTS:---preview '(bat --color=always --style=numbers --line-range=:200 {} || batcat --color=always --style=numbers --line-range=:200 {} || cat {}) 2>/dev/null'}"
export FZF_ALT_C_OPTS="${FZF_ALT_C_OPTS:---preview '(eza --tree --level=2 --icons=always --color=always {} || ls -la {}) 2>/dev/null'}"

# Label for the tmux status bar. Set it in a local file to override.
if [ -z "${TMUX_HOST_LABEL:-}" ]; then
  TMUX_HOST_LABEL=$(hostname 2>/dev/null | cut -d. -f1 | tr '[:lower:]' '[:upper:]')
  export TMUX_HOST_LABEL
fi
