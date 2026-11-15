"""Exercise display-scoped service dispatch and temporary recovery policy."""

from __future__ import annotations

import asyncio
import json
import os
import shlex
import shutil
import signal
import sys
from contextlib import suppress
from pathlib import Path
from typing import TYPE_CHECKING

import pytest
from notification_process import run

if TYPE_CHECKING:
    from collections.abc import Callable

pytestmark = pytest.mark.skipif(
    sys.platform != "linux", reason="The locker uses the Linux user service manager"
)
SOURCE = (
    Path(__file__).resolve().parents[2]
    / "modules/home/desktop/scripts/desktop-session-lock.sh"
)
FIXTURE = Path(__file__).with_name("fixtures") / "session_lock_commands.py"


@pytest.fixture
def dispatcher(tmp_path: Path) -> tuple[Callable[..., int], Path]:
    """Render the maintained launcher with private manager/compositor endpoints.

    Returns:
        A launcher and its isolated public fixture state.

    """
    state = tmp_path / "state"
    state.mkdir()
    (state / "instances.json").write_text(
        json.dumps([{"instance": "fixture", "wl_socket": "wayland-1"}])
    )
    (state / "policy.json").write_text(json.dumps({"bool": False}))
    tools = {
        name: shutil.which(name)
        for name in ("bash", "jq", "systemd-escape", "flock", "sha256sum", "timeout")
    }
    assert all(tools.values()), "The declared Linux fixture tools must be installed"
    script = tmp_path / "launcher.sh"
    text = SOURCE.read_text(encoding="utf-8")
    replacements = {
        "systemctl": shlex.join([sys.executable, str(FIXTURE), "systemctl"]),
        "hyprctl": shlex.join([sys.executable, str(FIXTURE), "hyprctl"]),
        "systemd_escape": shlex.quote(str(tools["systemd-escape"])),
        "jq": shlex.quote(str(tools["jq"])),
        "session_client": "false",
        "unit_template": "desktop-session-lock@.service",
        "ipc_timeout": "5s",
        "ipc_kill_after": "2s",
        "flock": shlex.quote(str(tools["flock"])),
        "sha256sum": shlex.quote(str(tools["sha256sum"])),
        "timeout": shlex.quote(str(tools["timeout"])),
    }
    for name, value in replacements.items():
        text = text.replace("@" + name + "@", value)
    script.write_text(text, encoding="utf-8")

    def invoke(mode: str, display: str = "wayland-1", status: int = 0) -> int:
        result = run(
            [str(tools["bash"]), str(script), mode],
            env=os.environ
            | {
                "LOCK_FIXTURE_STATE": str(state),
                "XDG_RUNTIME_DIR": str(state),
                "WAYLAND_DISPLAY": display,
                "LOCK_FIXTURE_MANAGER_STATUS": str(status),
            },
            capture_output=True,
            timeout=5,
        )
        (state / "last-error.txt").write_bytes(result.stderr)
        return result.returncode

    return invoke, state


def calls(state: Path) -> list[list[str]]:
    """Read the public call record.

    Returns:
        Recorded arguments to the fixture endpoints.

    """
    return [
        json.loads(line) for line in (state / "calls.jsonl").read_text().splitlines()
    ]


def test_lock_uses_distinct_display_units(
    dispatcher: tuple[Callable[..., int], Path],
) -> None:
    """Two Wayland connections must not share one locker service lifetime."""
    invoke, state = dispatcher
    assert invoke("lock", "wayland-1") == 0
    assert invoke("lock", "nested/socket") == 0
    first, second = calls(state)
    assert first[:3] == second[:3] == ["systemctl", "--user", "start"]
    assert first[-1] != second[-1]
    assert first[-1].startswith("desktop-session-lock@")
    assert second[-1].startswith("desktop-session-lock@")


@pytest.mark.parametrize("prior", [False, True])
@pytest.mark.parametrize("status", [0, 7])
def test_recovery_restores_policy_and_preserves_exit(
    dispatcher: tuple[Callable[..., int], Path], prior: bool, status: int
) -> None:
    """Successful or failed recovery restores the caller's existing security choice."""
    invoke, state = dispatcher
    (state / "policy.json").write_text(json.dumps({"bool": prior}))
    assert invoke("recover", status=status) == status
    assert json.loads((state / "policy.json").read_text()) == {"bool": prior}
    recorded = calls(state)
    manager = next(call for call in recorded if "start" in call)
    assert manager[:4] == ["systemctl", "--user", "start", "--wait"]
    assert all("reset-failed" not in call for call in recorded)
    restoration = next(call for call in reversed(recorded) if "eval" in call)
    assert "allow_session_lock_restore=" + str(prior).lower() in restoration[-1]


def test_ambiguous_compositor_does_not_change_policy(
    dispatcher: tuple[Callable[..., int], Path],
) -> None:
    """Recovery must refuse an ambiguous display instead of changing another session."""
    invoke, state = dispatcher
    (state / "instances.json").write_text(
        json.dumps([
            {"instance": "first", "wl_socket": "wayland-1"},
            {"instance": "second", "wl_socket": "wayland-1"},
        ])
    )
    assert invoke("recover") != 0
    assert all(call[0] != "systemctl" and "eval" not in call for call in calls(state))
    assert json.loads((state / "policy.json").read_text()) == {"bool": False}


@pytest.mark.parametrize("invalid", [None, 1, "true", {}, []])
def test_invalid_policy_does_not_enable_recovery(
    dispatcher: tuple[Callable[..., int], Path], invalid: object
) -> None:
    """An unexpected compositor schema must never relax the lock policy."""
    invoke, state = dispatcher
    (state / "policy.json").write_text(json.dumps({"bool": invalid}))
    assert invoke("recover") != 0
    assert all(call[0] != "systemctl" and "eval" not in call for call in calls(state))
    assert json.loads((state / "policy.json").read_text()) == {"bool": invalid}


async def fifo_reader(path: Path) -> tuple[asyncio.StreamReader, asyncio.BaseTransport]:
    """Subscribe to a FIFO before starting any producer.

    Returns:
        The notification reader and its owned transport.

    """
    os.mkfifo(path)
    descriptor = os.open(path, os.O_RDWR | os.O_NONBLOCK)
    event_source = os.fdopen(descriptor, "rb", buffering=0)
    reader = asyncio.StreamReader()
    protocol = asyncio.StreamReaderProtocol(reader)
    transport, _ = await asyncio.get_running_loop().connect_read_pipe(
        lambda: protocol, event_source
    )
    return reader, transport


async def recovery_lifecycle(state: Path, interruption: int | None) -> None:
    """Exercise overlapping or interrupted recoveries using FIFO notifications."""
    events = state / "events.fifo"
    reader, transport = await fifo_reader(events)
    children: list[asyncio.subprocess.Process] = []
    releases: list[int] = []

    async def start(token: str) -> asyncio.subprocess.Process:
        release = state / (token + ".fifo")
        os.mkfifo(release)
        releases.append(os.open(release, os.O_RDWR | os.O_NONBLOCK))
        process = await asyncio.create_subprocess_exec(
            str(shutil.which("bash")),
            str(state.parent / "launcher.sh"),
            "recover",
            env=os.environ
            | {
                "LOCK_FIXTURE_STATE": str(state),
                "LOCK_FIXTURE_EVENTS": str(events),
                "LOCK_FIXTURE_TOKEN": token,
                "LOCK_FIXTURE_RELEASE": str(release),
                "XDG_RUNTIME_DIR": str(state),
                "WAYLAND_DISPLAY": "wayland-1",
            },
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL,
            start_new_session=True,
        )
        children.append(process)
        return process

    async def event(kind: str, token: str) -> dict[str, object]:
        received = json.loads(await reader.readline())
        assert received["event"] == kind
        assert received["token"] == token
        return received

    try:
        async with asyncio.timeout(5):
            first = await start("first")
            await event("instances", "first")
            manager = await event("manager", "first")
            assert json.loads((state / "policy.json").read_text()) == {"bool": True}
            if interruption is not None:
                manager_pid = manager["pid"]
                assert isinstance(manager_pid, int)
                # Signal only the launcher, not its group or waiting manager.
                os.kill(first.pid, interruption)
                assert await first.wait() == 128 + interruption
                with pytest.raises(ProcessLookupError):
                    os.kill(manager_pid, 0)
            else:
                second = await start("second")
                await event("instances", "second")
                # A bounded negative notification check verifies the second
                # manager cannot run while the first recovery owns the policy.
                with pytest.raises(TimeoutError):
                    async with asyncio.timeout(0.2):
                        await reader.readline()
                os.write(releases[0], b"release\n")
                assert await first.wait() == 0
                await event("manager", "second")
                os.write(releases[1], b"release\n")
                assert await second.wait() == 0
            assert json.loads((state / "policy.json").read_text()) == {"bool": False}
    finally:
        for child in children:
            with suppress(ProcessLookupError):
                os.killpg(child.pid, signal.SIGKILL)
            await child.wait()
        transport.close()
        for release_fd in releases:
            os.close(release_fd)


def test_concurrent_recovery_restores_original_policy(
    dispatcher: tuple[Callable[..., int], Path],
) -> None:
    """A second recovery must not snapshot another caller's temporary policy."""
    _, state = dispatcher
    asyncio.run(recovery_lifecycle(state, None))


@pytest.mark.parametrize("interruption", [signal.SIGHUP, signal.SIGINT, signal.SIGTERM])
def test_signal_to_dispatcher_restores_policy_and_reaps_manager(
    dispatcher: tuple[Callable[..., int], Path], interruption: int
) -> None:
    """Launcher-only signals must restore policy without releasing authentication."""
    _, state = dispatcher
    asyncio.run(recovery_lifecycle(state, interruption))


def test_ignored_enable_refuses_to_start_manager(
    dispatcher: tuple[Callable[..., int], Path],
) -> None:
    """A successful compositor command is insufficient without policy readback."""
    invoke, state = dispatcher
    (state / "ignored-value.json").write_text(json.dumps(True))
    assert invoke("recover") != 0
    assert all("start" not in call for call in calls(state))
    assert json.loads((state / "policy.json").read_text()) == {"bool": False}
    assert (state / "last-error.txt").read_text().strip()


def test_ignored_restore_reports_failure(
    dispatcher: tuple[Callable[..., int], Path],
) -> None:
    """Recovery must report when the compositor leaves its temporary policy enabled."""
    invoke, state = dispatcher
    (state / "ignored-value.json").write_text(json.dumps(False))
    assert invoke("recover") != 0
    assert any("start" in call for call in calls(state))
    assert json.loads((state / "policy.json").read_text()) == {"bool": True}
    assert (state / "last-error.txt").read_text().strip()


def test_recovery_resets_only_selected_failed_unit(
    dispatcher: tuple[Callable[..., int], Path],
) -> None:
    """Explicit recovery clears its rate-limited unit before retrying the locker."""
    invoke, state = dispatcher
    marker = state / "unit-failed"
    marker.touch()
    assert invoke("recover") == 0
    assert not marker.exists()
    manager_calls = [call for call in calls(state) if call[0] == "systemctl"]
    assert [call[2] for call in manager_calls] == ["is-failed", "reset-failed", "start"]
    selected_unit = manager_calls[0][-1]
    assert selected_unit.startswith("desktop-session-lock@")
    assert all(call[-1] == selected_unit for call in manager_calls)
    assert manager_calls[0][:4] == ["systemctl", "--user", "is-failed", "--quiet"]
    assert manager_calls[1] == ["systemctl", "--user", "reset-failed", selected_unit]
    assert json.loads((state / "policy.json").read_text()) == {"bool": False}
