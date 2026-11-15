# shellcheck shell=bash
# Run explicit background work without replacing nix or changing its options.
set -euo pipefail
bounded_min_gib=@boundedMemoryMinGiB@
bounded_max_gib=@boundedMemoryMaxGiB@
bounded_reserve='@boundedReserve@'
bounded_high_percent='@boundedHighPercent@'
feedback_memory_max='@feedbackMemoryMax@'
feedback_reserve='@feedbackReserve@'
aggregate_memory_max='@memoryMax@'
bulk_available='@bulkMemoryAvailable@'
admission_timeout=@admissionSeconds@
memory_min_mib=''
memory_max_mib=''
elastic=0
disk_requests=()
storage_recovery=0
host_preserving=0

if [[ $# == 0 || $1 == --help ]]; then
  echo 'Usage: workstation-task [--feedback | --bounded-memory GiB] [--] COMMAND [ARGUMENT...]'
  echo 'Use --feedback only for tiny diagnostic checks (one CPU, @feedbackRuntimeSeconds@ seconds).'
  echo "Use --bounded-memory $bounded_min_gib..$bounded_max_gib for finite host work with a hard RAM cap, no swap,"
  echo 'a @boundedRuntimeSeconds@ second deadline and configured host reserve. Local Nix daemon access is blocked;'
  echo 'Nix evaluation is allowed, but daemon builds use the ordinary bulk mode.'
  echo 'Use --host-preserving with a bounded budget for filesystem-identity tests.'
  echo 'Use --status to inspect private scheduler lifecycle records.'
  echo 'Use --memory-min-mib L --memory-max-mib U for an elastic bounded allocation.'
  echo 'Use --admission-timeout SECONDS to bound lock and memory waits.'
  echo 'Use --storage-recovery only for explicit diagnostics or space-releasing maintenance.'
  echo 'Use --disk-mib /ABSOLUTE/PATH=MiB for each additional peak disk allocation.'
  echo 'Queue a development command in a bounded background systemd scope.'
  echo 'The queue stays held until all children exit; cancellation stops this task scope.'
  exit 0
fi
if [[ $1 == --status && $# == 1 ]]; then
  exec @taskEvents@ status
fi
lane=bulk
bounded_memory=0
while (($#)); do
  case "$1" in
  --host-preserving)
    host_preserving=1
    shift
    ;;
  --feedback)
    lane=feedback
    shift
    ;;
  --storage-recovery)
    storage_recovery=1
    shift
    ;;
  --disk-mib)
    if [[ $# -lt 2 ]]; then
      echo 'workstation-task: missing disk request' >&2
      exit 2
    fi
    disk_requests+=(--disk-mib "$2")
    shift 2
    ;;
  --bounded-memory)
    requested_memory=${2:-}
    if [[ ! $requested_memory =~ ^[1-9][0-9]*$ || ${#requested_memory} -gt ${#bounded_max_gib} ]] ||
      ((requested_memory < bounded_min_gib || requested_memory > bounded_max_gib)); then
      echo 'workstation-task: invalid bounded GiB budget' >&2
      exit 2
    fi
    bounded_memory=$((requested_memory * 1024 * 1024 * 1024))
    shift 2
    ;;
  --memory-min-mib | --memory-max-mib | --admission-timeout)
    option=$1
    value=${2:-}
    if [[ ! $value =~ ^[1-9][0-9]*$ || ${#value} -gt 7 ]]; then
      echo 'workstation-task: memory and deadline values must be positive bounded integers' >&2
      exit 2
    fi
    case "$option" in
    --memory-min-mib) memory_min_mib=$value ;;
    --memory-max-mib) memory_max_mib=$value ;;
    --admission-timeout) admission_timeout=$value ;;
    esac
    shift 2
    ;;
  *) break ;;
  esac
done
if [[ -n $memory_min_mib || -n $memory_max_mib ]]; then
  if [[ -z $memory_min_mib || -z $memory_max_mib ]] ||
    ((bounded_memory)); then
    echo 'workstation-task: supply a min/max pair without a fixed request' >&2
    exit 2
  fi
  if [[ $lane != bulk ]] || ((memory_min_mib < bounded_min_gib * 1024 || \
  memory_max_mib > bounded_max_gib * 1024 || memory_min_mib > memory_max_mib || \
  memory_min_mib % 1024 || memory_max_mib % 1024)); then
    echo 'workstation-task: elastic memory must fit whole-GiB bounded limits' >&2
    exit 2
  fi
  bounded_memory=$((memory_max_mib * 1024 * 1024))
  elastic=1
fi
if [[ $lane == feedback ]] && ((bounded_memory)); then
  echo 'workstation-task: feedback and bounded modes conflict' >&2
  exit 2
fi
if ((host_preserving)) && { [[ $lane == feedback ]] || ((bounded_memory == 0)); }; then
  echo 'workstation-task: host identity requires an explicit bounded allocation' >&2
  exit 2
fi
admission_deadline=$((SECONDS + admission_timeout))
if [[ ${1:-} == -- ]]; then shift; fi
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
  if [[ $high != '@memoryHigh@' || $max != "$aggregate_memory_max" ||
    $swap != '@memorySwapMax@' || $pressure != kill ]]; then
    echo 'workstation-task: activate the matching desktop memory policy first' >&2
    return 1
  fi
}
validate_policy

# Nested calls already share the outer scope and lock. Membership is checked
# only after validating the policy, never through an environment bypass flag.
if [[ $(</proc/self/cgroup) == *'/background-workload.slice/'* ]]; then
  if ((bounded_memory)); then
    echo 'workstation-task: select a bounded budget on the outermost invocation' >&2
    exit 2
  fi
  # Explicit nested declarations still need checking against current space.
  # The outer invocation owns the shared allocation; do not take its lock again.
  if ((${#disk_requests[@]})); then @diskAdmission@ admit "${disk_requests[@]}" >/dev/null; fi
  exec "$@"
fi

unit="workstation-task-$lane-$$-$RANDOM.scope"
@taskEvents@ queued "$unit" "$lane"
locker=''
launcher=''
waiter=''
scope_result=''
controller=''
growth=''
# Invoked by the EXIT trap, including exits from the signal handlers.
# shellcheck disable=SC2329
cleanup() {
  local status=$?
  trap - EXIT
  trap '' INT TERM HUP
  for owned in "$controller" "$growth"; do
    if [[ -n $owned ]]; then
      kill "$owned" 2>/dev/null || true
      wait "$owned" 2>/dev/null || true
    fi
  done
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
  if [[ $lane == feedback ]] || ((bounded_memory)); then
    systemctl --user reset-failed "$unit" >/dev/null 2>&1 || true
  fi
  @taskEvents@ completed "$unit" "$lane" "$status" "$scope_result" || true
  exit "$status"
}
trap 'cleanup' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# Open the existing reservations in their established mixed-version order.
# The controller takes them nonblocking only after capacity is healthy, and
# rechecks capacity under all locks. A waiting job must not own execution.
execution_locks=()
if [[ $lane == feedback ]]; then
  exec 8>@bulkLock@
  execution_locks+=(--lock-fd 8)
fi
lock="$XDG_RUNTIME_DIR/workstation-background.lock"
if [[ $lane == feedback ]]; then lock="$XDG_RUNTIME_DIR/workstation-feedback.lock"; fi
exec 9>"$lock"
execution_locks+=(--lock-fd 9)
if [[ $lane == bulk ]]; then
  exec 8>@bulkLock@
  execution_locks+=(--lock-fd 8)
fi
if ((bounded_memory)); then
  exec 7>"$XDG_RUNTIME_DIR/workstation-feedback.lock"
  execution_locks+=(--lock-fd 7)
fi
validate_policy
allocation_root="$XDG_RUNTIME_DIR/workstation-task-allocations"
mkdir -p "$allocation_root"
chmod 700 "$allocation_root"
allocation="$allocation_root/$unit.json"
if [[ ${WORKSTATION_JOB_ID:-} =~ ^[0-9a-f]{32}$ &&
  ${WORKSTATION_JOB_DIRECTORY:-} == */jobs/"$WORKSTATION_JOB_ID" &&
  -d ${WORKSTATION_JOB_DIRECTORY:-/nonexistent} ]]; then
  allocation="$WORKSTATION_JOB_DIRECTORY/memory-allocation.json"
fi
disk_mode=()
if [[ $lane == feedback ]] || ((storage_recovery)); then disk_mode=(--recovery); fi
minimum=1
maximum=1
reserve=$((bulk_available / 1024 / 1024 - 1))
if ((reserve < 0)); then reserve=0; fi
capacity_group=()
if ((bounded_memory)); then
  minimum=$((bounded_memory / 1024 / 1024))
  maximum=$minimum
  if ((elastic)); then
    minimum=$memory_min_mib
    maximum=$memory_max_mib
  fi
  reserve=$((bounded_reserve / 1024 / 1024))
elif [[ $lane == feedback ]]; then
  minimum=$((feedback_memory_max / 1024 / 1024))
  maximum=$minimum
  reserve=$((feedback_reserve / 1024 / 1024))
fi
if ((bounded_memory)) || [[ $lane == feedback ]]; then
  group=$(systemctl --user show background-workload.slice -p ControlGroup --value)
  capacity_group=(--group "/sys/fs/cgroup$group")
fi
remaining=$((admission_deadline - SECONDS))
if ((remaining <= 0)); then exit 124; fi
@memoryController@ admit --receipt "$allocation" --minimum "$minimum" --maximum "$maximum" \
  --reserve "$reserve" --quantum "$((elastic ? 1024 : 1))" --timeout "$remaining" \
  --healthy-seconds @admissionHealthySeconds@ --pressure-limit @admissionPressureLimit@ \
  --meminfo /proc/meminfo --root /sys/fs/cgroup "${capacity_group[@]}" "${execution_locks[@]}" >"$allocation.grant" &
controller=$!
status=0
wait "$controller" || status=$?
controller=''
if ((status)); then exit "$status"; fi
if ((bounded_memory)); then bounded_memory=$(($(<"$allocation.grant") * 1024 * 1024)); fi
validate_policy

# Recheck only after taking the shared execution lock. Durable submissions may
# retain WORKSTATION_DISK_REQUESTS through their existing explicit --env option.
@diskAdmission@ admit "${disk_requests[@]}" "${disk_mode[@]}" \
  --receipt "${allocation%.json}.disk.json" >/dev/null

if [[ $lane == bulk ]] && ((bounded_memory == 0)); then
  available=$(awk '$1 == "MemAvailable:" { printf "%.0f\n", $2 * 1024 }' /proc/meminfo) || available=unknown
  @taskEvents@ capacityChecked "$unit" "$lane" "${available:-unknown}" @bulkMemoryAvailable@ daemon
fi
properties=()
queue_owner=()
if [[ -n ${WORKSTATION_QUEUE_OWNER_UNIT:-} ]]; then
  if [[ ! $WORKSTATION_QUEUE_OWNER_UNIT =~ ^workstation-jobs(-audit-[0-9a-f]{32})?\.service$ ]]; then
    echo 'workstation-task: unsupported queue owner unit' >&2
    exit 64
  fi
  queue_owner=(--property="BindsTo=$WORKSTATION_QUEUE_OWNER_UNIT" --property="After=$WORKSTATION_QUEUE_OWNER_UNIT")
fi
collection=(--collect)
if ((bounded_memory)); then
  available=$(awk '$1 == "MemAvailable:" { printf "%.0f\n", $2 * 1024 }' /proc/meminfo) || available=unknown
  group=$(systemctl --user show background-workload.slice -p ControlGroup --value)
  current=$(<"/sys/fs/cgroup$group/memory.current") || current=unknown
  @taskEvents@ capacityChecked "$unit" "$lane" "${available:-unknown}" "$((bounded_memory + bounded_reserve))" bounded "${current:-unknown}" "$bounded_memory" "$aggregate_memory_max"
  collection=()
  properties=(
    --property=MemoryHigh=$((bounded_memory * bounded_high_percent / 100))
    --property=MemoryMax="$bounded_memory"
    --property=MemorySwapMax=0
    --property=RuntimeMaxSec=@boundedRuntimeSeconds@s
  )
fi
if [[ $lane == feedback ]]; then
  # Admission is a snapshot, not a reservation; aggregate hard limits remain authoritative.
  available=$(awk '$1 == "MemAvailable:" { printf "%.0f\n", $2 * 1024 }' /proc/meminfo) || available=unknown
  group=$(systemctl --user show background-workload.slice -p ControlGroup --value)
  current=$(<"/sys/fs/cgroup$group/memory.current") || current=unknown
  @taskEvents@ capacityChecked "$unit" "$lane" "${available:-unknown}" "$((feedback_memory_max + feedback_reserve))" feedback "${current:-unknown}" "$feedback_memory_max" "$aggregate_memory_max"
  # Keep failed units until their result is observed after descendants drain.
  collection=()
  properties=(
    --property=MemoryHigh=@feedbackMemoryHigh@
    --property=MemoryMax="$feedback_memory_max"
    --property=MemorySwapMax=@feedbackSwapMax@
    --property=CPUQuota=100%
    --property=TasksMax=256
    --property=RuntimeMaxSec=@feedbackRuntimeSeconds@s
  )
fi

if ((host_preserving)); then
  # The fixed privileged helper retains this scope and drops to the caller
  # before decoding the environment. The shared daemon stays inaccessible.
  set -- @hostCheckClient@ "$@"
elif [[ $lane == feedback ]] || ((bounded_memory)); then
  # Both confined profiles must exclude the separately accounted shared daemon.
  # Namespace setup fails closed; ordinary daemon builds retain bulk admission.
  set -- @bubblewrap@ --die-with-parent --bind / / --dev-bind /dev /dev \
    --ro-bind /nix/store /nix/store --ro-bind /nix/var/nix /nix/var/nix \
    --tmpfs /nix/var/nix/daemon-socket -- "$@"
fi

if ((SECONDS >= admission_deadline)); then exit 124; fi
@taskEvents@ admitted "$unit" "$lane"
# --scope preserves environment, cwd and terminal. Explicit stdin redirection
# prevents Bash from substituting /dev/null for the asynchronous launcher.
(
  if [[ $(</proc/self/oom_score_adj) -lt 500 ]]; then
    printf '500\n' >/proc/self/oom_score_adj
  fi
  exec systemd-run --user --scope --quiet "${collection[@]}" --expand-environment=no --unit="$unit" \
    --slice=background-workload.slice \
    --property=OOMPolicy=kill --property=TimeoutStopSec=5s "${queue_owner[@]}" "${properties[@]}" -- "$@"
) 9>&- 8>&- 7>&- <&0 &
launcher=$!
if ((elastic && bounded_memory < memory_max_mib * 1024 * 1024)); then
  @memoryController@ grow --receipt "$allocation" --reserve "$reserve" --quantum 1024 \
    --step @growthStepMiB@ --growth-seconds @growthHealthySeconds@ \
    --pressure-limit @admissionPressureLimit@ --high-percent "$bounded_high_percent" \
    --unit "$unit" &
  growth=$!
fi
status=0
wait "$launcher" || status=$?
launcher=''
@taskEvents@ commandFinished "$unit" "$lane" "$status"
# A command may intentionally leave background children. They stay in this
# scope and retain the queue until the entire scope becomes empty.
cgroup=$(systemctl --user show "$unit" -p ControlGroup --value)
if [[ -n $cgroup ]]; then
  @waitForCgroup@ "/sys/fs/cgroup$cgroup/cgroup.events" 9>&- 8>&- 7>&- &
  waiter=$!
  wait_status=0
  wait "$waiter" || wait_status=$?
  waiter=''
  # A failed observer must stop the scope through cleanup before the queue is
  # released. Preserve the command's failure if it already returned one.
  if ((status == 0)); then status=$wait_status; fi
fi
if [[ $lane == feedback ]] || ((bounded_memory)); then
  # A successful foreground may have left a child that later timed out or OOMed.
  scope_result=$(systemctl --user show "$unit" -p Result --value 2>/dev/null) || scope_result=unavailable
  if [[ $scope_result != success ]] && ((status == 0)); then status=1; fi
fi
exit "$status"
