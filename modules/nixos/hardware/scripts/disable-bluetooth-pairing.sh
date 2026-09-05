#!@bash@
# shellcheck shell=bash
set -euo pipefail
shopt -s nullglob

for adapter in /sys/class/bluetooth/hci*; do
  name="${adapter##*/}"
  [[ $name =~ ^hci[0-9]+$ ]] || continue
  @busctl@ set-property org.bluez "/org/bluez/$name" org.bluez.Adapter1 Pairable b false
done
