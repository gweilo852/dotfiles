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
      --interactive-zsh  Start zsh from interactive bash and in new tmux
                         windows, for an account whose login shell must stay
                         bash (Active Directory). Sets
                         DOTFILES_INTERACTIVE_ZSH=1 in
                         ~/.config/dotfiles/local.conf. Not on Unraid.
      --no-interactive-zsh
                         Remove that setting again (back up first).
      --skip-validate    Do not run the validation step.
  -h, --help             Show this help.
EOF
}

ORIG_ARGS=("$@")
NO_PACKAGES=0 RELEASE_BINARIES=0 WINDOWS_WEZTERM=0 UNRAID_OK=0 VALIDATE=1
INTERACTIVE_ZSH="" # 1 = turn on, 0 = turn off, empty = leave as it is
while [ $# -gt 0 ]; do
  case "$1" in
    -n | --dry-run) DRY_RUN=1 ;;
    -y | --yes) ASSUME_YES=1 ;;
    --no-packages) NO_PACKAGES=1 ;;
    --release-binaries) RELEASE_BINARIES=1 ;;
    --windows-wezterm) WINDOWS_WEZTERM=1 ;;
    --unraid) UNRAID_OK=1 ;;
    --interactive-zsh) INTERACTIVE_ZSH=1 ;;
    --no-interactive-zsh) INTERACTIVE_ZSH=0 ;;
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
info "system:   $(detect_distro)"

# --------------------------------------------------------------------
# Safety gates
# --------------------------------------------------------------------

case "$PLATFORM" in
  unraid)
    if [ "$UNRAID_OK" != 1 ]; then
      die "Unraid detected. Unraid mode must be selected explicitly: ./install.sh --unraid
See docs/installation.md#unraid before you continue."
    fi
    [ "$INTERACTIVE_ZSH" = 1 ] && die "--interactive-zsh is not available on Unraid; Unraid uses bash"
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
    macos) "$DOTFILES_DIR/scripts/bootstrap-macos.sh" || warn "package installation incomplete; continuing" ;;
    linux | wsl) "$DOTFILES_DIR/scripts/bootstrap-linux.sh" || warn "package installation incomplete; continuing" ;;
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

# zsh configuration only where zsh exists; bash is configured everywhere.
if has zsh; then
  link_file "$C/zsh/zshrc" "$HOME/.zshrc"
  migrate_zshrc "${LAST_BACKUP:-}"
  # Ubuntu (and ID_LIKE=ubuntu) /etc/zsh/zshrc runs its own compinit,
  # without -i, unless ~/.zshenv sets skip_global_compinit. That is a second
  # compinit, and it prompts or aborts on insecure directories. The same
  # condition as in that file; Debian and others are not affected.
  if grep -qs skip_global_compinit "$DOTFILES_SYSROOT/etc/zsh/zshrc" &&
    grep -qsE '^ID(_LIKE)?=.*ubuntu' "$DOTFILES_SYSROOT/etc/os-release"; then
    ensure_block "$HOME/.zshenv" zshenv "skip_global_compinit=1 # compinit runs once, in the managed ~/.zshrc"
  fi
else
  info "  zsh not installed: zsh configuration skipped (bash is configured)"
fi

link_file "$C/starship/starship.toml" "${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml"
link_file "$C/tmux/tmux.conf" "$HOME/.tmux.conf"

# WezTerm runs on the machine you type on. A headless Linux host (a VDI
# reached over SSH) does not need its config.
if [ "$PLATFORM" = macos ] || { [ "$PLATFORM" = linux ] && has wezterm; }; then
  link_file "$C/wezterm/wezterm.lua" "${XDG_CONFIG_HOME:-$HOME/.config}/wezterm/wezterm.lua"
fi

# Bash keeps the distribution's own ~/.bashrc and only adds a source line.
ensure_block "$HOME/.bashrc" bash "[ -r \"$C/bash/bashrc\" ] && . \"$C/bash/bashrc\""

# A bash login shell (SSH) reads one profile file and not ~/.bashrc. Most
# distributions' ~/.profile already loads ~/.bashrc; if the file that bash
# reads does not, add a block. The guard keeps sh and dash out, because
# they also read ~/.profile. With --interactive-zsh and no profile file at
# all, create ~/.profile, because the handoff starts from ~/.bashrc.
login_file=$(bash_login_file)
if [ -z "$login_file" ] && [ "$INTERACTIVE_ZSH" = 1 ]; then
  login_file="$HOME/.profile"
fi
if [ -n "$login_file" ] && ! grep -q 'bashrc' "$login_file" 2>/dev/null; then
  ensure_block "$login_file" bash_profile \
    "case \$- in *i*) [ -n \"\${BASH_VERSION:-}\" ] && [ -r \"\$HOME/.bashrc\" ] && . \"\$HOME/.bashrc\" ;; esac"
fi

# Interactive zsh handoff: a machine-local setting, in a marked block.
case "$INTERACTIVE_ZSH" in
  1)
    has zsh || warn "zsh not found; the handoff stays inactive until zsh is on PATH or DOTFILES_ZSH is set"
    ensure_block "$LOCAL_CONF" interactive-zsh "# Interactive bash and new tmux windows start zsh. The login shell stays.
# Turn off: ./install.sh --no-interactive-zsh (docs/active-directory.md)
DOTFILES_INTERACTIVE_ZSH=1"
    ;;
  0)
    if [ -f "$LOCAL_CONF" ] && grep -qF "$(block_begin interactive-zsh)" "$LOCAL_CONF"; then
      backup=$(backup_path "$LOCAL_CONF" copy) || die "cannot back up $LOCAL_CONF"
      change "back up $LOCAL_CONF -> $backup"
      [ "$DRY_RUN" = 1 ] || remove_block "$LOCAL_CONF" interactive-zsh
      change "remove interactive-zsh block from $LOCAL_CONF"
    else
      ok "interactive zsh handoff: no managed setting in $LOCAL_CONF"
    fi
    outside=$(awk -v b="$(block_begin interactive-zsh)" -v e="$(block_end interactive-zsh)" '
      $0 == b { s = 1; next } $0 == e { s = 0; next }
      !s && /^[[:space:]]*(export[[:space:]]+)?DOTFILES_INTERACTIVE_ZSH=/ { print NR }
    ' "$LOCAL_CONF" 2>/dev/null | paste -sd, -)
    [ -z "$outside" ] || warn "$LOCAL_CONF line(s) $outside set DOTFILES_INTERACTIVE_ZSH outside the managed block; edit them by hand"
    ;;
esac

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
  # shellcheck source=config/shell/zsh-handoff.sh
  . "$C/shell/zsh-handoff.sh"
  if _dotfiles_zsh_handoff_target; then
    echo "  interactive zsh handoff: on ($_dotfiles_zsh). Log in again; \$SHELL still shows bash."
  else
    echo "  interactive zsh handoff: $_dotfiles_zsh_why"
  fi
  echo "  start a new shell to load the configuration: exec \$SHELL -l"
  if [ "$PLATFORM" = unraid ]; then
    echo
    echo "  Unraid: \$HOME resets at boot. To relink at boot, see"
    echo "  $DOTFILES_DIR/platforms/unraid/user-script.sh (nothing was added to /boot)."
  fi
fi
