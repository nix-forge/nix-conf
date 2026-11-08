"""Cold and warm boots must preserve swap, security wrappers and user login."""

from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from test_driver.machine import QemuMachine

    machine: QemuMachine = cast("QemuMachine", None)

machine.start(allow_reboot=True)
for boot in range(2):
    if boot:
        machine.reboot()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("swap-workstation.swap")
    machine.wait_for_unit("systemd-tmpfiles-setup.service")
    machine.wait_for_unit("user@1000.service")
    machine.succeed("mountpoint /run/wrappers")
    machine.succeed("test -x /run/wrappers/bin/unix_chkpwd")
    machine.succeed("test $(stat -c %a /swap) = 700")
    machine.succeed("grep -q '^/swap/workstation ' /proc/swaps")
    machine.fail("journalctl -b --no-pager | grep -F 'ordering cycle'")
