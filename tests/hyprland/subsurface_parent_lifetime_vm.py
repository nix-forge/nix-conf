"""Validate current direct-DRM raw and repaired parent-first lifecycles."""

# Driver-provided guests are intentionally started sequentially to bound memory.
import json
import re
from typing import TYPE_CHECKING, cast

from hyprland.lifetime import lifetime_contract

if TYPE_CHECKING:
    from test_driver.machine import QemuMachine

    baseline: QemuMachine = cast("QemuMachine", None)
    repaired: QemuMachine = cast("QemuMachine", None)


def require_parent_protocols(capabilities: str) -> None:
    """Reject a parent that cannot support the actual nested backend requests."""
    versions = {
        name: int(version)
        for name, version in re.findall(
            r"interface:\s*'([^']+)',\s*version:\s*(\d+)", capabilities
        )
    }
    for interface, required in {
        "xdg_wm_base": 6,
        "wl_compositor": 6,
        "wl_seat": 9,
        "zwp_linux_dmabuf_v1": 4,
    }.items():
        assert versions.get(interface, 0) >= required, capabilities


def compositor_ready(guest: QemuMachine) -> tuple[int, str, str]:
    """Bind readiness and protocol evidence to the owned live compositor.

    Returns:
        The owned PID, signature and command environment.

    """
    pid = int(
        guest.succeed(
            "systemctl show --property=MainPID --value lifetime-compositor"
        ).strip()
    )
    assert pid > 0, "Owned compositor has no live service PID"
    instances = [
        json.loads(
            guest.succeed(
                "XDG_RUNTIME_DIR=/run/lifetime-proof python3 /etc/lifetime-observer/compositor_lifecycle.py startup "
                + str(pid)
                + " --runtime /run/lifetime-proof --evidence /tmp/lifetime-home/cache"
            )
        )
    ]
    observed = instances[0]
    instances = json.loads(
        guest.succeed("XDG_RUNTIME_DIR=/run/lifetime-proof hyprctl instances -j")
    )
    assert isinstance(instances, list), instances
    assert len(instances) == 1, instances
    assert all(
        instances[0].get(field) == observed[field]
        for field in ("pid", "instance", "wl_socket")
    ), instances
    instance = instances[0]
    signature, display = instance["instance"], instance["wl_socket"]
    assert isinstance(signature, str), instance
    assert re.fullmatch(r"[A-Za-z0-9_.-]+", signature), instance
    assert isinstance(display, str), instance
    assert re.fullmatch(r"wayland-[0-9]+", display), instance
    pid = int(
        guest.succeed(
            "systemctl show --property=MainPID --value lifetime-compositor"
        ).strip()
    )
    assert pid > 0, instance
    assert type(instance["pid"]) is int, instance
    assert instance["pid"] == pid, instance
    env = f"XDG_RUNTIME_DIR=/run/lifetime-proof WAYLAND_DISPLAY={display} HYPRLAND_INSTANCE_SIGNATURE={signature}"
    capabilities = guest.succeed(env + " wayland-info")
    require_parent_protocols(capabilities)
    monitors = json.loads(guest.succeed(env + " hyprctl monitors -j"))
    assert len(monitors) == 1, monitors
    assert monitors[0]["width"] > 0, monitors
    assert monitors[0]["height"] > 0, monitors
    rendering = guest.succeed(env + " hyprctl systeminfo")
    assert re.search(r"GL ver: 3\.[02]", rendering), rendering
    renderer = guest.succeed(
        "timeout 15 journalctl -u lifetime-compositor --no-pager --grep='Renderer:' | tail -c 8192"
    )
    assert re.search(r"Renderer: (?:llvmpipe|softpipe)\b", renderer), renderer
    return pid, signature, env


def verify_lifetime(
    guest: QemuMachine, *, expect_crash: bool, parent_only: bool = False
) -> None:
    """Require actual current protocol, renderer, lifecycle and manager exit gates."""
    guest.start()
    try:
        guest.wait_for_unit("multi-user.target")
        guest.wait_for_file("/dev/dri/card0")
        guest.succeed(
            "mkdir -m700 /run/lifetime-proof; mkdir -p /tmp/lifetime-home/cache /tmp/lifetime-proof"
        )
        guest.succeed(
            "systemd-run --unit=lifetime-compositor --property=Type=exec --property=RuntimeMaxSec=240 "
            "--setenv=XDG_RUNTIME_DIR=/run/lifetime-proof --setenv=LIBGL_ALWAYS_SOFTWARE=1 "
            "--setenv=AQ_DRM_DEVICES=/dev/dri/card0 --setenv=HOME=/tmp/lifetime-home "
            "--setenv=XDG_CACHE_HOME=/tmp/lifetime-home/cache --setenv=PATH=/run/current-system/sw/bin "
            "Hyprland --i-am-really-stupid --config /etc/lifetime-proof.lua"
        )
        guest.wait_for_unit("lifetime-compositor.service", timeout=45)
        pid, signature, env = compositor_ready(guest)
        command = (
            env
            + " timeout 240 python3 /etc/lifetime-observer/lifetime_cases.py "
            + str(pid)
            + " "
            + signature
        )
        if expect_crash:
            command += " --expect-crash"
        elif parent_only:
            command += " --child-first-control"
        guest.succeed(command + " > /tmp/lifetime-proof/cases.log 2>&1")
        receipt = json.loads(guest.succeed("cat /tmp/lifetime-proof/cases.json"))
        assert receipt["originalPidfdExitObserved"] is True, receipt
        assert receipt["managerCompletionObserved"] is True, receipt
        if expect_crash:
            reports = guest.succeed(
                "find /tmp/lifetime-home/cache -name 'hyprlandCrashReport*.txt' -exec cat '{}' +"
            )
            lifetime_contract.require_baseline(receipt["baselineFailure"], reports)
        elif parent_only:
            lifetime_contract.require_child_first_control(
                [tuple(record) for record in receipt["results"]], receipt["shutdown"]
            )
        else:
            lifetime_contract.require_repaired(
                [tuple(record) for record in receipt["results"]], receipt["shutdown"]
            )
    finally:
        guest.execute("timeout 15 systemctl stop lifetime-compositor")
        guest.execute(
            "timeout 15 journalctl -u lifetime-compositor --no-pager | tail -c 262144 > /tmp/lifetime-proof/compositor.log"
        )
        evidence_target = "baseline" if expect_crash else "repaired"
        guest.copy_from_machine("/tmp/lifetime-proof", target_dir=evidence_target)  # ruff: ignore[hardcoded-temp-file] -- Fresh guest-owned evidence.
        guest.copy_from_machine("/tmp/lifetime-home/cache", target_dir=evidence_target)  # ruff: ignore[hardcoded-temp-file] -- The current owned compositor cache only.
        guest.shutdown()


if globals().get("parent_only", False):
    verify_lifetime(baseline, expect_crash=False, parent_only=True)
else:
    verify_lifetime(baseline, expect_crash=True)
    verify_lifetime(repaired, expect_crash=False)
