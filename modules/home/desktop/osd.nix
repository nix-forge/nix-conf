{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.desktop.osd;
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  client = lib.getExe' pkgs.swayosd "swayosd-client";
  hyprBind = key: command: {
    _args = [
      key
      (lib.generators.mkLuaInline "hl.dsp.exec_cmd(${builtins.toJSON command})")
    ];
  };
in
{
  options.desktop.osd.enable = lib.mkEnableOption "SwayOSD for volume, brightness, and media feedback";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = isLinux;
        message = "desktop.osd is supported on Linux only.";
      }
    ];

    home.packages = [
      pkgs.brightnessctl
      pkgs.playerctl
      pkgs.swayosd
    ];

    xdg.configFile."swayosd/config.toml".source = pkgs.replaceVarsWith {
      name = "swayosd-config";
      src = ./config/swayosd.toml;
      replacements = { };
    };

    systemd.user.services.swayosd = {
      Unit = {
        Description = "SwayOSD server";
        PartOf = [ "graphical-session.target" ];
        After = [
          "graphical-session.target"
          "pipewire.service"
        ];
      };
      Service = {
        ExecStart = "${lib.getExe' pkgs.swayosd "swayosd-server"}";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    # Hardware media keys should behave like an ordinary desktop even when no
    # panel is visible. These bindings remain additive to a host's own layout.
    wayland.windowManager.hyprland.settings.bind =
      lib.mkIf config.wayland.windowManager.hyprland.enable
        (
          lib.mkAfter [
            (hyprBind "XF86AudioRaiseVolume" "${client} --output-volume raise")
            (hyprBind "XF86AudioLowerVolume" "${client} --output-volume lower")
            (hyprBind "XF86AudioMute" "${client} --output-volume mute-toggle")
            (hyprBind "XF86AudioMicMute" "${client} --input-volume mute-toggle")
            (hyprBind "XF86MonBrightnessUp" "${client} --brightness raise")
            (hyprBind "XF86MonBrightnessDown" "${client} --brightness lower")
            (hyprBind "XF86AudioPlay" "${client} --playerctl play-pause")
            (hyprBind "XF86AudioNext" "${client} --playerctl next")
            (hyprBind "XF86AudioPrev" "${client} --playerctl previous")
          ]
        );
  };
}
