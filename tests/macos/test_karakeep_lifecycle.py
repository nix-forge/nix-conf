"""Exercise launchd wrapper cancellation without starting Docker or a VM."""

from __future__ import annotations

import os
import shutil
import signal
import socket
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Disposable command fixtures only.
import sys
from contextlib import chdir, suppress
from pathlib import Path

import pytest

SCRIPT = (
    Path(__file__).resolve().parents[2] / "modules/home/scripts/karakeep-launchd.sh"
)


@pytest.mark.parametrize("stop_signal", [signal.SIGINT, signal.SIGTERM, signal.SIGHUP])
def test_stop_is_immediate_and_cleans_up_once(
    tmp_path: Path, stop_signal: signal.Signals
) -> None:
    """Stopping the wrapper must interrupt its keepalive and stop Compose once."""
    bash = shutil.which("bash")
    sleep = shutil.which("sleep")
    assert bash is not None
    assert sleep is not None
    log = tmp_path / "compose-log"
    compose = tmp_path / "compose"
    compose.write_text(f'#!{bash}\nprintf "%s\\n" "$*" >> "{log}"\n', encoding="utf-8")
    compose.chmod(0o700)
    keeper = tmp_path / "keeper"
    keeper.write_text(f'#!{bash}\necho ready\nexec "{sleep}" "$@"\n', encoding="utf-8")
    keeper.chmod(0o700)
    signal_reset = tmp_path / "signal-reset.py"
    signal_reset.write_text(
        """import os
import signal
import sys

for stop_signal in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
    signal.signal(stop_signal, signal.SIG_DFL)
os.execv(sys.argv[1], sys.argv[1:])
""",
        encoding="utf-8",
    )
    with socket.socket(socket.AF_UNIX) as docker:
        socket_path = Path("docker.sock")
        with chdir(tmp_path):
            docker.bind(str(socket_path))
        source = SCRIPT.read_text(encoding="utf-8")
        for token, value in {
            "bash": bash,
            "homeDirectory": str(tmp_path),
            "dockerSocket": str(socket_path),
            "colima": "false",
            "seq": shutil.which("seq"),
            "sleep": str(keeper),
            "dockerCompose": str(compose),
            "colimaForward": "true",
        }.items():
            assert value is not None
            source = source.replace(f"@{token}@", value)
        script = tmp_path / "launchd"
        script.write_text(source, encoding="utf-8")
        with subprocess.Popen(  # ruff: ignore[subprocess-without-shell-equals-true] - Fixed interpreter and fixture.
            [sys.executable, str(signal_reset), bash, str(script)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
            cwd=tmp_path,
            env={
                key: value
                for key, value in os.environ.items()
                if key not in {"BASH_ENV", "ENV"}
            },
        ) as process:
            try:
                assert process.stdout is not None
                assert process.stdout.readline().strip() == "ready"
                process.send_signal(stop_signal)
                assert process.wait(timeout=2) == 128 + stop_signal
                assert log.read_text(encoding="utf-8").splitlines() == ["up -d", "down"]
            finally:
                # Own process group also contains the keeper when testing the
                # old wrapper, whose foreground sleep defers signal handling.
                with suppress(ProcessLookupError):
                    os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=5)
