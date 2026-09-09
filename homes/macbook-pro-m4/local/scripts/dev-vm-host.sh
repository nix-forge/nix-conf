#!@bash@
# shellcheck shell=bash
set -euo pipefail

exec @resolver@ \
  --vmx @vmxFile@ \
  --leases @leaseFile@ \
  --lease-owner-uid 0 \
  --network @hostOnlyNetwork@ \
  "$@"
