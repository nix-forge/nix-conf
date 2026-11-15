# shellcheck shell=bash
# Sourced by Home Manager or the owning build phase.
spotifyApp=@lib_escapeShellArg_spotifyDarwinApp@
if [[ -d $spotifyApp ]]; then
  run /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$spotifyApp"
fi
