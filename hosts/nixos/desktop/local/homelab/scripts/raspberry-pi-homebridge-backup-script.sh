# shellcheck shell=bash
set -euo pipefail
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup="${STATE_DIRECTORY}/${stamp}.tar.zst.age"
partial="${backup}.partial"
trap 'rm -f "$partial"' EXIT

ssh -T -S none -o BatchMode=yes -o IdentitiesOnly=yes \
  -o StrictHostKeyChecking=yes -i @userHome@/.ssh/id_ed25519 \
  ianmh@@network_raspberryPiServerAddress@ \
  'sudo -n tar --exclude=homebridge/backups --exclude=homebridge/homebridge.log -C /var/lib -cf - homebridge scrypted' |
  zstd -q -1 -c |
  age -R @raspberry_pi_keys_desktop_pub@ -o "$partial"

mv "$partial" "$backup"
trap - EXIT
