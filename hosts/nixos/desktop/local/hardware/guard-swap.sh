# shellcheck shell=bash
# This guard runs before NixOS opens and formats the encrypted mapping.
set -euo pipefail
swap_device=$(readlink -e -- "$DEVICE")
if [[ ! -b $swap_device ]]; then
  echo 'Encrypted swap requires the existing dedicated block partition' >&2
  exit 1
fi
if [[ $(blockdev --getsize64 "$swap_device") != 8589934592 ||
$(blkid -p -s PART_ENTRY_TYPE -o value "$swap_device") != 0657fd6d-a4ab-43c4-84e5-0933c84b4f4f ]]; then
  echo 'Refusing encrypted swap setup: partition size or GPT type changed' >&2
  exit 1
fi

active_swaps=$(swapon --show=NAME --noheadings --raw)
while IFS= read -r active_swap; do
  if [[ -n $active_swap && $(readlink -e -- "$active_swap") == "$swap_device" ]]; then
    echo 'Plaintext swap is still active. Boot the new generation to enable encrypted swap.' >&2
    exit 1
  fi
done <<<"$active_swaps"

mountpoints=$(lsblk --nodeps --noheadings --output MOUNTPOINTS "$swap_device")
# Probe the disk directly: udev's lsblk metadata may still be incomplete at boot.
# GPT metadata makes this probe succeed even when no filesystem is present.
# Require success so read failures and ambiguous signatures cannot pass the guard.
signature=$(blkid -p -s TYPE -o value "$swap_device")
shopt -s nullglob
holders=(/sys/class/block/"${swap_device##*/}"/holders/*)
if [[ -n $mountpoints || ${#holders[@]} != 0 ||
  -n $signature && $signature != swap ]]; then
  echo 'Refusing encrypted swap setup: device is mounted, held, or has another filesystem' >&2
  exit 1
fi
