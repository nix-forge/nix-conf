# shellcheck shell=bash
plan=$(mktemp)
trap 'rm -f -- "$plan"' EXIT
@lib_getExe_wallpaperPolicy@ plan @connection@ >"$plan"
# Configuration paths are escaped literals, including dollar signs.
# shellcheck disable=SC2016
python3 @scripts_wallpaper_fetch_d2d_py@ \
  --connection @connection@ --plan "$plan" \
  --directory @lib_escapeShellArg_cfg_directory@ \
  --state @lib_escapeShellArg_config_xdg_stateHome_desktop_wallpaper@ \
  --width @toString_cfg_rotation_width@ --height @toString_cfg_rotation_height@ \
  --max-images @toString_cfg_connections_connection_maxImages@ \
  --max-pages @toString_cfg_connections_connection_maxCandidatePages@ \
  --max-downloads @toString_cfg_connections_connection_maxCandidateDownloads@
