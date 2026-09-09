#!@bash@
# shellcheck shell=bash
set -euo pipefail

if [ "$#" -ne 3 ] || [ "$1" != read ]; then
  printf 'Usage: local-control-environment-snapshot read ENVIRONMENT_FILE PROXY_MODE\n' >&2
  exit 64
fi
environment_file="$2"
proxy_mode="$3"
case "$proxy_mode" in enabled | disabled) ;; *)
  printf 'The environment snapshot received an invalid proxy mode.\n' >&2
  exit 64
  ;;
esac

required_settings=(
  LOCAL_CONTROL_PROJECT_DIRECTORY LOCAL_CONTROL_DATABASE_URL
  LOCAL_CONTROL_DATABASE_ENVIRONMENT_VARIABLE LOCAL_CONTROL_SCHEMA_COMMAND
  LOCAL_CONTROL_API_COMMAND LOCAL_CONTROL_WORKER_COMMAND
  LOCAL_CONTROL_FRONTEND_COMMAND LOCAL_CONTROL_PREPARE_COMMAND
  LOCAL_CONTROL_PREPARATION_INPUT LOCAL_CONTROL_READINESS_URL
)
[ "$proxy_mode" = enabled ] && required_settings+=(SERVICE_PROXY_ATTESTATION)
for required_setting in "${required_settings[@]}"; do unset "$required_setting"; done
unset SERVICE_PROXY_ATTESTATION

environment_snapshot_tmp="$(@mktemp@)"
trap '@rm@ -f "$environment_snapshot_tmp"' EXIT
@secureFileSystem@ read-generation-file "$environment_file" 600 >"$environment_snapshot_tmp"

environment_seen='|'
while IFS= read -r environment_line || [ -n "$environment_line" ]; do
  case "$environment_line" in "" | \#*) continue ;; *$'\r'*)
    printf 'The environment file contains a carriage return.\n' >&2
    exit 78
    ;;
  *=*)
    environment_name="${environment_line%%=*}"
    environment_value="${environment_line#*=}"
    ;;
  *)
    printf 'The environment file must contain only NAME=VALUE records.\n' >&2
    exit 78
    ;;
  esac
  case "$environment_name" in
  LOCAL_CONTROL_PROJECT_DIRECTORY | LOCAL_CONTROL_DATABASE_URL | LOCAL_CONTROL_DATABASE_ENVIRONMENT_VARIABLE | LOCAL_CONTROL_SCHEMA_COMMAND | LOCAL_CONTROL_API_COMMAND | LOCAL_CONTROL_WORKER_COMMAND | LOCAL_CONTROL_FRONTEND_COMMAND | LOCAL_CONTROL_PREPARE_COMMAND | LOCAL_CONTROL_PREPARATION_INPUT | LOCAL_CONTROL_READINESS_URL) ;;
  SERVICE_PROXY_ATTESTATION) [ "$proxy_mode" = enabled ] || {
    printf 'The environment file contains a proxy setting while the proxy is disabled.\n' >&2
    exit 78
  } ;;
  *)
    printf 'The environment file contains an unsupported setting: %s\n' "$environment_name" >&2
    exit 78
    ;;
  esac
  case "$environment_seen" in *"|$environment_name|"*)
    printf 'The environment file contains a duplicate setting: %s\n' "$environment_name" >&2
    exit 78
    ;;
  esac
  environment_seen="${environment_seen}${environment_name}|"
  export "$environment_name=$environment_value"
done <"$environment_snapshot_tmp"

for required_setting in "${required_settings[@]}"; do
  [ -n "${!required_setting:-}" ] || {
    printf 'The environment file is missing a required setting: %s\n' "$required_setting" >&2
    exit 78
  }
done
@cat@ "$environment_snapshot_tmp"
