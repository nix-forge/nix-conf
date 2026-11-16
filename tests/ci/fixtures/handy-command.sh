#!/usr/bin/env bash
set -euo pipefail
if [[ ${0##*/} == nix && $1 == build ]]; then
  echo artifact >>"$RUNNER_TEMP/calls"
  [[ ${FAIL_PHASE:-} != artifact ]] || exit 23
  [[ $* == *'.#checks.aarch64-darwin.handy-artifact'* ]]
  echo "$RUNNER_TEMP/exact-artifact"
elif [[ ${0##*/} == nix && $1 == print-dev-env ]]; then
  echo shell >>"$RUNNER_TEMP/calls"
  [[ ${FAIL_PHASE:-} != shell ]] || exit 24
  [[ $* == *'.#tests'* ]]
  if [[ $# == 5 && $3 == --profile && $4 == "$RUNNER_TEMP/handy-test-environment" && $5 == --json ]]; then
    printf 'recorded environment\n' >"$4"
    printf '{"captured": true}\n'
  else
    # A generated shell script need not parse in the caller's Bash version.
    # Reproduce the native capture/activation failure at that exact boundary.
    printf ';\n'
  fi
elif [[ ${0##*/} == nix && $1 == develop ]]; then
  [[ $2 == "$RUNNER_TEMP/handy-test-environment" && $3 == --command ]]
  [[ -f $2 ]]
  echo activate >>"$RUNNER_TEMP/calls"
  [[ ${FAIL_PHASE:-} != activate ]] || exit 26
  export HANDY_EXACT_ENVIRONMENT=realized
  shift 3
  exec "$@"
elif [[ ${0##*/} == python3 ]]; then
  [[ $HANDY_EXACT_ENVIRONMENT == realized ]]
  if [[ $1 == -m ]]; then
    echo native-process >>"$RUNNER_TEMP/calls"
    [[ $* == '-m pytest -m native_process tests/workstation/test_workstation_faults.py tests/workstation/test_workstation_jobs.py' ]]
  else
    [[ $HANDY_TEST_BUNDLE == "$RUNNER_TEMP/exact-artifact/Applications/Handy.app" ]]
    echo native >>"$RUNNER_TEMP/calls"
    [[ ${FAIL_PHASE:-} != native ]] || exit 25
    [[ $1 == */tests/macos/test_handy_signature.py ]]
  fi
else
  exit 99
fi
