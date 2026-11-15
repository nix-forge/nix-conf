"""Exercise the generated configuration with the NixOS VM driver."""

from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from test_driver.machine import QemuMachine

    machine: QemuMachine = cast("QemuMachine", None)

# Restores happen before the first boot, so tmpfiles cannot be relied on
# to repair these permissions after the installer formats the disks.
for path in [
    "/mnt/home/.snapshots",
    "/mnt/srv/data/.snapshots",
    "/mnt/srv/data/work/.snapshots",
]:
    assert machine.succeed("stat -c '%u:%g:%a' " + path).strip() == "0:0:700"
for user in ["ianmh", "alex"]:
    machine.fail("test -e /mnt/home/" + user)
machine.succeed("install -d -m 700 /mnt/var/lib/desktop-storage/keys")
machine.succeed(
    "install -m 600 /tmp/secret.key /mnt/var/lib/desktop-storage/keys/data.key"
)
machine.succeed(
    "install -m 600 /tmp/secret.key /mnt/var/lib/desktop-storage/keys/homelab.key"
)
