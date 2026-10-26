#!/usr/bin/env bash
# Check the installed configuration on this machine. Changes nothing.
#   scripts/doctor.sh          full check, including shell startup time
#   scripts/doctor.sh --quick  skip the slower checks
# Exit status is 1 when an error is found. Warnings do not fail.
set -uo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

QUICK=0
[ "${1:-}" = --quick ] && QUICK=1
ERRORS=0
bad() {
  ERRORS=$((ERRORS + 1))
  printf '  %sfail%s %s\n' "$_c_red" "$_c_off" "$*"
}

PLATFORM=$(detect_platform)
init_state_paths "$PLATFORM"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
C="$DOTFILES_DIR/config"
WEZTERM=$(command -v wezterm 2>/dev/null || true)
[ -z "$WEZTERM" ] && [ -x /Applications/WezTerm.app/Contents/MacOS/wezterm ] &&
  WEZTERM=/Applications/WezTerm.app/Contents/MacOS/wezterm

info "platform: $PLATFORM, $(detect_distro) ($DOTFILES_DIR)"

# --------------------------------------------------------------------
info "tools"
for tool in zsh starship zoxide fzf eza bat delta duf tmux git; do
  path=$(command -v "$tool" 2>/dev/null || true)
  [ -z "$path" ] && [ "$tool" = bat ] && path=$(command -v batcat 2>/dev/null || true)
  [ -z "$path" ] && [ -x "$DOTFILES_DIR/.local/bin/$tool" ] && path="$DOTFILES_DIR/.local/bin/$tool"
  # Release binaries: the managed bash and zsh configuration add
  # ~/.local/bin to PATH, also when the shell that runs this check has not.
  [ -z "$path" ] && [ -x "$HOME/.local/bin/$tool" ] && path="$HOME/.local/bin/$tool (on PATH in new shells)"
  if [ -n "$path" ]; then
    ok "$tool  ${_c_dim}$path${_c_off}"
  else
    warn "$tool not found (optional; the configuration falls back without it)"
  fi
done
if [ "$PLATFORM" = macos ]; then
  font=""
  for f in "$HOME"/Library/Fonts/CaskaydiaMono*Nerd* /Library/Fonts/CaskaydiaMono*Nerd*; do
    [ -e "$f" ] && font=$f
  done
  if [ -n "$font" ]; then
    ok "CaskaydiaMono Nerd Font"
  else
    warn "CaskaydiaMono Nerd Font not installed: brew install --cask font-caskaydia-mono-nerd-font"
  fi
fi

# --------------------------------------------------------------------
info "links"
check_link() { # source target
  if [ -L "$2" ] && [ "$(readlink "$2")" = "$1" ]; then
    ok "$2"
  elif [ -e "$2" ] || [ -L "$2" ]; then
    warn "$2 exists but is not managed (run install.sh to replace it)"
  else
    warn "$2 missing (run install.sh)"
  fi
}
if has zsh; then check_link "$C/zsh/zshrc" "$HOME/.zshrc"; fi
check_link "$C/starship/starship.toml" "$CFG/starship.toml"
check_link "$C/tmux/tmux.conf" "$HOME/.tmux.conf"
if [ "$PLATFORM" = macos ] || { [ "$PLATFORM" = linux ] && has wezterm; }; then
  check_link "$C/wezterm/wezterm.lua" "$CFG/wezterm/wezterm.lua"
  [ -e "$HOME/.wezterm.lua" ] && warn "~/.wezterm.lua exists and overrides $CFG/wezterm/wezterm.lua"
fi
if grep -qF "$(block_begin bash)" "$HOME/.bashrc" 2>/dev/null; then ok "~/.bashrc block"; else warn "~/.bashrc block missing"; fi
if has git; then
  if git config --global --get-all include.path 2>/dev/null | grep -qxF "$C/git/config"; then
    ok "git include"
  else
    warn "git include missing"
  fi
fi

# --------------------------------------------------------------------
info "duplicate or obsolete initialization"
# Active (uncommented) lines only. ~/.zshrc itself is the managed file.
for f in "$HOME/.zshrc.local" "$HOME/.zprofile" "$HOME/.zshenv"; do
  [ -f "$f" ] || continue
  hits=$(grep -nE '^[[:space:]]*[^#:[:space:]].*(starship init|oh-my-zsh\.sh|ZSH_THEME=|compinit|zoxide init|fzf --zsh|zsh-autosuggestions\.zsh|zsh-syntax-highlighting\.zsh|kube_ps1|kube-ps1|iterm2_shell_integration)' "$f" 2>/dev/null | cut -d: -f1 | paste -sd, -)
  if [ -n "$hits" ]; then
    warn "$f repeats managed initialization on line(s) $hits"
  else
    ok "$f"
  fi
  dup=$(grep -E '^(eval|source|\.|export|path=|fpath=)' "$f" | sort | uniq -d | head -n 1)
  [ -n "$dup" ] && warn "$f has a duplicated line: $(printf '%s' "$dup" | cut -c1-60)"
done
if [ -f "$HOME/.zshrc.local" ] && grep -qiE '(token|secret|password|api_key)[a-z_]*=' "$HOME/.zshrc.local"; then
  mode=$(ls -l "$HOME/.zshrc.local" | cut -c1-10)
  case "$mode" in
    -rw-------) ok "~/.zshrc.local holds credentials and is private (600)" ;;
    *) warn "~/.zshrc.local holds credentials but is $mode; run chmod 600 ~/.zshrc.local" ;;
  esac
fi
[ -d "$HOME/.oh-my-zsh" ] && info "  note: ~/.oh-my-zsh is still on disk but unused; remove it when you no longer need it"

# --------------------------------------------------------------------
info "configuration syntax"
if has zsh; then
  for f in "$C/zsh/zshrc" "$C/zsh/completion.zsh" "$C/zsh/plugins.zsh"; do
    zsh -n "$f" 2>/dev/null && ok "zsh -n ${f#"$DOTFILES_DIR"/}" || bad "zsh syntax: $f"
  done
fi
for f in "$C/bash/bashrc" "$C/shell/env.sh" "$C/shell/aliases.sh"; do
  bash -n "$f" 2>/dev/null && ok "bash -n ${f#"$DOTFILES_DIR"/}" || bad "bash syntax: $f"
done
if has starship; then
  err=$(STARSHIP_CONFIG="$C/starship/starship.toml" starship print-config 2>&1 >/dev/null)
  [ -z "$err" ] && ok "starship.toml" || bad "starship.toml: $err"
fi
if [ -n "$WEZTERM" ]; then
  err=$("$WEZTERM" --config-file "$C/wezterm/wezterm.lua" ls-fonts 2>&1 | grep -E 'ERROR|WARN' | head -n 3)
  [ -z "$err" ] && ok "wezterm.lua" || bad "wezterm.lua: $err"
fi
if has tmux; then
  sock="dotfiles-doctor-$$"
  if DOTFILES_TMUX_DIR="$C/tmux" tmux -L "$sock" -f "$C/tmux/tmux.conf" new-session -d true 2>/dev/null; then ok "tmux.conf"; else bad "tmux.conf failed to load"; fi
  tmux -L "$sock" kill-server 2>/dev/null
fi

# --------------------------------------------------------------------
info "tmux"
if has tmux; then
  v=$(tmux -V | sed 's/[^0-9.]*\([0-9][0-9.]*\).*/\1/')
  case "$v" in
    1.* | 2.[0-5] | 2.[0-5].*) bad "tmux $v is too old; 2.6 or later is needed" ;;
    2.* | 3.[01] | 3.[01].*) warn "tmux $v works; 3.2 or later is recommended" ;;
    *) ok "tmux $v" ;;
  esac
  infocmp tmux-256color >/dev/null 2>&1 && ok "tmux-256color terminfo" ||
    ok "no tmux-256color terminfo; screen-256color is used instead"
  [ -r "$HOME/.tmux.conf.local" ] && ok "~/.tmux.conf.local present (loaded last)"
  [ -n "${TMUX:-}" ] && ok "inside tmux session '$(tmux display -p '#S' 2>/dev/null)'"
else
  warn "tmux not installed (optional)"
fi
ok "clipboard backend for tmux copy: $(sh "$C/tmux/clipboard.sh" --detect) (plus OSC 52 to the terminal)"

# --------------------------------------------------------------------
info "shell"
# $SHELL is the account's login shell. It stays bash with the handoff on;
# the parent process is the shell that started this check.
login=$( (getent passwd "$(id -un)" 2>/dev/null ||
  DF_USER=$(id -un) awk -F: '$1 == ENVIRON["DF_USER"]' /etc/passwd 2>/dev/null) | cut -d: -f7 | head -n 1)
ok "login shell: ${login:-${SHELL:-unknown}}${login:+ (account)}, \$SHELL=${SHELL:-unset}"
ok "running from: $(ps -o comm= -p "$PPID" 2>/dev/null | sed 's/^-//')"
# shellcheck source=config/shell/zsh-handoff.sh
. "$C/shell/zsh-handoff.sh"
if _dotfiles_zsh_handoff_target; then
  ok "interactive zsh handoff: on ($_dotfiles_zsh, from $LOCAL_CONF)"
  "$_dotfiles_zsh" -f -c 'exit 0' 2>/dev/null || bad "$_dotfiles_zsh does not start; bash stays the shell"
  lf=$(bash_login_file)
  if [ -z "$lf" ]; then
    warn "no ~/.bash_profile, ~/.bash_login or ~/.profile: an SSH login does not read ~/.bashrc (run install.sh --interactive-zsh)"
  elif grep -q 'bashrc' "$lf"; then
    ok "SSH login path: $lf loads ~/.bashrc"
  else
    warn "$lf does not load ~/.bashrc, so an SSH login does not hand off (run install.sh)"
  fi
  [ "$PLATFORM" = unraid ] || [ "$(sh "$C/tmux/shell.sh" --print)" = "$_dotfiles_zsh" ] ||
    warn "tmux would not select $_dotfiles_zsh"
else
  ok "interactive zsh handoff: $_dotfiles_zsh_why"
fi

# --------------------------------------------------------------------
if has zsh && [ -L "$HOME/.zshrc" ]; then
  info "interactive zsh"
  # no_tty: an interactive shell must not take over this terminal.
  err=$(no_tty zsh -i -c exit 2>&1 >/dev/null)
  [ -z "$err" ] && ok "starts without errors" || bad "zsh startup output: $(printf '%s' "$err" | head -n 3)"
  n=$(no_tty zsh -i -c 'print -l $precmd_functions' 2>/dev/null | grep -c 'starship_precmd$')
  case "$n" in
    1) ok "prompt initialized once" ;;
    0) has starship && bad "starship prompt not initialized" ;;
    *) bad "starship initialized $n times" ;;
  esac
  if [ "$QUICK" = 0 ]; then
    start=$(perl -MTime::HiRes=time -e 'printf "%d", time*1000' 2>/dev/null || echo 0)
    for _ in 1 2 3; do no_tty zsh -i -c exit >/dev/null 2>&1; done
    end=$(perl -MTime::HiRes=time -e 'printf "%d", time*1000' 2>/dev/null || echo 0)
    [ "$start" != 0 ] && ok "startup time about $(((end - start) / 3)) ms"
  fi
fi

echo
if [ "$ERRORS" -gt 0 ]; then
  info "doctor: $ERRORS error(s), $WARNINGS warning(s)"
  exit 1
fi
info "doctor: no errors, $WARNINGS warning(s)"
