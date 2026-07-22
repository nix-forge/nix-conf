{
  wayland.windowManager.hyprland.settings.monitor =
    let
      ts = toString;
      origin = {
        x = 0;
        y = 0;
      };

      build-desktop-vars = name: {
        inherit name;
        resolution.x = ts 2560;
        resolution.y = ts 1440;
        scale = ts 1.25;
        position.x = ts origin.x;
        position.y = ts origin.y;
        refreshRate = ts 165;
        bitdepth = ts 10;
      };
      desktop-nvidia = build-desktop-vars "DP-1";
      desktop-amd-integrated = build-desktop-vars "DP-4";

      desktop-monitor-config =
        screen:
        (builtins.concatStringsSep "," [
          "${screen.name}"
          "${screen.resolution.x}x${screen.resolution.y}@${screen.refreshRate}"
          "${screen.position.x}x${screen.position.y}"
          "${screen.scale}"
          "bitdepth,${screen.bitdepth}"
          "cm"
          "srgb"
        ]);
    in
    [
      (desktop-monitor-config desktop-nvidia)
      (desktop-monitor-config desktop-amd-integrated)
    ];
}
