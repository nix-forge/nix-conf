#!/usr/bin/env bash
# Run as root on a native systemd host with the generated launcher and guest.
set -euo pipefail

if [[ $EUID != 0 || $# -lt 2 ]]; then
  echo 'Usage: check-libvirt-sleep-inhibitor.sh EXPECTED_GUEST COMMAND [ARGS...]' >&2
  exit 64
fi

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
guest=$1
shift
unit="libvirt-inhibitor-check-$$.service"
cleanup() {
  systemctl stop "$unit" >/dev/null 2>&1 || true
}
trap cleanup EXIT

check_lock() {
  systemd-inhibit --list --json=short | python3 "$test_directory/check_libvirt_sleep_locks.py" "$guest" "$1"
}

check_lock 0
systemd-run --collect --unit="$unit" \
  --property=Type=notify --property=NotifyAccess=all \
  --property=TimeoutStartSec=5 --property=NoNewPrivileges=yes \
  --property=ProtectSystem=strict --property=ProtectHome=yes \
  --property=PrivateTmp=yes --property=PrivateDevices=yes \
  --property=RestrictAddressFamilies=AF_UNIX -- "$@"
systemctl is-active --quiet "$unit"
check_lock 1
systemctl stop "$unit"
check_lock 0
echo 'PASS: readiness follows acquisition, and shutdown releases the sleep inhibitor.'
