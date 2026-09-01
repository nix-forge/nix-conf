#!@bash@
# shellcheck shell=bash
set -euo pipefail
export LC_ALL=C
[ "$#" -ge 6 ] || {
  printf 'Usage: local-control-service-gate ENVIRONMENT_FILE PREPARATION_STAMP STATE_DIRECTORY STATIC_DIGEST PROXY_MODE COMMAND...\n' >&2
  exit 64
}
gate_environment_file="$1"
gate_preparation_stamp="$2"
gate_state_directory="$3"
gate_static_configuration_digest="$4"
gate_proxy_mode="$5"
shift 5
case "$gate_proxy_mode" in enabled | disabled) ;; *)
  printf 'The service gate received an invalid proxy mode.\n' >&2
  exit 64
  ;;
esac

gate_environment_snapshot="$(@mktemp@ "$gate_state_directory/gate-environment.XXXXXX")"
if ! @environmentSnapshot@ read "$gate_environment_file" "$gate_proxy_mode" >"$gate_environment_snapshot"; then
  @rm@ -f "$gate_environment_snapshot"
  printf 'The service environment is missing, unsafe, or invalid.\n' >&2
  exit 0
fi
gate_preparation_state="$(@preparationProof@ compute "$gate_static_configuration_digest" "$gate_proxy_mode" "$gate_environment_snapshot")" || {
  @rm@ -f "$gate_environment_snapshot"
  printf 'The service preparation proof is unavailable.\n' >&2
  exit 0
}
gate_stamp_value="$(@secureFileSystem@ read-file "$gate_preparation_stamp" 600)" || {
  @rm@ -f "$gate_environment_snapshot"
  printf 'The service preparation stamp is missing or unsafe.\n' >&2
  exit 0
}
if [ "$gate_stamp_value" != "$gate_preparation_state" ]; then
  @rm@ -f "$gate_environment_snapshot"
  printf 'The service preparation stamp is stale.\n' >&2
  exit 0
fi
export LOCAL_CONTROL_ENVIRONMENT_SNAPSHOT="$gate_environment_snapshot"
exec "$@"
