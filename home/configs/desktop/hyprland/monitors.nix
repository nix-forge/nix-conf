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
let
  hyprctl = lib.bird.getExe' config.wayland.windowManager.hyprland.finalPackage "hyprctl";

  origin = {
    x = 0;
    y = 0;
  };
  inherit (config.wayland.windowManager.hyprland.monitors) desktop default;
in
{
  wayland.windowManager.hyprland = {
    monitors = {
      desktop = {
        name = "DP-1";
        resolution.x = 2560;
        resolution.y = 1440;
        scale = 1.333333;
        position.x = origin.x;
        position.y = origin.y;
        refreshRate = 165;
        bitdepth = 10;
      };

      # Any other random monitors (for example HDMI, or portable on DP-1)
      # should assume a position to the right of the desktop display.
      default = {
        name = "";
        resolution = "preferred";
        position.x = builtins.floor (desktop.position.x + desktop.size.x);
        position.y = desktop.position.y;
      };
    };

    # Unfortunately, fallbacks do not work.
    #
    # I had expected to be able to do something like
    # `"20".monitor = [ hotplug portable dock ];` to have the workspace
    # assigned to a monitor depending on what is connected.
    #
    # The way that it is right now, when monitors are missing I believe
    # the workspace positions are indeterminate, which is unfortunate.
    #
    # Eventually, I will solve this problem by completing
    # <https://github.com/spikespaz/hyprland-workspace-profiles>.
    #
    # Such a feature has been explicitly declined for inclusion in Hyprland.
    workspaceRules = {
      "1".monitor = desktop.name;
      "3".monitor = desktop.name;
      "5".monitor = desktop.name;
      "7".monitor = desktop.name;
      "9".monitor = desktop.name;

      "2".monitor = desktop.name;
      "4".monitor = desktop.name;
      "6".monitor = desktop.name;
      "8".monitor = desktop.name;
      "10".monitor = desktop.name;

      "11".monitor = desktop.name;
      "13".monitor = desktop.name;
      "15".monitor = desktop.name;
      "17".monitor = desktop.name;
      "19".monitor = desktop.name;

      # "12".monitor = hotplug.name;
      # "14".monitor = hotplug.name;
      # "16".monitor = hotplug.name;
      # "18".monitor = hotplug.name;
      # "20".monitor = hotplug.name;
    };

    # This is here to fix a Hyprland bug that seems to persist (repeat regression).
    # When a monitor is connected, all workspaces assigned to it will be moved.
    # Hyprland should already do that, but for some reason, it misses some.
    eventListener.handler.monitorAdd = lib.pipe config.wayland.windowManager.hyprland.workspaceRules [
      (lib.mapAttrsToList (
        ws: attrs: {
          inherit ws;
          mon = attrs.monitor;
        }
      ))
      (lib.groupBy' (wss: attrs: wss ++ [ attrs.ws ]) [ ] (attrs: attrs.mon))
      (lib.mapAttrsToList (
        mon: wss: ''
          if [[ "$HL_MONITOR_NAME" = '${mon}' ]]; then
            ${
              lib.concatStringsSep "\n  " (
                map (ws: "${hyprctl} dispatch moveworkspacetomonitor '${ws}' '${mon}'") wss
              )
            }
          fi
        ''
      ))
      lib.concatLines
    ];
  };
}
