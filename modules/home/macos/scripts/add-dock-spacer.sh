# shellcheck shell=bash
# Variables and functions are supplied by the owning activation or build phase.
run @dockutilExe@ \
  --add @lib_escapeShellArg@ \
  --type @spacerType@ \
  --section apps \
  --position end@withNoRestart_noRestart@
