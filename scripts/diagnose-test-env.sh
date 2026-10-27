#!/usr/bin/env bash
# Read-only diagnostics for test failures on a hardened host (a VDI).
#   scripts/diagnose-test-env.sh            all checks
#   scripts/diagnose-test-env.sh --no-pty   skip the pseudo-terminal checks
# Reports: temporary directories (mount options, a real execution probe),
# resource limits, cgroup memory limits and OOM counters, kernel OOM
# messages when readable, security agents by process name, and a small
# pseudo-terminal matrix with the exit status, signal and time of each run.
# Changes nothing except one temporary directory, which it removes. Prints
# variable names, never values. The pseudo-terminal checks start interactive
# shells on a Python PTY, the pattern that may be killed; an endpoint-
# security agent may report them. Use --no-pty if that is not acceptable.
set -uo pipefail
ROOT=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/lib.sh
. "$ROOT/scripts/lib.sh"

PTY_CHECKS=1
case "${1:-}" in
  --no-pty) PTY_CHECKS=0 ;;
  -h | --help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") ;;
  *) echo "usage: $0 [--no-pty]" >&2; exit 2 ;;
esac
note() { printf '  %s\n' "$*"; }

info "system"
note "$(detect_distro), $(uname -sr) $(uname -m), user $(id -un), shell process $(ps -o comm= -p "$PPID" 2>/dev/null)"
note "bash $BASH_VERSION, python3 $(python3 -c 'import sys; print(sys.version.split()[0])' 2>/dev/null || echo missing)"
names=$(env | cut -d= -f1 | grep -E '^(TELEPORT|SSH_CONNECTION|SSH_TTY|TMUX|TMPDIR|XDG_RUNTIME_DIR|DOTFILES_)' | sort | paste -sd' ' -)
note "set (names only): ${names:-none}"

info "temporary directories"
for d in "${DOTFILES_TEST_TMPDIR:-}" "${TMPDIR:-}" /tmp /var/tmp "${XDG_RUNTIME_DIR:-}"; do
  [ -n "$d" ] && [ -d "$d" ] || continue
  opts=$( (findmnt -no OPTIONS -T "$d" || df -P "$d" | awk 'NR == 2 { print "mounted on " $6 }') 2>/dev/null | head -n 1 | cut -c1-70)
  if DOTFILES_TEST_TMPDIR=$d TMPDIR=/nonexistent XDG_RUNTIME_DIR='' exec_tmpdir 0 | grep -qxF "$d"; then
    note "$d: exec ok   ($opts)"
  else
    note "$d: EXEC FAILS or not writable   ($opts)"
  fi
done
chosen=$(exec_tmpdir 40 || true)
note "clean-install test would use: ${chosen:-none (set DOTFILES_TEST_TMPDIR)}"

info "limits"
ulimit -a 2>/dev/null | grep -E 'max memory|virtual|cpu time|max user processes|open files' | sed 's/^/  /'
cg=""
if [ -r /proc/self/cgroup ]; then
  rel=$(awk -F: '$1 == "0" { print $3 }' /proc/self/cgroup)
  note "cgroup: ${rel:-$(head -n 1 /proc/self/cgroup)}"
  [ -n "$rel" ] && [ -d "/sys/fs/cgroup$rel" ] && cg="/sys/fs/cgroup$rel"
fi
oom_kills() { [ -n "$cg" ] && awk '$1 == "oom_kill" { print $2 }' "$cg/memory.events" 2>/dev/null; }
if [ -n "$cg" ]; then
  for f in memory.max memory.high pids.max; do
    [ -r "$cg/$f" ] && note "$f: $(cat "$cg/$f")"
  done
  note "memory.events oom_kill: $(oom_kills || echo unreadable)"
fi
if out=$(dmesg 2>/dev/null); then
  n=$(printf '%s\n' "$out" | grep -ciE 'out of memory|killed process' || true)
  note "kernel log: $n OOM line(s)"
else
  note "kernel log: not readable without privileges (expected)"
fi

info "security and monitoring agents (process names)"
agents=$(ps -eo comm= 2>/dev/null | sed 's,.*/,,' | sort -u | grep -iE 'falcon|crowdstrike|sentinel|s1-|mdatp|wdavdaemon|cbagent|cbdaemon|carbonblack|elastic-(agent|endpoint)|osquery|auditd|qualys|cylance|tanium|xagt|ds_agent|sophos|trend|wazuh|ossec|tetragon|falco|sysdig' | paste -sd' ' -)
note "${agents:-none recognised}"

if [ "$PTY_CHECKS" = 1 ] && has python3; then
  info "pseudo-terminal matrix (each types 'exit 0')"
  W=$(mktemp -d "${chosen:-${TMPDIR:-/tmp}}/dotfiles-diag.XXXXXX") || exit 1
  trap 'rm -rf "$W"' EXIT
  before=$(oom_kills || true)
  run_case() { # label, wrapper (direct|no_tty), command...
    local label=$1 wrap=$2 t0 rc status
    shift 2
    t0=$(date +%s)
    if [ "$wrap" = no_tty ]; then
      no_tty env -i HOME="$W" PATH="$PATH" TERM=xterm-256color python3 -I "$ROOT/tests/pty-run.py" --timeout 20 --line "exit 0" -- "$@" >"$W/out" 2>&1
    else
      env -i HOME="$W" PATH="$PATH" TERM=xterm-256color python3 -I "$ROOT/tests/pty-run.py" --timeout 20 --line "exit 0" -- "$@" </dev/null >"$W/out" 2>&1
    fi
    rc=$?
    status=$(grep -a 'pty-run: status' "$W/out" | tail -n 1)
    if [ -z "$status" ] && [ "$rc" -gt 128 ]; then
      status="RUNNER KILLED from outside by signal $((rc - 128)) ($(kill -l $((rc - 128)) 2>/dev/null)) after $(($(date +%s) - t0))s"
    fi
    printf '  %-34s %-7s rc=%-3s %s\n' "$label" "$wrap" "$rc" "${status#pty-run: status }"
  }
  for w in direct no_tty; do
    run_case "sh -i (baseline)" "$w" sh -i
    run_case "bash --norc --noprofile" "$w" bash --norc --noprofile
    run_case "bash --norc --noprofile -i" "$w" bash --norc --noprofile -i
    run_case "bash -l (login files)" "$w" bash -l
    has zsh && run_case "zsh -f -i" "$w" zsh -f -i
  done
  after=$(oom_kills || true)
  [ -n "$before" ] && note "cgroup oom_kill before/after: $before -> $after (an increase means the kernel killed for memory)"
  # A stub named like a privileged command, as test-clean-install.sh uses.
  for n in sudo notsudo; do
    printf '#!/bin/sh\nexit 97\n' >"$W/$n" && chmod 700 "$W/$n"
    env PATH="$W:/usr/bin:/bin" "$n" >/dev/null 2>&1
    note "stub named $n in $W: exit $? (97 = ran)"
  done
elif [ "$PTY_CHECKS" = 1 ]; then
  note "python3 missing: pseudo-terminal checks skipped"
fi

echo
info "reading the results"
note "EXEC FAILS on /tmp: noexec mount; the test suites now choose another directory."
note "RUNNER KILLED with no oom_kill increase: another process sent the signal."
note "Only the -i or zsh cases killed: a command-line rule, typical of an endpoint-security agent."
note "Everything rc=0: the environment is not the cause; rerun test-clean-install.sh --verbose."
