#!/usr/bin/env bash
# Install missing tools from pinned GitHub release archives into $BIN_DIR.
# Each archive is checked against the SHA-256 value in
# platforms/linux/release-binaries.tsv before extraction. Nothing that is
# downloaded is executed during installation.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
FORCE="${FORCE:-0}"

[ "$DOTFILES_UNAME" = Linux ] || die "release binaries are for Linux only"
case "$(uname -m)" in
  x86_64 | amd64) arch=x86_64 ;;
  aarch64 | arm64) arch=aarch64 ;;
  *) die "unsupported CPU architecture: $(uname -m)" ;;
esac

sha256() {
  if has sha256sum; then sha256sum "$1" | awk '{print $1}'
  elif has shasum; then shasum -a 256 "$1" | awk '{print $1}'
  else openssl dgst -sha256 "$1" | awk '{print $NF}'
  fi
}
fetch() {
  if has curl; then curl -fsSL --proto '=https' -o "$2" "$1"
  else wget -q -O "$2" "$1"
  fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

while IFS=$'\t' read -r tool version row_arch sum url; do
  case "$tool" in '#'* | '') continue ;; esac
  [ "$row_arch" = "$arch" ] || continue
  if [ "$FORCE" != 1 ] && { [ -x "$BIN_DIR/$tool" ] || has "$tool"; }; then
    ok "$tool"
    continue
  fi
  if [ "$DRY_RUN" = 1 ]; then
    change "install $tool $version to $BIN_DIR (sha256 ${sum:0:12}...)"
    continue
  fi
  archive="$tmp/$tool.tar.gz"
  fetch "$url" "$archive" || { warn "download failed: $url"; continue; }
  actual=$(sha256 "$archive")
  if [ "$actual" != "$sum" ]; then
    warn "$tool: checksum mismatch (expected $sum, got $actual); not installed"
    continue
  fi
  mkdir -p "$tmp/$tool" "$BIN_DIR"
  tar -xzf "$archive" -C "$tmp/$tool"
  bin=$(find "$tmp/$tool" -type f -name "$tool" | head -n 1)
  [ -n "$bin" ] || { warn "$tool: binary not found in archive"; continue; }
  install -m 0755 "$bin" "$BIN_DIR/$tool"
  change "install $tool $version to $BIN_DIR"
done <"$DOTFILES_DIR/platforms/linux/release-binaries.tsv"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) info "$BIN_DIR is added to PATH by the managed shell configuration" ;;
esac
