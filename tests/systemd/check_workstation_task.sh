#!/usr/bin/env bash
# Native desktop integration test. OOM allocations are confined to 96 MiB.
# The embedded bash programs intentionally expand variables in the child.
# shellcheck disable=SC2016
set -euo pipefail

policy=${1:?usage: check_workstation_task.sh POLICY_DIRECTORY}
runner="$policy/runner/bin/workstation-task"
work=$(mktemp -d)
unit="workstation-policy-test-$$.scope"
first=''
second=''
cleanup() {
  for child in "$first" "$second"; do
    [[ -z $child ]] || kill "$child" 2>/dev/null || true
  done
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

# Stdio, arguments, environment, working directory and exit status survive.
(
  cd "$work"
  export WORKSTATION_TEST_VALUE='value with spaces'
  "$runner" bash -c '
    [[ "$PWD" == "$1" && "$WORKSTATION_TEST_VALUE" == "value with spaces" ]]
    [[ "$2" == "literal * argument" ]]
    cat /proc/self/cgroup > "$1/cgroup"
  ' -- "$work" 'literal * argument'
)
grep -q '/background-workload.slice/' "$work/cgroup"
[[ $(printf 'stdin survives\n' | "$runner" cat) == 'stdin survives' ]]
# systemd-run otherwise expands dollar expressions even when the caller quoted
# them. Nix expressions and shell snippets must reach the command unchanged.
[[ $("$runner" printf '%s' '${WORKSTATION_UNSET_TEST}') == '${WORKSTATION_UNSET_TEST}' ]]
[[ $("$runner" printf '%s' '$HOME $$ ${HOME}') == '$HOME $$ ${HOME}' ]]
if "$runner" bash -c 'exit 23'; then
  echo 'Failed to propagate command failure' >&2
  exit 1
else
  [[ $? == 23 ]]
fi

# Reentrant calls share the outer scope instead of deadlocking on its lock.
timeout 10 "$runner" bash -c '
  cat /proc/self/cgroup > "$2/outer"
  "$1" cat /proc/self/cgroup > "$2/inner"
' -- "$runner" "$work"
cmp "$work/outer" "$work/inner"

# Two independent callers cannot run concurrently. The first stays blocked
# on a FIFO until the test releases it; the second must remain queued.
mkfifo "$work/release"
"$runner" bash -c '
  cat /proc/self/cgroup > "$1/first-scope"
  echo first-start > "$1/order"
  read -r _ < "$1/release"
  echo first-end >> "$1/order"
' -- "$work" &
first=$!
for _ in {1..100}; do
  [[ -f "$work/order" ]] && break
  sleep 0.05
done
[[ -f "$work/order" ]]
"$runner" bash -c 'cat /proc/self/cgroup > "$1/second-scope"; echo second >> "$1/order"' -- "$work" &
second=$!
sleep 0.2
[[ $(cat "$work/order") == first-start ]]
echo release >"$work/release"
wait "$first" "$second"
printf 'first-start\nfirst-end\nsecond\n' >"$work/expected"
cmp "$work/expected" "$work/order"

# Cancellation reaches the isolated workload, and successful commands retain
# the queue while their background descendants finish.
python3 - "$runner" "$work" <<'PY'
import os
import pathlib
import signal
import shutil
import subprocess
import sys
import time

runner, root = sys.argv[1], pathlib.Path(sys.argv[2])
for sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
    marker = root / f"signal-{sig}"
    command = "import os,pathlib,time,sys; pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); time.sleep(30)"
    job = subprocess.Popen([runner, sys.executable, "-c", command, str(marker)])
    try:
        for _ in range(100):
            if marker.exists():
                break
            time.sleep(0.05)
        assert marker.exists(), "workload did not start"
        job.send_signal(sig)
        assert job.wait(timeout=10) == 128 + sig
        process = pathlib.Path("/proc") / marker.read_text() / "stat"
        assert not process.exists() or process.read_text().split()[2] == "Z", "cancelled workload survived"
    finally:
        if job.poll() is None:
            job.terminate()
            job.wait(timeout=10)

holder_marker = root / "holder-started"
holder_code = "import pathlib,time,sys; pathlib.Path(sys.argv[1]).touch(); time.sleep(30)"
holder = subprocess.Popen([runner, sys.executable, "-c", holder_code, str(holder_marker)])
queued_marker = root / "queued-must-not-start"
queued = None
try:
    for _ in range(100):
        if holder_marker.exists():
            break
        time.sleep(0.05)
    assert holder_marker.exists()
    queued = subprocess.Popen([runner, "touch", str(queued_marker)])
    time.sleep(.2)
    queued.terminate()
    assert queued.wait(timeout=10) == 143
    assert not queued_marker.exists()
finally:
    if queued is not None and queued.poll() is None:
        queued.terminate()
        queued.wait(timeout=10)
    holder.terminate()
    holder.wait(timeout=10)

order = root / "descendant-order"
child = "import pathlib,time,sys; time.sleep(.5); pathlib.Path(sys.argv[1]).open('a').write('child-finished\\n')"
parent = "import pathlib,subprocess,sys; pathlib.Path(sys.argv[1]).write_text('parent-finished\\n'); subprocess.Popen([sys.executable,'-c',sys.argv[2],sys.argv[1]],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)"
trace = root / "descendant-execs"
tracer = shutil.which("strace")
assert tracer is not None, "strace is required to check idle waiting"
subprocess.run([tracer, "-f", "-yy", "-e", "trace=execve,poll", "-o", str(trace), runner, sys.executable, "-c", parent, str(order), child], check=True, timeout=10)
subprocess.run([runner, sys.executable, "-c", "import pathlib,sys; pathlib.Path(sys.argv[1]).open('a').write('second-started\\n')", str(order)], check=True, timeout=10)
assert order.read_text().splitlines() == ["parent-finished", "child-finished", "second-started"]
probes = [line for line in trace.read_text().splitlines() if '"is-active"' in line and line.endswith("= 0")]
assert len(probes) <= 1, f"Waiting for descendants repeatedly queried systemd: {len(probes)} probes"
waits = [line for line in trace.read_text().splitlines() if "poll(" in line and "cgroup.events" in line]
assert len(waits) < 10, f"Waiting for descendants spun on cgroup events: {len(waits)} wakeups"

# strace also waits for traced descendants. Check queue retention independently
# without it, for both successful and failing parents.
for status in (0, 23):
    exiting_parent = parent + f"; sys.exit({status})"
    completed = subprocess.run([runner, sys.executable, "-c", exiting_parent, str(order), child], check=False, timeout=10)
    assert completed.returncode == status
    assert order.read_text().splitlines() == ["parent-finished", "child-finished"]
# Cancellation must also interrupt the descendant wait.
for sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
    parent_marker = root / f"departed-parent-{sig}"
    child_marker = root / f"remaining-child-{sig}"
    child_code = "import os,pathlib,time,sys; pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); time.sleep(30)"
    parent_code = "import os,pathlib,subprocess,sys; pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); subprocess.Popen([sys.executable,'-c',sys.argv[3],sys.argv[2]],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)"
    job = subprocess.Popen([runner, sys.executable, "-c", parent_code, str(parent_marker), str(child_marker), child_code])
    try:
        for _ in range(100):
            if child_marker.exists() and parent_marker.exists() and not (pathlib.Path('/proc') / parent_marker.read_text()).exists():
                break
            time.sleep(.05)
        else:
            raise AssertionError("parent did not exit leaving its descendant")
        assert job.poll() is None, "queue released before descendant exited"
        job.send_signal(sig)
        assert job.wait(timeout=10) == 128 + sig
        process = pathlib.Path('/proc') / child_marker.read_text() / 'stat'
        assert not process.exists() or process.read_text().split()[2] == 'Z', "descendant survived cancellation"
    finally:
        if job.poll() is None:
            job.terminate()
            job.wait(timeout=10)

# A launch error must be visible and must release the queue.
failed = subprocess.run([runner, "/nonexistent/workstation-test-command"], check=False)
assert failed.returncode != 0
subprocess.run([runner, "true"], check=True, timeout=10)
PY

# A task is an indivisible failure group. Its child cannot leave a half-dead
# job behind, and a confined task OOM must not kill this supervising process.
if systemd-run --user --scope --quiet --unit="$unit" \
  --slice=background-workload.slice -p OOMPolicy=kill \
  -p MemoryMax=96M -p MemorySwapMax=0 \
  python3 -c '
import pathlib, subprocess, sys
group = pathlib.Path("/sys/fs/cgroup") / pathlib.Path("/proc/self/cgroup").read_text().strip().split("::", 1)[1].lstrip("/")
assert (group / "memory.max").read_text().strip() == str(96 * 1024 * 1024)
assert (group / "memory.oom.group").read_text().strip() == "1"
subprocess.run([sys.executable, "-c", "data=bytearray(128*1024*1024)"], check=False)
pathlib.Path(sys.argv[1]).touch()
' "$work/incorrect-survivor"; then
  echo 'Expected confined workload OOM' >&2
  exit 1
fi
[[ ! -e "$work/incorrect-survivor" ]]
for _ in {1..100}; do
  [[ $(systemctl --user show "$unit" -p Result --value) == oom-kill ]] && break
  sleep 0.05
done
[[ $(systemctl --user show "$unit" -p Result --value) == oom-kill ]]

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
