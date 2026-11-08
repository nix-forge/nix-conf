# shellcheck shell=bash
app=@lib_escapeShellArg_darwinApp@
if [ -d "$app" ]; then
  run /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
fi
