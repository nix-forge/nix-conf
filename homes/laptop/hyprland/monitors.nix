# The monitor and workspace positions are entirely dependent upon the order of
# which I plug in the displays. The portable monitor has to be plugged in
# with Thunderbolt before connecting the laptop to the dock.
# If the portable monitor isn't connected to the dock before the laptop,
# it will switch DP-5 and DP-6.
#
# TODO: Look into at a feature addition for Hyprland where
# monitor descriptions can be matched.
# Also could be fixed in HLWSP.
#
{
  lib,
  pkgs,
  config,
  ...
}:
{
  wayland.windowManager.hyprland.settings.monitor =
    let
      ts = number: builtins.toString number;
      origin = {
        x = 0;
        y = 0;
      };
      desktop = {
        name = "eDP-1";
        resolution.x = ts 3072;
        resolution.y = ts 1920;
        scale = ts 1.6;
        position.x = ts origin.x;
        position.y = ts origin.y;
        refreshRate = ts 60;
        bitdepth = ts 10;
      };
    in
    [
      (builtins.concatStringsSep "," [
        "${desktop.name}"
        "${desktop.resolution.x}x${desktop.resolution.y}@${desktop.refreshRate}"
        "${desktop.position.x}x${desktop.position.y}"
        "${desktop.scale}"
        "bitdepth,${desktop.bitdepth}"
        "cm"
        "auto"
      ])
    ];
}
