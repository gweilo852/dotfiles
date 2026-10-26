#!/usr/bin/env bash
# Install Linux and WSL dependencies with the system package manager.
# Called by install.sh. Uses sudo only for the package manager.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

pm=$(detect_pkg_manager)
case "$pm" in
  apt-get) col=2 ;; dnf) col=3 ;; pacman) col=4 ;; zypper) col=5 ;; apk) col=6 ;;
  *)
    warn "no supported package manager found. Use --release-binaries, or install the tools in docs/tools.md by hand."
    exit 0
    ;;
esac

# True when the tool behind a packages.tsv row is already present.
present() {
  local d
  case "$1" in
    bat) has bat || has batcat ;;
    zsh-autosuggestions | zsh-syntax-highlighting)
      for d in /usr/share /usr/share/zsh/plugins /usr/local/share /home/linuxbrew/.linuxbrew/share; do
        [ -r "$d/$1/$1.zsh" ] && return 0
      done
      return 1
      ;;
    *) has "$1" ;;
  esac
}

available() { # $1 = package name
  case "$pm" in
    apt-get)
      local cand
      cand=$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2}')
      [ -n "$cand" ] && [ "$cand" != "(none)" ]
      ;;
    *) return 0 ;; # other managers report unknown packages at install time
  esac
}

if [ "$(id -u)" != 0 ] && ! has sudo; then
  warn "sudo not found and not root; packages skipped. Use --release-binaries instead."
  exit 0
fi
as_root() { if [ "$(id -u)" = 0 ]; then "$@"; else sudo "$@"; fi; }

# First pass: which tools are missing.
missing=()
while IFS=$'\t' read -r -a row; do
  case "${row[0]}" in '#'* | '') continue ;; esac
  if present "${row[0]}"; then
    ok "${row[0]}"
  else
    missing+=("${row[$((col - 1))]}:${row[0]}")
  fi
done <"$DOTFILES_DIR/platforms/linux/packages.tsv"
[ ${#missing[@]} -eq 0 ] && exit 0

# apt needs a fresh index before it can report candidates.
if [ "$pm" = apt-get ]; then
  run as_root apt-get update -qq
fi

wanted=() unpackaged=()
for entry in "${missing[@]}"; do
  pkg=${entry%%:*} tool=${entry#*:}
  if [ "$pkg" = "-" ] || ! available "$pkg"; then
    unpackaged+=("$tool")
  else
    wanted+=("$pkg")
  fi
done

failed=()
for pkg in ${wanted[@]+"${wanted[@]}"}; do
  case "$pm" in
    apt-get) cmd=(as_root apt-get install -y -qq "$pkg") ;;
    dnf) cmd=(as_root dnf install -y -q "$pkg") ;;
    pacman) cmd=(as_root pacman -S --needed --noconfirm "$pkg") ;;
    zypper) cmd=(as_root zypper --non-interactive install "$pkg") ;;
    apk) cmd=(as_root apk add "$pkg") ;;
  esac
  if run "${cmd[@]}"; then change "install $pkg"; else failed+=("$pkg"); fi
done

for t in ${unpackaged[@]+"${unpackaged[@]}"} ${failed[@]+"${failed[@]}"}; do
  warn "$t is not available from $pm; install.sh --release-binaries can install it"
done
