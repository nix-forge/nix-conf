# shellcheck shell=bash
set -euo pipefail
image=/var/lib/actual-volume/actual.luks
mapper=actual-vault

if cryptsetup status "$mapper" >/dev/null 2>&1; then
  exit 0
fi

# A missing or replaced image must fail closed. Initial provisioning is attended.
if [ ! -f "$image" ] || [ -L "$image" ]; then
  echo "Actual vault image is missing or invalid: $image" >&2
  exit 1
fi

# The enrolled TPM2 token unlocks locally. Headless mode forbids a boot prompt.
exec "$SYSTEMD_CRYPTSETUP" attach "$mapper" "$image" none \
  tpm2-device=auto,headless=yes,tries=1
