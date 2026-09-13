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
keeper=''
# shellcheck disable=SC2329
cleanup() {
  local status=$?
  trap - EXIT
  trap '' INT TERM HUP
  if [[ -n $keeper ]]; then
    kill "$keeper" 2>/dev/null || true
    wait "$keeper" 2>/dev/null || true
  fi
  @dockerCompose@ down || true
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
@colimaForward@
# Bash defers traps while a foreground external command runs. Its wait builtin
# is interruptible, so launchd can stop this service promptly even while idle.
@sleep@ infinity &
keeper=$!
wait "$keeper"
