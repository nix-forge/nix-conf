#!@bash@
# shellcheck shell=bash
set -euo pipefail

if [ "$#" -ne 1 ] || [ "$1" != @sshPort@ ]; then
  printf 'dev-vm-proxy only permits the configured SSH port.\n' >&2
  exit 1
fi

# Resolve the lease only when the kernel selects the VMware host-only source.
# An unexpired DHCP lease can outlive its interface; without this guard macOS
# sends the private destination through its default route. Binding netcat to
# the same source address keeps the transport fail-closed if the route changes
# between resolution and connect. Do not pass `-w`: it also times out idle
# reads in a healthy SSH tunnel.
vm_host="$(@devVmHost@ \
  --require-route-source @hostOnlySourceAddress@ \
  --route-port "$1")"
exec /usr/bin/nc -4 -s @hostOnlySourceAddress@ "$vm_host" "$1"
