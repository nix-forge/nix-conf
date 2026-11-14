#!/usr/bin/env bash
# Native scope probes use test-only lock names; production jobs are never cancelled.
set -euo pipefail
runner=${1:?usage: check_workstation_feedback.sh RUNNER}
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

# Use the actual memory controller with a synthetic snapshot for tiny payloads.
# Keep private lock names and real scope/cgroup/daemon isolation behavior.
grep -Fq 'workstation-background.lock' "$runner"
grep -Fq 'workstation-feedback.lock' "$runner"
grep -Fq 'RuntimeMaxSec=120s' "$runner"
printf 'MemAvailable: 33554432 kB\n' >"$work/meminfo"
python3 "$test_directory/workstation_runner_fixture.py" \
  "$runner" "$work/private-source" "$work/meminfo"
sed -e "s/workstation-background.lock/workstation-test-bulk-$$.lock/g" \
  -e "s/workstation-feedback.lock/workstation-test-feedback-$$.lock/g" \
  -e "s|/run/workstation-workloads/bulk.lock|$work/shared-bulk.lock|g" \
  "$work/private-source" >"$work/private-queues"
chmod +x "$work/private-queues"
# Shorten only the fixture deadline. A successful foreground plus an expired
# descendant must still fail; the installed two-minute limit stays unchanged.
sed 's/RuntimeMaxSec=120s/RuntimeMaxSec=1s/' "$work/private-queues" >"$work/short-deadline"
chmod +x "$work/short-deadline"
python3 "$test_directory/check_workstation_feedback.py" "$work/private-queues" "$work/short-deadline"
python3 "$test_directory/check_workstation_lanes.py" "$work/private-queues"
python3 "$test_directory/test_workstation_bounded.py" "$runner"

# The real controller expires without starting a payload on invalid capacity.
# meminfo is expressed in KiB, so the boundary probe is one KiB below minimum.
minimum=$(sed -n "s/^bulk_available='\([0-9]*\)'$/\1/p" "$runner")
[[ $minimum =~ ^[0-9]+$ && $((minimum % 1024)) == 0 ]]
minimum_kib=$((minimum / 1024))
for available in 0 invalid '' "$((minimum_kib - 1))"; do
  printf 'MemAvailable: %s kB\n' "$available" >"$work/meminfo"
  for lane in bulk feedback; do
    # Feedback has a lower budget; only its own invalid snapshots must refuse.
    if [[ $lane == feedback && $available == "$((minimum_kib - 1))" ]]; then continue; fi
    flags=()
    if [[ $lane == feedback ]]; then flags=(--feedback); fi
    if "$work/private-queues" --admission-timeout 2 "${flags[@]}" touch "$work/should-not-exist"; then
      echo 'Invalid or insufficient capacity incorrectly succeeded' >&2
      exit 1
    else
      [[ $? == 124 ]]
    fi
    [[ ! -e $work/should-not-exist ]]
  done
done
printf 'MemAvailable: %s kB\n' "$minimum_kib" >"$work/meminfo"
[[ $("$work/private-queues" printf '%s' admitted) == admitted ]]
# A missing snapshot exercises the controller's real failed-read path.
rm "$work/meminfo"
if "$work/private-queues" --admission-timeout 2 touch "$work/should-not-exist"; then
  echo 'Unreadable capacity incorrectly succeeded' >&2
  exit 1
else
  [[ $? == 124 ]]
fi
[[ ! -e $work/should-not-exist ]]
printf 'MemAvailable: 33554432 kB\n' >"$work/meminfo"

# Literal arguments and nonzero payload statuses remain exact in the new lane.
# shellcheck disable=SC2016
[[ $("$work/private-queues" --feedback printf '%s' '$HOME $$ ${HOME}') == '$HOME $$ ${HOME}' ]]
if "$work/private-queues" --feedback bash -c 'exit 23'; then
  exit 1
else
  [[ $? == 23 ]]
fi
echo 'PASS: independent lanes, deadline failure after foreground exit, admission refusal, literal arguments and exit status'
