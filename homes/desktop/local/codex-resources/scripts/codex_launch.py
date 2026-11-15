"""Keep Chromium's self-created scope inside the desktop agent's slice."""

from __future__ import annotations

# ruff: file-ignore[start-process-with-partial-path, subprocess-without-shell-equals-true] -- Exact argv launches the caller-selected app; systemctl resolves from the packaged service PATH.
import contextlib
import json
import os
import signal
import subprocess  # ruff: ignore[suspicious-subprocess-import] -- The supervisor owns the gated child and calls the packaged service manager.
import sys
from pathlib import Path

SLICE = "app-codex.slice"
POLICY_NAME = "90-codex-slice.conf"


def policy_text() -> str:
    """Build an exact policy that replaces the broader Chromium limits.

    Returns:
        Slice placement and application-lifetime bindings.

    """
    unit = os.environ.get("CODEX_LAUNCH_UNIT")
    binding = "" if unit is None else f"[Unit]\nBindsTo={unit}\nAfter={unit}\n"
    return (
        f"# Owned Codex launch policy\n{binding}[Scope]\nSlice={SLICE}\n"
        "OOMPolicy=continue\nTimeoutStopSec=5s\nMemoryHigh=infinity\nMemoryMax=infinity\n"
        "MemorySwapMax=infinity\n"
    )


def cleanup(state: Path, runtime: Path, *, stop_scope: bool = False) -> None:
    """Remove the recorded policy, including after the supervisor is killed.

    Raises:
        RuntimeError: An ownership record points outside the scoped runtime path.

    """
    record = state / "policy.json"
    try:
        ownership = json.loads(record.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return
    policy = Path(ownership["path"])
    if policy.name != POLICY_NAME or policy.parent.parent != runtime / "systemd/user":
        msg = "Invalid Codex launch policy ownership record"
        raise RuntimeError(msg)
    with contextlib.suppress(FileNotFoundError):
        if policy.read_text(encoding="utf-8") == ownership["content"]:
            if stop_scope:
                # Verify ownership before stopping: policy creation may have
                # failed against a foreign file belonging to a reused PID.
                unit = policy.parent.name.removesuffix(".d")
                status = subprocess.run(
                    [
                        "systemctl",
                        "--user",
                        "show",
                        "--property=ActiveState",
                        "--value",
                        unit,
                    ],
                    check=False,
                    shell=False,
                    capture_output=True,
                    text=True,
                )
                # Forwarding to an existing singleton exits without ever
                # creating a new Chromium scope. That is a normal launch.
                if status.stdout.strip() in {"active", "activating", "deactivating"}:
                    subprocess.run(
                        ["systemctl", "--user", "stop", unit], check=True, shell=False
                    )
            policy.unlink()
            with contextlib.suppress(OSError):
                policy.parent.rmdir()
    record.unlink(missing_ok=True)
    subprocess.run(["systemctl", "--user", "daemon-reload"], check=False)


def gated_exec(descriptor: int, command: list[str]) -> None:
    """Execute only after the parent installs and reloads the exact PID policy."""
    token = os.read(descriptor, 1)
    os.close(descriptor)
    if token != b"1":
        sys.exit(1)
    os.execv(command[0], command)  # ruff: ignore[start-process-with-no-shell] -- Preserve the caller's exact argument vector.


def supervise(command: list[str]) -> int:
    """Install policy before exec and remove only this invocation's drop-in.

    Returns:
        The launched application's status, including signal termination.

    Raises:
        RuntimeError: The runtime directory belongs to a different user.

    """
    runtime = Path(os.environ["XDG_RUNTIME_DIR"])
    if runtime.stat().st_uid != os.getuid():
        msg = "The desktop runtime directory has the wrong owner"
        raise RuntimeError(msg)
    read_fd, write_fd = os.pipe2(os.O_CLOEXEC)
    child = subprocess.Popen(
        [sys.executable, __file__, "exec", str(read_fd), *command],
        pass_fds=(read_fd,),
        shell=False,
    )
    os.close(read_fd)
    directory = (
        runtime / "systemd/user" / f"app-org.chromium.Chromium-{child.pid}.scope.d"
    )
    policy = directory / POLICY_NAME
    state = Path(
        os.environ.get("RUNTIME_DIRECTORY", runtime / f"codex-launch-{os.getpid()}")
    )
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    content = policy_text()

    def forward(number: int, _frame: object) -> None:
        child.send_signal(number)

    previous = {
        number: signal.signal(number, forward)
        for number in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT)
    }
    try:
        directory.mkdir(parents=True, exist_ok=True)
        # Record intent first: ExecStopPost can recover any interruption during
        # policy creation, even SIGKILL or an OOM that bypasses Python finally.
        with (state / "policy.json").open("x", encoding="utf-8") as stream:
            json.dump({"path": str(policy), "content": content}, stream)
        # Publish a complete file atomically and exclusively. A killed writer
        # must not leave a partial policy that cannot prove its ownership.
        prepared = state / "scope.conf"
        with prepared.open("x", encoding="utf-8") as stream:
            stream.write(content)
        os.link(prepared, policy)
        subprocess.run(["systemctl", "--user", "daemon-reload"], check=True)
        os.write(write_fd, b"1")
        os.close(write_fd)
        write_fd = -1
        returncode = child.wait()
        return returncode if returncode >= 0 else 128 - returncode
    finally:
        if write_fd >= 0:
            os.close(write_fd)
        if child.poll() is None:
            child.terminate()
            child.wait()
        for number, handler in previous.items():
            signal.signal(number, handler)
        # Systemd's ExecStopPost owns production teardown. Removing the
        # BindsTo drop-in while this service is still active would sever the
        # relationship before helpers in the migrated scope are stopped.
        if "RUNTIME_DIRECTORY" not in os.environ:
            cleanup(state, runtime)


def main() -> int:
    """Dispatch supervisor and internal exec gate.

    Returns:
        Application exit status.

    """
    if sys.argv[1] == "cleanup":
        cleanup(
            Path(os.environ["RUNTIME_DIRECTORY"]),
            Path(os.environ["XDG_RUNTIME_DIR"]),
            stop_scope=True,
        )
        return 0
    if sys.argv[1] == "exec":
        gated_exec(int(sys.argv[2]), sys.argv[3:])
        return 1
    return supervise(sys.argv[1:])


if __name__ == "__main__":
    sys.exit(main())
