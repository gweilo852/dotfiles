#!/usr/bin/env bash
# Remove the managed configuration and restore backups.
# Removes only what install.sh recorded in its manifest. Packages, user
# files such as ~/.zshrc.local, and the backup directory are kept.
set -euo pipefail

DOTFILES_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$DOTFILES_DIR/scripts/lib.sh"

usage() {
  cat <<'EOF'
Usage: ./uninstall.sh [options]

  -n, --dry-run   Show what would change. Change nothing.
  -y, --yes       Do not ask for confirmation.
  -h, --help      Show this help.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -n | --dry-run) DRY_RUN=1 ;;
    -y | --yes) ASSUME_YES=1 ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
  shift
done

PLATFORM=$(detect_platform)
init_state_paths "$PLATFORM"
info "platform: $PLATFORM$([ "$DRY_RUN" = 1 ] && echo ' (dry run)')"

if [ "$DRY_RUN" != 1 ] && [ "$ASSUME_YES" != 1 ]; then
  [ -t 0 ] || die "not interactive: run with --dry-run to preview, then --yes to apply"
  "$DOTFILES_DIR/uninstall.sh" --dry-run
  echo
  confirm "Apply these changes?" || die "cancelled; nothing changed"
  echo
fi

DONE_TARGETS=""
seen() { case "$DONE_TARGETS" in *"|$1|"*) return 0 ;; esac; return 1; }
mark() { DONE_TARGETS="$DONE_TARGETS|$1|"; }

restore() { # $1 = target, $2 = backup
  [ -n "$2" ] || return 0
  if [ ! -e "$2" ] && [ ! -L "$2" ]; then
    warn "backup missing for $1: $2"
  elif [ -e "$1" ] || [ -L "$1" ]; then
    warn "$1 exists; backup not restored: $2"
  else
    run cp -pPR "$2" "$1"
    change "restore $1 from $2"
  fi
}

undo_link() { # target source backup
  if [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ]; then
    run rm "$1"
    change "remove link $1"
    restore "$1" "$3"
  elif [ -e "$1" ] || [ -L "$1" ]; then
    warn "$1 is not the managed link; left unchanged"
  else
    restore "$1" "$3"
  fi
}

undo_block() { # file marker
  if [ -f "$1" ] && grep -qF "$(block_begin "$2")" "$1"; then
    [ "$DRY_RUN" = 1 ] || remove_block "$1" "$2"
    change "remove $2 block from $1"
  fi
}

undo_gitinclude() { # source
  has git || return 0
  if git config --global --get-all include.path 2>/dev/null | grep -qxF "$1"; then
    # --fixed-value needs git 2.30+; older git takes an escaped regex.
    run git config --global --fixed-value --unset-all include.path "$1" 2>/dev/null ||
      run git config --global --unset-all include.path \
        "^$(printf '%s' "$1" | sed 's/[][\\.*^$/]/\\&/g')\$"
    change "remove include.path $1 from ~/.gitconfig"
  fi
}

undo_copy() { # target source backup
  if [ -f "$1" ] && cmp -s "$1" "$2"; then
    run rm "$1"
    change "remove copied file $1"
    restore "$1" "$3"
  elif [ -e "$1" ]; then
    warn "$1 differs from the managed copy; left unchanged"
  fi
}

if [ -f "$MANIFEST" ]; then
  info "undo changes recorded in $MANIFEST"
  # Newest entries first. Only the newest entry for each target is undone;
  # older backups stay in the backup directory.
  lines=$(awk '{ a[NR] = $0 } END { for (i = NR; i > 0; i--) print a[i] }' "$MANIFEST")
  while IFS=$'\t' read -r kind target src backup; do
    [ -n "$kind" ] || continue
    key="$kind:$target:$src"
    seen "$key" && continue
    mark "$key"
    case "$kind" in
      link) undo_link "$target" "$src" "$backup" ;;
      block) undo_block "$target" "$src" ;;
      gitinclude) undo_gitinclude "$src" ;;
      copy) undo_copy "$target" "$src" "$backup" ;;
      *) warn "unknown manifest entry: $kind" ;;
    esac
  done <<<"$lines"
  if [ "$DRY_RUN" != 1 ]; then
    mv "$MANIFEST" "$MANIFEST.uninstalled-$TIMESTAMP"
  fi
else
  # No manifest (for example after an Unraid reboot): remove only links
  # that point into this repository, and our marked blocks. Restore nothing.
  info "no manifest found; removing links into $DOTFILES_DIR only"
  for t in "$HOME/.zshrc" "$HOME/.tmux.conf" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/wezterm/wezterm.lua"; do
    if [ -L "$t" ]; then
      case "$(readlink "$t")" in
        "$DOTFILES_DIR"/*) run rm "$t"; change "remove link $t" ;;
      esac
    fi
  done
  undo_block "$HOME/.bashrc" bash
  undo_block "$HOME/.bash_profile" bash_profile
  undo_gitinclude "$DOTFILES_DIR/config/git/config"
fi

echo
info "$CHANGES change(s), $WARNINGS warning(s)$([ "$DRY_RUN" = 1 ] && echo '; nothing changed')"
echo "  kept: packages, ~/.zshrc.local, wezterm_local.lua, and backups in $BACKUP_ROOT"
[ -L "$HOME/.zshrc" ] || [ -e "$HOME/.zshrc" ] || echo "  note: no ~/.zshrc remains; zsh starts with its defaults"
