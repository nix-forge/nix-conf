# shellcheck shell=bash
[[ $1 == --locate-shell-integration-path && $2 == bash ]]
printf '%s\n' called >>"$EDITOR_CALLS"
if [[ ${LOOKUP_FAIL:-false} == true ]]; then
  exit 1
fi
printf '%s\n' "$SHELL_INTEGRATION_FILE"
