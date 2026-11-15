#!/usr/bin/env bash
# Native desktop integration test. OOM allocations are confined to 96 MiB.
# Dollar expressions below deliberately test literal argument forwarding.
# shellcheck disable=SC2016
set -euo pipefail

policy=${1:?usage: check-workstation-task.sh POLICY_DIRECTORY}
installed_runner="$policy/runner/bin/workstation-task"
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
unit="workstation-policy-test-$$.scope"
cleanup() {
  for scope_file in "$work/first-scope" "$work/second-scope"; do
    if [[ -f $scope_file ]]; then
      task_scope=$(<"$scope_file")
      systemctl --user stop "${task_scope##*/}" >/dev/null 2>&1 || true
    fi
  done
  systemctl --user stop "$unit" >/dev/null 2>&1 || true
  systemctl --user reset-failed "$unit" >/dev/null 2>&1 || true
  rm -rf -- "$work"
}
trap cleanup EXIT

# Tiny scope payloads need controlled admission, not a desktop-sized VM.
# The real controller, locks, limits and drain observer remain in the runner.
printf 'MemAvailable: 33554432 kB\n' >"$work/meminfo"
runner="$work/runner"
python3 "$test_directory/workstation_runner_fixture.py" \
  "$installed_runner" "$runner" "$work/meminfo" --adapt-storage

# Stdio, arguments, environment, working directory and exit status survive.
(
  cd "$work"
  export WORKSTATION_TEST_VALUE='value with spaces'
  "$runner" bash "$test_directory/workstation-task-child.sh" environment "$work" 'literal * argument'
)
grep -q '/background-workload.slice/' "$work/cgroup"
[[ $(printf 'stdin survives\n' | "$runner" cat) == 'stdin survives' ]]
# systemd-run otherwise expands dollar expressions even when the caller quoted
# them. Nix expressions and shell snippets must reach the command unchanged.
[[ $("$runner" printf '%s' '${WORKSTATION_UNSET_TEST}') == '${WORKSTATION_UNSET_TEST}' ]]
[[ $("$runner" printf '%s' '$HOME $$ ${HOME}') == '$HOME $$ ${HOME}' ]]
if "$runner" bash "$test_directory/workstation-task-child.sh" exit 23; then
  echo 'Failed to propagate command failure' >&2
  exit 1
else
  [[ $? == 23 ]]
fi

# Reentrant calls share the outer scope instead of deadlocking on its lock.
timeout 10 "$runner" bash "$test_directory/workstation-task-child.sh" reentrant "$runner" "$work"
cmp "$work/outer" "$work/inner"

# Process readiness uses FIFOs and pidfds; the OOM result uses D-Bus signals.
python3 "$test_directory/check_workstation_processes.py" "$runner" "$work"
python3 "$test_directory/check_workstation_oom.py" "$work" "$unit"

# Backup conflicts twice at the same path. Both original contents must remain
# available, including a copied store-like symlink target after it disappears.
mkdir "$work/state"
printf first >"$work/target"
ln -s "$work/target" "$work/config"
XDG_STATE_HOME="$work/state" "$policy/backup-command" "$work/config"
rm "$work/target"
printf second >"$work/config"
XDG_STATE_HOME="$work/state" "$policy/backup-command" "$work/config"
[[ ! -e "$work/config" ]]
find "$work/state" -name content -type f -exec cat {} \; | grep -q first
find "$work/state" -name content -type f -exec cat {} \; | grep -q second
[[ $(find "$work/state/home-manager/conflicts" -mindepth 1 -maxdepth 1 -type d | wc -l) == 2 ]]

# A stale store link has no content to copy, but must still be preserved and
# removed from the managed path so activation can replace it.
ln -s "$work/missing-store-target" "$work/config"
XDG_STATE_HOME="$work/state" "$policy/backup-command" "$work/config"
[[ ! -e "$work/config" && ! -L "$work/config" ]]
marker=$(find "$work/state/home-manager/conflicts" -name content-unavailable)
[[ -n $marker && -f $marker ]]
[[ $(readlink -- "${marker%/*}/original") == "$work/missing-store-target" ]]
[[ $(stat -c %a "${marker%/*}") == 700 ]]

echo 'PASS: workload isolation, arguments, exit status, nesting, queueing, cancellation, descendants, launch failure, confined OOM, and conflict preservation'

bash "$test_directory/check-workstation-feedback.sh" "$runner"
