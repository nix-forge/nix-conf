"""Probe real scope placement and task cleanup with disposable processes only."""

from __future__ import annotations

# ruff: file-ignore[suspicious-subprocess-import, subprocess-without-shell-equals-true, print] -- This bounded Linux integration probe owns each launched job and its fixtures.
import argparse
import contextlib
import json
import os
import select
import signal
import subprocess
import sys
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Generator

FIXTURES = Path(__file__).resolve().parents[1] / "codex/fixtures"
DEADLINE = 30


def require(condition: bool, message: str) -> None:
    """Fail a live integration assertion with a readable diagnostic.

    Raises:
        RuntimeError: The observed lifecycle differs from its contract.

    """
    if not condition:
        raise RuntimeError(message)


def reap(child: subprocess.Popen) -> int:
    """Wait on process exit notification with one overall deadline.

    Returns:
        Child exit status.

    Raises:
        RuntimeError: A disposable job exceeds its deadline.

    """
    fd = os.pidfd_open(child.pid)
    try:
        if not select.select([fd], [], [], DEADLINE)[0]:
            child.kill()
            child.wait()
            msg = "Disposable resource probe timed out"
            raise RuntimeError(msg)
        return child.wait()
    finally:
        os.close(fd)


def ready(child: subprocess.Popen) -> dict:
    """Wait for a fixture's single readiness record or early exit.

    Returns:
        Published disposable process identities.

    """
    assert child.stdout is not None
    fd = os.pidfd_open(child.pid)
    try:
        events = select.select([child.stdout, fd], [], [], DEADLINE)[0]
        require(child.stdout in events, "Resource fixture did not become ready")
        return json.loads(child.stdout.readline())
    finally:
        os.close(fd)


def wait_dead(pid: int) -> None:
    """Observe remote child exit without depending on systemd job ordering."""
    try:
        fd = os.pidfd_open(pid)
    except ProcessLookupError:
        return
    try:
        require(
            bool(select.select([fd], [], [], DEADLINE)[0]),
            "Disposable child survived cleanup",
        )
    finally:
        os.close(fd)


def alive(pid: int) -> bool:
    """Treat exited or zombie fixtures as stopped.

    Returns:
        Whether the fixture still runs.

    """
    try:
        fields = (
            Path(f"/proc/{pid}/stat")
            .read_text(encoding="utf-8")
            .rsplit(")", 1)[1]
            .split()
        )
        return fields[0] != "Z"
    except FileNotFoundError:
        return False


@contextlib.contextmanager
def job(
    command: list[str], environment: dict | None = None
) -> Generator[subprocess.Popen]:
    """Keep ownership and final cleanup with the integration probe.

    Yields:
        A foreground client with a bounded readiness/exit protocol.

    """
    with subprocess.Popen(
        command, stdout=subprocess.PIPE, text=True, env=environment
    ) as child:
        try:
            yield child
        finally:
            if child.poll() is None:
                child.terminate()
                reap(child)


def run(command: list[str], environment: dict | None = None) -> int:
    """Run a command through the bounded child observer.

    Returns:
        Command status.

    """
    with job(command, environment) as child:
        return reap(child)


def check(policy: Path) -> None:
    """Check exact launch placement and cleanup without opening Codex itself."""
    launch = str(policy / "launch/bin/codex-desktop-launch")
    environment = dict(os.environ, CODEX_TEST_CALLER="fixture environment\nsecond line")
    expected_umask = next(
        line.split()[1]
        for line in Path("/proc/self/status").read_text(encoding="utf-8").splitlines()
        if line.startswith("Umask:")
    )
    scope = [sys.executable, str(FIXTURES / "resource_scope.py")]
    # Before: Chromium's independent request leaves the parent's slice.
    require(
        run([
            "systemd-run",
            "--user",
            "--scope",
            "--collect",
            "--quiet",
            "--slice=app-codex.slice",
            "--expand-environment=no",
            *scope,
        ])
        != 0,
        "Baseline unexpectedly contained the independently created scope",
    )
    # After: both the pre-forked renderer and Chromium main share the budget.
    with job(
        [launch, *scope, "codex://fixture?$literal", "two words"], environment
    ) as child:
        observed = ready(child)
        require(
            observed["args"] == ["codex://fixture?$literal", "two words"],
            "Arguments changed",
        )
        require(
            observed["caller"] == environment["CODEX_TEST_CALLER"],
            "Caller environment changed",
        )
        require(observed["umask"] == expected_umask, "Caller file permissions changed")
        require(reap(child) == 0, "Managed placement probe failed")
        wait_dead(observed["backendPid"])
        require(
            not alive(observed["backendPid"]), "Normal app exit retained a backend tool"
        )
    # SIGKILL bypasses Python finally; ExecStopPost must still remove its policy.
    with job([launch, *scope, "hold"], environment) as child:
        observed = ready(child)
        policy_file = (
            Path(os.environ["XDG_RUNTIME_DIR"])
            / "systemd/user"
            / f"app-org.chromium.Chromium-{observed['pid']}.scope.d/90-codex-slice.conf"
        )
        require(policy_file.exists(), "Per-launch policy was not installed")
        os.kill(observed["supervisor"], signal.SIGKILL)
        require(reap(child) != 0, "Supervisor failure was hidden")
        wait_dead(observed["pid"])
        wait_dead(observed["rendererPid"])
        wait_dead(observed["backendPid"])
        require(
            not policy_file.exists(), "Supervisor failure retained stale PID policy"
        )
        require(
            not alive(observed["pid"]) and not alive(observed["rendererPid"]),
            "Failure retained application children",
        )
    check_tasks(str(policy / "task/bin/codex-task"), environment)
    print(
        "PASS: aggregate placement, literal arguments, environment, crash cleanup and task ownership"
    )


def check_tasks(task: str, environment: dict) -> None:
    """Check normal exit, interrupted clients and explicit owner cleanup."""
    temporary_command = [sys.executable, str(FIXTURES / "resource_task.py")]
    owner_a = dict(environment, CODEX_THREAD_ID=f"resource-probe-{os.getpid()}-a")
    owner_b = dict(environment, CODEX_THREAD_ID=f"resource-probe-{os.getpid()}-b")
    try:
        with job([task, "run", *temporary_command], owner_a) as child:
            observed = ready(child)
            require(reap(child) == 0, "Task command failed")
            require(not alive(observed["child"]), "Main-command exit retained a child")
        with job([task, "run", *temporary_command, "hold"], owner_a) as child:
            observed = ready(child)
            child.terminate()
            require(reap(child) != 0, "Task cancellation was hidden")
            wait_dead(observed["main"])
            wait_dead(observed["child"])
        with job([task, "run", *temporary_command, "hold"], owner_a) as child:
            observed = ready(child)
            clients = (
                Path(f"/proc/{child.pid}/task/{child.pid}/children")
                .read_text(encoding="utf-8")
                .split()
            )
            require(len(clients) == 1, "Task client ownership is ambiguous")
            os.kill(int(clients[0]), signal.SIGKILL)
            require(reap(child) != 0, "Task client failure was hidden")
            wait_dead(observed["main"])
            wait_dead(observed["child"])
        with (
            job([task, "run", *temporary_command, "hold"], owner_a) as first,
            job([task, "run", *temporary_command, "hold"], owner_b) as second,
        ):
            first_state, second_state = ready(first), ready(second)
            try:
                require(run([task, "finish"], owner_a) == 0, "Owner cleanup failed")
                reap(first)
                require(not alive(first_state["main"]), "Owner's service remains")
                require(
                    alive(second_state["main"]), "Cleanup stopped another owner's task"
                )
            finally:
                run([task, "finish"], owner_b)
                reap(second)
    finally:
        # Readiness failures must also release only this probe's two owners.
        run([task, "finish"], owner_a)
        run([task, "finish"], owner_b)


def main() -> None:
    """Install an isolated runtime slice only if normal activation has not yet done so."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("policy", type=Path)
    args = parser.parse_args()
    path = Path(os.environ["XDG_RUNTIME_DIR"]) / "systemd/user/app-codex.slice"
    normal = (
        Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
        / "systemd/user/app-codex.slice"
    )
    owned = not path.exists() and not normal.exists()
    try:
        if owned:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.symlink_to(args.policy / "slice")
            require(
                run(["systemctl", "--user", "daemon-reload"]) == 0,
                "Manager reload failed",
            )
        check(args.policy)
    finally:
        if owned:
            group = (
                Path("/sys/fs/cgroup/user.slice")
                / f"user-{os.getuid()}.slice"
                / f"user@{os.getuid()}.service/app.slice/app-codex.slice/cgroup.events"
            )
            populated = group.exists() and "populated 1" in group.read_text(
                encoding="utf-8"
            )
            if not populated:
                # Remove our file, never stop a shared slice: another launch
                # could race the empty-state observation above.
                path.unlink(missing_ok=True)
                run(["systemctl", "--user", "daemon-reload"])
            else:
                print("Keeping runtime slice policy: it still contains active work")


if __name__ == "__main__":
    main()
