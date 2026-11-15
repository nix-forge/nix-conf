# shellcheck shell=bash
device=/sys/bus/pci/devices/0000:11:00.6
if [[ -d $device &&
  "$(<"$device/vendor")" == 0x1022 &&
  "$(<"$device/device")" == 0x15e3 &&
  "$(<"$device/subsystem_vendor")" == 0x1462 &&
  "$(<"$device/subsystem_device")" == 0xed75 ]]; then
  printf '%s\n' none >"$device/driver_override"
fi
