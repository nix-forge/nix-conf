# shellcheck shell=bash
# Sourced by Home Manager or the owning build phase.
run /usr/bin/defaults write com.lujjjh.LinearMouse menuBarVisibilityMode \
  -string @lib_escapeShellArg_builtins_toJSON_cfg_menuBarVisibility@
run /usr/bin/defaults write com.lujjjh.LinearMouse menuBarVisibilityModeMigrationCompleted -bool true
run /usr/bin/defaults write com.lujjjh.LinearMouse showInMenuBar \
  -bool @lib_boolToString_cfg_menuBarVisibility_never@
run /usr/bin/defaults write com.lujjjh.LinearMouse menuBarBatteryDisplayMode \
  -string @lib_escapeShellArg_builtins_toJSON_cfg_menuBarBatteryDisplay@
run /usr/bin/defaults write com.lujjjh.LinearMouse showInDock \
  -bool @lib_boolToString_cfg_showInDock@
