#!/usr/bin/env bash
# Automated validation. Safe to run anywhere: installer tests use a
# temporary $HOME, and nothing outside it changes.
#   scripts/test.sh
# A check whose tool is not installed is skipped, not failed.
set -uo pipefail
ROOT=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT" || exit 1

PASS=0 FAIL=0 SKIP=0
pass() { PASS=$((PASS + 1)); printf '  ok    %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$*"; }
skip() { SKIP=$((SKIP + 1)); printf '  skip  %s\n' "$*"; }
section() { printf '\n== %s\n' "$*"; }
has() { command -v "$1" >/dev/null 2>&1; }

WEZTERM=$(command -v wezterm 2>/dev/null || true)
[ -z "$WEZTERM" ] && [ -x /Applications/WezTerm.app/Contents/MacOS/wezterm ] &&
  WEZTERM=/Applications/WezTerm.app/Contents/MacOS/wezterm

TMP=$(mktemp -d)
trap 'tkill 2>/dev/null; rm -rf "$TMP"' EXIT

BASH_FILES="install.sh uninstall.sh scripts/*.sh platforms/unraid/user-script.sh config/bash/bashrc config/shell/env.sh config/shell/aliases.sh config/shell/tmux.sh config/tmux/clipboard.sh tests/*.sh"
ZSH_FILES="config/zsh/zshrc config/zsh/completion.zsh config/zsh/plugins.zsh config/zsh/zshrc.local.example"

# --------------------------------------------------------------------
section "shell syntax"
for f in $BASH_FILES; do
  bash -n "$f" 2>"$TMP/err" && pass "bash -n $f" || fail "bash -n $f: $(cat "$TMP/err")"
done
if has zsh; then
  for f in $ZSH_FILES; do
    zsh -n "$f" 2>"$TMP/err" && pass "zsh -n $f" || fail "zsh -n $f: $(cat "$TMP/err")"
  done
else
  skip "zsh not installed"
fi
if has shellcheck; then
  # shellcheck disable=SC2086
  shellcheck -x $BASH_FILES >"$TMP/sc" 2>&1 && pass "shellcheck" || fail "shellcheck:
$(cat "$TMP/sc")"
else
  skip "shellcheck not installed"
fi

# --------------------------------------------------------------------
section "WezTerm, Starship, tmux and git configuration"
if [ -n "$WEZTERM" ]; then
  err=$("$WEZTERM" --config-file config/wezterm/wezterm.lua ls-fonts 2>&1 | grep -E 'ERROR|WARN')
  [ -z "$err" ] && pass "wezterm.lua loads" || fail "wezterm.lua: $err"
  printf 'local x =\n' >"$TMP/bad.lua"
  "$WEZTERM" --config-file "$TMP/bad.lua" ls-fonts 2>&1 | grep -q ERROR &&
    pass "wezterm check detects a broken file" || fail "wezterm check missed a broken file"
elif has luac; then
  luac -p config/wezterm/wezterm.lua && pass "luac -p wezterm.lua" || fail "wezterm.lua syntax"
else
  skip "wezterm and luac not installed"
fi

if has python3 && python3 -c 'import tomllib' 2>/dev/null; then
  python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' config/starship/starship.toml &&
    pass "starship.toml is valid TOML" || fail "starship.toml TOML syntax"
else
  skip "python3 tomllib not available"
fi
if has starship; then
  err=$(STARSHIP_CONFIG="$ROOT/config/starship/starship.toml" starship print-config 2>&1 >/dev/null)
  [ -z "$err" ] && pass "starship accepts starship.toml" || fail "starship: $err"
  out=$(tests/test-k8s-prompt.sh 2>&1) && pass "${out##*$'\n'}" || fail "Kubernetes prompt:
$out"
else
  skip "starship not installed"
fi

if has git; then
  git config -f config/git/config --list >/dev/null 2>&1 && pass "git config parses" || fail "git config syntax"
fi

awk -F'\t' '!/^#/ && NF {
  if (NF != 5 || $4 !~ /^[0-9a-f]{64}$/ || $5 !~ /^https:\/\// || $3 !~ /^(x86_64|aarch64)$/) { print "bad row: " $0; bad = 1 }
} END { exit bad }' platforms/linux/release-binaries.tsv && pass "release-binaries.tsv rows are well formed" ||
  fail "release-binaries.tsv"

# --------------------------------------------------------------------
section "tmux"
# Each server uses its own socket (-L) and a temporary HOME, so running
# sessions and the real ~/.tmux.conf.local are never touched.
TH="$TMP/tmux-home"
mkdir -p "$TH/bin"
ln -s "$ROOT/config/tmux/tmux.conf" "$TH/.tmux.conf"
SOCKETS=""
tserver() { # socket, env...  -> starts a server with the managed config
  local sock="dotfiles-test-$$-$1"
  shift
  SOCKETS="$SOCKETS $sock"
  env -i HOME="$TH" PATH="$TH/bin:$PATH" TERM=xterm-256color "$@" \
    tmux -L "$sock" -f "$TH/.tmux.conf" new-session -d -s t 'sleep 60' 2>&1
}
topt() { tmux -L "dotfiles-test-$$-$1" show -gv "$2" 2>/dev/null || tmux -L "dotfiles-test-$$-$1" show -sv "$2" 2>/dev/null; }
tkill() { for s in $SOCKETS; do tmux -L "$s" kill-server 2>/dev/null; done; SOCKETS=""; }

if has tmux; then
  pass "tmux available: $(tmux -V)"
  err=$(tserver std)
  [ -z "$err" ] && pass "tmux.conf loads without errors" || fail "tmux.conf: $err"
  want="mouse=on mode-keys=vi set-clipboard=on history-limit=100000 base-index=0 prefix=C-b automatic-rename=off @dotfiles_profile=standard"
  for kv in $want; do
    got=$(topt std "${kv%%=*}")
    [ "$got" = "${kv#*=}" ] && pass "tmux ${kv%%=*} = $got" || fail "tmux ${kv%%=*}: want ${kv#*=}, got '$got'"
  done
  case "$(topt std default-terminal)" in
    tmux-256color | screen-256color) pass "tmux default-terminal is a 256-colour entry" ;;
    *) fail "tmux default-terminal: $(topt std default-terminal)" ;;
  esac
  keys=$(tmux -L "dotfiles-test-$$-std" list-keys 2>/dev/null)
  for k in "copy-mode-vi +y +send-keys -X copy-pipe-and-cancel" "copy-mode-vi +v +send-keys -X begin-selection" \
    "root +F9 +last-window" "root +F10 +next-window" "prefix +r +source-file" "prefix +\\| +split-window -h"; do
    printf '%s\n' "$keys" | grep -qE -- "-T ${k%% *}.* ${k#* }|${k}" && pass "tmux key: $k" || fail "tmux key missing: $k"
  done

  # Copy end to end: wl-copy stub, Wayland session, Linux rules.
  printf '#!/bin/sh\ncat >"%s/copied"\n' "$TH" >"$TH/bin/wl-copy"
  chmod +x "$TH/bin/wl-copy"
  tserver copy WAYLAND_DISPLAY=wayland-test DOTFILES_UNAME=Linux >/dev/null
  tc="tmux -L dotfiles-test-$$-copy"
  $tc respawn-pane -k -t t 'printf "copy-me\n"; sleep 60'
  sleep 0.5
  $tc copy-mode -t t
  for x in history-top start-of-line begin-selection end-of-line; do $tc send-keys -t t -X "$x"; done
  $tc send-keys -t t y
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$TH/copied" ] && break; sleep 0.3; done
  grep -q copy-me "$TH/copied" 2>/dev/null && pass "tmux copy reaches the clipboard backend" || fail "tmux copy did not reach wl-copy"
  [ "$($tc show-buffer 2>/dev/null)" = copy-me ] && pass "tmux copy fills the tmux buffer" || fail "tmux buffer"

  # Local override, loaded last.
  printf 'set -g @local_test loaded\nset -g mouse off\n' >"$TH/.tmux.conf.local"
  tserver local >/dev/null
  [ "$(topt local @local_test)" = loaded ] && [ "$(topt local mouse)" = off ] &&
    pass "~/.tmux.conf.local is loaded and overrides" || fail "tmux local override not applied"
  rm -f "$TH/.tmux.conf.local"

  # Unraid: minimal profile, no clipboard helper.
  mkdir -p "$TMP/sys-unraid-t/etc"
  echo 'version="7.1.0"' >"$TMP/sys-unraid-t/etc/unraid-version"
  tserver unraid DOTFILES_SYSROOT="$TMP/sys-unraid-t" >/dev/null
  [ "$(topt unraid @dotfiles_profile)" = minimal ] && pass "Unraid selects the minimal tmux profile" || fail "Unraid tmux profile"
  tmux -L "dotfiles-test-$$-unraid" list-keys -T copy-mode-vi 2>/dev/null | grep -E ' y ' | grep -q copy-selection-and-cancel &&
    pass "Unraid copy uses OSC 52 only" || fail "Unraid copy binding"
  tkill
else
  skip "tmux not installed: tmux checks"
fi

# Clipboard backend selection, with stub tools and nothing else on PATH.
CB="$TMP/cb"
mkdir -p "$CB/all" "$CB/xsel" "$CB/none" "$TMP/sys-wsl2/proc"
echo "Linux version 5.15.0-microsoft-standard-WSL2" >"$TMP/sys-wsl2/proc/version"
for d in all xsel none; do
  for t in sh grep cat uname; do ln -sf "$(command -v "$t")" "$CB/$d/$t"; done
done
for t in pbcopy wl-copy xclip xsel clip.exe; do printf '#!/bin/sh\ncat >/dev/null\n' >"$CB/all/$t"; done
printf '#!/bin/sh\ncat >/dev/null\n' >"$CB/xsel/xsel"
chmod +x "$CB"/*/*
cbcase() { # want, dir, env...
  local want=$1 dir=$2 got
  shift 2
  got=$(env -i PATH="$CB/$dir" "$@" sh "$ROOT/config/tmux/clipboard.sh" --detect)
  [ "$got" = "$want" ] && pass "clipboard: $want ($*)" || fail "clipboard: want $want, got $got ($*)"
}
cbcase pbcopy all DOTFILES_UNAME=Darwin
cbcase wl-copy all DOTFILES_UNAME=Linux WAYLAND_DISPLAY=wayland-0
cbcase xclip all DOTFILES_UNAME=Linux DISPLAY=:0
cbcase xsel xsel DOTFILES_UNAME=Linux DISPLAY=:0
cbcase clip.exe all DOTFILES_UNAME=Linux DOTFILES_SYSROOT="$TMP/sys-wsl2"
cbcase none all DOTFILES_UNAME=Linux DOTFILES_SYSROOT="$TMP/sys-linux"
cbcase none none DOTFILES_UNAME=Linux DISPLAY=:0 WAYLAND_DISPLAY=wayland-0
printf 'x' | env -i PATH="$CB/none" DOTFILES_UNAME=Linux sh "$ROOT/config/tmux/clipboard.sh" &&
  pass "headless copy succeeds without clipboard tools" || fail "headless copy failed"

# Shell helpers against an isolated server.
helpers() { # shell
  env -i HOME="$TH" PATH="$PATH" DOTFILES_TMUX_SOCKET="dotfiles-test-$$-h$1" "$1" -c '
    . "'"$ROOT"'/config/shell/tmux.sh"
    tmux-workspace -d "demo.1" infra claude >/dev/null
    tmux-workspace -d "demo-1" infra codex >/dev/null
    printf "windows=%s\n" "$(command tmux -L "$DOTFILES_TMUX_SOCKET" list-windows -t "=demo-1" -F "#W" | paste -sd, -)"
    tmux-send -y demo-1:missing x >/dev/null 2>&1; echo "missing=$?"
    tmux-send -y nosuch:claude x >/dev/null 2>&1; echo "nosession=$?"
    tmux-send demo-1:claude x </dev/null >/dev/null 2>&1; echo "noprompt=$?"
    tmux-send -y demo-1:claude "echo helper-sent" >/dev/null; echo "send=$?"
    sleep 1
    command tmux -L "$DOTFILES_TMUX_SOCKET" capture-pane -p -t "=demo-1:claude" | grep -c "^helper-sent"
    command tmux -L "$DOTFILES_TMUX_SOCKET" kill-server'
}
if has tmux; then
  for sh_ in bash zsh; do
    has "$sh_" || continue
    out=$(helpers "$sh_" 2>&1 | paste -sd' ' -)
    [ "$out" = "windows=infra,claude,codex missing=1 nosession=1 noprompt=1 send=0 1" ] &&
      pass "$sh_: tm helpers create, refuse unsafe targets, and send" || fail "$sh_ helpers: $out"
  done
fi

# --------------------------------------------------------------------
section "platform detection"
detect() { (env "$@" bash -c '. scripts/lib.sh; detect_platform'); }
mkdir -p "$TMP/sys-wsl/proc" "$TMP/sys-linux/proc" "$TMP/sys-unraid/etc"
echo "Linux version 5.15.0-microsoft-standard-WSL2" >"$TMP/sys-wsl/proc/version"
echo "Linux version 6.8.0-generic" >"$TMP/sys-linux/proc/version"
echo 'version="7.1.0"' >"$TMP/sys-unraid/etc/unraid-version"
check_detect() { # expected, env...
  local want=$1 got
  shift
  got=$(detect "$@")
  [ "$got" = "$want" ] && pass "detect $want" || fail "detect: want $want, got $got ($*)"
}
check_detect macos DOTFILES_UNAME=Darwin DOTFILES_SYSROOT="$TMP/sys-linux" WSL_DISTRO_NAME=
check_detect linux DOTFILES_UNAME=Linux DOTFILES_SYSROOT="$TMP/sys-linux" WSL_DISTRO_NAME=
check_detect wsl DOTFILES_UNAME=Linux DOTFILES_SYSROOT="$TMP/sys-wsl" WSL_DISTRO_NAME=
check_detect wsl DOTFILES_UNAME=Linux DOTFILES_SYSROOT="$TMP/sys-linux" WSL_DISTRO_NAME=Ubuntu
check_detect unraid DOTFILES_UNAME=Linux DOTFILES_SYSROOT="$TMP/sys-unraid" WSL_DISTRO_NAME=
check_detect unraid DOTFILES_UNAME=Linux DOTFILES_SYSROOT="$TMP/sys-unraid" DOTFILES_PLATFORM=linux

# --------------------------------------------------------------------
section "installer in a temporary HOME"
H="$TMP/home"
mkdir -p "$H"
# Clean environment: no real HOME, XDG paths, or local tool overrides.
sandbox() {
  env -i HOME="$H" PATH="$PATH" TERM=xterm-256color LANG="${LANG:-C.UTF-8}" \
    TIMESTAMP="${TS:-20000101-000000}" NO_COLOR=1 \
    ${DOTFILES_UNAME_TEST:+DOTFILES_UNAME=$DOTFILES_UNAME_TEST} \
    ${DOTFILES_SYSROOT_TEST:+DOTFILES_SYSROOT=$DOTFILES_SYSROOT_TEST} \
    "$@"
}
snapshot() { (cd "$H" && find . -print0 | sort -z | xargs -0 ls -ld 2>/dev/null | awk '{$6=$7=$8=""; print}'; find . -type f -exec cksum {} + | sort); }

# Pre-existing user files, including old Oh My Zsh initialization.
cat >"$H/.zshrc" <<'EOF'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git kubectx)
source $ZSH/oh-my-zsh.sh
autoload -Uz compinit
compinit
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
eval "$(starship init zsh)"
PROMPT='$(kube_ps1)'$PROMPT
export WORK_SETTING="keep-me"
alias deploy='echo deploy'
EOF
printf 'set -g mouse on\n' >"$H/.tmux.conf"
printf 'alias k=kubectl\n' >"$H/.bashrc"
cp "$H/.zshrc" "$TMP/orig.zshrc"
cp "$H/.bashrc" "$TMP/orig.bashrc"

before=$(snapshot)
sandbox ./install.sh --dry-run --no-packages >"$TMP/dry.out" 2>&1
[ "$before" = "$(snapshot)" ] && pass "dry run changes nothing" || fail "dry run changed files"
grep -q 'would' "$TMP/dry.out" && pass "dry run lists planned changes" || fail "dry run printed no plan"

sandbox ./install.sh --no-packages >"$TMP/noyes.out" 2>&1 </dev/null &&
  fail "non-interactive run without --yes must stop" || pass "non-interactive run without --yes stops"
[ "$before" = "$(snapshot)" ] && pass "refused run changes nothing" || fail "refused run changed files"

TS=20000101-000001 sandbox ./install.sh --yes --no-packages --skip-validate >"$TMP/i1.out" 2>&1 ||
  fail "install exit status: $(tail -n 5 "$TMP/i1.out")"
expect_link() {
  [ "$(readlink "$H/$1")" = "$ROOT/$2" ] && pass "link ~/$1" || fail "link ~/$1 -> $(readlink "$H/$1")"
}
expect_link .zshrc config/zsh/zshrc
expect_link .tmux.conf config/tmux/tmux.conf
expect_link .config/starship.toml config/starship/starship.toml
case "$(uname -s)" in Darwin | Linux) expect_link .config/wezterm/wezterm.lua config/wezterm/wezterm.lua ;; esac

B="$H/.dotfiles-backups/20000101-000001"
cmp -s "$B/.zshrc" "$TMP/orig.zshrc" && pass "original .zshrc backed up" || fail "missing .zshrc backup"
grep -q 'mouse on' "$B/.tmux.conf" 2>/dev/null && pass "original .tmux.conf backed up" || fail "missing .tmux.conf backup"
cmp -s "$B/.bashrc" "$TMP/orig.bashrc" && pass "original .bashrc backed up" || fail "missing .bashrc backup"

L="$H/.zshrc.local"
grep -q 'WORK_SETTING="keep-me"' "$L" && grep -q "alias deploy=" "$L" &&
  pass "user settings migrated to .zshrc.local" || fail "user settings not migrated"
active=$(grep -vE '^[[:space:]]*(#|:)' "$L" | grep -cE 'oh-my-zsh|starship init|compinit|kube_ps1|brew shellenv|ZSH_THEME|plugins=')
[ "$active" = 0 ] && pass "duplicate initialization disabled in .zshrc.local" || fail "$active duplicate init line(s) still active"
if has zsh; then zsh -n "$L" && pass ".zshrc.local syntax" || fail ".zshrc.local syntax"; fi
[ "$(ls -l "$L" | cut -c1-10)" = "-rw-------" ] && pass ".zshrc.local is private (600)" || fail ".zshrc.local mode"
[ "$(grep -c '>>> dotfiles (bash)' "$H/.bashrc")" = 1 ] && pass "bash block added once" || fail "bash block count"
if has git; then
  [ "$(HOME="$H" git config --global --get-all include.path | grep -c "$ROOT/config/git/config")" = 1 ] &&
    pass "git include added" || fail "git include"
fi

after1=$(snapshot)
TS=20000101-000002 sandbox ./install.sh --yes --no-packages --skip-validate >"$TMP/i2.out" 2>&1
grep -q 'done: 0 change' "$TMP/i2.out" && pass "second install makes no changes" || fail "second install changed: $(grep 'done:' "$TMP/i2.out")"
[ "$after1" = "$(snapshot)" ] && pass "second install leaves files identical" || fail "second install changed files"
[ ! -e "$H/.dotfiles-backups/20000101-000002" ] && pass "second install makes no new backups" || fail "second install made backups"

# Interactive shells in the sandbox, with and without the optional tools.
filter() { sed $'s/\033\\[?1034h//g' | grep -vxE 'exit|.*no job control.*|.*cannot set terminal process group.*|.*Inappropriate ioctl.*' || true; }
if has zsh; then
  err=$(sandbox zsh -i -c exit 2>&1 >/dev/null | filter)
  [ -z "$err" ] && pass "zsh starts without errors" || fail "zsh startup: $err"
  if has starship; then
    n=$(sandbox zsh -i -c 'print -l $precmd_functions' 2>/dev/null | grep -c 'starship_precmd$')
    [ "$n" = 1 ] && pass "starship initialized exactly once" || fail "starship initialized $n times"
  fi
  err=$(env -i HOME="$H" PATH=/usr/bin:/bin HOMEBREW_PREFIX=/nonexistent TERM=xterm-256color \
    zsh -i -c 'll >/dev/null; lt >/dev/null; catp /dev/null' 2>&1 >/dev/null | filter)
  [ -z "$err" ] && pass "zsh degrades cleanly without optional tools" || fail "zsh without tools: $err"
fi
err=$(sandbox bash -i -c exit 2>&1 >/dev/null | filter)
[ -z "$err" ] && pass "bash starts without errors" || fail "bash startup: $err"
err=$(env -i HOME="$H" PATH=/usr/bin:/bin TERM=xterm-256color bash -i -c 'll >/dev/null' 2>&1 >/dev/null | filter)
[ -z "$err" ] && pass "bash degrades cleanly without optional tools" || fail "bash without tools: $err"

# Uninstall: a link the user replaced must survive.
rm "$H/.config/starship.toml" && printf '# mine\n' >"$H/.config/starship.toml"
before=$(snapshot)
sandbox ./uninstall.sh --dry-run >/dev/null 2>&1
[ "$before" = "$(snapshot)" ] && pass "uninstall dry run changes nothing" || fail "uninstall dry run changed files"
sandbox ./uninstall.sh --yes >"$TMP/u.out" 2>&1 || fail "uninstall exit status: $(tail -n 5 "$TMP/u.out")"
cmp -s "$H/.zshrc" "$TMP/orig.zshrc" && [ ! -L "$H/.zshrc" ] && pass "uninstall restores .zshrc" || fail "uninstall .zshrc"
grep -q 'mouse on' "$H/.tmux.conf" && [ ! -L "$H/.tmux.conf" ] && pass "uninstall restores .tmux.conf" || fail "uninstall .tmux.conf"
cmp -s "$H/.bashrc" "$TMP/orig.bashrc" && pass "uninstall removes the bash block exactly" || fail "uninstall .bashrc differs"
grep -q '# mine' "$H/.config/starship.toml" && pass "uninstall keeps a user-replaced file" || fail "uninstall removed a user file"
[ -f "$L" ] && pass "uninstall keeps .zshrc.local" || fail "uninstall removed .zshrc.local"
if has git; then
  HOME="$H" git config --global --get-all include.path 2>/dev/null | grep -q "$ROOT" &&
    fail "git include still present" || pass "uninstall removes git include"
fi
[ -d "$B" ] && pass "uninstall keeps backups" || fail "backups removed"

# --------------------------------------------------------------------
section "Linux VDI simulation"
# A Linux host with existing work settings, no root and no desktop.
H="$TMP/vdi-home"
mkdir -p "$H" "$TMP/sys-vdi/etc" "$TMP/sys-vdi/proc"
printf 'PRETTY_NAME="Rocky Linux 9.4 (Blue Onyx)"\nID="rocky"\nVERSION_ID="9.4"\n' >"$TMP/sys-vdi/etc/os-release"
echo "Linux version 5.14.0-427.el9.x86_64" >"$TMP/sys-vdi/proc/version"
got=$(env DOTFILES_UNAME=Linux DOTFILES_SYSROOT="$TMP/sys-vdi" bash -c '. scripts/lib.sh; detect_distro')
[ "$got" = "Rocky Linux 9.4 (Blue Onyx) (rocky 9.4)" ] && pass "distribution detected: $got" || fail "distro: $got"
cat >"$H/.bashrc" <<'EOF'
# distribution defaults
export WORK_PROXY_NOTE="keep"
alias deploy-story='echo work alias'
tm() { echo user-tm; }
EOF
printf 'export WORK_ENV="keep-zsh"\ntm() { echo user-tm-zsh; }\n' >"$H/.zshrc"
cp "$H/.bashrc" "$TMP/vdi.bashrc"
VDI() { DOTFILES_UNAME_TEST=Linux DOTFILES_SYSROOT_TEST="$TMP/sys-vdi" sandbox "$@"; }
VDI ./install.sh --dry-run --no-packages >"$TMP/vdi-dry.out" 2>&1
grep -q 'system:   Rocky Linux 9.4' "$TMP/vdi-dry.out" && pass "installer prints the distribution" || fail "installer distro line"
grep -q 'platform: linux' "$TMP/vdi-dry.out" && pass "installer detects linux" || fail "installer platform"
TS=20000101-000010 VDI ./install.sh --yes --no-packages --skip-validate >"$TMP/vdi.out" 2>&1 || fail "VDI install: $(tail -n 3 "$TMP/vdi.out")"
[ ! -e "$H/.config/wezterm/wezterm.lua" ] && pass "no WezTerm config on a host without WezTerm" || fail "WezTerm config linked on headless host"
head -n 4 "$H/.bashrc" | cmp -s - "$TMP/vdi.bashrc" && pass "existing ~/.bashrc content kept" || fail "~/.bashrc content changed"
out=$(env -i HOME="$H" PATH="$PATH" TERM=xterm-256color bash -i -c 'tm; echo "$WORK_PROXY_NOTE"; type deploy-story >/dev/null && echo alias-ok' 2>/dev/null | paste -sd' ' -)
[ "$out" = "user-tm keep alias-ok" ] && pass "bash keeps work aliases, variables and a user tm function" || fail "bash preservation: $out"
if has zsh; then
  out=$(env -i HOME="$H" PATH="$PATH" TERM=xterm-256color zsh -i -c 'tm; echo $WORK_ENV' 2>/dev/null | paste -sd' ' -)
  [ "$out" = "user-tm-zsh keep-zsh" ] && pass "zsh loads ~/.zshrc.local, and its tm wins" || fail "zsh local override: $out"
  out=$(env -i HOME="$H" PATH="$PATH" TERM=xterm-256color zsh -i -c 'whence -w tmux-send tmux-workspace z' 2>/dev/null | paste -sd' ' -)
  case "$out" in *"tmux-send: function"*"tmux-workspace: function"*) pass "zsh defines the tmux helpers" ;; *) fail "zsh helpers: $out" ;; esac
fi
TS=20000101-000011 VDI ./install.sh --yes --no-packages --skip-validate >"$TMP/vdi2.out" 2>&1
grep -q 'done: 0 change' "$TMP/vdi2.out" && pass "VDI install is idempotent" || fail "VDI second install: $(grep 'done:' "$TMP/vdi2.out")"
VDI ./uninstall.sh --yes >/dev/null 2>&1
cmp -s "$H/.bashrc" "$TMP/vdi.bashrc" && pass "VDI uninstall restores ~/.bashrc exactly" || fail "VDI uninstall .bashrc"
grep -q 'keep-zsh' "$H/.zshrc" && [ ! -L "$H/.zshrc" ] && pass "VDI uninstall restores ~/.zshrc" || fail "VDI uninstall .zshrc"

# --------------------------------------------------------------------
section "Unraid safety"
H="$TMP/unraid-home"
mkdir -p "$H"
before=$(snapshot)
out=$(DOTFILES_UNAME_TEST=Linux DOTFILES_SYSROOT_TEST="$TMP/sys-unraid" sandbox ./install.sh --yes 2>&1) &&
  fail "install without --unraid must refuse on Unraid" || {
  printf '%s' "$out" | grep -q 'must be selected explicitly' && pass "refuses without --unraid" || fail "wrong refusal: $out"
}
out=$(DOTFILES_UNAME_TEST=Linux DOTFILES_SYSROOT_TEST="$TMP/sys-unraid" sandbox ./install.sh --unraid --yes 2>&1) &&
  fail "install must refuse a repository outside /mnt" || {
  printf '%s' "$out" | grep -q 'persistent storage' && pass "refuses a repository outside /mnt" || fail "wrong refusal: $out"
}
[ "$before" = "$(snapshot)" ] && pass "refused Unraid runs change nothing" || fail "refused Unraid run changed files"
out=$(DOTFILES_UNAME_TEST=Linux DOTFILES_SYSROOT_TEST="$TMP/sys-linux" sandbox ./install.sh --unraid --yes 2>&1) &&
  fail "--unraid must refuse on a non-Unraid machine" || pass "--unraid refuses on non-Unraid"
writes=$(grep -nE '(>|>>|\bcp\b|\bmv\b|\bln\b|\btee\b|sed -i|\brm\b)[^#]*/boot' install.sh uninstall.sh scripts/*.sh platforms/unraid/*.sh || true)
[ -z "$writes" ] && pass "no script writes to /boot" || fail "possible write to /boot: $writes"

# --------------------------------------------------------------------
section "secret leakage"
files=$(git ls-files --cached --others --exclude-standard 2>/dev/null || find . -type f -not -path './.git/*')
patterns='-----BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|xox[abprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9_-]{20,}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.|(api[_-]?key|token|secret|passw(or)?d)[A-Za-z_]*[[:space:]]*[:=][[:space:]]*["'\'']?[A-Za-z0-9/+_.-]{16,}'
# shellcheck disable=SC2086
hits=$(printf '%s\n' $files | grep -v '^scripts/test.sh$' | xargs grep -nIiE "$patterns" 2>/dev/null || true)
[ -z "$hits" ] && pass "no credential patterns in tracked files" || fail "possible secret:
$hits"
# Private terms (employer names, hostnames) live outside the repository.
deny="${DOTFILES_DENYLIST:-$HOME/.config/dotfiles/denylist}"
if [ -r "$deny" ]; then
  # shellcheck disable=SC2086
  hits=$(printf '%s\n' $files | xargs grep -nIiF -f <(grep -v '^[[:space:]]*$' "$deny") 2>/dev/null | cut -d: -f1,2 || true)
  [ -z "$hits" ] && pass "no private terms from $deny" || fail "private terms found at: $hits"
else
  skip "no private denylist at $deny"
fi
if has gitleaks; then
  gitleaks detect --no-git --source . --redact >/dev/null 2>&1 && pass "gitleaks" || fail "gitleaks found secrets"
else
  skip "gitleaks not installed"
fi

printf '\n%d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" = 0 ]
