# shellcheck shell=bash
set -euo pipefail
# systemd-inhibit clears notification state in its child. Preserve only
# this service's socket so readiness still follows acquisition of the lock.
exec @getExe_pkgs_systemd_systemd_inhibit@ \
  --what=sleep --who="libvirt-guest-$1" \
  --why=managed-guest-is-running --mode=block \
  @getExe_pkgs_coreutils_env@ "NOTIFY_SOCKET=${NOTIFY_SOCKET:?}" \
  @sleepInhibitorReady@
