# shellcheck shell=bash
test -f @image@
if @pkgs_cryptsetup@/bin/cryptsetup status @mapper@ >/dev/null 2>&1; then
  echo "Lock the Actual volume before its cold backup" >&2
  exit 1
fi
