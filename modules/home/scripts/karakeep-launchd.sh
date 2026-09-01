#!@bash@
# shellcheck shell=bash
set -euo pipefail
export HOME=@homeDirectory@
docker_socket=@dockerSocket@
export DOCKER_HOST="unix://$docker_socket"
for _ in $(@seq@ 1 60); do
  [ -S "$docker_socket" ] && break
  @sleep@ 2
done
@dockerCompose@ up -d
@colimaForward@
trap '@dockerCompose@ down' INT TERM EXIT
while true; do @sleep@ 3600; done
