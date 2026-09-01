#!@bash@
# shellcheck shell=bash
set -euo pipefail

environment_state="$(@secureFileSystem@ inspect-generation-file @environmentFile@ 600)" || {
  printf 'Control-plane environment is unsafe; private proxy remains stopped.\n' >&2
  exit 0
}
if [ "$environment_state" = missing ]; then
  printf 'Control-plane environment is absent; private proxy remains stopped.\n' >&2
  exit 0
fi
exec @secureFileSystem@ exec-proxy @pkiDir@ @environmentFile@ @caddy@ \
  run --config @proxyConfig@ --adapter caddyfile
