#!/usr/bin/env bash
# Read-only checks before a first install, for a VDI or any new machine.
# Changes nothing and prints no secret values (only whether a variable is set).
#   scripts/preflight.sh
set -uo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PLATFORM=$(detect_platform)
init_state_paths "$PLATFORM"
note() { printf '  %s\n' "$*"; }

info "system"
ok "platform: $PLATFORM"
ok "distribution: $(detect_distro)"
ok "kernel: $(uname -sr), CPU: $(uname -m)"
if [ "$DOTFILES_UNAME" = Linux ] && has ldd; then
  ok "libc: $(ldd --version 2>&1 | head -n 1)"
fi
ok "user: $(id -un), login shell: ${SHELL:-unknown}, running: $(ps -o comm= -p "$PPID" 2>/dev/null | sed 's/^-//')"
# A directory account (Active Directory, LDAP) is not in /etc/passwd, and
# chsh cannot change its login shell. The handoff starts zsh from bash.
# Exact field match: directory names can contain regex characters (DOMAIN\user).
if [ "$DOTFILES_UNAME" = Linux ] && [ -r /etc/passwd ] &&
  ! DF_USER=$(id -un) awk -F: '$1 == ENVIRON["DF_USER"] { found = 1 } END { exit !found }' /etc/passwd; then
  login=$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7)
  note "directory account (not in /etc/passwd), login shell ${login:-unknown}: chsh cannot change it."
  note "To use zsh anyway: ./install.sh --interactive-zsh (docs/active-directory.md)"
fi
ok "package manager: $(detect_pkg_manager)"
if [ "$(id -u)" = 0 ]; then
  ok "running as root"
elif ! has sudo; then
  warn "no sudo: use --no-packages --release-binaries"
elif sudo -n true 2>/dev/null; then
  ok "sudo works without a password"
else
  note "sudo needs a password, or is not allowed. Without rights, use --no-packages --release-binaries."
fi

info "session"
if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
  ok "graphical session (DISPLAY or WAYLAND_DISPLAY set)"
else
  ok "no graphical session (expected over SSH); clipboard uses OSC 52"
fi
[ -n "${SSH_CONNECTION:-}" ] && ok "connected over SSH"
ok "TERM=${TERM:-unset}"
case "${LANG:-}${LC_ALL:-}" in
  *UTF-8* | *utf8* | *UTF8*) ok "UTF-8 locale" ;;
  *) warn "no UTF-8 locale (LANG=${LANG:-unset}); prompt icons may break. Try: export LANG=C.UTF-8" ;;
esac
if [ -n "${TMUX:-}" ]; then ok "inside tmux"; fi
for v in http_proxy https_proxy HTTPS_PROXY no_proxy; do
  [ -n "${!v:-}" ] && ok "$v is set (value not shown)"
done

info "home directory"
if [ -w "$HOME" ]; then ok "$HOME is writable"; else warn "$HOME is not writable"; fi
if has df; then
  avail=$(df -Pk "$HOME" 2>/dev/null | awk 'NR == 2 {print int($4 / 1024)}')
  [ -n "$avail" ] && ok "free space in home: ${avail} MB"
fi
for f in .zshrc .zprofile .zshenv .bashrc .bash_profile .profile .tmux.conf .config/starship.toml .gitconfig; do
  t="$HOME/$f"
  if [ -L "$t" ]; then
    note "~/$f is a symlink to $(readlink "$t")"
  elif [ -e "$t" ]; then
    note "~/$f exists ($(wc -l <"$t" | tr -d ' ') lines); backed up before any change"
  fi
done
[ -f "$MANIFEST" ] && note "already installed once: $MANIFEST"
[ -d "$HOME/.oh-my-zsh" ] && note "~/.oh-my-zsh exists; it is left in place"

info "tools (all optional)"
for tool in git curl zsh tmux starship fzf zoxide eza bat batcat delta duf infocmp; do
  if has "$tool"; then
    ver=$("$tool" --version 2>/dev/null | head -n 1)
    [ "$tool" = tmux ] && ver=$(tmux -V)
    ok "$tool ${_c_dim}${ver}${_c_off}"
  else
    note "missing: $tool"
  fi
done
if has tmux; then
  v=$(tmux -V | sed 's/[^0-9.]*\([0-9][0-9.]*\).*/\1/')
  case "$v" in
    1.* | 2.[0-5] | 2.[0-5].*) warn "tmux $v is older than 2.6; the tmux config needs 2.6 or later" ;;
    2.* | 3.[01] | 3.[01].*) note "tmux $v works; 3.2 or later is recommended" ;;
  esac
  infocmp tmux-256color >/dev/null 2>&1 || note "no tmux-256color terminfo; tmux uses screen-256color"
fi
ok "clipboard backend: $(sh "$DOTFILES_DIR/config/tmux/clipboard.sh" --detect)"

echo
info "next: ./install.sh --dry-run   (add --no-packages --release-binaries without root)"
