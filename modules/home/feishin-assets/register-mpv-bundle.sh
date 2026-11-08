# shellcheck shell=bash
# Variables and functions are supplied by the owning activation or build phase.
run /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f @lib_escapeShellArg_darwinMpvBundle_Applications_Feishin_mpv_@
