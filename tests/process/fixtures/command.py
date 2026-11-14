"""Provide local child and pipe behavior without network or private inputs."""

import os
import signal
import sys
from pathlib import Path

mode = sys.argv[1]
if mode == "echo":
    os.write(1, sys.stdin.buffer.read())
elif mode == "latin1":
    os.write(1, b"\xe9\r\n")
elif mode == "merged":
    os.write(1, b"stdout\n")
    os.write(2, b"stderr\n")
elif mode == "failure":
    os.write(1, b"output\n")
    os.write(2, b"diagnostic\n")
    sys.exit(7)
elif mode == "closed-pipes":
    os.write(1, b"ready\n")
    os.write(2, b"diagnostic\n")
    os.close(1)
    os.close(2)
    signal.pause()
elif mode in {"descendant", "closed-descendant"}:
    child = os.fork()
    if child == 0:
        if mode == "closed-descendant":
            os.close(1)
            os.close(2)
        signal.pause()
    else:
        if mode == "closed-descendant":
            marker = Path(sys.argv[2])
            pending = marker.with_name(marker.name + ".pending")
            pending.write_text(str(child), encoding="utf-8")
            pending.replace(marker)
        os.write(1, f"{child}\n".encode())
elif mode == "interrupt":
    os.kill(os.getppid(), signal.SIGINT)
    signal.pause()
elif mode == "environment":
    os.write(1, f"{Path.cwd()}\n{os.environ['FIXTURE_VALUE']}\n".encode())
else:
    raise ValueError(mode)
