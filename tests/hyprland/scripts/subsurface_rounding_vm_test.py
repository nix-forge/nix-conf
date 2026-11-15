"""Exercise subsurface rounding vm with the NixOS test driver."""

import json
import re
from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from collections.abc import Callable

    from test_driver.machine import QemuMachine

    # The test driver injects nodes and lifecycle functions at execution.
    machine: QemuMachine = cast("QemuMachine", None)
    start_all: Callable[[], None] = cast("Callable[[], None]", None)

start_all()
unit_status, unit_output = machine.execute(
    "mkdir -p /tmp/rounding-gtest-coverage; "
    "GCOV_PREFIX=/tmp/rounding-gtest-coverage hyprland_gtests > /tmp/gtests.log 2>&1"
)
machine.copy_from_machine("/tmp/gtests.log")
unit_output = machine.succeed("cat /tmp/gtests.log")
assert unit_status == 0, unit_output
assert re.search(r"\[\s*PASSED\s*\]\s+[1-9]\d* tests?", unit_output), unit_output
assert "[  FAILED  ]" not in unit_output, unit_output
try:
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_file("/dev/dri/card0")
    machine.succeed(
        "mkdir -m700 /run/rounding-proof; mkdir -p /tmp/rounding-home/cache /tmp/rounding-proof"
    )
    machine.succeed(
        "systemd-run --unit=rounding-compositor --property=Type=exec --property=RuntimeMaxSec=900 "
        "--setenv=XDG_RUNTIME_DIR=/run/rounding-proof --setenv=LIBGL_ALWAYS_SOFTWARE=1 "
        "--setenv=AQ_DRM_DEVICES=/dev/dri/card0 --setenv=HOME=/tmp/rounding-home "
        "--setenv=XDG_CACHE_HOME=/tmp/rounding-home/cache --setenv=PATH=/run/current-system/sw/bin "
        "Hyprland --i-am-really-stupid --config /etc/hypr-repro.lua"
    )
    machine.wait_for_unit("rounding-compositor.service", timeout=45)
    pid = int(
        machine.succeed(
            "systemctl show --property=MainPID --value rounding-compositor"
        ).strip()
    )
    assert pid > 0, "Owned compositor has no live service PID"
    instances = [
        json.loads(
            machine.succeed(
                "XDG_RUNTIME_DIR=/run/rounding-proof python3 /etc/rounding-observer/compositor_lifecycle.py startup "
                + str(pid)
                + " --runtime /run/rounding-proof --evidence /tmp/rounding-home/cache"
            )
        )
    ]
    observed = instances[0]
    instances = json.loads(
        machine.succeed("XDG_RUNTIME_DIR=/run/rounding-proof hyprctl instances -j")
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
        machine.succeed(
            "systemctl show --property=MainPID --value rounding-compositor"
        ).strip()
    )
    assert pid > 0, instance
    assert type(instance["pid"]) is int, instance
    assert instance["pid"] == pid, instance
    env = f"XDG_RUNTIME_DIR=/run/rounding-proof WAYLAND_DISPLAY={display} HYPRLAND_INSTANCE_SIGNATURE={signature}"
    capabilities = machine.succeed(env + " wayland-info")
    versions = {
        name: int(version)
        for name, version in re.findall(
            r"interface:\s*'([^']+)',\s*version:\s*(\d+)", capabilities
        )
    }
    for interface, minimum in {
        "xdg_wm_base": 6,
        "wl_compositor": 6,
        "wl_seat": 9,
        "zwp_linux_dmabuf_v1": 4,
    }.items():
        assert versions.get(interface, 0) >= minimum, capabilities
    monitors = json.loads(machine.succeed(env + " hyprctl monitors -j"))
    assert len(monitors) == 1, monitors
    assert monitors[0]["width"] > 0, monitors
    assert monitors[0]["height"] > 0, monitors
    rendering = machine.succeed(env + " hyprctl systeminfo")
    assert re.search(r"GL ver: 3\.[02]", rendering), rendering
    renderer_log = f"/run/rounding-proof/hypr/{signature}/hyprland.log"
    renderer = machine.succeed(
        f"timeout 15 grep -F 'Renderer: ' {renderer_log} | tail -c 8192"
    )
    assert re.search(r"Renderer: (?:llvmpipe|softpipe)\b", renderer), renderer
    env = "PYTHONPATH=/etc LIBGL_ALWAYS_SOFTWARE=1 HOME=/tmp/rounding-home " + env + " "
    # Root access is confined to this disposable guest, including its compositor.
    expect_failure = "@expectFailure@"

    cases = (
        [(1, 0)]
        if expect_failure == "True"
        else [(scale, blur) for scale in [1, 1.25, 2] for blur in [0, 1]]
    )
    for scale, blur in cases:
        logfile = f"/tmp/fixture-{scale}-{blur}.log"
        status, _ = machine.execute(
            env
            + f"REPRO_SCALE={scale} REPRO_BLUR={blur} python3 /etc/verify-rounding.py > {logfile} 2>&1"
        )
        machine.copy_from_machine(logfile)
        compositor_log = machine.succeed("cat " + logfile)
        for filename in machine.succeed(
            "find /tmp -maxdepth 1 -type f -name 'fixture-*.png'"
        ).splitlines():
            machine.copy_from_machine(filename, target_dir="rounding-screenshots")
        if expect_failure == "True":
            assert status != 0, "Baseline unexpectedly passed"
            assert "AssertionError:" in compositor_log, compositor_log
            assert any(
                marker in compositor_log
                for marker in (
                    "wrong pixels)",
                    "out-of-parent corner overflow",
                )
            ), "Baseline failed without a rounding pixel mismatch: " + compositor_log
        else:
            assert status == 0, compositor_log

finally:
    machine.execute("timeout 15 systemctl stop rounding-compositor")
    machine.execute(
        "timeout 15 journalctl -u rounding-compositor --no-pager | tail -c 262144 > /tmp/rounding-proof/compositor.log"
    )
    print(machine.succeed("tail -c 8192 /tmp/rounding-proof/compositor.log"))  # ruff: ignore[print] -- Bounded evidence from the owned guest compositor.
    machine.copy_from_machine("/tmp/rounding-proof")
