#!@bash@
# shellcheck shell=bash
set -euo pipefail

if [ "$#" -ne 1 ] || [ "$1" != @sshPort@ ]; then
  printf 'dev-vm-proxy only permits the configured SSH port.\n' >&2
  exit 1
fi

# Keep address resolution and transport reachability separate. Python's socket
# probe can report a spurious host-unreachable result on Darwin after a VMware
# adapter reset even when the system TCP stack can connect. The Darwin system
# netcat performs the real reachability check and becomes the SSH byte stream,
# so there is no check/use gap here. Do not pass `-w`: it also times out idle
# reads in a healthy SSH tunnel.
exec /usr/bin/nc "$(@devVmHost@)" "$1"
