# shellcheck shell=bash
if [ -z "${DRY_RUN:-}" ] && [ ! -d @lib_escapeShellArg_path@ ]; then
  echo @lib_escapeShellArg_msg@ >&2
  exit 1
fi
