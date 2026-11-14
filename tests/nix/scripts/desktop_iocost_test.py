"""Exercise desktop iocost with the NixOS test driver."""

from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from test_driver.machine import QemuMachine

    # The test driver injects nodes and lifecycle functions at execution.
    machine: QemuMachine = cast("QemuMachine", None)

machine.start()
machine.wait_for_unit("desktop-iocost.service")
device = machine.succeed("cat /sys/block/nvme0n1/dev").strip()
# The guest's kernel may default to mq-deadline. Reproduce the desktop's
# none scheduler explicitly before checking controller independence.
machine.succeed("echo none > /sys/block/nvme0n1/queue/scheduler")


def assert_enabled() -> None:
    """Verify that the kernel cost controller is enabled for the guest disk."""
    lines = machine.succeed("cat /sys/fs/cgroup/io.cost.qos").splitlines()
    settings = next(line.split()[1:] for line in lines if line.split()[0] == device)
    assert "enable=1" in settings, settings
    assert "ctrl=auto" in settings, settings
    model = machine.succeed("cat /sys/fs/cgroup/io.cost.model")
    assert any(
        line.startswith(device + " ") and "ctrl=auto" in line
        for line in model.splitlines()
    ), model


assert_enabled()
# This controller works with the ordinary NVMe scheduler; it does not
# require replacing the scheduler with BFQ.
assert "[none]" in machine.succeed("cat /sys/block/nvme0n1/queue/scheduler")
machine.succeed(f"echo '{device} enable=0' > /sys/fs/cgroup/io.cost.qos")
machine.succeed("udevadm trigger --action=change /sys/block/nvme0n1 && udevadm settle")
assert_enabled()
# Reapplying the service also handles already enumerated drives.
machine.succeed(f"echo '{device} enable=0' > /sys/fs/cgroup/io.cost.qos")
machine.succeed("systemctl restart desktop-iocost.service")
assert_enabled()
machine.succeed("systemd-run --unit=iocost-user-check --slice=user.slice sleep 10")
assert "default 200" in machine.succeed("cat /sys/fs/cgroup/user.slice/io.weight")
