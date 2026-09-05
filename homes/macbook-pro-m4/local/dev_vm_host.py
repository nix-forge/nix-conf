"""Resolve one VMware host-only guest from protected runtime metadata."""

from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import ipaddress
import os
import re
import socket
import stat
import sys
from pathlib import Path
from typing import Never

MAC_PATTERN = re.compile(r"[0-9a-f]{2}(?::[0-9a-f]{2}){5}")
VMX_ASSIGNMENT = re.compile(
    r'\s*([A-Za-z0-9_.:-]+)\s*=\s*"((?:[^"\\]|\\.)*)"\s*',
)
LEASE_HEADER = re.compile(r"lease\s+(\S+)\s*\{\s*")
LEASE_TIMESTAMP = re.compile(
    r"(starts|ends)\s+([0-6])\s+(\d{4}/\d{2}/\d{2})\s+"
    r"(\d{2}:\d{2}:\d{2})\s*;",
)
LEASE_HARDWARE = re.compile(
    r"hardware\s+ethernet\s+([0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5})\s*;",
)
MAX_VMX_BYTES = 4 * 1024 * 1024
MAX_LEASE_BYTES = 16 * 1024 * 1024
READ_CHUNK_BYTES = 64 * 1024
HOST_ONLY_PREFIX_LENGTH = 24
MIN_TCP_PORT = 1
MAX_TCP_PORT = 65_535
MAX_TCP_TIMEOUT_SECONDS = 30
MIN_FILE_PATH_PARTS = 2


class ResolutionError(RuntimeError):
    """A fail-closed runtime identity or reachability error."""


@dataclasses.dataclass(frozen=True)
class ProtectedFilePolicy:
    """Security policy for one runtime metadata file."""

    path: Path
    expected_uid: int
    maximum_bytes: int
    description: str


@dataclasses.dataclass(frozen=True)
class HostOnlyAdapter:
    """The uniquely selected host-only VM adapter."""

    index: str
    mac: str


@dataclasses.dataclass(frozen=True)
class LeaseRecord:
    """One complete DHCP lease identity and validity interval."""

    address: ipaddress.IPv4Address
    starts: dt.datetime
    ends: dt.datetime
    mac: str


@dataclasses.dataclass(frozen=True)
class ResolverConfig:
    """Inputs bound to one VM host-resolution operation."""

    vmx: ProtectedFilePolicy
    leases: ProtectedFilePolicy
    network: str
    now: dt.datetime


def _fail(message: str, *, cause: BaseException | None = None) -> Never:
    if cause is None:
        raise ResolutionError(message)
    raise ResolutionError(message) from cause


def _secure_open(policy: ProtectedFilePolicy) -> int:
    path = policy.path
    if not path.is_absolute() or any(part in {".", ".."} for part in path.parts):
        _fail(f"{policy.description} path must be absolute and normalized")
    if len(path.parts) < MIN_FILE_PATH_PARTS:
        _fail(f"{policy.description} path must identify a file")
    if not hasattr(os, "O_NOFOLLOW") or not hasattr(os, "O_DIRECTORY"):
        _fail("this host cannot enforce no-follow runtime metadata access")

    directory_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW
    file_flags = os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW
    directory_descriptor = -1
    try:
        directory_descriptor = os.open(path.anchor, directory_flags)
        for component in path.parts[1:-1]:
            next_descriptor = os.open(
                component,
                directory_flags,
                dir_fd=directory_descriptor,
            )
            os.close(directory_descriptor)
            directory_descriptor = next_descriptor
        descriptor = os.open(
            path.parts[-1],
            file_flags,
            dir_fd=directory_descriptor,
        )
    except OSError as error:
        _fail(
            f"{policy.description} could not be opened through non-symlink ancestry",
            cause=error,
        )
    finally:
        if directory_descriptor >= 0:
            os.close(directory_descriptor)

    opened_status = os.fstat(descriptor)
    if not stat.S_ISREG(opened_status.st_mode):
        os.close(descriptor)
        _fail(f"{policy.description} must be a regular file")
    if opened_status.st_uid != policy.expected_uid:
        os.close(descriptor)
        _fail(f"{policy.description} has the wrong owner")
    if opened_status.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
        os.close(descriptor)
        _fail(f"{policy.description} must not be group- or world-writable")
    return descriptor


def _read_descriptor(descriptor: int, maximum_bytes: int, description: str) -> bytes:
    chunks: list[bytes] = []
    total = 0
    while True:
        remaining = maximum_bytes + 1 - total
        chunk = os.read(descriptor, min(READ_CHUNK_BYTES, remaining))
        if not chunk:
            return b"".join(chunks)
        chunks.append(chunk)
        total += len(chunk)
        if total > maximum_bytes:
            _fail(f"{description} exceeds its maximum accepted size")


def _read_protected_file(policy: ProtectedFilePolicy) -> str:
    descriptor = _secure_open(policy)
    try:
        content = _read_descriptor(
            descriptor,
            policy.maximum_bytes,
            policy.description,
        )
    finally:
        os.close(descriptor)
    try:
        return content.decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        _fail(f"{policy.description} is not valid UTF-8", cause=error)


def _canonical_mac(value: str) -> str:
    candidate = value.lower()
    if MAC_PATTERN.fullmatch(candidate) is None:
        _fail("host-only adapter has a malformed MAC address")
    octets = bytes(int(part, 16) for part in candidate.split(":"))
    if octets == bytes(6) or octets[0] & 1:
        _fail("host-only adapter MAC address is not a valid unicast identity")
    return candidate


def _parse_vmx_values(vmx_text: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for line_number, raw_line in enumerate(vmx_text.splitlines(), start=1):
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        match = VMX_ASSIGNMENT.fullmatch(raw_line)
        if match is None:
            _fail(f"VMX contains a malformed assignment at line {line_number}")
        key = match.group(1).lower()
        if not key.startswith("ethernet"):
            continue
        if key in values:
            _fail("VMX contains a duplicate Ethernet setting")
        values[key] = match.group(2)
    return values


def _present_host_only_names(values: dict[str, str]) -> list[str]:
    adapter_names = {
        key.split(".", maxsplit=1)[0]
        for key in values
        if re.fullmatch(r"ethernet\d+\..+", key)
    }
    present_host_only: list[str] = []
    for adapter_name in sorted(adapter_names):
        present = values.get(f"{adapter_name}.present", "").lower()
        if present not in {"true", "false"}:
            _fail("VMX Ethernet presence is missing or malformed")
        connection_type = values.get(f"{adapter_name}.connectiontype", "").lower()
        if present == "true" and connection_type == "hostonly":
            present_host_only.append(adapter_name)
    return present_host_only


def _selected_adapter_mac(values: dict[str, str], adapter_name: str) -> str:
    address_type = values.get(f"{adapter_name}.addresstype", "").lower()
    generated = values.get(f"{adapter_name}.generatedaddress")
    configured = values.get(f"{adapter_name}.address")
    if address_type == "generated" and generated is not None and configured is None:
        return _canonical_mac(generated)
    if (
        address_type in {"static", "manual"}
        and configured is not None
        and generated is None
    ):
        return _canonical_mac(configured)
    _fail("host-only adapter must expose exactly one MAC matching its address type")


def parse_host_only_adapter(vmx_text: str) -> HostOnlyAdapter:
    """Select exactly one present host-only adapter and its authoritative MAC.

    Returns:
        The unique host-only adapter.

    """
    values = _parse_vmx_values(vmx_text)
    adapter_names = _present_host_only_names(values)
    if len(adapter_names) != 1:
        _fail("VMX must contain exactly one present host-only adapter")
    adapter_name = adapter_names[0]
    return HostOnlyAdapter(
        index=adapter_name,
        mac=_selected_adapter_mac(values, adapter_name),
    )


def _strip_lease_comment(line: str) -> str:
    quoted = False
    escaped = False
    output: list[str] = []
    for character in line:
        if escaped:
            output.append(character)
            escaped = False
        elif character == "\\" and quoted:
            output.append(character)
            escaped = True
        elif character == '"':
            output.append(character)
            quoted = not quoted
        elif character == "#" and not quoted:
            break
        else:
            output.append(character)
    if quoted:
        _fail("DHCP lease file contains an unterminated quoted value")
    return "".join(output).strip()


def _parse_lease_timestamp(statement: str, field: str) -> dt.datetime:
    match = LEASE_TIMESTAMP.fullmatch(statement)
    if match is None or match.group(1) != field:
        _fail(f"DHCP lease has a malformed {field} timestamp")
    try:
        value = dt.datetime.strptime(
            f"{match.group(3)} {match.group(4)}",
            "%Y/%m/%d %H:%M:%S",
        ).replace(tzinfo=dt.timezone.utc)
    except ValueError as error:
        _fail(f"DHCP lease has an invalid {field} timestamp", cause=error)
    isc_weekday = (value.weekday() + 1) % 7
    if int(match.group(2)) != isc_weekday:
        _fail(f"DHCP lease {field} weekday does not match its date")
    return value


def _build_lease(address_text: str, statements: list[str]) -> LeaseRecord:
    try:
        address = ipaddress.ip_address(address_text)
    except ValueError as error:
        _fail("DHCP lease contains an invalid address", cause=error)
    if not isinstance(address, ipaddress.IPv4Address):
        _fail("DHCP lease address must be IPv4")
    starts_values = [value for value in statements if value.startswith("starts ")]
    ends_values = [value for value in statements if value.startswith("ends ")]
    hardware_values = [value for value in statements if value.startswith("hardware ")]
    if len(starts_values) != 1 or len(ends_values) != 1 or len(hardware_values) != 1:
        _fail("DHCP lease record is incomplete or duplicates identity fields")
    starts = _parse_lease_timestamp(starts_values[0], "starts")
    ends = _parse_lease_timestamp(ends_values[0], "ends")
    if ends <= starts:
        _fail("DHCP lease ends before it starts")
    hardware = LEASE_HARDWARE.fullmatch(hardware_values[0])
    if hardware is None:
        _fail("DHCP lease has a malformed hardware identity")
    return LeaseRecord(
        address=address,
        starts=starts,
        ends=ends,
        mac=_canonical_mac(hardware.group(1)),
    )


def parse_leases(lease_text: str) -> list[LeaseRecord]:
    """Parse complete ISC DHCP lease records while rejecting malformed structure.

    Returns:
        All complete lease records in source order.

    """
    records: list[LeaseRecord] = []
    active_address: str | None = None
    active_statements: list[str] = []
    for line_number, raw_line in enumerate(lease_text.splitlines(), start=1):
        line = _strip_lease_comment(raw_line)
        if not line:
            continue
        if active_address is None:
            header = LEASE_HEADER.fullmatch(line)
            if header is not None:
                active_address = header.group(1)
                active_statements = []
            elif not line.endswith(";") or "{" in line or "}" in line:
                _fail(
                    "DHCP lease file contains malformed top-level data "
                    f"at line {line_number}",
                )
            continue
        if line == "}":
            records.append(_build_lease(active_address, active_statements))
            active_address = None
            active_statements = []
        elif "{" in line or "}" in line or not line.endswith(";"):
            _fail(
                f"DHCP lease record contains malformed data at line {line_number}",
            )
        else:
            active_statements.append(line)
    if active_address is not None:
        _fail("DHCP lease file ends inside an incomplete record")
    if not records:
        _fail("DHCP lease file contains no complete lease records")
    return records


def _eligible_leases(
    records: list[LeaseRecord],
    *,
    mac: str,
    network: ipaddress.IPv4Network,
    now: dt.datetime,
) -> list[LeaseRecord]:
    identities = {
        (record.address, record.starts, record.ends): record
        for record in records
        if record.mac == mac
        and record.address in network
        and record.address not in {network.network_address, network.broadcast_address}
        and record.starts <= now < record.ends
    }
    return list(identities.values())


def select_newest_lease(
    records: list[LeaseRecord],
    *,
    mac: str,
    network_text: str,
    now: dt.datetime,
) -> ipaddress.IPv4Address:
    """Choose the newest unique unexpired lease for one adapter and subnet.

    Returns:
        The uniquely selected host-only IPv4 address.

    """
    try:
        network = ipaddress.ip_network(network_text, strict=True)
    except ValueError as error:
        _fail("configured host-only network is invalid", cause=error)
    if (
        not isinstance(network, ipaddress.IPv4Network)
        or network.prefixlen != HOST_ONLY_PREFIX_LENGTH
    ):
        _fail("configured host-only network must be one IPv4 /24")
    if now.tzinfo is None or now.utcoffset() != dt.timedelta(0):
        _fail("lease comparison time must be UTC")

    eligible = _eligible_leases(records, mac=mac, network=network, now=now)
    if not eligible:
        _fail("no unexpired host-only DHCP lease matches the VM identity")
    ordered = sorted(
        eligible,
        key=lambda record: (record.starts, record.ends),
        reverse=True,
    )
    selected = ordered[0]
    tied_addresses = {
        record.address for record in ordered if record.starts == selected.starts
    }
    if len(tied_addresses) != 1:
        _fail("newest host-only DHCP lease is ambiguous")
    return selected.address


def resolve_host(config: ResolverConfig) -> str:
    """Resolve the current host-only address from protected VM and lease inputs.

    Returns:
        The current host-only IPv4 address as text.

    """
    vmx_text = _read_protected_file(config.vmx)
    lease_text = _read_protected_file(config.leases)
    adapter = parse_host_only_adapter(vmx_text)
    records = parse_leases(lease_text)
    return str(
        select_newest_lease(
            records,
            mac=adapter.mac,
            network_text=config.network,
            now=config.now,
        ),
    )


def require_tcp_reachable(host: str, port: int, timeout_seconds: float) -> None:
    """Require a bounded TCP connection to the selected endpoint."""
    valid_port = MIN_TCP_PORT <= port <= MAX_TCP_PORT
    valid_timeout = 0 < timeout_seconds <= MAX_TCP_TIMEOUT_SECONDS
    if not valid_port or not valid_timeout:
        _fail("TCP reachability parameters are invalid")
    try:
        with socket.create_connection((host, port), timeout=timeout_seconds):
            return
    except OSError as error:
        _fail(f"resolved VM is unreachable on TCP/{port}", cause=error)


def _validated_route_source(
    host: str,
    source_address: str,
    network_text: str,
) -> ipaddress.IPv4Address:
    try:
        host_address = ipaddress.ip_address(host)
        expected_source = ipaddress.ip_address(source_address)
        network = ipaddress.ip_network(network_text, strict=True)
    except ValueError as error:
        _fail("host-only route parameters are invalid", cause=error)
    if not isinstance(host_address, ipaddress.IPv4Address):
        _fail("host-only route host must be IPv4")
    if not isinstance(expected_source, ipaddress.IPv4Address):
        _fail("host-only route source must be IPv4")
    if not isinstance(network, ipaddress.IPv4Network):
        _fail("host-only route network must be IPv4")
    if network.prefixlen != HOST_ONLY_PREFIX_LENGTH:
        _fail("host-only route network must be one IPv4 /24")
    if host_address not in network or expected_source not in network:
        _fail("host-only route parameters do not share the configured IPv4 /24")
    reserved_addresses = {network.network_address, network.broadcast_address}
    if host_address in reserved_addresses or expected_source in reserved_addresses:
        _fail("host-only route cannot use a reserved network address")
    return expected_source


def require_host_only_route(
    host: str,
    port: int,
    source_address: str,
    network_text: str,
) -> None:
    """Require the kernel to select the configured host-only source address."""
    if not MIN_TCP_PORT <= port <= MAX_TCP_PORT:
        _fail("route probe port is invalid")
    expected_source = _validated_route_source(host, source_address, network_text)

    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as route_probe:
            route_probe.connect((host, port))
            selected_source = ipaddress.ip_address(route_probe.getsockname()[0])
    except (OSError, TypeError, ValueError) as error:
        _fail("host-only route could not be resolved", cause=error)
    if selected_source != expected_source:
        _fail("resolved VM route does not use the configured host-only source address")


def _utc_now(value: str | None) -> dt.datetime:
    if value is None:
        return dt.datetime.now(tz=dt.timezone.utc)
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        _fail("comparison time is malformed", cause=error)
    if parsed.tzinfo is None:
        _fail("comparison time must include a UTC offset")
    return parsed.astimezone(dt.timezone.utc)


def _resolver_config(options: argparse.Namespace) -> ResolverConfig:
    return ResolverConfig(
        vmx=ProtectedFilePolicy(
            path=Path(options.vmx),
            expected_uid=options.vmx_owner_uid,
            maximum_bytes=MAX_VMX_BYTES,
            description="development VM configuration",
        ),
        leases=ProtectedFilePolicy(
            path=Path(options.leases),
            expected_uid=options.lease_owner_uid,
            maximum_bytes=MAX_LEASE_BYTES,
            description="VMware DHCP lease file",
        ),
        network=options.network,
        now=_utc_now(options.now),
    )


def main(arguments: list[str] | None = None) -> int:
    """Run the fail-closed resolver command.

    Returns:
        Zero on success and one when resolution fails closed.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vmx", required=True)
    parser.add_argument("--leases", required=True)
    parser.add_argument("--vmx-owner-uid", type=int, default=os.getuid())
    parser.add_argument("--lease-owner-uid", type=int, default=0)
    parser.add_argument("--network", default="172.16.42.0/24")
    parser.add_argument("--require-tcp", type=int)
    parser.add_argument("--require-route-source")
    parser.add_argument("--route-port", type=int, default=22)
    parser.add_argument("--timeout-seconds", type=float, default=3.0)
    parser.add_argument("--now", help=argparse.SUPPRESS)
    options = parser.parse_args(arguments)
    try:
        host = resolve_host(_resolver_config(options))
        if options.require_route_source is not None:
            require_host_only_route(
                host,
                options.route_port,
                options.require_route_source,
                options.network,
            )
        if options.require_tcp is not None:
            require_tcp_reachable(host, options.require_tcp, options.timeout_seconds)
    except ResolutionError as error:
        sys.stderr.write(f"dev-vm-host: {error}\n")
        return 1
    sys.stdout.write(f"{host}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
