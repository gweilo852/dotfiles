#!/usr/bin/env bash
# Check the Starship Kubernetes display for each case in k8s-contexts.tsv.
# Uses a temporary kubeconfig; the real kubeconfig is never read.
set -euo pipefail
root=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

command -v starship >/dev/null 2>&1 || { echo "skip: starship not installed"; exit 0; }

# Colour name -> "r;g;b", from the palette in starship.toml.
rgb() {
  local hex
  hex=$(awk -F'"' -v n="$1" '$1 ~ "^"n" = " {print $2}' "$root/config/starship/starship.toml" | tr -d '#')
  printf '%d;%d;%d' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0 count=0
while IFS=$'\t' read -r ctx want colour; do
  case "$ctx" in '#'* | '') continue ;; esac
  count=$((count + 1))
  cat >"$tmp/config" <<YAML
apiVersion: v1
kind: Config
clusters: [{name: c, cluster: {server: "https://127.0.0.1:1"}}]
users: [{name: u, user: {}}]
contexts: [{name: "$ctx", context: {cluster: c, user: u}}]
current-context: "$ctx"
YAML
  out=$(cd "$tmp" && env -u STARSHIP_SHELL KUBECONFIG="$tmp/config" \
    STARSHIP_CONFIG="$root/config/starship/starship.toml" starship module kubernetes 2>&1)
  plain=$(printf '%s' "$out" | sed $'s/\033\\[[0-9;]*m//g' | sed 's/^⎈ //; s/ *$//')
  if [ "$plain" != "$want" ]; then
    echo "FAIL: $ctx -> '$plain' (want '$want')"
    fail=1
  elif ! printf '%s' "$out" | grep -q "38;2;$(rgb "$colour")m"; then
    echo "FAIL: $ctx -> '$plain' has the wrong colour (want $colour)"
    fail=1
  fi
done <"$root/tests/k8s-contexts.tsv"

# Displayed names must stay distinct for distinct production clusters.
dups=$(awk -F'\t' '!/^#/ && $3 == "red" {print $2}' "$root/tests/k8s-contexts.tsv" | sort | uniq -d)
[ -z "$dups" ] || { echo "FAIL: production contexts share a display name: $dups"; fail=1; }

[ "$fail" = 0 ] && echo "ok: $count Kubernetes context cases"
exit "$fail"
