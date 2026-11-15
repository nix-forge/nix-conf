# shellcheck shell=bash
# Variables and functions are supplied by the owning activation or build phase.
run @dockutilExe@ \
  --add @lib_escapeShellArg_folder_path@ \
  --section others \
  --view @showAsMap_folder_showAs@ \
  --display @folder_displayAs@ \
  --sort @arrangementMap_folder_arrangement@ \
  --position end@withNoRestart_noRestart@
