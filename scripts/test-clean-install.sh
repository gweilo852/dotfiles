#!/usr/bin/env bash
# Clean-install test: runs the real install.sh and uninstall.sh against
# temporary home directories and checks the result end to end.
#   scripts/test-clean-install.sh [--verbose] [--keep] [--help]
# Everything happens in one new directory from mktemp -d: HOME, the XDG
# directories, backups, the manifest and the tmux sockets. Package managers,
# sudo, chsh and downloads are blocked. Nothing outside that directory is
# changed; the last section checks this. See README "Clean-install testing".
set -uo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/test-clean-install.sh [options]

  -v, --verbose  Show the output of each installer, uninstaller and shell run.
  -k, --keep     Keep the test directory and print its location.
  -h, --help     Show this help.

Scenarios: clean home, existing configuration, idempotency, uninstall,
interactive zsh handoff (on a pseudo-terminal), tmux. Results are PASS,
FAIL or SKIP (a tool is missing). Exit status 1 when a check fails.
EOF
}

VERBOSE=0 KEEP=0
for arg in "$@"; do
  case "$arg" in
    -v | --verbose) VERBOSE=1 ;;
    -k | --keep) KEEP=1 ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

ROOT=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT" || exit 1
# shellcheck source=scripts/lib.sh
. "$ROOT/scripts/lib.sh" # no_tty, has

PASS=0 FAIL=0 SKIP=0
pass() { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$*"; }
fail() {
  FAIL=$((FAIL + 1))
  printf '  FAIL  %s\n' "$*"
  # In GitHub Actions, also an annotation (visible without the job log).
  [ -z "${GITHUB_ACTIONS:-}" ] || printf '::error title=test-clean-install.sh::%s\n' "$(printf '%s' "$*" | head -c 400 | tr '\n' ' ')"
}
skip() { SKIP=$((SKIP + 1)); printf '  SKIP  %s\n' "$*"; }
section() { printf '\n== %s\n' "$*"; }
check() { # description, command...: PASS when the command succeeds
  local what=$1
  shift
  if "$@"; then pass "$what"; else fail "$what"; fi
}

# --------------------------------------------------------------------
# The test directory and its cleanup
# --------------------------------------------------------------------

MARK=.dotfiles-clean-install-test
# Under /tmp, not $TMPDIR: tmux socket paths must stay short (macOS allows
# 104 bytes, and $TMPDIR there is deep under /var/folders).
T=$(mktemp -d /tmp/dotfiles-clean-install.XXXXXX) || { echo "mktemp -d failed" >&2; exit 1; }
T=$(cd -P "$T" && pwd)
TOKEN="$$.$RANDOM.$(date +%s)"
printf '%s\n' "$TOKEN" >"$T/$MARK"
LOG="$T/logs"
mkdir -p "$LOG" "$T/tmux" "$T/run" "$T/shim"
chmod 700 "$T/tmux" "$T/run"

cleanup() {
  local rc=$? s
  trap - EXIT INT TERM HUP
  # tmux servers of this run only: their sockets are under $T/tmux.
  for s in "$T"/tmux/*/*; do
    [ -S "$s" ] && tmux -S "$s" kill-server 2>/dev/null
  done
  if [ "$KEEP" = 1 ]; then
    printf '\nkept: %s\n' "$T"
    exit "$rc"
  fi
  # Remove only the directory that this run created and marked.
  case "$T" in
    */dotfiles-clean-install.??????) ;;
    *) echo "not removing $T: unexpected name" >&2; exit "$rc" ;;
  esac
  if [ -f "$T/$MARK" ] && [ "$(cat "$T/$MARK")" = "$TOKEN" ]; then
    chmod -R u+w "$T" 2>/dev/null
    rm -rf "$T"
  else
    echo "not removing $T: marker missing or different" >&2
  fi
  exit "$rc"
}
trap cleanup EXIT
trap 'echo "interrupted" >&2; exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# --------------------------------------------------------------------
# The isolated environment
# --------------------------------------------------------------------

# Commands that change the system or download. Each stub records the call
# and fails; the last section checks that the log is empty.
for c in sudo su doas apt apt-get dpkg dnf yum pacman zypper apk brew chsh usermod passwd curl wget; do
  printf '#!/bin/sh\necho "$0 $*" >>"%s/blocked.log"\necho "test-clean-install: blocked: ${0##*/}" >&2\nexit 97\n' "$T" >"$T/shim/$c"
  chmod +x "$T/shim/$c"
done

# Reduced PATHs: core tools only (no zsh, no starship), and core plus zsh.
BIN_MIN="$T/bin-min" BIN_ZSH="$T/bin-zsh"
mkdir -p "$BIN_MIN" "$BIN_ZSH"
for c in bash sh env cat ps grep sed awk tr cut dirname basename readlink ls mkdir rm mv cp ln chmod \
  touch id uname hostname head tail sort uniq wc date stty tty sleep find cmp mktemp tput infocmp locale; do
  p=$(command -v "$c" 2>/dev/null) || continue
  ln -s "$p" "$BIN_MIN/$c"
  ln -s "$p" "$BIN_ZSH/$c"
done
ZSH_BIN=$(command -v zsh 2>/dev/null || true)
[ -n "$ZSH_BIN" ] && ln -s "$ZSH_BIN" "$BIN_ZSH/zsh"
PY=$(command -v python3 2>/dev/null || true)
USER_NAME=$(id -un)

# Run a command in the isolated environment: new HOME, XDG directories,
# tmux socket directory, no system git config, the blocking stubs first on
# PATH, and no terminal (no_tty). Extra VAR=value words go before the
# command: sb HOME [VAR=value...] command...
sb() {
  local home=$1
  shift
  no_tty env -i HOME="$home" USER="$USER_NAME" LOGNAME="$USER_NAME" SHELL=/bin/bash \
    PATH="$T/shim:$PATH" TERM=xterm-256color LANG="${LANG:-C.UTF-8}" \
    XDG_CONFIG_HOME="$home/.config" XDG_CACHE_HOME="$home/.cache" \
    XDG_DATA_HOME="$home/.local/share" XDG_STATE_HOME="$home/.local/state" \
    XDG_RUNTIME_DIR="$T/run" TMUX_TMPDIR="$T/tmux" GIT_CONFIG_NOSYSTEM=1 NO_COLOR=1 \
    TIMESTAMP="${TS:-20000101-000000}" "$@"
}
# Run and keep the output in $LOG/NAME.log (shown with --verbose).
logged() { # NAME HOME [VAR=value...] command...
  local name=$1 rc
  shift
  sb "$@" >"$LOG/$name.log" 2>&1
  rc=$?
  if [ "$VERBOSE" = 1 ]; then
    printf '  ---- %s (exit %s)\n' "$name" "$rc"
    sed 's/^/  | /' "$LOG/$name.log"
  fi
  return "$rc"
}
show_log() { tail -n "${2:-8}" "$LOG/$1.log" | sed 's/^/        | /'; }

# Files, links and modes under a home; .cache is left out, because shells
# write completion caches there.
snapshot() {
  (cd "$1" && find . -path ./.cache -prune -o -print | LC_ALL=C sort | while IFS= read -r f; do
    if [ -L "$f" ]; then
      printf '%s -> %s\n' "$f" "$(readlink "$f")"
    elif [ -f "$f" ]; then
      printf '%s %s %s\n' "$f" "$(ls -ld "$f" | cut -c1-10)" "$(cksum <"$f")"
    else
      printf '%s %s\n' "$f" "$(ls -ld "$f" | cut -c1-10)"
    fi
  done)
}
count() { grep -c -- "$1" "$2" 2>/dev/null || true; }
filter_shell_noise() {
  sed $'s/\033\\[?1034h//g' |
    grep -vxE 'exit|.*no job control.*|.*cannot set terminal process group.*|.*Inappropriate ioctl.*' || true
}

# A probe line typed into a shell. It prints, for example,
#   R:zsh:42:zsh:1:keep:profile
# shell variable : arithmetic : process name : handoff marker : WORK_VAR :
# PROFILE_VAR. The typed text has $((40+2)), the output 42, so a match is
# always output.
# shellcheck disable=SC2016
PROBE='echo "R:${ZSH_VERSION:+zsh}${BASH_VERSION:+bash}:$((40+2)):$(ps -o comm= -p $$ | sed -e "s,.*/,," -e "s,^-,,"):${DOTFILES_ZSH_HANDOFF:-}:${WORK_VAR:-}:${PROFILE_VAR:-}"'
results() { grep -o 'R:[a-z]*:42:[^[:space:]]*' "$LOG/$1.txt" 2>/dev/null | paste -sd' ' -; }

# Type lines into a command on a new pseudo-terminal.
#   pty NAME HOME "line; line" [VAR=value...] command...
# Lines are separated by ";;". The transcript is in $LOG/NAME.txt.
pty() {
  local name=$1 home=$2 lines=$3 l rest
  shift 3
  local args=()
  rest=$lines
  while [ -n "$rest" ]; do
    l=${rest%%;;*}
    args+=(--line "$l")
    case "$rest" in *";;"*) rest=${rest#*;;} ;; *) rest="" ;; esac
  done
  sb "$home" "$PY" -I "$ROOT/tests/pty-run.py" --timeout 40 ${args[@]+"${args[@]}"} -- env "$@" >"$LOG/$name.log" 2>&1
  tr -d '\r' <"$LOG/$name.log" >"$LOG/$name.txt"
  if [ "$VERBOSE" = 1 ]; then
    printf '  ---- pty %s\n' "$name"
    sed 's/^/  | /' "$LOG/$name.txt"
  fi
}
expect_result() { # description, pty name, expected results (space separated)
  local got
  got=$(results "$2")
  if [ "$got" = "$3" ]; then
    pass "$1"
  else
    fail "$1: want '$3', got '$got'"
    tail -n 6 "$LOG/$2.txt" | sed 's/^/        | /'
  fi
}

# Metadata (never contents) of files that the test must not touch, in the
# real home and in the account's home from the user database.
REAL_HOME=$HOME
PW_HOME=$( (getent passwd "$USER_NAME" 2>/dev/null | cut -d: -f6) ||
  (dscl . -read "/Users/$USER_NAME" NFSHomeDirectory 2>/dev/null | awk '{print $2}'))
stat_sig() { stat -c '%s %Y %i %F' "$1" 2>/dev/null || stat -f '%z %m %i %HT' "$1" 2>/dev/null; }
fingerprint() {
  local h p
  for h in "$REAL_HOME" ${PW_HOME:+"$PW_HOME"}; do
    for p in .zshrc .zshrc.local .zprofile .zshenv .bashrc .bash_profile .bash_login .profile \
      .tmux.conf .tmux.conf.local .gitconfig .config/git/config .config/starship.toml \
      .config/wezterm/wezterm.lua .config/dotfiles/local.conf .local/state/dotfiles/manifest.tsv \
      .ssh/config .kube/config .claude/settings.json .claude/CLAUDE.md .aws/credentials \
      .config/gcloud/configurations/config_default; do
      if [ -e "$h/$p" ] || [ -L "$h/$p" ]; then
        printf '%s/%s %s\n' "$h" "$p" "$(stat_sig "$h/$p")"
      else
        printf '%s/%s absent\n' "$h" "$p"
      fi
    done
    printf '%s backups: %s\n' "$h" "$(ls -1 "$h/.dotfiles-backups" 2>/dev/null | wc -l | tr -d ' ')"
  done
}
FP_BEFORE=$(fingerprint)

expected_platform() {
  case "$(uname -s)" in
    Darwin) echo macos ;;
    Linux)
      if [ -f /etc/unraid-version ]; then echo unraid
      elif [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; then echo wsl
      else echo linux
      fi
      ;;
    *) echo unknown ;;
  esac
}
PLATFORM=$(expected_platform)

printf 'dotfiles clean-install test\n  repository: %s\n  test dir:   %s\n  platform:   %s\n' "$ROOT" "$T" "$PLATFORM"
printf '  tools:      zsh=%s tmux=%s starship=%s git=%s python3=%s\n' \
  "$(has zsh && echo yes || echo no)" "$(has tmux && tmux -V | cut -d' ' -f2 || echo no)" \
  "$(has starship && echo yes || echo no)" "$(has git && echo yes || echo no)" "$([ -n "$PY" ] && echo yes || echo no)"
if [ "$PLATFORM" = unraid ]; then
  echo "Unraid needs the repository under /mnt and --unraid; this test runs on macOS, Linux and WSL." >&2
  exit 2
fi

# --------------------------------------------------------------------
section "isolation"
case "$T/" in
  "$REAL_HOME"/*) fail "test directory is inside the real home: $T" ;;
  *) pass "test directory is outside the real home" ;;
esac
hits=$(grep -nE 'getent|getpwnam|getpwuid|dscl|~[A-Za-z_]' install.sh uninstall.sh scripts/lib.sh \
  scripts/bootstrap-*.sh scripts/install-release-binaries.sh | grep -v '^[^:]*:[0-9]*:[[:space:]]*#' || true)
[ -z "$hits" ] && pass "installer finds the home directory only through \$HOME (no user database lookup)" ||
  fail "installer reads the user database: $hits"
H="$T/probe-home"
mkdir -p "$H"
out=$(sb "$H" bash -c 'echo ~; cd && pwd' | paste -sd' ' -)
[ "$out" = "$H $H" ] && pass "bash resolves ~ to the test home" || fail "bash ~: $out"
if has zsh; then
  out=$(sb "$H" zsh -f -c 'print ~')
  [ "$out" = "$H" ] && pass "zsh resolves ~ to the test home" || fail "zsh ~: $out"
fi
if has git; then
  sb "$H" git config --global test.isolated yes
  [ -f "$H/.gitconfig" ] && pass "git --global writes the test home" || fail "git --global wrote elsewhere"
  rm -f "$H/.gitconfig"
fi
out=$(sb "$H" sudo true 2>&1)
case "$out" in *blocked*) pass "sudo is blocked in the test environment" ;; *) fail "sudo not blocked: $out" ;; esac
: >"$T/blocked.log"

# --------------------------------------------------------------------
section "clean home: install"
H="$T/home-clean"
mkdir -p "$H"
got=$(sb "$H" bash -c '. "$1"; detect_platform' sh "$ROOT/scripts/lib.sh")
[ "$got" = "$PLATFORM" ] && pass "platform detection: $got" || fail "platform detection: want $PLATFORM, got $got"

before=$(snapshot "$H")
logged clean-dry "$H" ./install.sh --dry-run --no-packages
[ "$before" = "$(snapshot "$H")" ] && pass "dry run changes nothing" || fail "dry run changed the home"
logged clean-noyes "$H" ./install.sh --no-packages && fail "a run without --yes and without a terminal must stop" ||
  pass "a run without --yes and without a terminal stops"
[ "$before" = "$(snapshot "$H")" ] && pass "the refused run changes nothing" || fail "the refused run changed the home"

# The real installer, with its validation step (doctor.sh --quick).
if TS=20000101-000001 logged clean-install "$H" ./install.sh --yes --no-packages; then
  pass "install.sh --yes --no-packages exits 0"
else
  fail "install.sh exit status"
  show_log clean-install
fi
grep -q "platform: $PLATFORM" "$LOG/clean-install.log" && pass "installer reports platform $PLATFORM" || fail "installer platform line"
grep -q 'doctor: no errors' "$LOG/clean-install.log" && pass "installer validation (doctor.sh) reports no errors" ||
  { fail "installer validation"; grep -E 'fail|error' "$LOG/clean-install.log" | head -n 5 | sed 's/^/        | /'; }

expect_links() { # home, then "relative-path repository-path" pairs on stdin
  local home=$1 rel src n=0
  while read -r rel src; do
    n=$((n + 1))
    if [ "$(readlink "$home/$rel")" = "$ROOT/$src" ] && [ -e "$home/$rel" ]; then
      pass "link ~/$rel -> $src"
    else
      fail "link ~/$rel: $(readlink "$home/$rel" 2>/dev/null || echo missing)"
    fi
  done
  links=$(find "$home" -type l | wc -l | tr -d ' ')
  [ "$links" = "$n" ] && pass "exactly $n links, no duplicates" || fail "$links links, want $n"
}
links_for_platform() {
  has zsh && echo ".zshrc config/zsh/zshrc"
  echo ".tmux.conf config/tmux/tmux.conf"
  echo ".config/starship.toml config/starship/starship.toml"
  if [ "$PLATFORM" = macos ] || { [ "$PLATFORM" = linux ] && has wezterm; }; then
    echo ".config/wezterm/wezterm.lua config/wezterm/wezterm.lua"
  fi
}
links_for_platform | expect_links "$H"

# Permissions.
if has zsh; then
  [ "$(ls -l "$H/.zshrc.local" | cut -c1-10)" = "-rw-------" ] && pass "~/.zshrc.local is private (600)" ||
    fail "~/.zshrc.local mode $(ls -l "$H/.zshrc.local" | cut -c1-10)"
fi
ww=$(find "$H" ! -type l -perm -002 | head -n 3)
[ -z "$ww" ] && pass "no world-writable files" || fail "world-writable: $ww"

# Backups and manifest: nothing existed, so nothing is backed up.
[ ! -e "$H/.dotfiles-backups" ] && pass "clean home: no backup directory" || fail "clean home: unexpected backups"
M="$H/.local/state/dotfiles/manifest.tsv"
if [ -f "$M" ]; then
  pass "manifest written: ${M#"$T"/}"
  bad=$(awk -F'\t' -v h="$H/" 'NF != 4 || $1 !~ /^(link|block|gitinclude|copy)$/ || index($2, h) != 1' "$M")
  [ -z "$bad" ] && pass "every manifest entry is well formed and inside the test home" || fail "manifest entries: $bad"
  dup=$(cut -f1,2,3 "$M" | sort | uniq -d)
  [ -z "$dup" ] && pass "no duplicate manifest entries" || fail "duplicate manifest entries: $dup"
else
  fail "manifest missing: $M"
fi

# Shell initialization.
err=$(sb "$H" bash -i -c 'exit' 2>&1 >/dev/null | filter_shell_noise)
[ -z "$err" ] && pass "interactive bash starts without errors" || fail "bash startup: $err"
out=$(sb "$H" bash -i -c 'type ll >/dev/null && type tmux-workspace >/dev/null && echo "loaded=$_DOTFILES_BASH_LOADED"' 2>/dev/null)
[ "$out" = loaded=1 ] && pass "bash loads the managed configuration (aliases, tmux helpers)" || fail "bash configuration: $out"
out=$(sb "$H" bash -c '. ~/.bashrc; echo only-this')
[ "$out" = only-this ] && pass "non-interactive bash prints nothing extra (scp, sftp)" || fail "non-interactive bash output: $out"
out=$(sb "$H" bash -l -c 'echo only-this')
[ "$out" = only-this ] && pass "non-interactive login bash prints nothing extra" || fail "bash -lc output: $out"
if has zsh; then
  err=$(sb "$H" zsh -i -c 'exit' 2>&1 >/dev/null | filter_shell_noise)
  [ -z "$err" ] && pass "interactive zsh starts without errors" || fail "zsh startup: $err"
  out=$(sb "$H" zsh -i -c 'print -r -- "$DOTFILES_DIR"' 2>/dev/null)
  [ "$out" = "$ROOT" ] && pass "zsh loads the managed configuration" || fail "zsh configuration: $out"
else
  skip "zsh not installed: zsh initialization"
fi
if has starship; then
  n=$(sb "$H" bash -i -c 'echo "$PROMPT_COMMAND"' 2>/dev/null | grep -o 'starship_precmd' | wc -l | tr -d ' ')
  [ "$n" = 1 ] && pass "bash: starship initialized once" || fail "bash: starship in PROMPT_COMMAND $n times"
  if has zsh; then
    n=$(sb "$H" zsh -i -c 'print -l $precmd_functions' 2>/dev/null | grep -c 'starship_precmd$')
    [ "$n" = 1 ] && pass "zsh: starship initialized once" || fail "zsh: starship initialized $n times"
  fi
else
  skip "starship not installed: prompt initialization"
fi

# Git.
if has git; then
  n=$(sb "$H" git config --global --get-all include.path | grep -cxF "$ROOT/config/git/config")
  [ "$n" = 1 ] && pass "git include added once" || fail "git include count $n"
  [ "$(sb "$H" git config --global --includes --get delta.navigate)" = true ] && pass "git reads the managed settings through the include" ||
    fail "git include does not resolve"
  outside=$(sb "$H" git config --global --list --show-origin | grep -v "file:$H/" | grep -v "file:$ROOT/" || true)
  [ -z "$outside" ] && pass "git global settings come only from the test home and the repository" || fail "git origins: $outside"
fi

# Local overrides, loaded after the managed configuration.
printf 'export CLEAN_ZSH_LOCAL=zsh-local\n' >>"$H/.zshrc.local"
printf 'export CLEAN_BASH_LOCAL=bash-local\n' >>"$H/.bashrc"
printf 'set -g @clean_local yes\nset -g history-limit 4242\n' >"$H/.tmux.conf.local"
out=$(sb "$H" bash -i -c 'echo "$CLEAN_BASH_LOCAL"' 2>/dev/null)
[ "$out" = bash-local ] && pass "bash: settings after the block in ~/.bashrc apply" || fail "bash local: $out"
if has zsh; then
  out=$(sb "$H" zsh -i -c 'echo "$CLEAN_ZSH_LOCAL"' 2>/dev/null)
  [ "$out" = zsh-local ] && pass "zsh: ~/.zshrc.local applies" || fail "zsh local: $out"
fi

# No duplicate initialization when the files are sourced again.
# Compared with one load: the inherited PATH may hold duplicates already
# (Debian's ~/.profile adds ~/.local/bin again after ~/.bashrc).
once=$(sb "$H" bash -i -c 'echo "$PATH"' 2>/dev/null)
twice=$(sb "$H" bash -i -c '. ~/.bashrc; . ~/.bashrc; echo "$PATH"' 2>/dev/null)
[ -n "$once" ] && [ "$once" = "$twice" ] && pass "bash: sourcing ~/.bashrc again adds no PATH entries" ||
  fail "bash PATH changes on reload: $once -> $twice"
if has starship; then
  n=$(sb "$H" bash -i -c '. ~/.bashrc; echo "$PROMPT_COMMAND"' 2>/dev/null | grep -o 'starship_precmd' | wc -l | tr -d ' ')
  [ "$n" = 1 ] && pass "bash: sourcing ~/.bashrc again keeps one starship hook" || fail "bash: $n starship hooks"
fi
if has zsh; then
  out=$(sb "$H" zsh -i -c 'source ~/.zshrc; print -l $path | sort | uniq -d; print -l $precmd_functions | sort | uniq -d' 2>/dev/null)
  [ -z "$out" ] && pass "zsh: sourcing ~/.zshrc again adds no PATH entries or prompt hooks" || fail "zsh duplicates: $out"
fi

# --------------------------------------------------------------------
section "tmux (isolated socket under the test directory)"
if has tmux; then
  pass "tmux $(tmux -V | cut -d' ' -f2)"
  tx() { sb "$H" tmux -L clean "$@"; }
  ref=$(sb "$H" tmux -L ref -f /dev/null start-server \; show-options -gv default-shell 2>/dev/null)
  sb "$H" tmux -L ref kill-server 2>/dev/null
  err=$(tx new-session -d -s demo-project -n edit 2>&1)
  [ -z "$err" ] && pass "configuration loads; session demo-project created" || fail "tmux start: $err"
  [ "$(tx show-options -gv @clean_local)" = yes ] && [ "$(tx show-options -gv history-limit)" = 4242 ] &&
    pass "~/.tmux.conf.local is loaded last" || fail "tmux local override"
  tx new-session -d -s STORY-1234
  tx new-window -d -t demo-project: -n shell
  tx split-window -d -t demo-project:shell
  [ "$(tx list-windows -t demo-project -F '#W' | paste -sd, -)" = "edit,shell" ] && pass "window created" || fail "tmux windows"
  [ "$(tx list-panes -t demo-project:shell | wc -l | tr -d ' ')" = 2 ] && pass "pane created" || fail "tmux panes"
  [ "$(tx list-sessions -F '#S' | LC_ALL=C sort | paste -sd, -)" = "STORY-1234,demo-project" ] && pass "sessions listed" || fail "tmux sessions"
  tx source-file "$H/.tmux.conf" && pass "configuration reload (source-file)" || fail "tmux reload"
  [ "$(tx show-options -gv default-shell)" = "$ref" ] && pass "handoff off: new windows use the tmux default ($ref)" ||
    fail "tmux default-shell: $(tx show-options -gv default-shell), want $ref"
  out=$(sb "$H" bash -c '. "$1/config/shell/tmux.sh"; DOTFILES_TMUX_SOCKET=clean tmux-workspace -d STORY-1234 claude codex' sh "$ROOT")
  [ "$(tx list-windows -t STORY-1234 -F '#W' | tail -n 2 | paste -sd, -)" = "claude,codex" ] &&
    pass "tmux-workspace helper adds windows to a story session" || fail "tmux-workspace: $out"
  socket=$(tx display-message -p '#{socket_path}')
  case "$socket" in "$T"/tmux/*) pass "socket is inside the test directory" ;; *) fail "socket outside the test directory: $socket" ;; esac
  tx kill-server
  sleep 0.2
  ! tx has-session 2>/dev/null && pass "test server stopped; no other server touched" || fail "tmux server still running"
else
  skip "tmux not installed: tmux checks"
fi

# --------------------------------------------------------------------
section "clean home: idempotency and uninstall"
before=$(snapshot "$H")
local_before=$(cksum "$H/.bashrc" "$H/.tmux.conf.local" ${ZSH_BIN:+"$H/.zshrc.local"})
TS=20000101-000002 logged clean-install2 "$H" ./install.sh --yes --no-packages --skip-validate
grep -q 'done: 0 change' "$LOG/clean-install2.log" && pass "second install makes no changes" ||
  fail "second install: $(grep 'done:' "$LOG/clean-install2.log")"
[ "$before" = "$(snapshot "$H")" ] && pass "second install leaves every file identical" || fail "second install changed files"
[ ! -e "$H/.dotfiles-backups/20000101-000002" ] && pass "second install makes no backups" || fail "second install made backups"
[ "$(count '>>> dotfiles (bash)' "$H/.bashrc")" = 1 ] && pass "one bash block" || fail "bash block count"
[ "$local_before" = "$(cksum "$H/.bashrc" "$H/.tmux.conf.local" ${ZSH_BIN:+"$H/.zshrc.local"})" ] &&
  pass "local files unchanged" || fail "local files changed"
logged clean-dry2 "$H" ./install.sh --dry-run --no-packages
grep -q 'dry run: 0 change' "$LOG/clean-dry2.log" && pass "dry run after install plans 0 changes" || fail "dry run plans changes"

logged clean-undry "$H" ./uninstall.sh --dry-run
[ "$before" = "$(snapshot "$H")" ] && pass "uninstall dry run changes nothing" || fail "uninstall dry run changed files"
logged clean-uninstall "$H" ./uninstall.sh --yes && pass "uninstall.sh --yes exits 0" || { fail "uninstall exit status"; show_log clean-uninstall; }
left=$(find "$H" -type l)
[ -z "$left" ] && pass "all managed links removed" || fail "links left: $left"
blocks=$(grep -rl '>>> dotfiles (' "$H" --exclude-dir=.dotfiles-backups 2>/dev/null || true)
[ -z "$blocks" ] && pass "no managed blocks left" || fail "blocks left in: $blocks"
grep -qx 'export CLEAN_BASH_LOCAL=bash-local' "$H/.bashrc" && pass "user lines in ~/.bashrc kept" || fail "~/.bashrc user lines lost"
[ -f "$H/.tmux.conf.local" ] && pass "~/.tmux.conf.local kept" || fail "~/.tmux.conf.local removed"
if has zsh; then [ -f "$H/.zshrc.local" ] && pass "~/.zshrc.local kept" || fail "~/.zshrc.local removed"; fi
if has git; then
  [ ! -e "$H/.gitconfig" ] && pass "~/.gitconfig that install created is removed when empty" || fail "~/.gitconfig left: $(cat "$H/.gitconfig")"
fi
before=$(snapshot "$H")
logged clean-uninstall2 "$H" ./uninstall.sh --yes && grep -q '^==> 0 change' "$LOG/clean-uninstall2.log" &&
  pass "second uninstall is safe and makes no changes" || { fail "second uninstall"; show_log clean-uninstall2; }
[ "$before" = "$(snapshot "$H")" ] && pass "second uninstall leaves every file identical" || fail "second uninstall changed files"

# --------------------------------------------------------------------
section "existing configuration"
H="$T/home-existing"
mkdir -p "$H/.config/dotfiles" "$H/.ssh"
cat >"$H/.bashrc" <<'EOF'
# synthetic distribution ~/.bashrc (test data)
export EXAMPLE_PROXY_NOTE="keep-bash"
alias deploy-test='echo synthetic alias'
tm() { echo user-tm; }
EOF
cat >"$H/.profile" <<'EOF'
# synthetic ~/.profile in the Debian style (test data)
if [ -n "$BASH_VERSION" ]; then
  if [ -f "$HOME/.bashrc" ]; then . "$HOME/.bashrc"; fi
fi
export EXAMPLE_PROFILE_VAR="keep-profile"
EOF
cat >"$H/.zshrc" <<'EOF'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git)
source $ZSH/oh-my-zsh.sh
eval "$(starship init zsh)"
export EXAMPLE_WORK_SETTING="keep-zsh"
EOF
printf 'export EXAMPLE_ZSH_LOCAL="keep-local"\n' >"$H/.zshrc.local"
chmod 600 "$H/.zshrc.local"
printf 'set -g mouse off\n' >"$H/.tmux.conf"
printf 'set -g @example_local yes\n' >"$H/.tmux.conf.local"
printf '[user]\n\tname = Example User\n\temail = user@example.net\n[alias]\n\tst = status\n' >"$H/.gitconfig"
printf '# synthetic local settings\nEXAMPLE_KEY=1\n' >"$H/.config/dotfiles/local.conf"
printf 'Host example\n  HostName example.net\n' >"$H/.ssh/config"
printf 'unrelated\n' >"$H/notes.txt"
mkdir -p "$T/orig-existing"
(cd "$H" && cp -p .bashrc .profile .zshrc .zshrc.local .tmux.conf .tmux.conf.local .gitconfig notes.txt "$T/orig-existing/")
cp -p "$H/.ssh/config" "$T/orig-existing/ssh-config"
cp -p "$H/.config/dotfiles/local.conf" "$T/orig-existing/local.conf"
git_before=$(sb "$H" git config --global --list 2>/dev/null)
same() { cmp -s "$H/$1" "$T/orig-existing/${2:-$1}"; }
local_untouched() { same .zshrc.local && same .tmux.conf.local && same .config/dotfiles/local.conf local.conf && same .ssh/config ssh-config && same notes.txt && same .profile; }

TS=20000101-000003 logged existing-install "$H" ./install.sh --yes --no-packages --skip-validate &&
  pass "install over existing configuration exits 0" || { fail "install exit status"; show_log existing-install; }
B="$H/.dotfiles-backups/20000101-000003"
for f in .bashrc .tmux.conf .gitconfig; do
  cmp -s "$B/$f" "$T/orig-existing/$f" && pass "backup of ~/$f matches the original" || fail "backup of ~/$f"
done
if has zsh; then cmp -s "$B/.zshrc" "$T/orig-existing/.zshrc" && pass "backup of ~/.zshrc matches the original" || fail "backup of ~/.zshrc"; fi
head -n 4 "$H/.bashrc" | cmp -s - "$T/orig-existing/.bashrc" && pass "existing ~/.bashrc lines kept in place" || fail "~/.bashrc lines changed"
[ "$(count '>>> dotfiles (bash)' "$H/.bashrc")" = 1 ] && pass "bash block added once" || fail "bash block count"
[ "$(count '>>> dotfiles' "$H/.profile")" = 0 ] && pass "~/.profile already loads ~/.bashrc: no block added" || fail "~/.profile changed"
local_untouched && pass "local files unchanged (.zshrc.local, .tmux.conf.local, local.conf, .ssh/config, .profile)" || fail "a local file changed"
links_for_platform | expect_links "$H"
if has git; then
  [ "$(sb "$H" git config --global user.name)" = "Example User" ] && [ "$(sb "$H" git config --global alias.st)" = status ] &&
    pass "git user settings kept" || fail "git user settings lost"
  [ "$(sb "$H" git config --global --get-all include.path | grep -cxF "$ROOT/config/git/config")" = 1 ] &&
    pass "git include added once" || fail "git include count"
fi
out=$(sb "$H" bash -l -i -c 'tm; echo "$EXAMPLE_PROXY_NOTE $EXAMPLE_PROFILE_VAR"; type deploy-test >/dev/null && echo alias-ok' 2>/dev/null | paste -sd' ' -)
[ "$out" = "user-tm keep-bash keep-profile alias-ok" ] && pass "bash login keeps aliases, variables and a user tm function" ||
  fail "bash preservation: $out"
if has zsh; then
  out=$(sb "$H" zsh -i -c 'echo "$EXAMPLE_ZSH_LOCAL"' 2>/dev/null)
  [ "$out" = keep-local ] && pass "zsh uses the existing ~/.zshrc.local" || fail "zsh local: $out"
  if has starship; then
    n=$(sb "$H" zsh -i -c 'print -l $precmd_functions' 2>/dev/null | grep -c 'starship_precmd$')
    [ "$n" = 1 ] && pass "zsh: starship initialized once" || fail "zsh: starship $n times"
  fi
fi
before=$(snapshot "$H")
TS=20000101-000004 logged existing-install2 "$H" ./install.sh --yes --no-packages --skip-validate
grep -q 'done: 0 change' "$LOG/existing-install2.log" && [ "$before" = "$(snapshot "$H")" ] &&
  pass "second install: no changes, no new backups" || fail "second install: $(grep 'done:' "$LOG/existing-install2.log")"

logged existing-uninstall "$H" ./uninstall.sh --yes || { fail "uninstall exit status"; show_log existing-uninstall; }
same .bashrc && pass "uninstall restores ~/.bashrc exactly" || fail "~/.bashrc differs after uninstall"
same .tmux.conf && [ ! -L "$H/.tmux.conf" ] && pass "uninstall restores ~/.tmux.conf" || fail "~/.tmux.conf not restored"
if has zsh; then same .zshrc && [ ! -L "$H/.zshrc" ] && pass "uninstall restores ~/.zshrc" || fail "~/.zshrc not restored"; fi
if has git; then
  [ "$(sb "$H" git config --global --list 2>/dev/null)" = "$git_before" ] && pass "uninstall restores the git settings" ||
    fail "git settings differ after uninstall"
fi
local_untouched && pass "uninstall leaves local and unrelated files unchanged" || fail "uninstall changed a local file"
before=$(snapshot "$H")
logged existing-uninstall2 "$H" ./uninstall.sh --yes && [ "$before" = "$(snapshot "$H")" ] &&
  pass "second uninstall changes nothing" || fail "second uninstall changed files"

# --------------------------------------------------------------------
section "interactive zsh handoff: install"
H="$T/home-zsh"
mkdir -p "$H"
printf '# synthetic (test data)\nexport WORK_VAR=keep\n' >"$H/.bashrc"
cat >"$H/.profile" <<'EOF'
# synthetic ~/.profile in the Debian style (test data)
if [ -n "$BASH_VERSION" ]; then
  if [ -f "$HOME/.bashrc" ]; then . "$HOME/.bashrc"; fi
fi
export PROFILE_VAR=profile
EOF
cp "$H/.bashrc" "$T/zsh.bashrc"
cp "$H/.profile" "$T/zsh.profile"
LC="$H/.config/dotfiles/local.conf"
TS=20000101-000005 logged zsh-install "$H" ./install.sh --yes --no-packages --skip-validate --interactive-zsh &&
  pass "install.sh --interactive-zsh exits 0" || { fail "install --interactive-zsh"; show_log zsh-install; }
grep -qx 'DOTFILES_INTERACTIVE_ZSH=1' "$LC" && [ "$(count '>>> dotfiles (interactive-zsh)' "$LC")" = 1 ] &&
  pass "local.conf has the setting, in one marked block" || fail "local.conf content"
grep -q "block	$LC	interactive-zsh" "$H/.local/state/dotfiles/manifest.tsv" && pass "the setting is in the manifest" ||
  fail "local.conf block not in manifest"
before=$(snapshot "$H")
TS=20000101-000006 logged zsh-install2 "$H" ./install.sh --yes --no-packages --skip-validate --interactive-zsh
TS=20000101-000007 logged zsh-install3 "$H" ./install.sh --yes --no-packages --skip-validate
grep -q 'done: 0 change' "$LOG/zsh-install2.log" && grep -q 'done: 0 change' "$LOG/zsh-install3.log" &&
  [ "$before" = "$(snapshot "$H")" ] && pass "repeat runs, with and without the option, change nothing" ||
  fail "repeat runs changed files"
if has zsh; then
  grep -q "interactive zsh handoff: on" "$LOG/zsh-install.log" && pass "installer reports the handoff as on" || fail "installer summary"
else
  grep -q 'zsh not found' "$LOG/zsh-install.log" && pass "without zsh the installer warns; the handoff stays inactive" || fail "installer zsh warning"
fi
mkdir -p "$T/sys-unraid/etc"
echo 'version="7.1.0"' >"$T/sys-unraid/etc/unraid-version"
out=$(sb "$H" DOTFILES_UNAME=Linux DOTFILES_SYSROOT="$T/sys-unraid" ./install.sh --yes --unraid --interactive-zsh 2>&1)
case "$out" in *"not available on Unraid"*) pass "--interactive-zsh is refused on Unraid" ;; *) fail "Unraid refusal: $out" ;; esac

# --------------------------------------------------------------------
section "interactive zsh handoff: shells"
if ! has zsh; then
  skip "zsh not installed: handoff shells"
elif [ -z "$PY" ]; then
  skip "python3 not installed: pseudo-terminal tests"
else
  # Interactive shells on a real pseudo-terminal.
  pty login "$H" "$PROBE;;exit" bash -l
  expect_result "login bash (SSH) hands off to zsh; profile and bashrc variables kept" login "R:zsh:42:zsh:1:keep:profile"
  pty nonlogin "$H" "$PROBE;;exit" bash -i
  expect_result "non-login interactive bash hands off to zsh" nonlogin "R:zsh:42:zsh:1:keep:"
  pty parent "$H" 'echo "PP:$(ps -o comm= -p $PPID | sed "s,.*/,,"):$((7*6))";;exit' bash -l
  pp=$(grep -o 'PP:[^:]*:42' "$LOG/parent.txt" | tail -n 1)
  case "$pp" in PP:*sh:42 | PP::42) fail "a shell stays behind zsh ($pp)" ;; PP:*) pass "bash is replaced (exec), not nested ($pp)" ;; *) fail "parent probe: no output" ;; esac
  pty escape "$H" "$PROBE;;exit" DOTFILES_NO_ZSH=1 bash -i
  expect_result "escape: DOTFILES_NO_ZSH=1 bash -i stays bash" escape "R:bash:42:bash::keep:"
  pty dashc "$H" "" bash -i -c "$PROBE"
  expect_result "bash -ic COMMAND on a terminal runs the command in bash" dashc "R:bash:42:bash::keep:"
  pty sshcmd "$H" "" SSH_CONNECTION="192.0.2.1 50000 192.0.2.2 22" bash -c ". ~/.bashrc; $PROBE"
  expect_result "ssh -t host COMMAND style (bash -c on a terminal) stays bash" sshcmd "R:bash:42:bash::keep:"
  pty dumb "$H" "$PROBE;;exit" TERM=dumb bash -i
  expect_result "TERM=dumb (editor shells) stays bash" dumb "R:bash:42:bash::keep:"
  pty nozsh "$H" "$PROBE;;exit" PATH="$BIN_MIN" HOMEBREW_PREFIX=/nonexistent bash -i
  expect_result "zsh missing from PATH: bash stays, no error" nozsh "R:bash:42:bash::keep:"
  ! grep -qiE 'cannot start|not found|error' "$LOG/nozsh.txt" && pass "no error text when zsh is missing" ||
    fail "error text with zsh missing: $(grep -iE 'cannot start|not found|error' "$LOG/nozsh.txt" | head -n 2)"
  pty badzsh "$H" "$PROBE;;exit" DOTFILES_ZSH=/nonexistent/zsh bash -l
  expect_result "DOTFILES_ZSH points to a missing file: bash stays" badzsh "R:bash:42:bash::keep:profile"
  pty nostarship "$H" "$PROBE;;exit" PATH="$BIN_ZSH" HOMEBREW_PREFIX=/nonexistent bash -i
  expect_result "starship missing: zsh still starts with the plain prompt" nostarship "R:zsh:42:zsh:1:keep:"
  ! grep -qE 'command not found|no such file' "$LOG/nostarship.txt" && pass "no errors without starship" ||
    fail "errors without starship: $(grep -E 'command not found|no such file' "$LOG/nostarship.txt" | head -n 2)"
  pty nested "$H" "$PROBE;;bash -i;;$PROBE;;exit;;$PROBE;;exit" bash -l
  expect_result "bash started from the zsh stays bash (no loop); exit returns to zsh" nested \
    "R:zsh:42:zsh:1:keep:profile R:bash:42:bash:1:keep:profile R:zsh:42:zsh:1:keep:profile"
  printf '#!/usr/bin/env bash\necho "S:${BASH_VERSION:+bash}:$((1+1))"\n' >"$H/script.sh"
  printf '#!/bin/sh\necho "P:posix:$((2+3))"\n' >"$H/posix.sh"
  chmod +x "$H/script.sh" "$H/posix.sh"
  pty scripts "$H" '~/script.sh;;~/posix.sh;;exit' bash -l
  grep -qx 'S:bash:2' "$LOG/scripts.txt" && grep -qx 'P:posix:5' "$LOG/scripts.txt" &&
    pass "scripts started from the zsh use their own interpreters" || fail "script interpreters"
  if has starship; then
    # Non-login: on Debian /etc/profile resets PATH, which can drop the
    # starship in ~/.local/bin of the real home.
    pty reinit "$H" 'source ~/.zshrc;;echo "N:$(print -l $precmd_functions | grep -c starship_precmd):$((1+1))";;exit' bash -i
    grep -qx 'N:1:2' "$LOG/reinit.txt" && pass "sourcing ~/.zshrc again in the handed-off zsh keeps one prompt hook" ||
      fail "zsh re-init: $(grep -o 'N:[0-9]*:2' "$LOG/reinit.txt")"
  fi
fi

# Without a terminal: never hand off.
out=$(sb "$H" bash -c "$PROBE" | grep -o 'R:[^ ]*')
[ "$out" = "R:bash:42:bash:::" ] && pass "non-interactive bash -c stays bash" || fail "bash -c: $out"
out=$(sb "$H" SSH_CONNECTION="192.0.2.1 50000 192.0.2.2 22" bash -c ". ~/.bashrc; $PROBE")
[ "$out" = "R:bash:42:bash::keep:" ] && pass "ssh host COMMAND style (bash -c, no terminal) prints only its output" || fail "ssh-style: $out"
out=$(sb "$H" bash -i -c "$PROBE" 2>/dev/null)
[ "$out" = "R:bash:42:bash::keep:" ] && pass "bash -ic without a terminal stays bash" || fail "bash -ic: $out"
# The data arrives on stdin, as with scp and sftp (no_tty replaces this
# script's stdin, so the inner shell opens the file).
printf 'payload\n' >"$T/payload"
sb "$H" sh -c 'exec bash -c ". ~/.bashrc; cat >\"\$HOME/copied\"" <"$1"' sh "$T/payload" >"$T/scp.out" 2>&1
grep -qx payload "$H/copied" && [ ! -s "$T/scp.out" ] && pass "scp/sftp style transfer through bash -c is clean" || fail "transfer: $(cat "$T/scp.out")"

# tmux follows the setting.
if has tmux && has zsh; then
  ref=$(sb "$H" tmux -L zref -f /dev/null start-server \; show-options -gv default-shell 2>/dev/null)
  sb "$H" tmux -L zref kill-server 2>/dev/null
  zt() { sb "$H" tmux -L zclean "$@"; }
  zt new-session -d -s STORY-1234
  want=$(sb "$H" sh "$ROOT/config/tmux/shell.sh" --print)
  [ "$(zt show-options -gv default-shell)" = "$want" ] && case "$want" in /*zsh) true ;; *) false ;; esac &&
    pass "handoff on: tmux default-shell is $want" || fail "tmux default-shell: $(zt show-options -gv default-shell), want $want"
  zt new-window -d -t STORY-1234: -n work
  sleep 0.5
  [ "$(zt display-message -p -t STORY-1234:work '#{pane_current_command}')" = zsh ] && pass "a new window runs zsh" ||
    fail "new window runs $(zt display-message -p -t STORY-1234:work '#{pane_current_command}')"
fi

# Turn it off again.
TS=20000101-000008 logged zsh-off "$H" ./install.sh --yes --no-packages --skip-validate --no-interactive-zsh
! grep -q 'DOTFILES_INTERACTIVE_ZSH' "$LC" && pass "--no-interactive-zsh removes the setting" || fail "setting still in local.conf"
[ -f "$H/.dotfiles-backups/20000101-000008/.config/dotfiles/local.conf" ] && pass "local.conf backed up first" || fail "no local.conf backup"
if has zsh && [ -n "$PY" ]; then
  pty off "$H" "$PROBE;;exit" bash -l
  expect_result "after --no-interactive-zsh, a login bash stays bash" off "R:bash:42:bash::keep:profile"
fi
if has tmux && has zsh; then
  zt source-file "$H/.tmux.conf"
  [ "$(zt show-options -gv default-shell)" = "$ref" ] && pass "tmux reload returns to the default shell ($ref)" ||
    fail "tmux reload kept $(zt show-options -gv default-shell)"
  zt kill-server
fi
TS=20000101-000009 logged zsh-on "$H" ./install.sh --yes --no-packages --skip-validate --interactive-zsh
grep -qx 'DOTFILES_INTERACTIVE_ZSH=1' "$LC" && pass "--interactive-zsh turns it on again" || fail "turn on again"

logged zsh-uninstall "$H" ./uninstall.sh --yes || { fail "uninstall exit status"; show_log zsh-uninstall; }
cmp -s "$H/.bashrc" "$T/zsh.bashrc" && cmp -s "$H/.profile" "$T/zsh.profile" &&
  pass "uninstall restores ~/.bashrc and ~/.profile exactly" || fail "~/.bashrc or ~/.profile differ"
! grep -q 'DOTFILES_INTERACTIVE_ZSH' "$LC" 2>/dev/null && pass "uninstall removes the handoff setting" || fail "handoff setting left"
if has zsh && [ -n "$PY" ]; then
  pty after "$H" "$PROBE;;exit" bash -l
  expect_result "after uninstall, a login bash stays bash" after "R:bash:42:bash::keep:profile"
fi

# A home without any profile file: bash login reads nothing, so
# --interactive-zsh creates ~/.profile; uninstall deletes it again.
H="$T/home-noprofile"
mkdir -p "$H"
TS=20000101-000010 logged noprofile-install "$H" ./install.sh --yes --no-packages --skip-validate --interactive-zsh
grep -q 'BASH_VERSION' "$H/.profile" 2>/dev/null && pass "no profile file: ~/.profile created with a bash-only block" || fail "~/.profile not created"
out=$(sb "$H" sh -l -c 'echo profile-ok' 2>&1)
[ "$out" = profile-ok ] && pass "sh login shells read the new ~/.profile without errors" || fail "sh -l: $out"
if has zsh && [ -n "$PY" ]; then
  pty noprofile "$H" "$PROBE;;exit" bash -l
  expect_result "login bash hands off through the new ~/.profile" noprofile "R:zsh:42:zsh:1::"
fi
logged noprofile-uninstall "$H" ./uninstall.sh --yes
[ ! -e "$H/.profile" ] && [ ! -e "$H/.bashrc" ] && [ ! -e "$H/.config/dotfiles/local.conf" ] &&
  pass "uninstall deletes the files that install created (.profile, .bashrc, local.conf)" ||
  fail "left: $(cd "$H" && ls -A .profile .bashrc .config/dotfiles/local.conf 2>/dev/null | paste -sd' ' -)"

# --------------------------------------------------------------------
section "nothing outside the test directory changed"
[ "$FP_BEFORE" = "$(fingerprint)" ] && pass "real home: shell, git, tmux, ssh, kube, cloud and Claude files unchanged" ||
  fail "real home changed: $(diff <(printf '%s\n' "$FP_BEFORE") <(fingerprint) | head -n 6)"
[ ! -s "$T/blocked.log" ] && pass "no sudo, package manager, chsh or download was called" ||
  fail "blocked commands were called: $(head -n 5 "$T/blocked.log")"
stray=$(ls -d "/tmp/tmux-$(id -u)/clean" "/tmp/tmux-$(id -u)/zclean" 2>/dev/null || true)
[ -z "$stray" ] && pass "no test socket in the default tmux directory" || fail "test sockets outside the test directory: $stray"

printf '\n%d PASS, %d FAIL, %d SKIP\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" = 0 ]
