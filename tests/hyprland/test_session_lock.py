"""Exercise locker lifetime and isolation without locking a real display."""

from __future__ import annotations

import os
import re
import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Isolated fixture commands exercise the public launcher.
import sys
from collections.abc import Callable
from contextlib import suppress
from pathlib import Path
from typing import TYPE_CHECKING

import pytest
from notification_process import run as run_command
from waits import wait_child, wait_file

pytestmark = pytest.mark.skipif(
    not hasattr(os, "pidfd_open"), reason="Wayland locker supervision uses Linux pidfds"
)

if TYPE_CHECKING:
    from collections.abc import Iterator

SCRIPT = (
    Path(__file__).resolve().parents[2] / "modules/home/desktop/scripts/session-lock.sh"
)
BASH = shutil.which("bash") or ""
if not BASH:
    pytest.skip("Bash is required", allow_module_level=True)
type LockEnvironment = tuple[
    dict[str, str], Callable[[Path, str], subprocess.Popen[bytes]]
]


@pytest.fixture
def lock_environment(tmp_path: Path) -> Iterator[LockEnvironment]:
    """Give each test a private runtime and a disposable locker command.

    Yields:
        The private environment and launcher for fixture processes.

    """
    runtime = tmp_path / "runtime"
    runtime.mkdir(mode=0o700)
    child = tmp_path / "locker.sh"
    child.write_text(
        re.sub(
            r"__fixture_[0-9]+__",
            lambda match: {"__fixture_0__": f"{BASH}"}[match[0]],
            (
                Path(__file__).with_name("fixtures") / "ready-session-lock.sh.in"
            ).read_text(encoding="utf-8"),
        ),
        encoding="utf-8",
    )
    child.chmod(0o700)
    env = os.environ | {
        "XDG_RUNTIME_DIR": str(runtime),
        "WAYLAND_DISPLAY": "wayland-test-a",
    }
    env.pop("BASH_ENV", None)
    processes = []

    def launch(marker: Path, display: str) -> subprocess.Popen[bytes]:
        process = subprocess.Popen(  # ruff: ignore[subprocess-without-shell-equals-true] - Fixed executable and disposable fixture paths.
            [BASH, str(SCRIPT), "lock", str(child), str(marker)],
            env=env | {"WAYLAND_DISPLAY": display},
            start_new_session=True,
        )
        processes.append(process)
        return process

    yield env, launch
    for process in processes:
        # The fixture owns a new process group, including flock and sleep.
        with suppress(ProcessLookupError):
            os.killpg(process.pid, 15)
        wait_child(process)


def test_duplicate_request_reuses_active_locker(
    tmp_path: Path, lock_environment: LockEnvironment
) -> None:
    """A second request succeeds without starting a competing locker."""
    env, launch = lock_environment
    first = tmp_path / "first"
    launch(first, "wayland-test-a")
    wait_file(first)
    second = tmp_path / "second"
    assert wait_child(launch(second, "wayland-test-a")) == 0
    assert not second.exists()
    result = run_command(
        [BASH, str(SCRIPT), "running"], env=env, check=False, timeout=5
    )
    assert result.returncode == 0


def test_another_display_does_not_suppress_lock(
    tmp_path: Path, lock_environment: LockEnvironment
) -> None:
    """One user's two compositor connections lock independently."""
    _, launch = lock_environment
    first, second = tmp_path / "first", tmp_path / "second"
    launch(first, "wayland-test-a")
    wait_file(first)
    launch(second, "wayland-test-b")
    wait_file(second)


def test_unrelated_hyprlock_name_does_not_suppress_lock(
    tmp_path: Path, lock_environment: LockEnvironment
) -> None:
    """An external process named hyprlock is not a lock acknowledgement."""
    _, launch = lock_environment
    named = tmp_path / "hyprlock"
    # Nix's coreutils can be a multicall binary: renaming sleep makes it exit.
    # A copied Python executable retains a real, live process under this name.
    shutil.copyfile(sys.executable, named)
    named.chmod(0o700)
    ready = tmp_path / "unrelated-ready"
    unrelated = subprocess.Popen(  # ruff: ignore[subprocess-without-shell-equals-true] - Disposable Python process with a readiness marker.
        [
            str(named),
            str(Path(__file__).resolve().parents[1] / "fixtures/process.py"),
            "marker-stall",
            str(ready),
            "30",
        ],
        env=os.environ | {"PYTHONHOME": sys.base_prefix},
    )
    try:
        wait_file(ready)
        assert unrelated.poll() is None
        marker = tmp_path / "started"
        launch(marker, "wayland-test-a")
        wait_file(marker)
    finally:
        unrelated.terminate()
        wait_child(unrelated)


def test_exit_releases_lock_and_stale_file_is_harmless(
    tmp_path: Path, lock_environment: LockEnvironment
) -> None:
    """A failed launch does not block a later request."""
    env, launch = lock_environment
    result = run_command(
        [BASH, str(SCRIPT), "lock", "false"], env=env, check=False, timeout=5
    )
    assert result.returncode == 1
    assert list(Path(env["XDG_RUNTIME_DIR"]).glob("desktop-session-lock-*.lock"))
    status = run_command(
        [BASH, str(SCRIPT), "running"], env=env, check=False, timeout=5
    )
    assert status.returncode == 1
    marker = tmp_path / "retry"
    launch(marker, "wayland-test-a")
    wait_file(marker)


def test_missing_display_refuses_ambiguous_launch(
    tmp_path: Path, lock_environment: LockEnvironment
) -> None:
    """Missing session identity must not use a shared global lock."""
    env, _ = lock_environment
    env.pop("WAYLAND_DISPLAY")
    marker = tmp_path / "unexpected"
    result = run_command(
        [BASH, str(SCRIPT), "lock", "touch", str(marker)],
        env=env,
        check=False,
        capture_output=True,
        timeout=5,
    )
    assert result.returncode != 0
    assert not marker.exists()
