# shellcheck shell=bash
# Variables and functions are supplied by the owning activation or build phase.
run /usr/bin/defaults write com.lujjjh.LinearMouse SUEnableAutomaticChecks -bool false
run /usr/bin/defaults write com.lujjjh.LinearMouse SUAutomaticallyUpdate -bool false
