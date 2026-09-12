#!@bash@
# shellcheck shell=bash
set -euo pipefail
shopt -s nullglob

adapters=()
for adapter in /sys/class/bluetooth/hci*; do
  name="${adapter##*/}"
  [[ $name =~ ^hci[0-9]+$ ]] || continue
  adapters+=("$name")
done
exec @python@ @policyScript@ "$@" "${adapters[@]}"
