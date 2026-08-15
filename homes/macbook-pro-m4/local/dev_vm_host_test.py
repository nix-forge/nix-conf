"""Focused fixtures for VMware VMX and DHCP lease resolution."""

from __future__ import annotations

import datetime as dt
import importlib.util
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

MODULE_PATH = Path(
    os.environ.get("DEV_VM_HOST_MODULE", Path(__file__).with_name("dev_vm_host.py"))
)
SPEC = importlib.util.spec_from_file_location("dev_vm_host", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    message = "Could not load the VM host resolver module"
    raise RuntimeError(message)
resolver = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = resolver
SPEC.loader.exec_module(resolver)

NOW = dt.datetime(2026, 8, 12, 16, 0, tzinfo=dt.timezone.utc)
CURRENT_UID = os.getuid()
NEW_MAC = "00:0c:29:e3:5c:79"
OLD_MAC = "00:0c:29:35:9f:d5"


def _isc_timestamp(value: dt.datetime) -> str:
    weekday = (value.weekday() + 1) % 7
    return f"{weekday} {value:%Y/%m/%d %H:%M:%S}"


def _lease(address: str, mac: str, starts: dt.datetime, ends: dt.datetime) -> str:
    return (
        f"lease {address} {{\n"
        f"  starts {_isc_timestamp(starts)};\n"
        f"  ends {_isc_timestamp(ends)};\n"
        f"  hardware ethernet {mac};\n"
        '  client-hostname "fixture";\n'
        "}\n"
    )


def _vmx(mac: str = NEW_MAC, *, second_host_only: bool = False) -> str:
    second = ""
    if second_host_only:
        second = (
            'ethernet2.present = "TRUE"\n'
            'ethernet2.connectionType = "hostonly"\n'
            'ethernet2.addressType = "static"\n'
            'ethernet2.address = "00:0c:29:e3:5c:80"\n'
        )
    return (
        '.encoding = "UTF-8"\n'
        'ethernet0.present = "TRUE"\n'
        'ethernet0.connectionType = "nat"\n'
        'ethernet0.addressType = "generated"\n'
        'ethernet0.generatedAddress = "00:0c:29:e3:5c:6f"\n'
        'ethernet1.present = "TRUE"\n'
        'ethernet1.connectionType = "hostonly"\n'
        'ethernet1.addressType = "generated"\n'
        f'ethernet1.generatedAddress = "{mac}"\n'
        f"{second}"
    )


class ResolverTests(unittest.TestCase):
    """Exercise resolver identity, freshness, and protected-path invariants."""

    def setUp(self) -> None:
        """Create owner-only fixture inputs for one test."""
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve(strict=True)
        self.vmx = self.root / "fixture.vmx"
        self.leases = self.root / "leases"

    @staticmethod
    def _write(path: Path, value: str) -> None:
        path.write_text(value, encoding="utf-8")
        path.chmod(0o600)

    def _resolve(self) -> str:
        return resolver.resolve_host(
            resolver.ResolverConfig(
                vmx=resolver.ProtectedFilePolicy(
                    path=self.vmx,
                    expected_uid=CURRENT_UID,
                    maximum_bytes=resolver.MAX_VMX_BYTES,
                    description="development VM configuration",
                ),
                leases=resolver.ProtectedFilePolicy(
                    path=self.leases,
                    expected_uid=CURRENT_UID,
                    maximum_bytes=resolver.MAX_LEASE_BYTES,
                    description="VMware DHCP lease file",
                ),
                network="172.16.42.0/24",
                now=NOW,
            ),
        )

    def test_regenerated_mac_selects_its_current_lease(self) -> None:
        """A regenerated adapter MAC selects only its matching fresh lease."""
        self._write(self.vmx, _vmx())
        self._write(
            self.leases,
            _lease(
                "172.16.42.128",
                OLD_MAC,
                NOW - dt.timedelta(days=2),
                NOW + dt.timedelta(days=2),
            )
            + _lease(
                "172.16.42.129",
                NEW_MAC,
                NOW - dt.timedelta(hours=1),
                NOW + dt.timedelta(hours=3),
            ),
        )
        self.assertEqual("172.16.42.129", self._resolve())

    def test_static_mac_selects_its_current_lease(self) -> None:
        """A configured static MAC is accepted when it is the sole MAC source."""
        configured_vmx = (
            _vmx()
            .replace('addressType = "generated"', 'addressType = "static"', 2)
            .replace("generatedAddress", "address", 2)
        )
        self._write(self.vmx, configured_vmx)
        self._write(
            self.leases,
            _lease(
                "172.16.42.129",
                NEW_MAC,
                NOW - dt.timedelta(hours=1),
                NOW + dt.timedelta(hours=3),
            ),
        )
        self.assertEqual("172.16.42.129", self._resolve())

    def test_multiple_mac_sources_fail_closed(self) -> None:
        """Generated adapters reject an additional configured MAC source."""
        self._write(
            self.vmx,
            _vmx() + 'ethernet1.address = "00:0c:29:e3:5c:81"\n',
        )
        self._write(
            self.leases,
            _lease(
                "172.16.42.129",
                NEW_MAC,
                NOW - dt.timedelta(hours=1),
                NOW + dt.timedelta(hours=3),
            ),
        )
        with self.assertRaisesRegex(resolver.ResolutionError, "exactly one MAC"):
            self._resolve()

    def test_stale_and_fresh_duplicate_selects_fresh_record(self) -> None:
        """An expired duplicate cannot outrank a matching fresh lease."""
        self._write(self.vmx, _vmx())
        self._write(
            self.leases,
            _lease(
                "172.16.42.128",
                NEW_MAC,
                NOW - dt.timedelta(days=2),
                NOW - dt.timedelta(days=1),
            )
            + _lease(
                "172.16.42.129",
                NEW_MAC,
                NOW - dt.timedelta(minutes=20),
                NOW + dt.timedelta(hours=2),
            ),
        )
        self.assertEqual("172.16.42.129", self._resolve())

    def test_expired_only_lease_fails(self) -> None:
        """A matching but expired lease never resolves a host."""
        self._write(self.vmx, _vmx())
        self._write(
            self.leases,
            _lease(
                "172.16.42.128",
                NEW_MAC,
                NOW - dt.timedelta(hours=2),
                NOW - dt.timedelta(hours=1),
            ),
        )
        with self.assertRaisesRegex(resolver.ResolutionError, "no unexpired"):
            self._resolve()

    def test_multiple_present_host_only_adapters_fail(self) -> None:
        """More than one present host-only adapter is ambiguous."""
        self._write(self.vmx, _vmx(second_host_only=True))
        self._write(
            self.leases,
            _lease(
                "172.16.42.129",
                NEW_MAC,
                NOW - dt.timedelta(minutes=20),
                NOW + dt.timedelta(hours=2),
            ),
        )
        with self.assertRaisesRegex(resolver.ResolutionError, "exactly one"):
            self._resolve()

    def test_malformed_vmx_fails_closed(self) -> None:
        """A malformed VMX assignment cannot yield an adapter identity."""
        self._write(self.vmx, _vmx() + 'ethernet3.present = "TRUE\n')
        self._write(
            self.leases,
            _lease(
                "172.16.42.129",
                NEW_MAC,
                NOW - dt.timedelta(minutes=20),
                NOW + dt.timedelta(hours=2),
            ),
        )
        with self.assertRaisesRegex(resolver.ResolutionError, "malformed assignment"):
            self._resolve()

    def test_incomplete_lease_fails_closed(self) -> None:
        """A lease missing its closing record delimiter is rejected."""
        self._write(self.vmx, _vmx())
        self._write(
            self.leases,
            _lease(
                "172.16.42.129",
                NEW_MAC,
                NOW - dt.timedelta(minutes=20),
                NOW + dt.timedelta(hours=2),
            ).removesuffix("}\n"),
        )
        with self.assertRaisesRegex(resolver.ResolutionError, "incomplete record"):
            self._resolve()

    def test_symlink_inputs_fail_closed(self) -> None:
        """Leaf symlinks cannot redirect either protected metadata input."""
        real_vmx = self.root / "real.vmx"
        real_leases = self.root / "real.leases"
        self._write(real_vmx, _vmx())
        self._write(
            real_leases,
            _lease(
                "172.16.42.129",
                NEW_MAC,
                NOW - dt.timedelta(minutes=20),
                NOW + dt.timedelta(hours=2),
            ),
        )
        self.vmx.symlink_to(real_vmx)
        self.leases.symlink_to(real_leases)
        with self.assertRaisesRegex(resolver.ResolutionError, "non-symlink ancestry"):
            self._resolve()
        self.vmx.unlink()
        self._write(self.vmx, _vmx())
        with self.assertRaisesRegex(resolver.ResolutionError, "non-symlink ancestry"):
            self._resolve()

    def test_symlink_parent_fails_closed(self) -> None:
        """A symlinked ancestor cannot redirect a protected metadata input."""
        real_directory = self.root / "real"
        real_directory.mkdir()
        linked_directory = self.root / "linked"
        linked_directory.symlink_to(real_directory, target_is_directory=True)
        self.vmx = linked_directory / "fixture.vmx"
        self.leases = real_directory / "leases"
        self._write(real_directory / "fixture.vmx", _vmx())
        self._write(
            self.leases,
            _lease(
                "172.16.42.129",
                NEW_MAC,
                NOW - dt.timedelta(minutes=20),
                NOW + dt.timedelta(hours=2),
            ),
        )
        with self.assertRaisesRegex(resolver.ResolutionError, "non-symlink ancestry"):
            self._resolve()

    def test_wrong_owner_expectation_fails_closed(self) -> None:
        """A file outside its required ownership identity is rejected."""
        self._write(self.vmx, _vmx())
        self._write(
            self.leases,
            _lease(
                "172.16.42.129",
                NEW_MAC,
                NOW - dt.timedelta(minutes=20),
                NOW + dt.timedelta(hours=2),
            ),
        )
        config = resolver.ResolverConfig(
            vmx=resolver.ProtectedFilePolicy(
                path=self.vmx,
                expected_uid=CURRENT_UID + 1,
                maximum_bytes=resolver.MAX_VMX_BYTES,
                description="development VM configuration",
            ),
            leases=resolver.ProtectedFilePolicy(
                path=self.leases,
                expected_uid=CURRENT_UID,
                maximum_bytes=resolver.MAX_LEASE_BYTES,
                description="VMware DHCP lease file",
            ),
            network="172.16.42.0/24",
            now=NOW,
        )
        with self.assertRaisesRegex(resolver.ResolutionError, "wrong owner"):
            resolver.resolve_host(config)

    def test_tied_newest_addresses_are_ambiguous(self) -> None:
        """Equally new leases for different addresses remain ambiguous."""
        self._write(self.vmx, _vmx())
        starts = NOW - dt.timedelta(minutes=20)
        self._write(
            self.leases,
            _lease("172.16.42.129", NEW_MAC, starts, NOW + dt.timedelta(hours=2))
            + _lease(
                "172.16.42.130",
                NEW_MAC,
                starts,
                NOW + dt.timedelta(hours=3),
            ),
        )
        with self.assertRaisesRegex(resolver.ResolutionError, "ambiguous"):
            self._resolve()

    def test_tcp_reachability_uses_the_resolved_endpoint(self) -> None:
        """Reachability probes the resolved address and fails on connection error."""
        with mock.patch.object(resolver.socket, "create_connection") as connect:
            resolver.require_tcp_reachable("172.16.42.129", 22, 1.0)
            connect.assert_called_once_with(("172.16.42.129", 22), timeout=1.0)
        with (
            mock.patch.object(
                resolver.socket, "create_connection", side_effect=OSError("unreachable")
            ),
            self.assertRaisesRegex(resolver.ResolutionError, "unreachable"),
        ):
            resolver.require_tcp_reachable("172.16.42.129", 22, 0.1)


if __name__ == "__main__":
    unittest.main()
