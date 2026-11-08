#!/usr/bin/env bash
# Native scope probes use test-only lock names; production jobs are never cancelled.
set -euo pipefail
runner=${1:?usage: check_workstation_feedback.sh RUNNER}
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

# Keep the installed source, helpers, resource policy and environment. Change only
# queue names so tiny fake bulk jobs cannot interfere with real queued work.
# The tiny lane fixtures simulate sufficient capacity independently of actual
# host load; low-capacity refusal is exercised separately below.
grep -Fq 'workstation-background.lock' "$runner"
grep -Fq 'workstation-feedback.lock' "$runner"
grep -Fq 'RuntimeMaxSec=120s' "$runner"
sed -e "s/workstation-background.lock/workstation-test-bulk-$$.lock/g" \
  -e "s/workstation-feedback.lock/workstation-test-feedback-$$.lock/g" \
  -e "s|/run/workstation-workloads/bulk.lock|$work/shared-bulk.lock|g" \
  -e 's/^  available=.*/  available=34359738368/' \
  "$runner" >"$work/private-queues"
chmod +x "$work/private-queues"
# Shorten only the fixture deadline. A successful foreground plus an expired
# descendant must still fail; the installed two-minute limit stays unchanged.
sed 's/RuntimeMaxSec=120s/RuntimeMaxSec=1s/' "$work/private-queues" >"$work/short-deadline"
chmod +x "$work/short-deadline"
python3 "$test_directory/check_workstation_feedback.py" "$work/private-queues" "$work/short-deadline"
python3 "$test_directory/check_workstation_lanes.py" "$work/private-queues"
python3 "$test_directory/test_workstation_bounded.py" "$runner"

# Simulate inadequate capacity only in this disposable source fixture. Refusal
# must occur before the payload runs, with no change to host memory policy.
sed '/^  available=/c\  available=0' "$work/private-queues" >"$work/no-capacity"
chmod +x "$work/no-capacity"
if "$work/no-capacity" --feedback touch "$work/should-not-exist"; then
  echo 'Capacity refusal incorrectly succeeded' >&2
  exit 1
else
  [[ $? == 75 ]]
fi
[[ ! -e "$work/should-not-exist" ]]

# The same disposable low-capacity fixture must refuse bulk work before the
# payload starts; this exercises the bulk lane's own admission branch.
if "$work/no-capacity" touch "$work/bulk-should-not-exist"; then
  echo 'Bulk capacity refusal incorrectly succeeded' >&2
  exit 1
else
  [[ $? == 75 ]]
fi
[[ ! -e "$work/bulk-should-not-exist" ]]

# Exercise malformed, missing and boundary snapshots through the real admission
# branch. These private queues run only tiny fixture payloads, never builds.
minimum=$(sed -n "s/^  local available minimum_available='\([0-9]*\)'$/\1/p" "$runner")
[[ $minimum =~ ^[0-9]+$ ]]
for available in invalid '' "$((minimum - 1))"; do
  sed "/^  available=/c\\  available='$available'" "$work/private-queues" >"$work/bulk-capacity"
  chmod +x "$work/bulk-capacity"
  if "$work/bulk-capacity" touch "$work/bulk-should-not-exist"; then
    echo 'Invalid or insufficient bulk capacity incorrectly succeeded' >&2
    exit 1
  else
    [[ $? == 75 ]]
  fi
  [[ ! -e "$work/bulk-should-not-exist" ]]
done
sed "/^  available=/c\\  available='$minimum'" "$work/private-queues" >"$work/bulk-capacity"
chmod +x "$work/bulk-capacity"
[[ $("$work/bulk-capacity" printf '%s' admitted) == admitted ]]
# Preserve a literal failing read inside the disposable runner.
# shellcheck disable=SC2016
sed '/^  available=/c\  available=$(false) || return 75' "$work/private-queues" >"$work/bulk-capacity"
if "$work/bulk-capacity" touch "$work/bulk-should-not-exist"; then
  echo 'Unreadable bulk capacity incorrectly succeeded' >&2
  exit 1
else
  [[ $? == 75 ]]
fi
[[ ! -e "$work/bulk-should-not-exist" ]]

# Literal arguments and nonzero payload statuses remain exact in the new lane.
# shellcheck disable=SC2016
[[ $("$work/private-queues" --feedback printf '%s' '$HOME $$ ${HOME}') == '$HOME $$ ${HOME}' ]]
if "$work/private-queues" --feedback bash -c 'exit 23'; then
  exit 1
else
  [[ $? == 23 ]]
fi
echo 'PASS: independent lanes, deadline failure after foreground exit, admission refusal, literal arguments and exit status'
