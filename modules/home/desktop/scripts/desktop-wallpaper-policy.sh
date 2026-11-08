# shellcheck shell=bash
python3 @scripts_wallpaper_policy_py@ \
  --catalog @wallpaper_catalog_json@ --config @policyDefaults@ \
  --preferences @lib_escapeShellArg_config_xdg_stateHome_desktop_wallpaper_pr@ "$@"
case "${1:-}" in
connection | category | source | personal)
  @lib_getExe_pkgs_systemd_systemctl@ --user start --no-block desktop-wallpaper-rotate.service || true
  ;;
esac
