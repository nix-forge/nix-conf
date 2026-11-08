"""Exercise application recovery with the NixOS test driver."""

from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from test_driver.machine import QemuMachine

    # The test driver injects nodes and lifecycle functions at execution.
    machine: QemuMachine = cast("QemuMachine", None)

machine.start()
machine.wait_for_unit("fixture-writer.service")
machine.succeed("echo persisted-generation-2 > /var/lib/recovery-fixture/live")
machine.succeed("systemctl start application-recovery-fixture-backup.service")
machine.wait_for_unit("fixture-writer.service")
machine.succeed("rm /var/lib/recovery-fixture/live")
machine.succeed("systemctl start application-recovery-fixture-drill.service")
machine.succeed("test -f /var/lib/application-recovery/fixture/drill-success.json")
machine.fail("test -e /var/lib/recovery-fixture/forbidden")
machine.fail("systemctl start application-recovery-failing-backup.service")
machine.wait_for_unit("fixture-writer.service")
machine.fail("test -e /var/lib/application-recovery/failing/backup-success.json")
machine.succeed("test -f /var/lib/application-recovery/failing/backup-attempt.json")
