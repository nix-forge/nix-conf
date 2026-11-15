# shellcheck shell=bash
set -euo pipefail
shopt -s nullglob
patterns=(@patterns@)
for device in /sys/block/*; do
  name="${device##*/}"
  selected=false
  for pattern in "${patterns[@]}"; do
    # Match the explicitly configured device glob.
    # shellcheck disable=SC2053
    if [[ $name == $pattern ]]; then
      selected=true
      break
    fi
  done
  if [[ $selected != true ]]; then continue; fi
  # A disk can disappear while udev events reconcile the initial snapshot.
  if [[ ! -r $device/dev ]]; then continue; fi
  if ! properties=$(udevadm info --query=property --path="$device"); then continue; fi
  profiled=false
  while IFS='=' read -r key value; do
    if [[ $key == IOCOST_SOLUTIONS && -n $value ]]; then profiled=true; fi
  done <<<"$properties"
  if [[ $profiled == true ]]; then continue; fi
  if ! number=$(cat "$device/dev"); then continue; fi
  @enable@ "$number"
done
