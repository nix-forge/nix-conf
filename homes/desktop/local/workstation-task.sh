# shellcheck shell=bash
# Run explicit background work without replacing nix or changing its options.
if [[ $# == 0 || $1 == --help ]]; then
  echo 'Usage: workstation-task [--] COMMAND [ARGUMENT...]'
  echo 'Queue a development command in a bounded background systemd scope.'
  echo 'The queue stays held until all children exit; cancellation stops this task scope.'
  exit 0
fi
if [[ $1 == -- ]]; then shift; fi
if [[ $# == 0 ]]; then
  echo 'workstation-task: missing command' >&2
  exit 2
fi

: "${XDG_RUNTIME_DIR:?workstation-task requires a logged-in systemd user session}"
validate_policy() {
  local settings high='' max='' swap='' pressure=''
  settings=$(systemctl --user show background-workload.slice \
    -p MemoryHigh -p MemoryMax -p MemorySwapMax -p ManagedOOMMemoryPressure)
  while IFS='=' read -r key value; do
    case "$key" in
    MemoryHigh) high=$value ;;
    MemoryMax) max=$value ;;
    MemorySwapMax) swap=$value ;;
    ManagedOOMMemoryPressure) pressure=$value ;;
    esac
  done <<<"$settings"
  if [[ $high != '@memoryHigh@' || $max != '@memoryMax@' ||
    $swap != '@memorySwapMax@' || $pressure != kill ]]; then
    echo 'workstation-task: activate the matching desktop memory policy first' >&2
    return 1
  fi
}
validate_policy

# Nested calls already share the outer scope and lock. Membership is checked
# only after validating the policy, never through an environment bypass flag.
if [[ $(</proc/self/cgroup) == *'/background-workload.slice/'* ]]; then
  exec "$@"
fi

unit="workstation-task-$$-$RANDOM.scope"
locker=''
launcher=''
waiter=''
# Invoked by the EXIT trap, including exits from the signal handlers.
# shellcheck disable=SC2329
cleanup() {
  local status=$?
  trap - EXIT
  trap '' INT TERM HUP
  if [[ -n $waiter ]]; then
    kill "$waiter" 2>/dev/null || true
    wait "$waiter" 2>/dev/null || true
  fi
  if [[ -n $locker ]]; then
    kill "$locker" 2>/dev/null || true
    wait "$locker" 2>/dev/null || true
  fi
  if [[ -n $launcher ]]; then
    # Ask the launcher to exit before stopping the scope. Stop also handles a
    # command that ignores SIGTERM; TimeoutStopSec bounds that cleanup.
    kill "$launcher" 2>/dev/null || true
  fi
  # Stop all remaining descendants before releasing the queue lock. Only the
  # newly created scope belongs to this invocation; existing work is untouched.
  systemctl --user stop "$unit" >/dev/null 2>&1 || true
  if [[ -n $launcher ]]; then
    wait "$launcher" 2>/dev/null || true
    systemctl --user stop "$unit" >/dev/null 2>&1 || true
  fi
  exit "$status"
}
trap 'cleanup' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# Only this supervisor owns the lock. Waiting asynchronously permits signal
# handling while queued. The workload never inherits the lock descriptor.
exec 9>"$XDG_RUNTIME_DIR/workstation-background.lock"
flock --exclusive 9 &
locker=$!
wait "$locker"
locker=''
validate_policy

# --scope preserves environment, cwd and terminal. Explicit stdin redirection
# prevents Bash from substituting /dev/null for the asynchronous launcher.
(
  if [[ $(</proc/self/oom_score_adj) -lt 500 ]]; then
    printf '500\n' >/proc/self/oom_score_adj
  fi
  exec systemd-run --user --scope --quiet --collect --expand-environment=no --unit="$unit" \
    --slice=background-workload.slice \
    --property=OOMPolicy=kill --property=TimeoutStopSec=5s -- "$@"
) 9>&- <&0 &
launcher=$!
status=0
wait "$launcher" || status=$?
launcher=''
# A command may intentionally leave background children. They stay in this
# scope and retain the queue until the entire scope becomes empty.
cgroup=$(systemctl --user show "$unit" -p ControlGroup --value)
if [[ -n $cgroup ]]; then
  @waitForCgroup@ "/sys/fs/cgroup$cgroup/cgroup.events" 9>&- &
  waiter=$!
  wait_status=0
  wait "$waiter" || wait_status=$?
  waiter=''
  # A failed observer must stop the scope through cleanup before the queue is
  # released. Preserve the command's failure if it already returned one.
  if ((status == 0)); then status=$wait_status; fi
fi
exit "$status"
