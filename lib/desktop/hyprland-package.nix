{
  config,
  pkgs,
  osConfig ? null,
}:
let
  homePackage = config.wayland.windowManager.hyprland.package;
  systemPackage =
    if osConfig != null && (osConfig.programs.hyprland.enable or false) then
      osConfig.programs.hyprland.package or null
    else
      null;
in
if homePackage != null then
  homePackage
else if systemPackage != null then
  systemPackage
else
  pkgs.hyprland
