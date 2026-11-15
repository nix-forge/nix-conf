"""Exercise noogle with the NixOS test driver."""

from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from test_driver.machine import QemuMachine

    # The test driver injects nodes and lifecycle functions at execution.
    machine: QemuMachine = cast("QemuMachine", None)

import json

machine.start()
machine.wait_for_unit("multi-user.target")
expected = json.loads(machine.succeed("cat /etc/expected-arguments.json"))
for name, arguments in expected.items():
    received = json.loads(machine.succeed(f"cat /run/{name}.json"))
    assert received == arguments, (name, received, arguments)
