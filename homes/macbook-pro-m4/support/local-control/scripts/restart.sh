#!@bash@
# shellcheck shell=bash
set -euo pipefail

domain="gui/$(id -u)"
for service in database proxy; do
  label="$domain/local.services.local-control-$service"
  if launchctl print "$label" >/dev/null 2>&1; then
    launchctl kickstart -k "$label"
  fi
done
