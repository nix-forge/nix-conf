"""Behavior checks for the host-owned wildcard DNS migration."""

import importlib.util
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = (
    Path(__file__).resolve().parents[2]
    / "hosts/nixos/desktop/local/homelab/scripts/ensure_homelab_dns.py"
)
spec = importlib.util.spec_from_file_location("homelab_dns", SCRIPT)
assert spec is not None
assert spec.loader is not None
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
DOMAIN = "example.test"
ZONE_ID = "0123456789abcdef0123456789abcdef"
ADDRESS = "192.168.1.10"
RECORD_ID = "abcdef0123456789abcdef0123456789"


def record(hostname: str, *, address: str = ADDRESS) -> dict[str, object]:
    """Make a DNS-only A record returned by Cloudflare.

    Returns:
        A representative DNS record.

    """
    return {
        "id": RECORD_ID,
        "name": hostname,
        "type": "A",
        "content": address,
        "proxied": False,
    }


class DnsReconciliationTests(unittest.TestCase):
    """The wildcard is live before any exact record is removed."""

    def test_wildcard_lookup_uses_exact_api_filter(self) -> None:
        """A wildcard record name must not broaden the Cloudflare API search."""
        wildcard = f"*.{DOMAIN}"

        def request(
            _token: str,
            _method: str,
            url: str,
            _hostname: str,
            _payload: dict[str, str | bool | int] | None = None,
        ) -> object:
            if "name.exact=%2A." in url:
                return []
            return [record(f"media.{DOMAIN}")]

        with patch.object(module, "request", side_effect=request):
            self.assertEqual(
                module.list_records("fixture-token", "https://example.test", wildcard),
                [],
            )

    def test_creates_and_verifies_wildcard_before_deleting_exact_record(self) -> None:
        """Migration keeps DNS working and stops advertising the site name."""
        wildcard = f"*.{DOMAIN}"
        exact = f"media.{DOMAIN}"
        records = {wildcard: [], exact: [record(exact)]}
        calls: list[tuple[str, str]] = []

        def request(
            _token: str,
            method: str,
            _url: str,
            hostname: str,
            _payload: dict[str, str | bool | int] | None = None,
        ) -> object:
            calls.append((method, hostname))
            if method == "GET":
                return records[hostname]
            if method == "POST":
                records[wildcard] = [record(wildcard)]
            if method == "DELETE":
                records[exact] = []
            return {}

        with patch.object(module, "request", side_effect=request):
            module.reconcile(DOMAIN, ADDRESS, ["media"], "fixture-token", ZONE_ID)

        self.assertEqual(
            calls,
            [
                ("GET", wildcard),
                ("GET", exact),
                ("POST", wildcard),
                ("GET", wildcard),
                ("DELETE", wildcard),
            ],
        )
        self.assertEqual(records[exact], [])

    def test_repeated_run_makes_no_changes(self) -> None:
        """After migration, the wildcard alone satisfies all managed sites."""
        wildcard = f"*.{DOMAIN}"

        def request(
            _token: str,
            method: str,
            _url: str,
            hostname: str,
            _payload: dict[str, str | bool | int] | None = None,
        ) -> object:
            self.assertEqual(method, "GET")
            return [record(wildcard)] if hostname == wildcard else []

        with patch.object(module, "request", side_effect=request):
            module.reconcile(
                DOMAIN, ADDRESS, ["media", "downloads"], "fixture-token", ZONE_ID
            )

    def test_exact_caa_keeps_its_a_record_while_other_names_migrate(self) -> None:
        """A CAA policy suppresses wildcard DNS, so its exact A must remain."""
        wildcard = f"*.{DOMAIN}"
        policy_host = f"media.{DOMAIN}"
        other_host = f"downloads.{DOMAIN}"
        protected = [record(policy_host), {"type": "CAA", "name": policy_host}]
        records = {
            wildcard: [],
            policy_host: protected,
            other_host: [record(other_host)],
        }

        def request(
            _token: str,
            method: str,
            _url: str,
            hostname: str,
            _payload: dict[str, str | bool | int] | None = None,
        ) -> object:
            if method == "GET":
                return records[hostname]
            if method == "POST":
                records[wildcard] = [record(wildcard)]
            if method == "DELETE":
                records[other_host] = []
            return {}

        with patch.object(module, "request", side_effect=request):
            module.reconcile(
                DOMAIN, ADDRESS, ["media", "downloads"], "fixture-token", ZONE_ID
            )
        self.assertEqual(records[policy_host], protected)
        self.assertEqual(records[other_host], [])

    def test_mismatch_prevents_all_writes(self) -> None:
        """A conflicting exact record stops the migration during preflight."""
        calls: list[str] = []

        def request(
            _token: str,
            method: str,
            _url: str,
            hostname: str,
            _payload: dict[str, str | bool | int] | None = None,
        ) -> object:
            calls.append(method)
            if hostname.startswith("conflict."):
                return [record(hostname, address="192.168.1.11")]
            return []

        with (
            patch.object(module, "request", side_effect=request),
            self.assertRaisesRegex(RuntimeError, "refusing to overwrite"),
        ):
            module.reconcile(
                DOMAIN, ADDRESS, ["existing", "conflict"], "fixture-token", ZONE_ID
            )
        self.assertEqual(calls, ["GET", "GET", "GET"])

    def test_other_exact_record_prevents_wildcard_cutover(self) -> None:
        """An exact TXT or CAA record suppresses wildcard resolution."""
        exact = f"media.{DOMAIN}"

        def request(
            _token: str,
            method: str,
            _url: str,
            hostname: str,
            _payload: dict[str, str | bool | int] | None = None,
        ) -> object:
            self.assertEqual(method, "GET")
            return [{"type": "CAA", "name": exact}] if hostname == exact else []

        with (
            patch.object(module, "request", side_effect=request),
            self.assertRaisesRegex(RuntimeError, "refusing to overwrite"),
        ):
            module.reconcile(DOMAIN, ADDRESS, ["media"], "fixture-token", ZONE_ID)

    def test_unverified_wildcard_cannot_trigger_deletion(self) -> None:
        """A delayed or failed wildcard creation leaves exact records intact."""
        exact = f"media.{DOMAIN}"
        calls: list[str] = []

        def request(
            _token: str,
            method: str,
            _url: str,
            hostname: str,
            _payload: dict[str, str | bool | int] | None = None,
        ) -> object:
            calls.append(method)
            return [record(exact)] if hostname == exact else []

        with (
            patch.object(module, "request", side_effect=request),
            self.assertRaisesRegex(RuntimeError, "Wildcard DNS record was not visible"),
        ):
            module.reconcile(DOMAIN, ADDRESS, ["media"], "fixture-token", ZONE_ID)
        self.assertNotIn("DELETE", calls)

    def test_invalid_zone_id_never_calls_api(self) -> None:
        """Reject malformed zone identifiers before any network request."""
        with (
            patch.object(module, "request") as request,
            self.assertRaisesRegex(RuntimeError, "Invalid Cloudflare zone ID"),
        ):
            module.reconcile(DOMAIN, ADDRESS, ["media"], "fixture-token", "bad")
        request.assert_not_called()

    def test_invalid_domain_never_calls_api(self) -> None:
        """An invalid domain must not create or remove DNS records."""
        with (
            patch.object(module, "request") as request,
            self.assertRaisesRegex(RuntimeError, "Invalid HTTPS domain"),
        ):
            module.reconcile("bad/domain", ADDRESS, ["media"], "fixture-token", ZONE_ID)
        request.assert_not_called()

    def test_api_failure_does_not_report_zone_id_or_record_name(self) -> None:
        """HTTP diagnostics must not expose the private zone ID in journals."""
        with (
            patch.object(
                module.urllib.request,
                "urlopen",
                side_effect=OSError("URL includes secret"),
            ),
            self.assertRaisesRegex(
                module.DnsRecordError, "DNS API request failed"
            ) as error,
        ):
            module.reconcile(DOMAIN, ADDRESS, ["media"], "fixture-token", ZONE_ID)
        self.assertNotIn(ZONE_ID, str(error.exception))
        self.assertNotIn("media", str(error.exception))


if __name__ == "__main__":
    unittest.main()
