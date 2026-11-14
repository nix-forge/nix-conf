# shellcheck shell=bash
if findmnt -rnC -t btrfs --mountpoint @homelabMountPoint@ >/dev/null; then
  btrfs scrub start -B -d -r @homelabMountPoint@
fi
