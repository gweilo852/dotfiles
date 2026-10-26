#!/usr/bin/env bash
# Install macOS dependencies with Homebrew. Called by install.sh.
# Never runs a remote install script: without Homebrew it stops with advice.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if ! has brew; then
  warn "Homebrew not found. Install it from https://brew.sh, then run install.sh again."
  exit 0
fi
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1

brewfile="$DOTFILES_DIR/platforms/macos/Brewfile"
if brew bundle check --no-upgrade --file "$brewfile" >/dev/null 2>&1; then
  ok "Homebrew packages (platforms/macos/Brewfile)"
else
  brew bundle check --no-upgrade --verbose --file "$brewfile" 2>/dev/null |
    sed -n 's/^→ /  missing: /p' || true
  run brew bundle install --no-upgrade --file "$brewfile"
  change "install missing Homebrew packages"
fi

if [ -d /Applications/WezTerm.app ] || [ -d "$HOME/Applications/WezTerm.app" ]; then
  ok "WezTerm.app"
else
  run brew install --cask wezterm
  change "install WezTerm"
fi
