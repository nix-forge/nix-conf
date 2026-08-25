#!@bash@
# shellcheck shell=bash
set -euo pipefail

@minidvRuntime@

printf '%s\n' '== MiniDV / FireWire diagnostic report =='
printf 'Generated: %s\n' "$(date --iso-8601=seconds)"
printf 'Kernel: %s\n' "$(uname -r)"

printf '\n%s\n' '-- PCI FireWire controller --'
lspci -nnk | grep -A5 -i -E 'firewire|1394' || printf '%s\n' 'No PCI FireWire controller is currently enumerated.'

printf '\n%s\n' '-- modern kernel modules --'
for module in firewire_ohci firewire_core; do
  printf '%s: ' "$module"
  modinfo -F filename "$module" 2>/dev/null || printf '%s\n' 'not available in this kernel'
done
lsmod | grep -E '^firewire_(ohci|core)' || printf '%s\n' 'Modern FireWire modules are not loaded.'

printf '\n%s\n' '-- FireWire character devices and access --'
shopt -s nullglob
nodes=(/dev/fw*)
if [ "${#nodes[@]}" -eq 0 ]; then
  printf '%s\n' 'No /dev/fw* nodes exist.'
else
  ls -l -- "${nodes[@]}"
  getfacl -p -- "${nodes[@]}" || true
  for node in "${nodes[@]}"; do
    printf '\nudevadm for %s\n' "$node"
    udevadm info --query=all --name="$node" || true
  done
fi

printf '\n%s\n' '-- FireWire bus nodes --'
sysfs=/sys/bus/firewire/devices
if [ ! -d "$sysfs" ]; then
  printf '%s\n' 'No FireWire sysfs bus exists.'
else
  found=0
  for device in "$sysfs"/fw*; do
    [ -e "$device" ] || continue
    found=1
    printf 'node=%s\n' "$(basename "$device")"
    for attribute in is_local guid vendor model units; do
      [ -r "$device/$attribute" ] && printf '  %s=%s\n' "$attribute" "$(cat "$device/$attribute")"
    done
  done
  [ "$found" -eq 1 ] || printf '%s\n' 'No FireWire controller or remote nodes are present.'
fi

printf '\n%s\n' '-- recent FireWire kernel log (last 200 matching lines) --'
# A bus-reset storm can generate thousands of nearly identical entries.  The
# complete boot journal remains available through journalctl, but a bounded
# diagnostic report must finish promptly and retain the most recent evidence.
journalctl -k -b --no-pager | grep -i -E 'firewire|1394|ohci' | tail -n 200 ||
  printf '%s\n' 'No FireWire-related kernel messages in this boot.'

printf '\n%s\n' 'A healthy setup has a PCI controller bound to firewire_ohci, a local sysfs node (is_local=1), a remote Sony node (is_local=0), and accessible /dev/fw* nodes. Do not change device permissions until this report shows the actual attributes.'
