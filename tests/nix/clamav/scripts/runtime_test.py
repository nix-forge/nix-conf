"""Exercise runtime with the NixOS test driver."""

import shlex
from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from test_driver.machine import QemuMachine

    # The test driver injects nodes and lifecycle functions at execution.
    machine: QemuMachine = cast("QemuMachine", None)

machine.start()
# With the old dependency, freshclam waits forever for this offline
# machine and neither clamd nor multi-user.target completes startup.
machine.wait_for_unit("multi-user.target", timeout=30)
machine.succeed('clamav-fixture-ready "$(cat /etc/clamav/fixture-socket)" 10')
unit = machine.succeed("systemctl cat clamdscan.service")
commands = [
    shlex.split(line.partition("=")[2])
    for line in unit.splitlines()
    if line.startswith("ExecStart=")
]
assert len(commands) == 1
assert commands[0][1:3] == ["--workers", "1"]
machine.succeed("systemctl start --no-block clamav-freshclam.service")
machine.wait_until_succeeds(
    "test $(systemctl show -p ActiveState --value clamav-freshclam.service) = activating"
)
machine.succeed("systemctl is-active clamav-daemon.service")
machine.succeed("systemctl start clamdscan.service", timeout=30)
machine.succeed(
    "test $(systemctl show -p ActiveState --value clamav-freshclam.service) = activating"
)

# A missing database must fail visibly and recover after a successful
# update without an operator restarting the daemon.
machine.succeed("systemctl stop clamav-daemon.service")
machine.fail("systemctl is-active clamav-daemon.service")
machine.succeed("rm /var/lib/clamav/fixture.ndb")
machine.succeed("systemctl start --no-block clamav-daemon.service")
machine.wait_until_succeeds(
    "test $(systemctl show -p NRestarts --value clamav-daemon.service) -gt 0"
)
machine.succeed("printf 'online\\n' > /run/fixture-network-online", timeout=10)
machine.succeed('clamav-fixture-ready "$(cat /etc/clamav/fixture-socket)" 10')
machine.succeed("systemctl is-active clamav-daemon.service")

# A local test signature proves that the scan sees both host temporary
# directories. PrivateTmp=true would incorrectly report a clean scan.
canaries = (
    machine.succeed("mktemp --tmpdir=/tmp clamav-fixture.XXXXXX").strip(),
    machine.succeed("mktemp --tmpdir=/var/tmp clamav-fixture.XXXXXX").strip(),
)
for path in canaries:
    machine.succeed(f"printf LOCAL_CLAMAV_REGRESSION_SIGNATURE > {shlex.quote(path)}")
machine.fail("systemctl start clamdscan.service", timeout=30)
machine.succeed(
    "test $(systemctl show -p ExecMainStatus --value clamdscan.service) = 1"
)
output = machine.succeed("journalctl -u clamdscan.service --no-pager -o cat")
for path in canaries:
    assert any(
        line.startswith(f"{path!r}:") and "LocalFixture.UNOFFICIAL FOUND" in line
        for line in output.splitlines()
    )
machine.succeed("rm -- " + " ".join(shlex.quote(path) for path in canaries))
machine.succeed("systemctl reset-failed clamdscan.service")
machine.succeed("systemctl start clamdscan.service", timeout=30)
machine.succeed("test $(systemctl show -p Result --value clamdscan.service) = success")
