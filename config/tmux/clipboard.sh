#!/bin/sh
# Copy standard input to the system clipboard of this machine.
# Called by tmux copy mode (config/tmux/tmux.conf). tmux also sends every
# copy to the terminal with OSC 52, so this helper is only the local path.
#
#   clipboard.sh            copy stdin with the first usable backend
#   clipboard.sh --detect   print the backend name and exit
#
# Backends, in order: pbcopy (macOS), wl-copy (Wayland), xclip or xsel
# (X11), clip.exe (WSL). Without one, input is discarded and the exit
# status is 0, so headless systems need nothing installed.
# DOTFILES_SYSROOT and DOTFILES_UNAME are test hooks.

has() { command -v "$1" >/dev/null 2>&1; }

detect() {
  if [ "${DOTFILES_UNAME:-$(uname -s)}" = Darwin ] && has pbcopy; then
    echo pbcopy
  elif [ -n "${WAYLAND_DISPLAY:-}" ] && has wl-copy; then
    echo wl-copy
  elif [ -n "${DISPLAY:-}" ] && has xclip; then
    echo xclip
  elif [ -n "${DISPLAY:-}" ] && has xsel; then
    echo xsel
  elif { [ -n "${WSL_DISTRO_NAME:-}" ] ||
    grep -qi microsoft "${DOTFILES_SYSROOT:-}/proc/version" 2>/dev/null; } && has clip.exe; then
    echo clip.exe
  else
    echo none
  fi
}

backend=$(detect)
if [ "${1:-}" = --detect ]; then
  echo "$backend"
  exit 0
fi

case "$backend" in
  pbcopy) exec pbcopy ;;
  wl-copy) exec wl-copy ;;
  xclip) exec xclip -selection clipboard -in ;;
  xsel) exec xsel --clipboard --input ;;
  clip.exe) exec clip.exe ;;
  *) cat >/dev/null ;;
esac
