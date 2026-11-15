# shellcheck shell=bash
set -euo pipefail
mode=${1:?fixture mode required}
shift
case $mode in
environment)
  [[ $PWD == "$1" && $WORKSTATION_TEST_VALUE == 'value with spaces' ]]
  [[ $2 == 'literal * argument' ]]
  cat /proc/self/cgroup >"$1/cgroup"
  ;;
reentrant)
  cat /proc/self/cgroup >"$2/outer"
  "$1" cat /proc/self/cgroup >"$2/inner"
  ;;
queue-first)
  cat /proc/self/cgroup >"$1/first-scope"
  echo first-start >"$1/order"
  echo "$$" >"$2"
  read -r _ <"$3"
  echo first-end >>"$1/order"
  ;;
queue-second)
  cat /proc/self/cgroup >"$1/second-scope"
  echo second >>"$1/order"
  ;;
exit) exit "$1" ;;
*)
  echo "Unknown fixture mode: $mode" >&2
  exit 2
  ;;
esac
