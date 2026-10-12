"""Compare parent-first teardown on the exact unpatched and repaired compositor."""

from typing import TYPE_CHECKING, Protocol, cast

if TYPE_CHECKING:
    from collections.abc import Callable


class Guest(Protocol):
    """The small NixOS driver interface used by this regression."""

    def succeed(self, command: str) -> str:
        """Execute a successful guest command."""
        ...

    def execute(self, command: str) -> tuple[int, str]:
        """Execute a guest command and return its status and output."""
        ...

    def wait_for_file(self, path: str, *, timeout: int = 60) -> None:
        """Wait for a guest file with a bounded deadline."""
        ...

    def copy_from_machine(self, path: str) -> None:
        """Preserve a guest log as test evidence."""
        ...


def verify(guest: Guest, *, expect_crash: bool) -> None:
    """Require the original crash and successful repaired lifecycle scenarios."""
    guest.succeed("mkdir -m700 /run/lifetime-parent")
    guest.succeed(
        "XDG_RUNTIME_DIR=/run/lifetime-parent WLR_BACKENDS=headless "
        "WLR_RENDERER=pixman cage -- sleep 600 > /var/log/lifetime-cage.log 2>&1 &"
    )
    guest.wait_for_file("/run/lifetime-parent/wayland-0")
    guest.wait_for_file("/dev/dri/renderD128")
    status, _ = guest.execute(
        "XDG_RUNTIME_DIR=/run/lifetime-parent WAYLAND_DISPLAY=wayland-0 "
        "LIBGL_ALWAYS_SOFTWARE=1 AQ_BACKEND=wayland KEEP_TEST_OUTPUT=1 "
        "HYPRLAND_TEST_SCENARIOS='orphan disconnect feedback child-first' "
        'bash /etc/lifetime-probe/check-subsurface-teardown.sh "$HYPRLAND_UNDER_TEST" '
        "> /var/log/lifetime-probe.log 2>&1"
    )
    output = guest.succeed("cat /var/log/lifetime-probe.log")
    guest.copy_from_machine("/var/log/lifetime-probe.log")
    guest.copy_from_machine("/var/log/lifetime-cage.log")
    if expect_crash:
        assert status != 0, "Unpatched parent-first teardown unexpectedly succeeded"
        reports = guest.succeed(
            "find /tmp -name 'hyprlandCrashReport*.txt' -exec cat '{}' +"
        )
        assert "posRelativeToParent" in reports, (
            "The baseline failed without reproducing the parent-lifetime crash: "
            + output
        )
    else:
        assert status == 0, output
        assert "PASS: compositor survived every selected subsurface lifecycle" in output
        assert "exited cleanly" in output


# NixOS's test driver supplies these guests and the lifecycle entrypoint.
_start = cast("Callable[[], None]", globals()["start_all"])
_start()
verify(cast("Guest", globals()["baseline"]), expect_crash=True)
verify(cast("Guest", globals()["repaired"]), expect_crash=False)
