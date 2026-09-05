#!@bash@
# shellcheck shell=bash
set -euo pipefail

exec @python@ @resolver@ \
  --vmx @vmxFile@ \
  --leases @leaseFile@ \
  --lease-owner-uid 0 \
  --network @hostOnlyNetwork@ \
  "$@"
