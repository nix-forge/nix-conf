# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
if rg --line-number \
  --glob '!**/modules/home/dev/containers.nix' \
  '(oci-containers[.]containers[.][^[:space:]]+[[:space:]]*=|docker-compose|docker[[:space:]]+(compose|run)|podman[[:space:]]+(compose|run)|\bimage[[:space:]]*=[[:space:]]*"[^"[:space:]]+@sha256:)' \
  @runtimeConfiguration@; then
  echo 'Application and host modules must use native packages and service modules, not container images or orchestration.' >&2
  exit 1
fi
touch "$out"
