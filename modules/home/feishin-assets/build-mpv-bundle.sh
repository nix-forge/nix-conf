# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
mkdir -p "$out/Applications"
app="$out/Applications/Feishin mpv.app"
if [[ -d @config_programs_mpv_finalPackage_unwrapped@/Applications/mpv.app ]]; then
  cp -R @config_programs_mpv_finalPackage_unwrapped@/Applications/mpv.app "$app"
  chmod -R u+w "$app"
else
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cp -L @lib_escapeShellArg_mpvBinary@ "$app/Contents/MacOS/mpv"
fi
cp @pkgs_feishin@/Applications/Feishin.app/Contents/Resources/icon.icns \
  "$app/Contents/Resources/icon.icns"
find "$app" -name .gitkeep -delete
python3 @scripts_feishin_check_py@ "$app/Contents/Info.plist"
@lib_getExe_pkgs_rcodesign@ sign "$app"
