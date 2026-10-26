# shellcheck shell=bash
# Shared helpers for install.sh, uninstall.sh and scripts/*.sh.
# Source this file; do not execute it. Compatible with bash 3.2 (macOS).

DOTFILES_DIR="${DOTFILES_DIR:-$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${ASSUME_YES:-0}"
# Test hooks. DOTFILES_SYSROOT prefixes /etc and /proc lookups, and
# DOTFILES_UNAME replaces `uname -s`, so tests can simulate other platforms.
DOTFILES_SYSROOT="${DOTFILES_SYSROOT:-}"
DOTFILES_UNAME="${DOTFILES_UNAME:-$(uname -s)}"
TIMESTAMP="${TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"
CHANGES=0
WARNINGS=0

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  _c_dim=$'\033[2m' _c_red=$'\033[31m' _c_grn=$'\033[32m'
  _c_ylw=$'\033[33m' _c_blu=$'\033[34m' _c_off=$'\033[0m'
else
  _c_dim='' _c_red='' _c_grn='' _c_ylw='' _c_blu='' _c_off=''
fi

info() { printf '%s==>%s %s\n' "$_c_blu" "$_c_off" "$*"; }
ok() { printf '  %sok%s   %s\n' "$_c_grn" "$_c_off" "$*"; }
warn() {
  WARNINGS=$((WARNINGS + 1))
  printf '  %swarn%s %s\n' "$_c_ylw" "$_c_off" "$*" >&2
}
die() {
  printf '%serror:%s %s\n' "$_c_red" "$_c_off" "$*" >&2
  exit 1
}
# Report a change. In dry-run mode the change is described, not made.
change() {
  CHANGES=$((CHANGES + 1))
  if [ "$DRY_RUN" = 1 ]; then
    printf '  %swould%s %s\n' "$_c_ylw" "$_c_off" "$*"
  else
    printf '  %sdone%s %s\n' "$_c_grn" "$_c_off" "$*"
  fi
}
# Run a command, or print it in dry-run mode.
run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf '  %s[dry-run]%s %s\n' "$_c_dim" "$_c_off" "$*"
  else
    "$@"
  fi
}
has() { command -v "$1" >/dev/null 2>&1; }

# Run a command in a new session, without a controlling terminal, with
# stdin from /dev/null. Use it for every check that starts an interactive
# shell (zsh -i, bash -i). On a terminal, such a shell makes its own process
# group the foreground group. zsh execs the last command of -c and never
# gives the terminal back; a later bash -i then stops the caller with
# SIGTTIN ("Stopped" over SSH, seen on Debian 11 with bash 5.1).
no_tty() {
  if has perl; then
    perl -MPOSIX -e 'POSIX::setsid(); exec { $ARGV[0] } @ARGV or die "$ARGV[0]: $!\n"' "$@" </dev/null
  elif has setsid; then
    setsid -w "$@" </dev/null
  else
    "$@" </dev/null
  fi
}

confirm() { # $1 = question. Returns 0 for yes.
  [ "$ASSUME_YES" = 1 ] && return 0
  [ -t 0 ] || return 1
  printf '%s [y/N] ' "$1"
  local reply
  read -r reply
  case "$reply" in [Yy] | [Yy][Ee][Ss]) return 0 ;; *) return 1 ;; esac
}

# --------------------------------------------------------------------
# Platform detection
# --------------------------------------------------------------------

# Prints one of: macos, linux, wsl, unraid, unknown.
# Unraid is checked first and cannot be overridden, so a forced platform
# never bypasses the Unraid safety rules.
detect_platform() {
  if [ -f "$DOTFILES_SYSROOT/etc/unraid-version" ]; then
    echo unraid
    return
  fi
  if [ -n "${DOTFILES_PLATFORM:-}" ]; then
    echo "$DOTFILES_PLATFORM"
    return
  fi
  case "$DOTFILES_UNAME" in
    Darwin) echo macos ;;
    Linux)
      if [ -n "${WSL_DISTRO_NAME:-}" ] ||
        grep -qi microsoft "$DOTFILES_SYSROOT/proc/version" 2>/dev/null; then
        echo wsl
      else
        echo linux
      fi
      ;;
    *) echo unknown ;;
  esac
}

# Prints the distribution, for example "Ubuntu 22.04.4 LTS (ubuntu 22.04)",
# from /etc/os-release. Prints "unknown" when the file is missing.
detect_distro() {
  local f="$DOTFILES_SYSROOT/etc/os-release"
  if [ "$DOTFILES_UNAME" = Darwin ] && [ -z "$DOTFILES_SYSROOT" ]; then
    echo "macOS $(sw_vers -productVersion 2>/dev/null)"
  elif [ -r "$f" ]; then
    (
      # shellcheck disable=SC1090
      . "$f"
      echo "${PRETTY_NAME:-${NAME:-Linux}} (${ID:-unknown} ${VERSION_ID:-})"
    )
  else
    echo unknown
  fi
}

detect_pkg_manager() {
  local pm
  for pm in brew apt-get dnf pacman zypper apk; do
    if has "$pm"; then
      echo "$pm"
      return
    fi
  done
  echo none
}

# Persistent state and backups. On Unraid, $HOME lives in RAM, so both
# live next to the repository on persistent storage instead.
init_state_paths() { # $1 = platform
  if [ "$1" = unraid ]; then
    STATE_DIR="${DOTFILES_STATE_DIR:-$DOTFILES_DIR/.state}"
    BACKUP_ROOT="${DOTFILES_BACKUP_ROOT:-$DOTFILES_DIR/.backups}"
  else
    STATE_DIR="${DOTFILES_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles}"
    BACKUP_ROOT="${DOTFILES_BACKUP_ROOT:-$HOME/.dotfiles-backups}"
  fi
  MANIFEST="$STATE_DIR/manifest.tsv"
  BACKUP_DIR="$BACKUP_ROOT/$TIMESTAMP"
  # Machine-local settings (config/shell/zsh-handoff.sh). Owned by the user.
  # shellcheck disable=SC2034 # read by install.sh, uninstall.sh, doctor.sh
  LOCAL_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/local.conf"
}

# The file that a bash login shell (SSH) reads: the first of these that
# exists. Prints nothing when none exists.
bash_login_file() {
  local f
  for f in .bash_profile .bash_login .profile; do
    if [ -f "$HOME/$f" ]; then
      echo "$HOME/$f"
      return
    fi
  done
}

# --------------------------------------------------------------------
# Manifest: one TSV line per change, so uninstall touches only our files.
#   kind  target  source  backup
# kinds: link, block, gitinclude, copy
# An empty backup field on a block or gitinclude means the file did not
# exist before; uninstall then deletes it when nothing else is left in it.
# --------------------------------------------------------------------

manifest_add() {
  [ "$DRY_RUN" = 1 ] && return 0
  mkdir -p "$STATE_DIR"
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "${4:-}" >>"$MANIFEST"
}

# Back up a path. $2 = move (default) or copy. Prints the backup path.
backup_path() {
  local target=$1 mode=${2:-move} rel dest
  case "$target" in
    "$HOME"/*) rel=${target#"$HOME"/} ;;
    *) rel=${target#/} ;;
  esac
  dest="$BACKUP_DIR/$rel"
  if [ "$DRY_RUN" != 1 ]; then
    mkdir -p "$(dirname "$dest")" || return 1
    chmod 700 "$BACKUP_ROOT" 2>/dev/null
    if [ "$mode" = copy ]; then
      cp -pP "$target" "$dest" || return 1
    else
      mv "$target" "$dest" || return 1
    fi
  fi
  echo "$dest"
}

# Link $2 -> $1. An existing file is moved to the backup directory first,
# and LAST_BACKUP holds its path (empty when nothing was backed up).
link_file() {
  local src=$1 target=$2 backup=""
  LAST_BACKUP=""
  if [ -L "$target" ] && [ "$(readlink "$target")" = "$src" ]; then
    ok "$target"
    return 0
  fi
  if [ -e "$target" ] || [ -L "$target" ]; then
    backup=$(backup_path "$target" move) || die "cannot back up $target"
    change "back up $target -> $backup"
  fi
  run mkdir -p "$(dirname "$target")"
  run ln -s "$src" "$target"
  change "link $target -> $src"
  # shellcheck disable=SC2034 # read by install.sh
  LAST_BACKUP=$backup
  manifest_add link "$target" "$src" "$backup"
}

# Copy $1 to $2 (used where a symlink cannot work, such as Windows).
copy_file() {
  local src=$1 target=$2 backup=""
  if [ -f "$target" ] && cmp -s "$src" "$target"; then
    ok "$target"
    return 0
  fi
  if [ -e "$target" ]; then
    backup=$(backup_path "$target" move) || die "cannot back up $target"
    change "back up $target -> $backup"
  fi
  run cp "$src" "$target"
  change "copy $src -> $target"
  manifest_add copy "$target" "$src" "$backup"
}

block_begin() { printf '# >>> dotfiles (%s) >>>' "$1"; }
block_end() { printf '# <<< dotfiles (%s) <<<' "$1"; }

# Append a marked block to $1 once. $2 = marker name, $3 = block body.
ensure_block() {
  local file=$1 marker=$2 body=$3 backup=""
  if [ -f "$file" ] && grep -qF "$(block_begin "$marker")" "$file"; then
    ok "$file ($marker block)"
    return 0
  fi
  if [ -e "$file" ]; then
    backup=$(backup_path "$file" copy) || die "cannot back up $file"
    change "back up $file -> $backup"
  fi
  if [ "$DRY_RUN" != 1 ]; then
    mkdir -p "$(dirname "$file")"
    printf '\n%s\n%s\n%s\n' "$(block_begin "$marker")" "$body" "$(block_end "$marker")" >>"$file"
  fi
  change "add $marker block to $file"
  manifest_add block "$file" "$marker" "$backup"
}

# Remove a marked block from $1 in place.
remove_block() {
  local file=$1 marker=$2 tmp
  tmp=$(mktemp) || return 1
  # Also drop the blank line that ensure_block puts before the block.
  awk -v b="$(block_begin "$marker")" -v e="$(block_end "$marker")" '
    $0 == b { skip = 1; held = 0; next }
    $0 == e { skip = 0; next }
    skip { next }
    held { print ""; held = 0 }
    $0 == "" { held = 1; next }
    { print }
    END { if (held) print "" }
  ' "$file" >"$tmp" && cat "$tmp" >"$file"
  rm -f "$tmp"
}

# --------------------------------------------------------------------
# Zsh migration: turn an existing ~/.zshrc into ~/.zshrc.local.
# Lines that the managed configuration now owns (prompt, compinit,
# plugins, history) are disabled, not deleted. Everything else is kept.
# --------------------------------------------------------------------

migrate_zshrc() { # $1 = previous ~/.zshrc (usually its backup copy)
  local src=$1 dest="$HOME/.zshrc.local" tmp
  if [ -e "$dest" ]; then
    ok "$dest exists; left unchanged"
    return 0
  fi
  if [ -z "$src" ]; then
    run cp "$DOTFILES_DIR/config/zsh/zshrc.local.example" "$dest"
    run chmod 600 "$dest"
    change "create $dest from the example"
    return 0
  fi
  if [ "$DRY_RUN" = 1 ]; then
    change "create $dest from your previous .zshrc (duplicate initialization disabled)"
    return 0
  fi
  tmp=$(mktemp) || die "mktemp failed"
  {
    printf '# ~/.zshrc.local: machine-specific settings. Not managed by dotfiles.\n'
    printf '# Migrated from %s on %s.\n' "$src" "$TIMESTAMP"
    printf '# Lines that start with ": # [dotfiles]" are now handled by the managed\n'
    printf '# configuration. Delete them when you are satisfied.\n\n'
    awk '
      /^[[:space:]]*#/ { print; next }
      /starship init/ || /oh-my-zsh\.sh/ ||
      /^[[:space:]]*(export[[:space:]]+)?ZSH(_THEME)?=/ ||
      /^[[:space:]]*plugins=\(.*\)[[:space:]]*$/ ||
      /^[[:space:]]*autoload[[:space:]]+-U[z]?[[:space:]]+compinit/ ||
      /^[[:space:]]*compinit([[:space:]]|$)/ ||
      /zoxide init/ || /fzf --zsh/ || /\.fzf\.zsh/ ||
      /zsh-autosuggestions\.zsh/ || /zsh-syntax-highlighting\.zsh/ ||
      /brew shellenv/ || /(kubectl|helm) completion zsh/ ||
      /iterm2_shell_integration/ || /kube-ps1/ || /kube_ps1/ ||
      /^[[:space:]]*(PROMPT|PS1|RPROMPT)=/ ||
      /google-cloud-sdk\/(path|completion)\.zsh\.inc/ ||
      /^[[:space:]]*(HISTFILE|HISTSIZE|SAVEHIST)=/ ||
      /^[[:space:]]*setopt[[:space:]]+(HIST_|SHARE_HISTORY|EXTENDED_HISTORY|INC_APPEND)/ ||
      /^[[:space:]]*zstyle[[:space:]]+.?:completion:/ {
        match($0, /^[[:space:]]*/)
        print substr($0, 1, RLENGTH) ": # [dotfiles] " substr($0, RLENGTH + 1)
        next
      }
      { print }
    ' "$src"
  } >"$tmp"
  if has zsh && ! zsh -n "$tmp" 2>/dev/null; then
    {
      printf '# ~/.zshrc.local: machine-specific settings. Not managed by dotfiles.\n'
      printf '# Automatic migration of %s failed a syntax check.\n' "$src"
      printf '# Uncomment the lines you still need.\n\n'
      sed 's/^/# /' "$src"
    } >"$tmp"
    warn "$dest needs manual review: every line is commented out"
  fi
  mv "$tmp" "$dest" && chmod 600 "$dest"
  change "create $dest from $src (duplicate initialization disabled)"
}
