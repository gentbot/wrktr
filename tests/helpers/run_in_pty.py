#!/usr/bin/env python3
"""Run a bash command inside a pseudo-terminal so `[ -t 0 ]` is true.

Usage: run_in_pty.py '<bash command>' '<text to type on stdin>'

Prints the combined output and exits with the command's exit status.
"""
import os
import pty
import sys
import time


def main():
    cmd, stdin_text = sys.argv[1], sys.argv[2]
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp("bash", ["bash", "-c", cmd])
    time.sleep(0.3)
    os.write(fd, stdin_text.encode())
    out = b""
    while True:
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            break
        if not chunk:
            break
        out += chunk
    _, status = os.waitpid(pid, 0)
    sys.stdout.write(out.decode(errors="replace").replace("\r", ""))
    sys.exit(os.waitstatus_to_exitcode(status))


main()
