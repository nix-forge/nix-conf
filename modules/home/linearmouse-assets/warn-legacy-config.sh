# shellcheck shell=bash
if [ -e @lib_escapeShellArg_legacyConfigFile@ ]; then
  echo "warning: @legacyConfigFile@ takes precedence over the Home Manager-managed LinearMouse configuration" >&2
fi
