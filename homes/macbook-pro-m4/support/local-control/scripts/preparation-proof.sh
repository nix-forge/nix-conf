#!@bash@
# shellcheck shell=bash
set -euo pipefail
export LC_ALL=C

if [ "$#" -ne 4 ] || [ "$1" != compute ]; then
  printf 'Usage: local-control-preparation-proof compute STATIC_DIGEST PROXY_MODE ENVIRONMENT_FILE\n' >&2
  exit 64
fi
static_configuration_digest="$2"
proxy_mode="$3"
environment_file="$4"
case "$proxy_mode" in enabled | disabled) ;; *)
  printf 'The preparation proof received an invalid proxy mode.\n' >&2
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

proof_environment_snapshot="$(@mktemp@)"
trap '@rm@ -f "$proof_environment_snapshot"' EXIT
@environmentSnapshot@ read "$environment_file" "$proxy_mode" >"$proof_environment_snapshot"

environment_seen='|'
while IFS= read -r environment_line || [ -n "$environment_line" ]; do
  case "$environment_line" in "" | \#*) continue ;; *=*)
    environment_name="${environment_line%%=*}"
    environment_value="${environment_line#*=}"
    ;;
  *)
    printf 'The environment file must contain only NAME=VALUE records.\n' >&2
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
done <"$proof_environment_snapshot"
for required_setting in "${required_settings[@]}"; do
  [ -n "${!required_setting:-}" ] || {
    printf 'A required service setting is missing.\n' >&2
    exit 78
  }
done

preparation_project_directory="$LOCAL_CONTROL_PROJECT_DIRECTORY"
source_identity="$(@secureFileSystem@ exec-source "$preparation_project_directory" @sourceIdentity@)" || {
  printf 'The project directory could not be opened as a stable source root.\n' >&2
  exit 78
}
read -r preparation_revision preparation_files_digest <<EOF
$source_identity
EOF
case "$preparation_revision" in "" | *[!0-9a-fA-F]*)
  printf 'The Git revision was not a deterministic hexadecimal identifier.\n' >&2
  exit 78
  ;;
esac
case "$preparation_files_digest" in "" | *[!0-9a-fA-F]*)
  printf 'The source digest was not a deterministic hexadecimal identifier.\n' >&2
  exit 78
  ;;
esac
case "${#preparation_revision}" in 40 | 64) ;; *)
  printf 'The Git revision has an unexpected length.\n' >&2
  exit 78
  ;;
esac
[ "${#preparation_files_digest}" -eq 64 ] || {
  printf 'The source digest has an unexpected length.\n' >&2
  exit 78
}

environment_file_digest="$(@sha256sum@ "$proof_environment_snapshot" | @cut@ -d ' ' -f 1)" || {
  printf 'The environment snapshot could not be hashed safely.\n' >&2
  exit 78
}
preparation_runtime_digest="$({
  printf 'project-directory\0%s\0' "$preparation_project_directory"
  printf 'static-configuration-digest\0%s\0' "$static_configuration_digest"
  printf 'proxy-mode\0%s\0' "$proxy_mode"
  printf 'environment-file-digest\0%s\0' "$environment_file_digest"
  for runtime_setting in "${required_settings[@]}"; do
    runtime_value="${!runtime_setting}"
    runtime_value_digest="$(@sha256sum@ <<<"$runtime_value")"
    runtime_value_digest="${runtime_value_digest%% *}"
    printf '%s\0%s\0' "$runtime_setting" "$runtime_value_digest"
  done
  if [ "$proxy_mode" = disabled ]; then
    printf 'SERVICE_PROXY_ATTESTATION\0disabled\0'
  fi
} | @sha256sum@ | @cut@ -d ' ' -f 1)" || {
  printf 'The launch configuration could not be hashed safely.\n' >&2
  exit 78
}

printf '%s\0%s\0%s\0%s\0%s\0%s' \
  "$preparation_project_directory" "$LOCAL_CONTROL_PREPARATION_INPUT" \
  "$preparation_revision" "$preparation_files_digest" "$environment_file_digest" \
  "$preparation_runtime_digest" | @sha256sum@ | @cut@ -d ' ' -f 1
