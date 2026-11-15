# shellcheck shell=bash
set -euo pipefail
device="${1-}"
if [[ ! $device =~ ^[0-9]+:[0-9]+$ ]]; then
  echo 'Expected a whole-disk major:minor device number' >&2
  exit 2
fi
root=@cgroupRoot@
if [[ ! -w $root/io.cost.model || ! -w $root/io.cost.qos ]]; then
  echo 'The kernel I/O cost controller is unavailable or not writable' >&2
  exit 1
fi
# A measured operator policy takes precedence over adaptive defaults.
for policy in "$root/io.cost.model" "$root/io.cost.qos"; do
  while read -r candidate settings; do
    if [[ $candidate == "$device" && " $settings " == *' ctrl=user '* ]]; then
      exit 0
    fi
  done <"$policy"
done
printf '%s ctrl=auto\n' "$device" >"$root/io.cost.model"
printf '%s enable=1 ctrl=auto\n' "$device" >"$root/io.cost.qos"
