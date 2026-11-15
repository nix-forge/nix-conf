# shellcheck shell=bash
set -euo pipefail
umask 077
mapper=actual-vault
mount=/srv/actual
if [ "$(id -u)" -ne 0 ]; then
  echo 'Run as root with sudo.' >&2
  exit 1
fi
case "${1:-}" in
unlock)
  systemctl reset-failed actual-vault-open.service srv-actual.mount actual.service
  systemctl start actual.service actual.timer
  ;;
lock)
  systemctl stop actual.timer actual.service actual-vault-ready.service
  if mountpoint -q "$mount"; then
    systemctl stop srv-actual.mount
  fi
  if cryptsetup status "$mapper" >/dev/null 2>&1; then
    cryptsetup close "$mapper"
  fi
  systemctl stop actual-vault-open.service
  ;;
status)
  cryptsetup status "$mapper" || true
  findmnt "$mount" || true
  systemctl --no-pager status actual.service || true
  ;;
*)
  echo 'Usage: actual-vault {unlock|lock|status}' >&2
  exit 2
  ;;
esac
