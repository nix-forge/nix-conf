# shellcheck shell=bash
actual="$(</proc/sys/kernel/hostname)"
expected=@expectedHostname@
if [[ -e /run/booted-system && $actual != "$expected" && ${EXPECTED_HOSTNAME:-} != "$expected" ]]; then
  echo "refusing to activate '$expected' on host '$actual'" >&2
  echo "set EXPECTED_HOSTNAME='$expected' only for an intentional hostname migration" >&2
  exit 1
fi
