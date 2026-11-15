# shellcheck shell=bash
set -euo pipefail
# Filled by forward_environment from the packaged prelude.
environment=()

if [[ -z ${CODEX_THREAD_ID:-} ]]; then
  echo 'codex-task requires the owning CODEX_THREAD_ID.' >&2
  exit 2
fi
owner=$(printf '%s' "$CODEX_THREAD_ID" | sha256sum)
prefix="codex-task-${owner:0:32}"
action=${1:-}
if [[ $# -gt 0 ]]; then shift; fi
case "$action" in
run)
  if [[ $# -eq 0 ]]; then
    echo 'Usage: codex-task run COMMAND [ARGS...]' >&2
    exit 2
  fi
  forward_environment
  unit="$prefix-$(cat /proc/sys/kernel/random/uuid).service"
  client=''
  # Cancellation owns this invocation only, even when the foreground client
  # is interrupted before the task reaches an explicit finish operation.
  # shellcheck disable=SC2329
  cleanup() {
    local status=$?
    trap - EXIT
    trap '' INT TERM HUP
    # The client may fail independently while its service is still running.
    systemctl --user stop -- "$unit" >/dev/null 2>&1 || true
    if [[ -n $client ]]; then
      kill "$client" 2>/dev/null || true
      wait "$client" 2>/dev/null || true
    fi
    # Cover a launch request accepted between the first stop and client exit.
    systemctl --user stop -- "$unit" >/dev/null 2>&1 || true
    exit "$status"
  }
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  # Services end with their main command; systemd cleans surviving children.
  systemd-run --user --wait --pipe --collect --quiet \
    --service-type=exec --expand-environment=no --slice=app-codex.slice \
    --unit="$unit" \
    --working-directory="$PWD" \
    --property=KillMode=control-group --property=TimeoutStopSec=15s \
    --property="UMask=$(umask)" \
    --property=CPUWeight=50 --property=IOWeight=50 \
    "${environment[@]}" -- "$@" <&0 &
  client=$!
  status=0
  wait "$client" || status=$?
  client=''
  exit "$status"
  ;;
finish | list)
  listing=$(systemctl --user list-units --type=service --all \
    --plain --no-legend "$prefix-*.service")
  units=()
  while read -r unit _; do
    if [[ -n $unit ]]; then units+=("$unit"); fi
  done <<<"$listing"
  if [[ ${#units[@]} -gt 0 ]]; then
    if [[ $action == finish ]]; then
      systemctl --user stop -- "${units[@]}"
    else
      printf '%s\n' "${units[@]}"
    fi
  fi
  ;;
*)
  echo 'Usage: codex-task {run COMMAND [ARGS...]|list|finish}' >&2
  exit 2
  ;;
esac
