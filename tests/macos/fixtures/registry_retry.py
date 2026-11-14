"""Fail once and report launchd recovery through a private test socket."""

import socket
import sys
from pathlib import Path

address, marker = sys.argv[1:]
state = Path(marker)
first = not state.exists()
state.touch()
with socket.socket(socket.AF_UNIX) as client:
    client.connect(address)
    client.sendall(b"failed" if first else b"recovered")
sys.exit(1 if first else 0)
