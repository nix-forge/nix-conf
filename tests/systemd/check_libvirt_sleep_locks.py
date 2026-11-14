"""Assert the libvirt guest owns the expected native sleep inhibitor."""

import json
import sys

locks = [
    lock
    for lock in json.load(sys.stdin)
    if lock["who"] == "libvirt-guest-" + sys.argv[1]
    and lock["what"] == "sleep"
    and lock["mode"] == "block"
]
assert len(locks) == int(sys.argv[2]), locks
