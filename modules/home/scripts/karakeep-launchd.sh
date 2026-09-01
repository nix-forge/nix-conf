#!@bash@
# shellcheck shell=bash
set -euo pipefail
export HOME=@homeDirectory@
docker_socket=@dockerSocket@
export DOCKER_HOST="unix://$docker_socket"
if [ ! -S "$docker_socket" ]; then
  # Karakeep is an explicit always-on local service. Starting its VM here does
  # not make Docker generally start at login when Karakeep remains disabled.
  @colima@ start
fi
for _ in $(@seq@ 1 60); do
  [ -S "$docker_socket" ] && break
  @sleep@ 2
done
@dockerCompose@ up -d
@colimaForward@
trap '@dockerCompose@ down' INT TERM EXIT
while true; do @sleep@ 3600; done
