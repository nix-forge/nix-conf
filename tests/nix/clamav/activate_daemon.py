"""Pass the fixture's listening socket through systemd's activation protocol."""

import os
import sys

descriptor = int(sys.argv[1])
if descriptor != 3:  # ruff: ignore[magic-value-comparison] - systemd's first activation descriptor is fd 3.
    os.dup2(descriptor, 3, inheritable=True)
    os.close(descriptor)
else:
    os.set_inheritable(descriptor, True)
environment = {
    **os.environ,
    "LISTEN_PID": str(os.getpid()),
    "LISTEN_FDS": "1",
    "LISTEN_FDNAMES": "clamd",
}
os.execve(sys.argv[2], sys.argv[2:], environment)  # ruff: ignore[start-process-with-no-shell] - Nix supplies an absolute clamd path and fixed arguments.
