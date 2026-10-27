#!/usr/bin/env python3
"""Run a command on a new pseudo-terminal and type lines into it.

    python3 -I tests/pty-run.py [--timeout S] [--line TEXT]... -- COMMAND [ARG]...

The command runs in a new session with the PTY as its controlling terminal,
so it never touches the caller's terminal. Each --line is typed (with Enter)
when the command waits for input: its line editor (bash readline, zsh ZLE)
has put the terminal in non-canonical mode and the output has been quiet
for a moment. A program without a line editor gets the line after a longer
quiet period instead.

The transcript goes to stdout as it arrives, so it survives when this
process is killed. The last line on stderr is a status line:
    pty-run: status exit=0 elapsed=1.42s lines=2/2
    pty-run: status signal=9(SIGKILL) elapsed=0.80s lines=1/2
    pty-run: status timeout=40s elapsed=40.00s lines=1/2
The exit status is the command's, 128+N for a signal, or 124 after the
timeout (only then does this script kill the command's process group). No
status line at all means that this script itself was killed from outside.
"""
import argparse
import fcntl
import os
import pty
import select
import signal
import struct
import sys
import termios
import time

QUIET = 0.4  # seconds without output before a line is typed
NO_EDITOR_QUIET = 2.0  # the same for a program that never leaves canonical mode


def editor_waiting(fd):
    """True when the terminal is in non-canonical mode (a line editor reads)."""
    try:
        return not termios.tcgetattr(fd)[3] & termios.ICANON
    except termios.error:
        return False


def signame(n):
    try:
        return signal.Signals(n).name
    except ValueError:
        return "SIG%d" % n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--timeout", type=float, default=20.0)
    ap.add_argument("--line", action="append", default=[])
    ap.add_argument("command", nargs=argparse.REMAINDER)
    args = ap.parse_args()
    cmd = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not cmd:
        ap.error("no command")

    start = time.time()
    pid, fd = pty.fork()
    if pid == 0:
        try:
            os.execvp(cmd[0], cmd)
        except OSError as e:
            sys.stderr.write("pty-run: %s: %s\n" % (cmd[0], e))
            os._exit(127)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))

    out = sys.stdout.buffer
    deadline = start + args.timeout
    pending = list(args.line)
    last = time.time()
    status = None

    def emit(data):
        out.write(data)
        out.flush()

    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 0.02)
        if r:
            try:
                data = os.read(fd, 65536)
            except OSError:
                data = b""
            if not data:
                break
            emit(data)
            last = time.time()
            continue
        done, st = os.waitpid(pid, os.WNOHANG)
        if done:
            status = st
            # Drain what is left.
            while select.select([fd], [], [], 0.1)[0]:
                try:
                    data = os.read(fd, 65536)
                except OSError:
                    break
                if not data:
                    break
                emit(data)
            break
        quiet = time.time() - last
        if pending and quiet >= QUIET and (editor_waiting(fd) or quiet >= NO_EDITOR_QUIET):
            os.write(fd, pending.pop(0).encode() + b"\r")
            last = time.time()

    # After EOF the command is exiting; give it a moment.
    grace = time.time() + 3
    while status is None and time.time() < min(grace, deadline):
        done, st = os.waitpid(pid, os.WNOHANG)
        if done:
            status = st
        else:
            time.sleep(0.05)
    sent = "lines=%d/%d" % (len(args.line) - len(pending), len(args.line))
    elapsed = "elapsed=%.2fs" % (time.time() - start)
    if status is None:
        try:
            os.killpg(pid, signal.SIGKILL)
        except OSError:
            pass
        try:
            os.waitpid(pid, 0)
        except ChildProcessError:
            pass
        sys.stderr.write("\npty-run: timeout after %.0fs\n" % args.timeout)
        sys.stderr.write("pty-run: status timeout=%.0fs %s %s\n" % (args.timeout, elapsed, sent))
        return 124
    if os.WIFEXITED(status):
        rc = os.WEXITSTATUS(status)
        sys.stderr.write("\npty-run: status exit=%d %s %s\n" % (rc, elapsed, sent))
        return rc
    sig = os.WTERMSIG(status)
    sys.stderr.write("\npty-run: status signal=%d(%s) %s %s\n" % (sig, signame(sig), elapsed, sent))
    return 128 + sig


if __name__ == "__main__":
    sys.exit(main())
