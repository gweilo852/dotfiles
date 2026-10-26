#!/usr/bin/env bash
# Install the managed terminal configuration. Safe to run more than once.
# Run ./install.sh --help for options.
set -euo pipefail

DOTFILES_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$DOTFILES_DIR/scripts/lib.sh"

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

  -n, --dry-run          Show what would change. Change nothing.
  -y, --yes              Do not ask for confirmation.
      --no-packages      Do not install packages. Only link configuration.
      --release-binaries Install missing tools from pinned, checksum-verified
                         GitHub release archives into a user bin directory
                         (Linux, WSL and Unraid only).
      --windows-wezterm  WSL only: copy the WezTerm config to the Windows
                         user profile (%USERPROFILE%\.wezterm.lua).
      --unraid           Required on Unraid. Selects the minimal Unraid mode.
      --skip-validate    Do not run the validation step.
  -h, --help             Show this help.
EOF
}

ORIG_ARGS=("$@")
NO_PACKAGES=0 RELEASE_BINARIES=0 WINDOWS_WEZTERM=0 UNRAID_OK=0 VALIDATE=1
while [ $# -gt 0 ]; do
  case "$1" in
    -n | --dry-run) DRY_RUN=1 ;;
    -y | --yes) ASSUME_YES=1 ;;
    --no-packages) NO_PACKAGES=1 ;;
    --release-binaries) RELEASE_BINARIES=1 ;;
    --windows-wezterm) WINDOWS_WEZTERM=1 ;;
    --unraid) UNRAID_OK=1 ;;
    --skip-validate) VALIDATE=0 ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
  shift
done
export DRY_RUN ASSUME_YES DOTFILES_DIR TIMESTAMP

PLATFORM=$(detect_platform)
init_state_paths "$PLATFORM"
export DOTFILES_PLATFORM_DETECTED=$PLATFORM

info "dotfiles: $DOTFILES_DIR"
info "platform: $PLATFORM$([ "$DRY_RUN" = 1 ] && echo ' (dry run)')"

# --------------------------------------------------------------------
# Safety gates
# --------------------------------------------------------------------

case "$PLATFORM" in
  unraid)
    if [ "$UNRAID_OK" != 1 ]; then
      die "Unraid detected. Unraid mode must be selected explicitly: ./install.sh --unraid
See docs/installation.md#unraid before you continue."
    fi
    # $HOME and / live in RAM on Unraid, and /boot is FAT32 (no symlinks).
    case "$DOTFILES_DIR" in
      /mnt/*) ;;
      *) die "On Unraid the repository must live on persistent storage under /mnt
(for example /mnt/user/appdata/dotfiles). Current location: $DOTFILES_DIR" ;;
    esac
    NO_PACKAGES=1
    ;;
  unknown) die "unsupported platform: $DOTFILES_UNAME" ;;
  *)
    [ "$UNRAID_OK" = 1 ] && die "--unraid was given, but this machine is not Unraid"
    ;;
esac
[ "$WINDOWS_WEZTERM" = 1 ] && [ "$PLATFORM" != wsl ] && die "--windows-wezterm works only on WSL"
[ "$RELEASE_BINARIES" = 1 ] && [ "$PLATFORM" = macos ] && die "--release-binaries is for Linux; use Homebrew on macOS"

# Show the plan and ask before the first real change.
if [ "$DRY_RUN" != 1 ] && [ "$ASSUME_YES" != 1 ]; then
  [ -t 0 ] || die "not interactive: run with --dry-run to preview, then --yes to apply"
  "$DOTFILES_DIR/install.sh" --dry-run "${ORIG_ARGS[@]}"
  echo
  confirm "Apply these changes?" || die "cancelled; nothing changed"
  echo
fi

# --------------------------------------------------------------------
# Prerequisites and packages
# --------------------------------------------------------------------

info "prerequisites"
for tool in git curl; do
  if has "$tool"; then ok "$tool"; else warn "$tool not found"; fi
done

if [ "$NO_PACKAGES" = 1 ]; then
  info "packages: skipped"
else
  info "packages"
  case "$PLATFORM" in
    macos) "$DOTFILES_DIR/scripts/bootstrap-macos.sh" ;;
    linux | wsl) "$DOTFILES_DIR/scripts/bootstrap-linux.sh" ;;
  esac
fi

if [ "$RELEASE_BINARIES" = 1 ]; then
  info "release binaries"
  if [ "$PLATFORM" = unraid ]; then
    BIN_DIR="$DOTFILES_DIR/.local/bin" "$DOTFILES_DIR/scripts/install-release-binaries.sh"
  else
    BIN_DIR="$HOME/.local/bin" "$DOTFILES_DIR/scripts/install-release-binaries.sh"
  fi
fi

# --------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------

info "configuration"
C="$DOTFILES_DIR/config"

if [ "$PLATFORM" != unraid ] || has zsh; then
  link_file "$C/zsh/zshrc" "$HOME/.zshrc"
  migrate_zshrc "${LAST_BACKUP:-}"
fi

link_file "$C/starship/starship.toml" "${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml"
link_file "$C/tmux/tmux.conf" "$HOME/.tmux.conf"

case "$PLATFORM" in
  macos | linux)
    link_file "$C/wezterm/wezterm.lua" "${XDG_CONFIG_HOME:-$HOME/.config}/wezterm/wezterm.lua"
    ;;
esac

# Bash keeps the distribution's own ~/.bashrc and only adds a source line.
ensure_block "$HOME/.bashrc" bash "[ -r \"$C/bash/bashrc\" ] && . \"$C/bash/bashrc\""
if [ -f "$HOME/.bash_profile" ] && ! grep -q 'bashrc' "$HOME/.bash_profile"; then
  ensure_block "$HOME/.bash_profile" bash_profile \
    "case \$- in *i*) [ -r \"\$HOME/.bashrc\" ] && . \"\$HOME/.bashrc\" ;; esac"
fi

if has git; then
  if git config --global --get-all include.path 2>/dev/null | grep -qxF "$C/git/config"; then
    ok "git include $C/git/config"
  else
    backup=""
    if [ -f "$HOME/.gitconfig" ]; then
      backup=$(backup_path "$HOME/.gitconfig" copy) || die "cannot back up ~/.gitconfig"
      change "back up $HOME/.gitconfig -> $backup"
    fi
    run git config --global --add include.path "$C/git/config"
    change "add include.path $C/git/config to ~/.gitconfig"
    manifest_add gitinclude "$HOME/.gitconfig" "$C/git/config" "$backup"
  fi
else
  warn "git not found; git settings skipped"
fi

if [ "$WINDOWS_WEZTERM" = 1 ]; then
  winprofile=$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r') || true
  [ -n "$winprofile" ] || die "cannot find the Windows user profile"
  winhome=$(wslpath "$winprofile")
  copy_file "$C/wezterm/wezterm.lua" "$winhome/.wezterm.lua"
  [ -e "$winhome/.config/wezterm/wezterm.lua" ] &&
    warn "$winhome/.config/wezterm/wezterm.lua also exists; WezTerm reads ~/.wezterm.lua first"
fi

# --------------------------------------------------------------------
# Validation and summary
# --------------------------------------------------------------------

if [ "$DRY_RUN" != 1 ] && [ "$VALIDATE" = 1 ]; then
  info "validation"
  "$DOTFILES_DIR/scripts/doctor.sh" --quick || WARNINGS=$((WARNINGS + 1))
fi

echo
if [ "$DRY_RUN" = 1 ]; then
  info "dry run: $CHANGES change(s) planned, $WARNINGS warning(s). Nothing changed."
else
  info "done: $CHANGES change(s), $WARNINGS warning(s)"
  [ -d "$BACKUP_DIR" ] && echo "  backups:  $BACKUP_DIR"
  echo "  manifest: $MANIFEST"
  echo "  local settings (never managed): ~/.zshrc.local, ~/.config/wezterm/wezterm_local.lua"
  echo "  start a new shell to load the configuration: exec \$SHELL -l"
  if [ "$PLATFORM" = unraid ]; then
    echo
    echo "  Unraid: \$HOME resets at boot. To relink at boot, see"
    echo "  $DOTFILES_DIR/platforms/unraid/user-script.sh (nothing was added to /boot)."
  fi
fi
