#!/usr/bin/env python3
"""Run a command on a new pseudo-terminal and type lines into it.

    python3 -I tests/pty-run.py [--timeout S] [--line TEXT]... -- COMMAND [ARG]...

The command runs in a new session with the PTY as its controlling terminal,
so it never touches the caller's terminal. Each --line is typed (with Enter)
after the output has been quiet for a moment, as a person would at a
prompt. The transcript goes to stdout. The exit status is the command's, or
124 after the timeout (the command's process group is then killed).
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

QUIET = 0.4  # seconds without output that count as "waiting at a prompt"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--timeout", type=float, default=20.0)
    ap.add_argument("--line", action="append", default=[])
    ap.add_argument("command", nargs=argparse.REMAINDER)
    args = ap.parse_args()
    cmd = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not cmd:
        ap.error("no command")

    pid, fd = pty.fork()
    if pid == 0:
        try:
            os.execvp(cmd[0], cmd)
        except OSError as e:
            sys.stderr.write("pty-run: %s: %s\n" % (cmd[0], e))
            os._exit(127)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))

    out = bytearray()
    deadline = time.time() + args.timeout
    pending = list(args.line)
    last = time.time()
    status = None
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                data = os.read(fd, 65536)
            except OSError:
                data = b""
            if not data:
                break
            out += data
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
                out += data
            break
        if pending and time.time() - last >= QUIET:
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
    sys.stdout.write(out.decode("utf-8", "replace"))
    sys.stdout.flush()
    if status is None:
        try:
            os.killpg(pid, signal.SIGKILL)
        except OSError:
            pass
        try:
            os.waitpid(pid, 0)
        except ChildProcessError:
            pass
        sys.stderr.write("pty-run: timeout after %.0fs\n" % args.timeout)
        return 124
    if os.WIFEXITED(status):
        return os.WEXITSTATUS(status)
    return 128 + os.WTERMSIG(status)


if __name__ == "__main__":
    sys.exit(main())
