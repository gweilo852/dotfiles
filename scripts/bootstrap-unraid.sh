#!/usr/bin/env bash
# Unraid preflight and install. Run from the repository on persistent
# storage, for example /mnt/user/appdata/dotfiles.
#
# What it does: checks the environment, then runs install.sh --unraid,
# which links the bash, Starship and tmux configuration into $HOME (RAM)
# and keeps state and backups next to the repository.
# What it never does: install packages, write to /boot, or change the
# Unraid boot configuration (/boot/config/go).
#
# Extra options are passed to install.sh, for example --dry-run or
# --release-binaries.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ "$(detect_platform)" = unraid ] || die "this is not an Unraid server"

info "Unraid preflight"
ok "Unraid $(sed -n 's/^version="\(.*\)"/\1/p' /etc/unraid-version 2>/dev/null)"
case "$DOTFILES_DIR" in
  /mnt/*) ok "repository on persistent storage: $DOTFILES_DIR" ;;
  *) die "move the repository under /mnt (not /root or /boot): $DOTFILES_DIR" ;;
esac
for tool in bash git tmux starship zoxide fzf eza bat; do
  if has "$tool" || [ -x "$DOTFILES_DIR/.local/bin/$tool" ]; then ok "$tool"; else info "  optional, missing: $tool"; fi
done
echo

exec "$DOTFILES_DIR/install.sh" --unraid "$@"
