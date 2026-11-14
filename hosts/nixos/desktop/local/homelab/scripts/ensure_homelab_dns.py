"""Replace per-app public DNS records with one private-address wildcard."""

import json
import os
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

RECORD_PAGE_SIZE = 100
MAX_DOMAIN_LENGTH = 253
MAX_LABEL_LENGTH = 63
MIN_DOMAIN_LABELS = 2


class DnsRecordError(RuntimeError):
    """The selected DNS record cannot be reconciled safely."""


def request(
    token: str,
    method: str,
    url: str,
    _hostname: str,
    payload: dict[str, str | bool | int] | None = None,
) -> object:
    """Call the fixed Cloudflare zone API.

    Returns:
        The API's result.

    Raises:
        DnsRecordError: Cloudflare rejects the request.

    """
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(  # ruff: ignore[suspicious-url-open-usage] - API is a fixed HTTPS zone URL.
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as response:  # ruff: ignore[suspicious-url-open-usage]
            result = json.load(response)
    except OSError, ValueError:
        # HTTPError contains the full URL, including the private zone ID.
        message = "Cloudflare DNS API request failed"
        raise DnsRecordError(message) from None
    if (
        not isinstance(result, dict)
        or not result.get("success")
        or "result" not in result
    ):
        message = f"Cloudflare DNS API rejected {method}"
        raise DnsRecordError(message)
    return result["result"]


def list_records(token: str, api: str, hostname: str) -> list[dict[str, object]]:
    """Get exact records, never a resolved wildcard answer.

    Returns:
        Exact DNS records at this name.

    Raises:
        DnsRecordError: The API returns an invalid or truncated record list.

    """
    query = urllib.parse.urlencode({
        "name.exact": hostname,
        "per_page": RECORD_PAGE_SIZE,
    })
    result = request(token, "GET", f"{api}?{query}", hostname)
    if not isinstance(result, list) or not all(
        isinstance(item, dict) for item in result
    ):
        message = "Invalid Cloudflare DNS response"
        raise DnsRecordError(message)
    if len(result) == RECORD_PAGE_SIZE:
        message = "Too many DNS records to reconcile safely"
        raise DnsRecordError(message)
    return result


def matching_a_record(
    records: list[dict[str, object]], hostname: str, address: str
) -> dict[str, object] | None:
    """Accept only one exact, DNS-only A record with the expected address.

    Returns:
        The matching record, or None when the name has no exact records.

    Raises:
        DnsRecordError: Another record could override wildcard resolution.

    """
    if not records:
        return None
    if len(records) != 1 or any(
        record.get("type") != "A"
        or record.get("name") != hostname
        or record.get("content") != address
        or record.get("proxied") is not False
        for record in records
    ):
        message = "Unexpected DNS records; refusing to overwrite"
        raise DnsRecordError(message)
    return records[0]


def site_a_record(
    records: list[dict[str, object]], hostname: str, address: str
) -> tuple[dict[str, object] | None, bool]:
    """Check an exact site and identify CAA policies that require its A record.

    Returns:
        The expected A record and whether an exact CAA policy must be retained.

    Raises:
        DnsRecordError: Records conflict with the expected private address.

    """
    if not records:
        return None, False
    if any(
        record.get("name") != hostname or record.get("type") not in {"A", "CAA"}
        for record in records
    ):
        message = "Unexpected DNS records; refusing to overwrite"
        raise DnsRecordError(message)
    address_records = [record for record in records if record["type"] == "A"]
    if len(address_records) != 1:
        message = "Unexpected DNS records; refusing to overwrite"
        raise DnsRecordError(message)
    address_record = matching_a_record(address_records, hostname, address)
    return address_record, len(records) > 1


def preflight_sites(
    domain: str, token: str, api: str, address: str, names: list[str]
) -> tuple[list[str], int]:
    """Identify exact A records that can safely yield to the wildcard.

    Returns:
        Deletable record IDs and a count of CAA-protected exact names.

    Raises:
        DnsRecordError: An existing site record is unsafe to change.

    """
    if len(names) != len(set(names)):
        message = "Duplicate HTTPS site names"
        raise DnsRecordError(message)
    legacy_records: list[str] = []
    policy_retained = 0
    for name in names:
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", name):
            message = "Invalid HTTPS site name"
            raise DnsRecordError(message)
        hostname = f"{name}.{domain}"
        record, has_caa_policy = site_a_record(
            list_records(token, api, hostname), hostname, address
        )
        if record is not None:
            if has_caa_policy:
                # An exact CAA record suppresses the wildcard A answer. Keep
                # its matching A record and the certificate policy together.
                policy_retained += 1
                continue
            record_id = record.get("id")
            if not isinstance(record_id, str) or not re.fullmatch(
                r"[0-9a-f]{32}", record_id
            ):
                message = "Invalid DNS record ID; refusing to delete"
                raise DnsRecordError(message)
            legacy_records.append(record_id)
    return legacy_records, policy_retained


def reconcile(
    domain: str, address: str, names: list[str], token: str, zone_id: str
) -> None:
    """Preflight, create the wildcard, then remove only matching legacy records.

    Raises:
        DnsRecordError: A site name or existing record is unsafe to change.

    """
    labels = domain.split(".")
    if (
        len(domain) > MAX_DOMAIN_LENGTH
        or len(labels) < MIN_DOMAIN_LABELS
        or any(
            len(label) > MAX_LABEL_LENGTH
            or re.fullmatch(r"[a-z0-9](?:[a-z0-9-]*[a-z0-9])?", label) is None
            for label in labels
        )
    ):
        message = "Invalid HTTPS domain"
        raise DnsRecordError(message)
    if not re.fullmatch(r"[0-9a-f]{32}", zone_id):
        message = "Invalid Cloudflare zone ID"
        raise DnsRecordError(message)
    api = f"https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records"
    wildcard = f"*.{domain}"
    wildcard_record = matching_a_record(
        list_records(token, api, wildcard), wildcard, address
    )
    legacy_records, policy_retained = preflight_sites(
        domain, token, api, address, names
    )

    # Exact records override wildcard DNS. Create and verify its replacement
    # before removing any of them, so a failed API request keeps old names live.
    if wildcard_record is None:
        request(
            token,
            "POST",
            api,
            wildcard,
            {
                "type": "A",
                "name": wildcard,
                "content": address,
                "proxied": False,
                "ttl": 1,
            },
        )
        if (
            matching_a_record(list_records(token, api, wildcard), wildcard, address)
            is None
        ):
            message = "Wildcard DNS record was not visible; keeping exact records"
            raise DnsRecordError(message)
    for record_id in legacy_records:
        request(token, "DELETE", f"{api}/{record_id}", wildcard)
    sys.stdout.write(
        f"Wildcard DNS ready; removed {len(legacy_records)} exact HTTPS records; "
        f"retained {policy_retained} with CAA policy\n"
    )


def main() -> int:
    """Read the runtime token and reconcile all declared site names.

    Returns:
        Exit status, with API and credential failures reported without secret paths.

    Raises:
        SystemExit: Required command arguments are absent.

    """
    minimum_arguments = 4
    if len(sys.argv) < minimum_arguments:
        message = "usage: ensure_homelab_dns.py DOMAIN ADDRESS SITE [SITE ...]"
        raise SystemExit(message)
    domain, address, *names = sys.argv[1:]
    try:
        credential_dir = Path(os.environ["CREDENTIALS_DIRECTORY"])
        token = (
            (credential_dir / "cloudflare-token").read_text(encoding="utf-8").strip()
        )
        zone_id = (
            (credential_dir / "cloudflare-zone-id").read_text(encoding="utf-8").strip()
        )
        reconcile(domain, address, names, token, zone_id)
    except DnsRecordError as error:
        sys.stderr.write(f"{error}\n")
        return 1
    except OSError, KeyError:
        sys.stderr.write("DNS credentials unavailable\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
