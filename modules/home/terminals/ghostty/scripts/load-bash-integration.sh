# shellcheck shell=bash
if [[ -n ${GHOSTTY_RESOURCES_DIR-} ]]; then
  builtin source -- "@bashIntegration@/bash/ghostty.bash"
fi
